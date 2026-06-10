"""
Unit tests for _automation/benchmark-runner/scripts/get_next_eval.py

Uses unittest.mock to avoid any real git/gh/network calls.
"""

import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, call, mock_open, patch

# Make the script importable without executing main()
SCRIPT_DIR = Path(__file__).resolve().parents[1] / "benchmark-runner" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

import get_next_eval as gne  # noqa: E402


class TestNormalizeModelName(unittest.TestCase):
    def test_lowercase(self):
        self.assertEqual(gne.normalize_model_name("Claude"), "claude")

    def test_strips_spaces(self):
        self.assertEqual(gne.normalize_model_name("Claude Sonnet 4.6"), "claudesonnet46")

    def test_strips_hyphens(self):
        self.assertEqual(gne.normalize_model_name("claude-sonnet-4-6"), "claudesonnet46")

    def test_strips_dots(self):
        self.assertEqual(gne.normalize_model_name("claude.sonnet.4.6"), "claudesonnet46")

    def test_variant_equivalence(self):
        self.assertEqual(
            gne.normalize_model_name("Claude Sonnet 4.6"),
            gne.normalize_model_name("claude-sonnet-4-6"),
        )

    def test_gemini_normalization(self):
        self.assertEqual(gne.normalize_model_name("gemini-2.0-flash"), "gemini20flash")

    def test_gpt_normalization(self):
        self.assertEqual(gne.normalize_model_name("gpt-4o"), "gpt4o")


class TestEvalSelection(unittest.TestCase):
    def _eval_cases(self, runs_model=0):
        # Equal run counts so the secondary tie-break (day-digit / distributed hash)
        # governs selection. select_eval prioritises the least-benchmarked issue first,
        # so _runs_model is the primary sort key.
        return [
            {
                "id": f"github-issue-{n}",
                "_skill_sha": f"sha{n}",
                "_runs_model": runs_model,
                "_runs_total": runs_model,
                "_last_run_model": "",
            }
            for n in [21, 22, 23, 24, 27]
        ]

    def test_least_benchmarked_issue_selected_first(self):
        # The primary sort key is _runs_model: the issue with the fewest
        # prior benchmark runs for this model wins regardless of the secondary tie-break.
        cases = self._eval_cases(runs_model=5)
        cases[2]["_runs_model"] = 0  # github-issue-23 has been run the least
        selected = gne.select_eval(
            cases,
            "test-model",
            "distributed",
            "alice",
            "2026-04-21",
            datetime(2026, 4, 21, tzinfo=timezone.utc),
        )
        self.assertEqual(selected["id"], "github-issue-23")

    def test_daily_selection_preserves_day_digit_logic(self):
        selected = gne.select_eval(
            self._eval_cases(),
            "test-model",
            "daily",
            "alice",
            "2026-04-21",
            datetime(2026, 4, 24, tzinfo=timezone.utc),
        )
        self.assertEqual(selected["id"], "github-issue-24")

    def test_distributed_selection_is_stable_for_same_runner(self):
        selected_1 = gne.select_eval(
            self._eval_cases(),
            "test-model",
            "distributed",
            "alice",
            "2026-04-21",
            datetime(2026, 4, 21, tzinfo=timezone.utc),
        )
        selected_2 = gne.select_eval(
            self._eval_cases(),
            "test-model",
            "distributed",
            "alice",
            "2026-04-21",
            datetime(2026, 4, 21, tzinfo=timezone.utc),
        )
        self.assertEqual(selected_1["id"], selected_2["id"])

    def test_distributed_selection_spreads_different_runners(self):
        alice = gne.select_eval(
            self._eval_cases(),
            "test-model",
            "distributed",
            "alice",
            "2026-04-21",
            datetime(2026, 4, 21, tzinfo=timezone.utc),
        )
        bob = gne.select_eval(
            self._eval_cases(),
            "test-model",
            "distributed",
            "bob",
            "2026-04-21",
            datetime(2026, 4, 21, tzinfo=timezone.utc),
        )
        self.assertNotEqual(alice["id"], bob["id"])

    def test_default_selection_salt_uses_utc_minute(self):
        salt = gne.get_default_selection_salt(
            datetime(2026, 4, 21, 13, 45, 59, tzinfo=timezone.utc)
        )
        self.assertEqual(salt, "2026-04-21T13:45Z")


class TestCheckGithubComments(unittest.TestCase):
    """fetch_and_check_comments returns (already_done, runs_model, runs_total, last_run_model).

    These tests assert on the already_done flag and the per-model run count.
    """

    def _make_comment(self, sha, model_display):
        # Creates a comment with both prose (for legacy detection) and a
        # BENCHMARK_COMPLETE marker (for marker-based detection).
        marker_payload = json.dumps(
            {"eval_id": "github-issue-21", "model": model_display, "skill_sha": sha}
        )
        return {
            "body": (
                f"## Automated Benchmark Results — `group-sequential-design`\n"
                f"| **Skill version** | `{sha}` |\n"
                f"| **Model** | `{model_display}` |\n"
                f"\n<!-- BENCHMARK_COMPLETE: {marker_payload} -->"
            ),
            "created_at": "2026-01-01T00:00:00Z",
        }

    @patch("get_next_eval.subprocess.run")
    def test_exact_match_returns_true(self, mock_run):
        sha = "abc123"
        model = "claude-sonnet-4-6"
        mock_run.return_value = MagicMock(
            stdout=json.dumps({"comments": [self._make_comment(sha, model)]}),
            returncode=0,
        )
        already_done, runs_model, runs_total, last_run = gne.fetch_and_check_comments(
            "github-issue-21", sha, model
        )
        self.assertTrue(already_done)
        self.assertEqual(runs_model, 1)
        self.assertEqual(runs_total, 1)

    @patch("get_next_eval.subprocess.run")
    def test_variant_model_name_still_matches(self, mock_run):
        sha = "abc123"
        mock_run.return_value = MagicMock(
            stdout=json.dumps(
                {"comments": [self._make_comment(sha, "Claude Sonnet 4.6")]}
            ),
            returncode=0,
        )
        # Pass with hyphens — should still match after normalisation
        self.assertTrue(
            gne.fetch_and_check_comments("github-issue-21", sha, "claude-sonnet-4-6")[0]
        )

    @patch("get_next_eval.subprocess.run")
    def test_different_sha_returns_false(self, mock_run):
        mock_run.return_value = MagicMock(
            stdout=json.dumps(
                {"comments": [self._make_comment("old-sha", "claude-sonnet-4-6")]}
            ),
            returncode=0,
        )
        already_done, runs_model, runs_total, last_run = gne.fetch_and_check_comments(
            "github-issue-21", "new-sha", "claude-sonnet-4-6"
        )
        self.assertFalse(already_done)
        # A COMPLETE marker exists for this model (old-sha), so runs_model=1.
        self.assertEqual(runs_model, 1)
        self.assertEqual(runs_total, 1)

    @patch("get_next_eval.subprocess.run")
    def test_no_comments_returns_false(self, mock_run):
        mock_run.return_value = MagicMock(stdout=json.dumps({"comments": []}), returncode=0)
        already_done, runs_model, runs_total, last_run = gne.fetch_and_check_comments(
            "github-issue-21", "abc123", "claude-sonnet-4-6"
        )
        self.assertFalse(already_done)
        self.assertEqual(runs_model, 0)
        self.assertEqual(runs_total, 0)
        self.assertEqual(last_run, "")

    @patch("get_next_eval.fetch_issue_comments_via_api")
    @patch("get_next_eval.subprocess.run")
    def test_gh_failure_returns_false_with_warning(self, mock_run, mock_api):
        import subprocess
        mock_run.side_effect = subprocess.CalledProcessError(1, "gh", stderr="auth error")
        mock_api.side_effect = RuntimeError("GH_TOKEN or GITHUB_TOKEN is not set")
        # Should not raise — both gh and API fallback fail; run history unknown.
        already_done, runs_model, runs_total, last_run = gne.fetch_and_check_comments(
            "github-issue-21", "abc123", "claude-sonnet-4-6"
        )
        self.assertFalse(already_done)
        self.assertIsNone(runs_model)
        self.assertIsNone(runs_total)

    @patch("get_next_eval.fetch_issue_comments_via_api")
    @patch("get_next_eval.subprocess.run")
    def test_gh_failure_uses_api_fallback(self, mock_run, mock_api):
        import subprocess
        sha = "abc123"
        model = "claude-sonnet-4-6"
        mock_run.side_effect = subprocess.CalledProcessError(1, "gh", stderr="auth error")
        mock_api.return_value = [self._make_comment(sha, model)]
        self.assertTrue(gne.fetch_and_check_comments("github-issue-21", sha, model)[0])
        mock_api.assert_called_once_with("21")

    @patch("get_next_eval.fetch_issue_comments_via_api")
    @patch("get_next_eval.subprocess.run")
    def test_gh_missing_returns_false_with_warning(self, mock_run, mock_api):
        mock_run.side_effect = FileNotFoundError(2, "No such file or directory", "gh")
        mock_api.side_effect = RuntimeError("GH_TOKEN or GITHUB_TOKEN is not set")
        # Should not raise when gh binary is absent — API fallback fails, so the
        # run history is unknown.
        already_done, runs_model, runs_total, last_run = gne.fetch_and_check_comments(
            "github-issue-21", "abc123", "claude-sonnet-4-6"
        )
        self.assertFalse(already_done)
        self.assertIsNone(runs_model)
        self.assertIsNone(runs_total)

    def test_invalid_issue_id_returns_false(self):
        already_done, runs_model, runs_total, last_run = gne.fetch_and_check_comments(
            "not-a-valid-id", "sha", "model"
        )
        self.assertFalse(already_done)
        self.assertIsNone(runs_model)
        self.assertIsNone(runs_total)


class TestGetSkillContentSha(unittest.TestCase):
    def _make_skill_dir(self, tmp_path, files):
        """Create a temporary skill directory with the given {rel_path: content} files."""
        import os
        skill_dir = Path(tmp_path) / "my-skill"
        for rel, content in files.items():
            fpath = skill_dir / rel
            fpath.parent.mkdir(parents=True, exist_ok=True)
            fpath.write_text(content)
        return skill_dir

    def test_returns_hex_string(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            skill_dir = self._make_skill_dir(tmp, {"SKILL.md": "hello"})
            sha = gne.get_skill_content_sha(skill_dir)
            self.assertRegex(sha, r"^[0-9a-f]{64}$")

    def test_deterministic_same_files(self):
        import tempfile
        files = {"SKILL.md": "content A", "reference.md": "content B"}
        with tempfile.TemporaryDirectory() as tmp1, tempfile.TemporaryDirectory() as tmp2:
            sha1 = gne.get_skill_content_sha(self._make_skill_dir(tmp1, files))
            sha2 = gne.get_skill_content_sha(self._make_skill_dir(tmp2, files))
            self.assertEqual(sha1, sha2)

    def test_different_content_gives_different_sha(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp1, tempfile.TemporaryDirectory() as tmp2:
            sha1 = gne.get_skill_content_sha(self._make_skill_dir(tmp1, {"SKILL.md": "v1"}))
            sha2 = gne.get_skill_content_sha(self._make_skill_dir(tmp2, {"SKILL.md": "v2"}))
            self.assertNotEqual(sha1, sha2)

    def test_excludes_evals_directory(self):
        import tempfile
        base_files = {"SKILL.md": "skill content"}
        with tempfile.TemporaryDirectory() as tmp1, tempfile.TemporaryDirectory() as tmp2:
            sha_without = gne.get_skill_content_sha(self._make_skill_dir(tmp1, base_files))
            sha_with_evals = gne.get_skill_content_sha(
                self._make_skill_dir(tmp2, {**base_files, "evals/case.json": '{"id":"test"}'})
            )
            # Adding a file under evals/ must not change the hash
            self.assertEqual(sha_without, sha_with_evals)

    def test_ignores_non_md_py_files(self):
        import tempfile
        base_files = {"SKILL.md": "content"}
        with tempfile.TemporaryDirectory() as tmp1, tempfile.TemporaryDirectory() as tmp2:
            sha1 = gne.get_skill_content_sha(self._make_skill_dir(tmp1, base_files))
            sha2 = gne.get_skill_content_sha(
                self._make_skill_dir(tmp2, {**base_files, "data.csv": "a,b,c"})
            )
            self.assertEqual(sha1, sha2)


class TestWriteRunManifest(unittest.TestCase):
    def test_creates_manifest_file(self, *_):
        import tempfile, os
        with tempfile.TemporaryDirectory() as tmpdir:
            original_runs_dir = gne.RUNS_DIR
            gne.RUNS_DIR = Path(tmpdir)
            try:
                eval_case = {"id": "github-issue-21", "_skill_name": "group-sequential-design"}
                gne.write_run_manifest(eval_case, "claude-sonnet-4-6", "abc123", "dispatched")
                manifest = Path(tmpdir) / "runs.json"
                self.assertTrue(manifest.exists())
                records = json.loads(manifest.read_text())
                self.assertEqual(len(records), 1)
                self.assertEqual(records[0]["eval_id"], "github-issue-21")
                self.assertEqual(records[0]["status"], "dispatched")
            finally:
                gne.RUNS_DIR = original_runs_dir

    def test_appends_to_existing_manifest(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            original_runs_dir = gne.RUNS_DIR
            gne.RUNS_DIR = Path(tmpdir)
            try:
                eval_case = {"id": "github-issue-21", "_skill_name": "gsd"}
                gne.write_run_manifest(eval_case, "model-a", "sha1", "dispatched")
                gne.write_run_manifest(eval_case, "model-b", "sha2", "dispatched")
                records = json.loads((Path(tmpdir) / "runs.json").read_text())
                self.assertEqual(len(records), 2)
            finally:
                gne.RUNS_DIR = original_runs_dir


if __name__ == "__main__":
    unittest.main()
