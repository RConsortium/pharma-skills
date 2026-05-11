# AUTO.md — Self-contained runbook for the local A/B benchmark

You are an agent. Read this file and execute the steps below. **You do not
need to read the scripts in this directory unless you meet errors.** Their behavior, inputs, and
outputs are documented here. Follow the following instruction to run the evaluation

---

## GitHub Access — Use Whichever Method Works

Throughout this skill you will read issue comments, post issue comments, and create release assets. **Use whatever method is available in your environment** — pick the one that works without prompting:

| Method | Best when | Notes |
|---|---|---|
| `mcp__github__*` MCP tools | Running inside Claude Code with the GitHub MCP server | No token required; preferred when available |
| `gh` CLI (`gh issue view`, `gh release upload`, etc.) | Running locally with `gh` authenticated | Concise, supports all operations |
| REST API via `curl` | Anywhere with `GH_TOKEN` / `GITHUB_TOKEN` set | Universal fallback; use for release-asset upload (no MCP equivalent) |
| Provider-specific GitHub tools (Codex, Gemini, etc.) | Running under another agent CLI | Use whatever the host provides |

Reason about which method to use; do not enforce a rigid order. If one fails, try another. Always confirm the operation succeeded (e.g., the comment URL came back, the asset was uploaded) before continuing.

For release-asset upload there is currently no MCP tool — use `gh release upload` or `curl` POST to the upload URL.

---

## 1. R Environment Pre-flight
Always run first. Idempotent — safe to re-run.
```bash
bash _automation/benchmark-runner/scripts/setup_r_env.sh
```

Exits non-zero on failure — stop and report the error. Do not proceed.

## 2. Set up Next Eval

`{CURRENT_MODEL_NAME}` is the model ID you want benchmarked (e.g. `claude-sonnet-4-6`, `claude-opus-4-7`). Capture the bench-dir path the script prints on its final stdout line — Steps 3 and 4 need it.

```bash
bench_dir=$(bash _automation/benchmark-runner/scripts/auto_run/prep_ab.sh --model {CURRENT_MODEL_NAME})
```
Optional flags:
```bash
--runner-id {YOUR_NAME}           # stable per-person ordering
--priority-issue github-issue-{N} # force a specific eval (N = issue number)
```

If the dispatcher prints `STATUS: UP_TO_DATE`, there is no pending eval for this model — stop here.

---

## 3. Stage — run agents

Runs Agent A (with skill) and Agent B (without skill) in parallel for the prepared issue;
JSON results land in `agent_{A,B}/run.json` and artifacts in
`agent_{A,B}/output_{A,B}/`.

```bash
_automation/benchmark-runner/scripts/auto_run/run_agents_ab.sh "$bench_dir" --model {CURRENT_MODEL_NAME}
```

## 4. Stage — evaluation
Post as a **new comment** using whichever GitHub access method is available (see "GitHub Access" above). 

```bash
_automation/benchmark-runner/scripts/auto_run/evaluate_ab.sh "$bench_dir"
```
