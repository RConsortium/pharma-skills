# pharma_skills — Agent Instructions

## Repository Overview

This repository is a collection of agent skills for pharmaceutical R&D, built for Claude Code and compatible LLM agents. Skills follow the [agentskills.io](https://agentskills.io) specification.

## Directory Structure

```
pharma_skills/
├── group-sequential-design/   ← Main clinical trial design skill
│   ├── SKILL.md               ← Agent workflow instructions
│   ├── evals/evals.json       ← Benchmark test cases
│   └── scripts/               ← Supporting R and Python scripts
├── _automation/               ← Automation skills (see below)
│   ├── benchmark-runner/      ← A/B benchmark orchestration
│   ├── issue-to-eval/         ← GitHub Issue → evals.json converter
│   └── weekly-summary/        ← Weekly activity → Slack
└── .github/
    ├── ISSUE_TEMPLATE/benchmark.md  ← Template for benchmark issues
    └── workflows/             ← CI: skill validation + benchmark scheduling
```

## Available Skills and Trigger Phrases

| Skill | When to invoke |
|---|---|
| `group-sequential-design` | "design a Phase 3 trial", "group sequential design", "alpha spending", "interim analysis planning" |
| `benchmark-runner` | "run benchmarks", "compare skill performance", "eval the skills" |
| `benchmark-summary` | "update the benchmark summary", "generate benchmark analysis", "summarize skill vs no-skill results", "add failure patterns", produce `benchmark_analysis_*.md` |
| `issue-to-eval` | "parse this issue into a benchmark", "sync all benchmark issues" |
| `weekly-summary` | "generate weekly summary", "post to Slack" |

## Agent Guardrails

- **Do NOT edit `evals/evals.json` directly.** Use the `issue-to-eval` skill to add or update evaluation cases from GitHub Issues.
- **Do NOT run `benchmark-runner` unless explicitly requested.** It spawns sub-agents and posts to GitHub Issues.
- **Do NOT modify files in `_automation/` unless the task specifically targets automation.** The automation skills are self-contained.
- When running scripts, invoke them from the repository root so relative paths resolve correctly.

## Environment Variables

| Variable | Used by | Purpose |
|---|---|---|
| `PHARMA_SKILLS_SLACK_CHANNEL` | `weekly-summary` | Slack channel ID for posting. If unset, the skill reads from `_automation/weekly-summary/config.json`. |

## Contributing

See `LIFECYCLE.md` for the full skill development lifecycle (Design → Development → Evaluation → Release).

---

## Combined Benchmark Summary Format

When asked to produce or update the benchmark summary, generate a document (and optionally a GitHub issue) following this exact structure. Save it as `benchmark_analysis_YYYY-MM-DD.md` in the repo root.

### Selection rules

- **One row per benchmark issue.** Use the **latest completed run** for each issue — ignore runs marked partial, timeout, rate-limit hit, or where both agents produced no output.
- **Do not treat `claude-sonnet-4-7` as a different model** from `claude-sonnet-4-6`; list both simply as "Claude Sonnet". Similarly collapse minor version suffixes (e.g. `claude-opus-4-7` → "Claude Opus").
- For each issue, record: run date, model, with-skill score (fraction + %), without-skill score, and a one-sentence verdict.

### Section 1 — Benchmark Summary Table

```markdown
## Benchmark Summary: Latest Completed Run per Issue (Skill vs No Skill)

| Issue | Scenario | Run Date | Model | With Skill | Without Skill | Verdict |
|-------|----------|----------|-------|-----------|--------------|---------|
| #N | <short description> | YYYY-MM-DD | <model> | X% (n/d) | Y% (n/d) | ✅/❌/➕ <one sentence> |
```

Verdict icons: ✅ = skill wins, ❌ = no-skill wins, ➕ = tie.

For no-skill wins, always add a parenthetical explaining whether it is a **skill scope gap** (wrong framework applied) or an **orchestration/environment bug** (not a content failure).

At the bottom of the table, add a note listing any excluded runs and why (partial, timeout, no output).

### Section 2 — Overall Scorecard

```markdown
## Overall Scorecard

| | With Skill | Without Skill |
|--|------------|--------------|
| **Wins** | N | N |
| **Ties** | N | N |
| **Avg score (excl. trivial)** | X% | Y% |

**The N no-skill wins are all structural skill gaps, not base model superiority:**

| Issue | No-skill win reason |
|-------|-------------------|
| #N | <one line> |

**What the benchmarks confirm the skill does well:**
- <bullet per consistent value driver>
```

Exclude issues with a trivial assertion (e.g. a dry-run with a single sanity-check assertion) from the average score calculation; note which issues were excluded.

### Section 3 — Failure Pattern Analysis

For each failure pattern, use this template:

```markdown
### Pattern N — <Short name>

**Affects:** #N, #N (scenario names)
**Verdict:** <skill wins / no-skill wins / both fail> — <one sentence on what the data shows>

<Two to four sentences describing what went wrong, with specific evidence from the benchmark runs.>

**Root cause:** <One sentence identifying the specific gap in SKILL.md / reference.md / examples.md / post_design.md.>

**Recommended fix:** <Concrete change — which file, what to add/change, example wording if helpful.>

**Priority:** P0 / P1 / P2 / P3 — <one-line justification>
```

Priority scale:
- **P0** — skill produces scientifically invalid or dangerous output for in-scope inputs
- **P1** — skill silently produces incorrect methodology (wrong framework, wrong estimand)
- **P2** — skill produces a correct but sub-optimal design, or execution reliability issue
- **P3** — gap already partially mitigated by skill; fix prevents residual risk

End the section with a **Priority Summary** table:

```markdown
## Priority Summary

| Pattern | Issues affected | Skill wins? | Priority |
|---------|----------------|-------------|----------|
| N. <name> | #N, #N | ✅/❌/Weak | **PN** — <one-line reason> |
```

---

## Local Benchmark Conventions (Windows)

This repo is cloned at `C:/Users/zhangp/pharma-skills/pharma-skills/`. All benchmark work runs from that directory. The GitHub issues being benchmarked live at https://github.com/RConsortium/pharma-skills/issues.

### Output directories

Agent outputs go directly in the repo root — **do not use `/tmp/`**:

```
output_{issue_id}_A/    ← Agent A (with skill)
output_{issue_id}_B/    ← Agent B (without skill)
```

Example for issue 74: `output_74_A/` and `output_74_B/`.

### R environment

R 4.4.1 is installed at `C:/Program Files/R/R-4.4.1/`. All required packages (`gsDesign`, `gsDesign2`, `lrstat`, `graphicalMCP`, `eventPred`, `ggplot2`, `jsonlite`, `digest`) are pre-installed.

- **Skip `setup_r_env.sh`** — it uses `apt`/`sudo` which are unavailable on this machine.
- In Bash, use the full path: `"/c/Program Files/R/R-4.4.1/bin/Rscript.exe" script.R`
- Via PowerShell: `& "C:\Program Files\R\R-4.4.1\bin\Rscript.exe" script.R`
- Calling `Rscript` without the full path in bash causes a segfault on this machine.

### Benchmark runner — Step 2 (local override)

Replace the `/tmp/benchmark_{id}/` directory layout from SKILL.md with:

```bash
# Create output dirs in the repo root
mkdir -p output_{id}_A output_{id}_B

# Run Agent A (with skill) from repo root
cat prompt_A.txt | claude -p --verbose --model claude-sonnet-4-6 \
  --allowedTools "Bash,Read,Write,Edit,Glob" \
  --output-format stream-json 2>&1 | tee agent_{id}_A_run.jsonl

# Run Agent B (without skill) from repo root
cat prompt_B.txt | claude -p --verbose --model claude-sonnet-4-6 \
  --allowedTools "Bash,Read,Write,Edit,Glob" \
  --output-format stream-json 2>&1 | tee agent_{id}_B_run.jsonl
```

Prompt files and JSONL logs can be staged in `C:/Users/zhangp/AppData/Local/Temp/` to avoid committing them.

Note `--verbose` is required when using `--output-format stream-json` with `claude -p`.

Agent A's prompt is ~236 KB (bundled skill resources). Set `CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000` to avoid the default 32K output cap being hit mid-response:

```bash
CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 cat prompt_A.txt | claude -p --verbose ...
```

Output-cap hits are usually caused by the agent doing too much in one turn (write script + run + write report all bundled). The skill itself handles this via the **Pacing — one artifact per turn** rule in `group-sequential-design/SKILL.md`. If you see `max_tokens` truncation, fix it by tightening that rule, not by raising the cap further (64K is the model ceiling).

### Benchmark runner — Step 4 (archive)

Zip from the repo root:

```bash
zip -r benchmark_results_{eval_id}.zip output_{id}_A/ output_{id}_B/ \
  agent_{id}_A_run.jsonl agent_{id}_B_run.jsonl
```
