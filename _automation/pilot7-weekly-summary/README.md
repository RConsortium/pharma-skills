# Pilot 7 Weekly Summary

Generates a weekly progress update for
[`RConsortium/submissions-pilot7-synthetic-data`](https://github.com/RConsortium/submissions-pilot7-synthetic-data)
and posts it to the `#pilot7-sdtm-adam-tlf-bench` Slack channel
(`C0B44HS7CNA`).

- `SKILL.md` — agent workflow instructions
- `config.json` — target repo, Slack channel, word limit, lookback window
- `scripts/get_weekly_data.py` — fetches commits/PRs/issues/releases from the
  GitHub REST API (no local checkout of pilot7 required)

## Running manually

Point an agent at `SKILL.md`, or fetch the raw data yourself:

```bash
python3 _automation/pilot7-weekly-summary/scripts/get_weekly_data.py
```

The script works unauthenticated for the public pilot7 repo; set `GH_TOKEN`
or `GITHUB_TOKEN` to raise the API rate limit.

## Scheduling as a Claude Code Routine (Friday afternoon)

Go to [claude.ai/code/routines](https://claude.ai/code/routines) → **New routine**:

| Field | Value |
|---|---|
| **Repository** | `RConsortium/pharma-skills` |
| **Environment** | Any environment with default network access and the Slack integration enabled (R is **not** required for this skill) |
| **Trigger** | Schedule — weekly, **Friday at 16:00 (America/New_York)** |
| **Prompt** | See below |

Routine prompt:

```
Generate the weekly progress summary for RConsortium/submissions-pilot7-synthetic-data.
Follow the instructions in _automation/pilot7-weekly-summary/SKILL.md exactly.
Post the summary to the configured Slack channel.
```

After creating the routine, click **Run now** once to verify that the GitHub
API is reachable and the summary lands in the Slack channel.

To redirect the post (e.g. for testing), set `PILOT7_SLACK_CHANNEL` in the
environment config — it overrides `slack_channel` in `config.json`.
