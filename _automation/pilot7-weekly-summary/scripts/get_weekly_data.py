"""Collect weekly activity data for the repo configured in config.json.

Unlike weekly-summary/scripts/get_weekly_data.py, this script targets a
remote repository (it does not assume a local checkout), so all data is
fetched from the GitHub REST API. Works unauthenticated for public repos;
set GH_TOKEN or GITHUB_TOKEN to raise the rate limit or access private repos.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

CONFIG_PATH = Path(__file__).resolve().parents[1] / "config.json"
API_ROOT = "https://api.github.com"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {}


def api_get(path: str, params: dict | None = None):
    """GET a GitHub API path and return parsed JSON. Exit with error on failure."""
    url = f"{API_ROOT}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url)
    request.add_header("Accept", "application/vnd.github+json")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError) as e:
        print(f"Error: GitHub API request failed: {url}\n{e}", file=sys.stderr)
        sys.exit(1)


def get_weekly_data() -> dict:
    config = load_config()
    repo: str = config["repo"]
    lookback_days: int = config.get("lookback_days", 7)
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=lookback_days)
    since_date = since.strftime("%Y-%m-%d")

    commits = api_get(
        f"/repos/{repo}/commits",
        {"since": since.strftime("%Y-%m-%dT%H:%M:%SZ"), "per_page": 100},
    )
    commits_summary = [
        {
            "sha": c["sha"][:7],
            "message": c["commit"]["message"].split("\n")[0],
            "author": (c.get("author") or {}).get("login")
            or c["commit"]["author"]["name"],
        }
        for c in commits
    ]

    issues_result = api_get(
        "/search/issues",
        {"q": f"repo:{repo} is:issue updated:>={since_date}", "per_page": 100},
    )
    issues_summary = [
        {"number": i["number"], "title": i["title"], "state": i["state"]}
        for i in issues_result.get("items", [])
    ]

    prs_result = api_get(
        "/search/issues",
        {"q": f"repo:{repo} is:pr updated:>={since_date}", "per_page": 100},
    )
    prs_summary = [
        {
            "number": pr["number"],
            "title": pr["title"],
            "state": pr["state"],
            "merged": bool((pr.get("pull_request") or {}).get("merged_at")),
        }
        for pr in prs_result.get("items", [])
    ]

    releases = api_get(f"/repos/{repo}/releases", {"per_page": 20})
    releases_summary = [
        {"tag": r["tag_name"], "name": r["name"], "published_at": r["published_at"]}
        for r in releases
        if r.get("published_at") and r["published_at"] >= since.strftime("%Y-%m-%dT%H:%M:%SZ")
    ]

    return {
        "repo": repo,
        "week_starting": since_date,
        "week_ending": now.strftime("%Y-%m-%d"),
        "commits": {
            "total_count": len(commits_summary),
            "authors": sorted({c["author"] for c in commits_summary}),
            "highlights": commits_summary[:10],
        },
        "issues": {
            "total_updated": len(issues_summary),
            "list": issues_summary,
        },
        "pull_requests": {
            "total_updated": len(prs_summary),
            "list": prs_summary,
        },
        "releases": {
            "total_published": len(releases_summary),
            "list": releases_summary,
        },
    }


if __name__ == "__main__":
    print(json.dumps(get_weekly_data(), indent=2))
