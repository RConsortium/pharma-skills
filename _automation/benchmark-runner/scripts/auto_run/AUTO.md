# AUTO.md — Self-contained runbook for the local A/B benchmark

You are an agent. Read this file and execute the steps below. **You do not
need to read the scripts in this directory unless you meet errors.** Their behavior, inputs, and
outputs are documented here.

---

## 1. Resolve inputs

| Input | How to determine it |
|---|---|
| `MODEL` | Canonical API model ID for **your own runtime** (e.g. `claude-sonnet-4-6`, `claude-opus-4-7`, `gemini-3-pro-preview`). Read from your Runtime Context — never use a display name. |

Verify the environment is provisioned:

- `R --version` shows ≥ 4.4
- `claude --version` works (Claude Code CLI on `PATH`)
- Optional: `gh auth status` succeeds (needed for dedup, `--upload`, `--post`)

If any prerequisite is missing, **stop and report** — do not install system
packages without explicit user permission.

---

## 2. Stage — prep
set EVAL_ID to github-issue-60 then run following
```bash
bench_dir=$(_automation/benchmark-runner/scripts/auto_run/prep_ab.sh \
              ${EVAL_ID:+"$EVAL_ID"} --model "$MODEL")
```

---

## 3. Stage — run agents

Runs Agent A (with skill) and Agent B (without skill) in parallel via
`claude -p`. Per-arm progress is redirected to `agent_{A,B}/runner.log`;
JSON results land in `agent_{A,B}/run.json` and artifacts in
`agent_{A,B}/output_{A,B}/`.

```bash
_automation/benchmark-runner/scripts/auto_run/run_agents_ab.sh "$bench_dir"
```
