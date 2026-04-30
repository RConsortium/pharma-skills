---
name: benchmark-summary
description: Generate a combined benchmark analysis for the group-sequential-design skill by reading all benchmark GitHub issues, selecting the latest completed run per issue, and producing a structured three-section report (summary table + overall scorecard + failure pattern analysis). Use this skill whenever the user asks to update the benchmark summary, generate the benchmark analysis, summarize skill vs no-skill results, add failure patterns, or produce `benchmark_analysis_YYYY-MM-DD.md`. Always invoke for any request to compare skill performance across issues over time.
---

# Benchmark Summary Skill

Produce the combined benchmark analysis document for `RConsortium/pharma-skills`. This involves reading benchmark results that live as comments on GitHub issues, selecting the right run for each, and synthesizing them into a structured report following the format defined in `CLAUDE.md`.

Repository: `RConsortium/pharma-skills`  
Output file: `benchmark_analysis_YYYY-MM-DD.md` in the repo root  
GitHub issue: post to `RConsortium/pharma-skills` after saving locally

---

## Step 1 — Discover all benchmark issues

List every open issue with a `[benchmark]` title prefix:

```bash
gh issue list --repo RConsortium/pharma-skills --limit 100 --json number,title,state \
  | jq '[.[] | select(.title | startswith("[benchmark]"))]'
```

Collect the issue numbers. Also fetch non-prefixed benchmark issues that are known eval cases (e.g. issues identified in prior summaries). When in doubt, fetch the issue and check whether it contains an "Automated Benchmark Results" comment.

---

## Step 2 — Fetch results for each issue

For each issue number, fetch all comments:

```bash
gh issue view <N> --repo RConsortium/pharma-skills --comments
```

Each benchmark result comment contains a **Run Metadata** table with:
- `Run date` — use this to order runs chronologically
- `Model` — collapse as described in Step 3
- A **Scorecard** table with With Skill / Without Skill scores
- A **Verdict** paragraph

Collect all result comments per issue. There may be multiple runs (different models or re-runs).

---

## Step 3 — Select the latest completed run per issue

Apply these rules in order to choose one run per issue:

**Exclude a run if any of these apply:**
- The scorecard note says "Partial run", "timeout", "rate-limit", "hit limit", or similar
- Both agents produced no output files
- The run was terminated before either agent finished
- The comment explicitly notes the run was superseded by a later one

**From the remaining completed runs, pick the most recent** by `Run date`.

**Model name normalisation** — collapse version suffixes for display:
- `claude-sonnet-4-6`, `claude-sonnet-4-7` → **Claude Sonnet**
- `claude-opus-4-5`, `claude-opus-4-7` → **Claude Opus**
- `claude-haiku-*` → **Claude Haiku**
- `gemini-*-flash*` → **Gemini Flash**
- `gemini-*-pro*` → **Gemini Pro**

---

## Step 4 — Build the three-section document

Follow the exact format specified in `CLAUDE.md` ("Combined Benchmark Summary Format"). Read that section now if not already in context.

### Section 1 — Benchmark Summary Table

One row per issue. Columns: Issue, Scenario, Run Date, Model, With Skill (score%), Without Skill (score%), Verdict.

- Verdict icon: ✅ skill wins, ❌ no-skill wins, ➕ tie
- For no-skill wins, parenthetically classify as **skill scope gap** (wrong framework applied) or **orchestration/environment bug** (not a content failure)
- After the table, add a note listing excluded runs and why

### Section 2 — Overall Scorecard

Count wins/ties from the table. Compute average score for each column, excluding issues where the only assertion is a trivial sanity check (e.g. a dry-run confirming a basic statistical fact). Note which issues were excluded from the average and why.

Include:
- Win/tie/loss counts
- Avg score (with exclusions noted)
- A table explaining each no-skill win
- Bullet list of consistent skill strengths drawn from the evidence

### Section 3 — Failure Pattern Analysis

Identify recurring failure modes across issues. For each pattern:

- Name it concisely
- List affected issues and scenarios
- State the verdict (who won, what the data shows)
- Describe what specifically went wrong, with evidence from the runs
- State the root cause (which file is missing the fix: `SKILL.md`, `reference.md`, `examples.md`, `post_design.md`)
- Propose a concrete fix (which file, what to add, example wording)
- Assign a priority using this scale:
  - **P0** — skill produces scientifically invalid output without warning
  - **P1** — skill silently uses wrong methodology or estimand
  - **P2** — skill produces correct but sub-optimal design, or execution reliability issue
  - **P3** — gap partially mitigated by skill; fix closes residual risk

Close with a Priority Summary table.

Patterns to always check for (add others as evidence warrants):
- Scope gate missing (skill applies GSD to out-of-scope design)
- Competing-risks detection absent
- Post-design timing checks missing
- Prompt bundle size / misrouting
- Verification simulation not enforced
- Load-bearing reference files at risk during refactoring

---

## Step 5 — Save locally and post to GitHub

**Save locally:**

```
benchmark_analysis_YYYY-MM-DD.md
```

in the repo root (`C:/Users/zhangp/pharma-skills/pharma-skills/` on this machine). Use today's date.

**Post to GitHub** (requires user confirmation before posting):

```bash
gh issue create \
  --repo RConsortium/pharma-skills \
  --title "[analysis] Benchmark failure pattern analysis — group-sequential-design skill (YYYY-MM-DD)" \
  --body "$(cat benchmark_analysis_YYYY-MM-DD.md)"
```

Report the issue URL after posting.

---

## Incremental updates

If a prior `benchmark_analysis_*.md` already exists in the repo root, read it first. For each issue already in the prior summary, only re-fetch and update the row if a newer completed run exists on GitHub since the prior summary date. For new issues not yet in the prior summary, add them. Carry forward failure patterns from the prior summary and update or add new ones based on any new evidence.

This allows the summary to grow incrementally without re-reading every issue from scratch each time.
