# pharma_skills — Agent Instructions

## Repository Overview

This repository is a collection of agent skills for pharmaceutical R&D, built for Claude Code and compatible LLM agents. Skills follow the [agentskills.io](https://agentskills.io) specification.

## Directory Structure

```
pharma_skills/
├── group-sequential-design/   ← Clinical trial design skill
│   ├── SKILL.md               ← Agent workflow instructions
│   ├── evals/evals.json       ← Benchmark test cases
│   └── scripts/               ← Supporting R and Python scripts
├── admiral/                   ← admiral ADaM derivation skill family
│   ├── SKILL.md               ← Shared conventions (date rules, flags, QC)
│   ├── admiral-adsl/          ← Subject-level dataset (ADSL)
│   ├── admiral-bds/           ← BDS findings datasets (ADVS, ADLB)
│   └── admiral-adae/          ← Adverse events dataset (ADAE)
├── _automation/               ← Automation skills (see below)
│   ├── benchmark-runner/      ← A/B benchmark orchestration
│   ├── issue-to-eval/         ← GitHub Issue → evals.json converter
│   ├── weekly-summary/        ← Weekly activity → Slack
│   └── pilot7-weekly-summary/ ← Pilot 7 weekly activity → Slack (Friday)
└── .github/
    ├── ISSUE_TEMPLATE/benchmark.md  ← Template for benchmark issues
    └── workflows/             ← CI: skill validation + benchmark scheduling
```

## Available Skills and Trigger Phrases

| Skill | When to invoke |
|---|---|
| `group-sequential-design` | "design a Phase 3 trial", "group sequential design", "alpha spending", "interim analysis planning" |
| `admiral/admiral-adsl` | "derive ADSL", "create subject-level dataset", "admiral ADSL" |
| `admiral/admiral-bds` | "derive ADVS", "derive ADLB", "vital signs dataset", "lab dataset", "BDS findings", "admiral BDS" |
| `admiral/admiral-adae` | "derive ADAE", "adverse events dataset", "TEAE flag", "treatment-emergent", "admiral ADAE" |
| `benchmark-runner` | "run benchmarks", "compare skill performance", "eval the skills" |
| `benchmark-summary` | "update the benchmark summary", "generate benchmark analysis", "summarize skill vs no-skill results", "add failure patterns", produce `benchmark_analysis_*.md` |
| `issue-to-eval` | "parse this issue into a benchmark", "sync all benchmark issues" |
| `weekly-summary` | "generate weekly summary", "post to Slack" |
| `pilot7-weekly-summary` | "pilot7 weekly update", "summarize pilot7 progress", "submissions-pilot7-synthetic-data weekly summary" |

## Agent Guardrails

- **Do NOT edit `evals/evals.json` directly.** Use the `issue-to-eval` skill to add or update evaluation cases from GitHub Issues.
- **Do NOT run `benchmark-runner` unless explicitly requested.** It spawns sub-agents and posts to GitHub Issues.
- **Do NOT modify files in `_automation/` unless the task specifically targets automation.** The automation skills are self-contained.
- When running scripts, invoke them from the repository root so relative paths resolve correctly.

## Environment Variables

| Variable | Used by | Purpose |
|---|---|---|
| `PHARMA_SKILLS_SLACK_CHANNEL` | `weekly-summary` | Slack channel ID for posting. If unset, the skill reads from `_automation/weekly-summary/config.json`. |
| `PILOT7_SLACK_CHANNEL` | `pilot7-weekly-summary` | Slack channel ID for posting. If unset, the skill reads from `_automation/pilot7-weekly-summary/config.json`. |

## Contributing

See `LIFECYCLE.md` for the full skill development lifecycle (Design → Development → Evaluation → Release).

---

## Combined Benchmark Summary Format

The output format (three-section structure, selection rules, verdict icons, failure pattern template, priority scale) is defined in `_automation/benchmark-summary/SKILL.md`. Read that file when producing or updating a benchmark summary.

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
