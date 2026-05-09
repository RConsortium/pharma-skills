# AUTO.md — Self-contained runbook for the local A/B benchmark

You are an agent. Read this file and execute the steps below. **You do not
need to read the scripts in this directory unless you meet errors.** Their behavior, inputs, and
outputs are documented here. Follow the following instruction to run the evaluation

---

## 1. R Environment Pre-flight
Always run first. Idempotent — safe to re-run.
```bash
bash _automation/benchmark-runner/scripts/setup_r_env.sh
```

Exits non-zero on failure — stop and report the error. Do not proceed.

## 2. Set up Next Eval

```bash
bash _automation/benchmark-runner/scripts/auto_run/prep_ab.sh --model  {CURRENT_MODEL_NAME}
```
Optional flags:
```bash
--runner-id {YOUR_NAME}           # stable per-person ordering
--priority_issue github-issue-{N} # force a specific eval
```
---

## 3. Stage — run agents

Runs Agent A (with skill) and Agent B (without skill) in parallel for the prepared issue;
JSON results land in `agent_{A,B}/run.json` and artifacts in
`agent_{A,B}/output_{A,B}/`.

```bash
_automation/benchmark-runner/scripts/auto_run/run_agents_ab.sh "$bench_dir"
```
