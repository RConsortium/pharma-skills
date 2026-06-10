---
name: pilot7-weekly-summary
description: Generate a concise weekly progress summary for the RConsortium/submissions-pilot7-synthetic-data repository and post it to the pilot7 Slack channel. Use this for the Friday weekly update on pilot7 synthetic data progress.
---

# Pilot 7 Weekly Summary Skill

This skill automates a weekly progress update for the
[`RConsortium/submissions-pilot7-synthetic-data`](https://github.com/RConsortium/submissions-pilot7-synthetic-data)
repository (R Consortium Submissions Pilot 7 — synthetic SDTM/ADaM/TLF data),
posted to the `#pilot7-sdtm-adam-tlf-bench` Slack channel.

## Configuration

Before running, read `_automation/pilot7-weekly-summary/config.json` to load:
- `repo` — the GitHub repository to summarize
- `max_words` — word limit for the summary (default 200)
- `slack_channel` — Slack channel ID to post to (overridden by `PILOT7_SLACK_CHANNEL` env var)
- `lookback_days` — how many days of activity to include (default 7)

If `PILOT7_SLACK_CHANNEL` is set in the environment, it takes precedence over `config.json`.
If neither is set, **stop and report an error** — do not guess a channel ID.

## Steps

1. **Research Recent Activity**
   - Run from the repository root:
     ```bash
     python3 _automation/pilot7-weekly-summary/scripts/get_weekly_data.py
     ```
   - The script queries the GitHub REST API for the configured repo (no local
     checkout of pilot7 is needed). Set `GH_TOKEN` or `GITHUB_TOKEN` if the
     unauthenticated rate limit is hit.
   - Use the JSON output to identify commits, open/closed issues,
     merged/open PRs, and any releases published this week.

2. **Generate Summary**
   - Write a summary under `max_words` words (from config) in Slack mrkdwn format,
     aimed at the pilot7 working group (statisticians and statistical programmers).
   - Use the following structure:
     *🧪 submissions-pilot7-synthetic-data — week of [DATE]*
     • *Commits:* [count + contributors + one-line highlight]
     • *PRs:* [merged/open count + key change, e.g. data generation, P21 fixes]
     • *Issues:* [opened/closed count + notable item]
     • *Releases:* [tag + name, only if any were published]
     • *TL;DR:* [1–2 sentences on overall momentum and what to watch next week]
   - Skip any section with no activity. If the whole week had no activity,
     post a single line saying so rather than an empty skeleton.
   - Link PR/issue numbers to their GitHub URLs
     (e.g. `<https://github.com/RConsortium/submissions-pilot7-synthetic-data/pull/47|#47>`).
   - Be direct and terse.

3. **Slack Output**
   - Read the Slack channel from the environment variable `PILOT7_SLACK_CHANNEL`,
     falling back to `slack_channel` in `config.json`.
   - Post the summary to that channel using an available Slack integration tool.

4. **File Output**
   - Save the summary as a markdown file:
     `/sessions/[session-dir]/mnt/outputs/pilot7-weekly-summary-[YYYY-MM-DD].md`
     (or `outputs/pilot7-weekly-summary-[YYYY-MM-DD].md` if no session mount exists —
     do **not** commit this file to the repo).
   - Output the path to the saved file so the user can review it.
