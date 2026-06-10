"""
Unit tests for _automation/pilot7-weekly-summary/scripts/get_weekly_data.py
"""

import importlib.util
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

# Load under a unique module name: weekly-summary's tests also import a module
# called get_weekly_data, and a plain `import` would collide in sys.modules.
SCRIPT_PATH = (
    Path(__file__).resolve().parents[1]
    / "pilot7-weekly-summary" / "scripts" / "get_weekly_data.py"
)
_spec = importlib.util.spec_from_file_location("pilot7_get_weekly_data", SCRIPT_PATH)
p7 = importlib.util.module_from_spec(_spec)
sys.modules["pilot7_get_weekly_data"] = p7
_spec.loader.exec_module(p7)


class TestLoadConfig(unittest.TestCase):
    def test_returns_defaults_when_no_file(self):
        with patch("pilot7_get_weekly_data.CONFIG_PATH") as mock_path:
            mock_path.exists.return_value = False
            config = p7.load_config()
        self.assertEqual(config, {})

    def test_repo_config_checked_in(self):
        # The committed config must point at the pilot7 repo and Slack channel.
        config = p7.load_config()
        self.assertEqual(config["repo"], "RConsortium/submissions-pilot7-synthetic-data")
        self.assertEqual(config["slack_channel"], "C0B44HS7CNA")


class TestGetWeeklyData(unittest.TestCase):
    @patch(
        "pilot7_get_weekly_data.load_config",
        return_value={"repo": "RConsortium/submissions-pilot7-synthetic-data", "lookback_days": 7},
    )
    @patch("pilot7_get_weekly_data.api_get")
    def test_structure(self, mock_api, _):
        recent = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        commits = [
            {
                "sha": "abcdef1234567",
                "commit": {"message": "feat: add eCRF-based generation\n\nbody", "author": {"name": "Zifeng"}},
                "author": {"login": "zifengwang"},
            }
        ]
        issues = {"items": [{"number": 10, "title": "MedDRA mapping", "state": "open"}]}
        prs = {
            "items": [
                {
                    "number": 47,
                    "title": "Rerun P21 fixes",
                    "state": "closed",
                    "pull_request": {"merged_at": recent},
                }
            ]
        }
        releases = [
            {"tag_name": "v0.2.0", "name": "v0.2.0", "published_at": recent},
            {"tag_name": "v0.1.0", "name": "v0.1.0", "published_at": "2020-01-01T00:00:00Z"},
        ]
        mock_api.side_effect = [commits, issues, prs, releases]

        data = p7.get_weekly_data()
        self.assertEqual(data["repo"], "RConsortium/submissions-pilot7-synthetic-data")
        self.assertEqual(data["commits"]["total_count"], 1)
        self.assertEqual(data["commits"]["highlights"][0]["sha"], "abcdef1")
        self.assertEqual(
            data["commits"]["highlights"][0]["message"],
            "feat: add eCRF-based generation",
        )
        self.assertEqual(data["issues"]["total_updated"], 1)
        self.assertTrue(data["pull_requests"]["list"][0]["merged"])
        # Only the release published inside the lookback window is included
        self.assertEqual(data["releases"]["total_published"], 1)
        self.assertEqual(data["releases"]["list"][0]["tag"], "v0.2.0")

    @patch(
        "pilot7_get_weekly_data.load_config",
        return_value={"repo": "RConsortium/submissions-pilot7-synthetic-data", "lookback_days": 14},
    )
    @patch("pilot7_get_weekly_data.api_get")
    def test_lookback_days_from_config(self, mock_api, _):
        mock_api.side_effect = [[], {"items": []}, {"items": []}, []]
        data = p7.get_weekly_data()
        expected_start = (datetime.now(timezone.utc) - timedelta(days=14)).strftime("%Y-%m-%d")
        self.assertEqual(data["week_starting"], expected_start)
        self.assertEqual(data["commits"]["total_count"], 0)
        self.assertEqual(data["releases"]["total_published"], 0)

    @patch(
        "pilot7_get_weekly_data.load_config",
        return_value={"repo": "RConsortium/submissions-pilot7-synthetic-data"},
    )
    @patch("pilot7_get_weekly_data.api_get")
    def test_commit_author_falls_back_to_name(self, mock_api, _):
        commits = [
            {
                "sha": "1234567abcdef",
                "commit": {"message": "fix typo", "author": {"name": "Peng Zhang"}},
                "author": None,
            }
        ]
        mock_api.side_effect = [commits, {"items": []}, {"items": []}, []]
        data = p7.get_weekly_data()
        self.assertEqual(data["commits"]["highlights"][0]["author"], "Peng Zhang")


if __name__ == "__main__":
    unittest.main()
