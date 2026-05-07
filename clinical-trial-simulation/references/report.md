# Simulation Report — Structure for QC

This file describes how to write the simulation report at the end of
the workflow. **It is the policy hook for organizational
customization** — edit this file to encode your group's reporting
standards. Defaults below are reasonable starting points.

## Purpose

The report is what the user reads. It serves three purposes:

1. **Answer the research questions.** Operating characteristics
   presented next to the questions they answer.
2. **Enable QC.** A reviewer audits each piece incrementally — code,
   rationale, and result side by side.
3. **Reproducibility.** The report plus the script is enough to rerun
   the simulation and get the same results.

## Self-containment rule

**Every report must be readable end-to-end without consulting any
other report or external file.** When two simulation runs share
design elements (boundaries, milestone triggers, accrual schedule,
arm structure), each report **inlines the full code and literals
itself** — never write "identical to the other run, see X" or
"reuses the boundaries from run Y, see file Z".

Cross-references are acceptable only for *narrative framing* (e.g.,
"this run extends the question raised in the NPH report") — never
for code, parameter values, boundary literals, or anything a
reviewer would need to verify the design. If a reviewer can't
reproduce the simulation from this report alone, the report has
failed its QC purpose.

This sometimes means duplicating a code block across reports.
Duplication is fine; broken cross-references at audit time are not.

## Structure: build-order spine

Mirror the build order in the report. The agent assembled the
simulation block by block; the report walks the reader through the
same sequence. Each section pairs (a) the relevant code snippet,
(b) a short paragraph explaining what was implemented and the
parameters used, (c) caveats inline if any.

```
0. Cost and token usage           — top of report; session-total tokens + cost
0.5 Run artifacts                 — file tree + reproduction recipe
1. Why this design                — opening rationale (thought trail)
2. Confirmed parameters           — single source of truth (table)
2.5 Boundary computation          — only if external tools (rpact /
                                    gsDesign / multcomp / ...) were used
3. Arms (with endpoints)          — per arm: endpoint(...) calls +
                                    arm() + add_endpoints(), bundled
4. Trial setup                    — n, duration, accrual, dropout, stratification
5. Milestones                     — per milestone (trigger + action summary)
6. Action functions               — per action (full body verbatim)
7. Operating characteristics      — mapped back to research questions
8. Caveats and limitations        — placeholders, stubs, helper-dependencies
```

The build-order sections that have a clear *design* meaning (3-7)
each pair a code block with explanation. **The listener and the
`controller(...) / controller$run()` calls are plumbing — omit them
from the report.** They are identical across designs and add noise to
the audit trail.

### Code style in the report

Code blocks in the report are for review, not just illustration. Two
rules:

- **One statement per line.** Never chain with `;`. A reviewer must
  be able to scan the code block top to bottom and comment on
  individual lines.
- **Show the code as it actually appears in the script** — same
  variable names, same arguments, same line breaks. The report is
  the script narrated, not a paraphrase.

### 0. Cost and token usage (at the very top of the report)

A small table reporting the total token usage and cost for the
entire session — from the moment `/simulate` was invoked to the
moment the report is generated. The user wants to see this without
having to run any extra command.

The agent retrieves these via whatever telemetry is available in the
running environment. Likely paths in Claude Code:

- **`/cost` slash command output** — if the agent can capture it
  (read the conversation log, parse a recent `/cost` invocation).
- **Session JSONL log** at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`
  — each turn typically records `usage` with `input_tokens`,
  `output_tokens`, `cache_creation_input_tokens`,
  `cache_read_input_tokens`. Sum across turns; multiply by the
  model's per-token rate.
- **Telemetry directory** at `~/.claude/telemetry/` if usage events
  are emitted there.

Use the recorded model name to look up the rate. If multiple models
were used in the session (rare), sum their costs.

If automated retrieval genuinely isn't possible, leave the placeholder
table and one line asking the user to run `/cost` and paste the
numbers — but make a real effort first.

Recommended format:

| Metric | Value |
|---|---|
| Input tokens | ... |
| Output tokens | ... |
| Cache read tokens | ... |
| Cache write tokens | ... |
| Total cost (USD) | $... |
| Model | claude-opus-4-7 (or actual) |
| Session duration | hh:mm |
| TrialSimulator version | required; capture via `packageVersion("TrialSimulator")` |
| R version | e.g., `4.5.2` |

### 0.5 Run artifacts

A `tree`-style listing of every file produced by this run, each
annotated with its size and a one-line purpose, followed by a 2–3
line shell recipe to reproduce the outputs from the scripts. Keeps
the reviewer oriented on *where to look* before diving into the
design.

Two parts:

**File tree.** Each entry is `name` + `size` + brief description.
Sizes are useful as a quick sanity check (a 0-byte `output.rds`
signals a failed run; the rds size also conveys dimensionality).
Filenames must match the `Output organization` section of `SKILL.md`
exactly. Files that don't apply to a given design are omitted, not
shown empty (no `actions.R` if no non-doNothing actions; no
`boundaries.R` if no external boundary tool; etc.).

**Reproduction recipe.** A short block of `Rscript` calls answering
"if I delete the .rds files, can I recover them?" Order matters:
boundaries first (if used) since they emit the literals that
`main.R` hardcodes; then `main.R` to regenerate the simulation
output; then the HTML re-render. Adapt the recipe to the files that
exist for this run.

**Worked example:**

````
runs/<trial_name>/
├── scripts/
│   ├── boundaries.R    1.5K   rpact / gsDesign boundary derivation (run once)
│   ├── actions.R       7.8K   one entry per action function
│   └── main.R          7.8K   endpoints, arms, trial, milestones,
│                              listener, controller, run, OC summary
├── output.rds          198K   raw controller$get_output() (1000 reps)
├── oc_summary.rds      6.4K   OC list saved by main.R for the report
├── report.md           21K    this document (source of truth)
└── report.html         31K    rendered via markdown::mark_html
````

```sh
Rscript scripts/boundaries.R          # once, to confirm boundary literals
Rscript scripts/main.R                # regenerates output.rds, oc_summary.rds
Rscript -e 'markdown::mark_html("report.md", output = "report.html")'
```

### 1. Why this design

A short paragraph (3-6 sentences) capturing the reasoning that led to
this design.

- **Mode A (exploration):** include the alternatives that were
  considered and briefly why each was set aside. This is a thought
  trail — visible reasoning is more auditable than polished claims.
- **Mode B (implementation):** restate the user's brief in the
  agent's words so the user can confirm the interpretation.

### 2. Confirmed parameters

A single table that is the source of truth for every value used in
the simulation. Subsequent sections reference this table rather than
restating numbers.

**Required columns: three.** Every row must populate all three.

| Column | What goes here |
|---|---|
| **Parameter** | Short name of the parameter, in clinical/statistical terms (not the R variable name unless they happen to match). |
| **Value** | The exact value used in the simulation (number, expression, distribution + parameters, data.frame literal, helper-derived literal). |
| **Source / Notes** | Where the value came from. Pick the most specific applicable category from the controlled vocabulary below. |

**Source / Notes — controlled vocabulary** (use one; combine with a short explanation when needed):

- **`user`** — copied verbatim from the user's spec.
- **`user (translated)`** — user-provided in clinical terms, mechanically translated to a TS-compatible form. Show the translation, e.g. *"15% dropout by mo 50 → `rate = -log(0.85)/50`"*.
- **`inferred`** — the user did not specify; the agent picked a sensible default. State the default and why in one phrase, e.g. *"inferred — ORR readout typical of solid-tumor trials"*. **Inferred values must be confirmed (or at least surfaced) with the user before expensive runs.**
- **`derived`** — computed from other parameters in this table or from a helper. Cite the source, e.g. *"derived: `solveThreeStateModel(median_pfs=7, median_os=15, corr=0.68) → h01 = 0.0750`"*, or *"derived from `boundaries.R` (rpact)"*.
- **`package convention`** — a default the package or skill prescribes (e.g., `seed = NULL`, `silent = TRUE`, `plot_event = FALSE`). Brief; no rationale needed.
- **`stub`** / **`DUMMY`** — a placeholder decision rule, combination test, or boundary that needs replacement before the design is finalized. **Highlight prominently** (bold, prefix `STUB:`, or both) so reviewers cannot miss it.

Always include rows for: endpoint distribution parameters per arm, readout times for non-TTE endpoints, correlation structure (and the generator implementing it), sample size, duration, accrual schedule, dropout, stratification factors, milestone trigger thresholds, and any helper-derived literals.

**Worked example:**

| Parameter | Value | Source / Notes |
|---|---|---|
| N (1:1) | 500 | user |
| Accrual | uniform 20/mo (`StaggeredRecruiter`, `accrual_rate = data.frame(end_time=Inf, piecewise_rate=20)`) | user |
| Dropout | exponential, `rate = -log(0.85)/50 = 0.003250` | user (translated): "15% by mo 50" |
| ORR readout | 6 mo | inferred — typical solid-tumor first response assessment; confirm before production |
| PFS — control | `rexp(rate = log(2)/20)` | user |
| PFS — treatment, 6-mo delay scenario | `PiecewiseConstantExponentialRNG(risk = data.frame(end_time=c(6,1000), piecewise_risk=c(log(2)/20, 0.55*log(2)/20)))` | derived from user's NPH spec; `tail_end = 1000` per package gotcha |
| GSD efficacy bounds (z) | (3.0204, 2.3762, 2.0303) at IF (0.49, 0.75, 1.00) | derived from `boundaries.R` (rpact, asOF, alpha=0.024) |
| D_total | 269 events | derived from `boundaries.R` (rpact, 90% power assumption) |
| Combination test alpha allocation | **STUB:** equal split | stub — placeholder; replace with the protocol's pre-specified allocation |
| Seed | `NULL` (auto per replicate) | package convention |

### 2.5 Boundary computation (only if external tools were used)

If decision boundaries were computed via an external package
(`rpact`, `gsDesign`, `multcomp`, `gMCP`, etc.), include both the
**call** and the **output** verbatim from the boundary script. The
reviewer must be able to reproduce the calculation without leaving
the report. Do not paraphrase the call or summarize the output.

```r
# scripts/boundaries.R contents — verbatim
library(rpact)
design <- getDesignGroupSequential(
  kMax             = 2,
  informationRates = c(0.66, 1.00),
  alpha            = 0.025,
  beta             = 0.20,
  sided            = 1,
  typeOfDesign     = "asOF"
)
sample <- getSampleSizeSurvival(design = design, hazardRatio = 0.74,
                                allocationRatioPlanned = 1)
```

```
# output of running boundaries.R — verbatim (key fields):
Critical z-values (one-sided, upper):  2.524  1.992
Local one-sided alpha at each stage:   0.005798  0.023210
Max events (final, 100% IF):           351
Interim events (66% IF):               232
```

The literals from this output are what get hardcoded into the
relevant `milestone(...)` extra args or `action_*` functions in §6.
Cross-reference §2 (Confirmed parameters) so the reviewer can
verify the literals match.

Skip this section entirely when no external boundary tool was used.

### 3. Arms (with endpoints)

Bundle each arm's full assembly into one block: the `endpoint(...)`
call(s) for that arm, the `arm(...)` call, and the `$add_endpoints(...)`
call. Define everything for one arm before moving to the next. This
matches the package's build order and lets a reviewer audit each arm
in one pass without scrolling.

Per arm:

- Code block showing `endpoint(...)` → `arm(...)` → `$add_endpoints(...)`,
  one statement per line, verbatim from the script.
- Short paragraph: what the arm represents clinically, what
  distribution / generator was chosen and why, readout times for
  non-TTE endpoints, any filter conditions, any helper used to
  derive parameters.
- Caveats inline (e.g., "`CorrelatedPfsAndOs3` is incompatible with
  Cox PH; final analysis uses log-rank instead.")

When two or more arms share the same endpoint structure with only
parameter differences, the explanation can be written once at the
top of the section and arms below reference it — but **the code
blocks per arm should still be shown in full** so each arm is
self-contained for review. A small per-arm parameter table is also
fine when many arms differ only in numeric values.

### 4. Trial setup

Show the `trial(...)` call. Explain:
- Sample size and duration (and whether `set_duration`/`resize` will
  modify them adaptively).
- Accrual schedule and the rationale (e.g., "30/mo for the first 6
  months reflects ramp-up; 50/mo thereafter").
- Dropout: which distribution and the helper that produced its
  parameters (`weibullDropout(...)` if used).
- Stratification factors (if any) and which baseline endpoints
  implement them.

### 5. Milestones

Per milestone:
- Show the `milestone(...)` call with its `when` condition.
- One paragraph: what triggers it (in clinical terms), what happens
  at the trigger, when in the trial it is expected to fire (cite
  expected milestone time from the calibration run if available).

### 6. Action functions

**Show the full body of each action function** as a code block —
verbatim from the script, one statement per line. Prose summaries
are not enough for QC; the reviewer needs to see the actual logic.
The code block should already be liberally commented (see SKILL.md
"Comment action functions liberally" rule).

After (not before) the code block, add a short narrative covering:

- **Trigger** — restate from §5.
- **Data lock** — what `get_locked_data` returns at this point;
  which arms / endpoints are populated.
- **Analysis** — which test, which wrapper, why this choice. **If
  a stub for a combination/group-sequential test, flag it
  prominently.**
- **Adaptation** — which `trial$*()` methods are called, with the
  rule. **If a dummy rule, flag it: "DUMMY: replace with actual
  rule."**
- **What gets saved** — each `trial$save()` mapped to which
  operating characteristic it supports.

The narrative annotates the code block; it does not replace it.

### 7. Operating characteristics

For each operating characteristic the user asked about:
- Restate the research question in the user's words.
- Show the answer (number, with the post-processing call that
  produced it: e.g., `mean(out$reject_h0)`).
- A small table or plot if the OC has structure (per-arm power,
  per-stage decision rates, allocation distribution).
- Cite which `trial$save()` call from §6 supplies the underlying
  value.

**Milestone-time plots (`summarizeMilestoneTime(out)`) are
opt-in, not default.** The precondition for calling the function
is in `helpers.md` (post-simulation utilities) — read it before
deciding. Quick decision tree once the precondition holds:

1. **Include without asking** when the user's question is about
   timing — phrasings like "expected duration," "when will the IA
   fire," "study completion date," operational feasibility, or
   binding-interim accounting.
2. **Omit without asking** when the user's question is about
   *power* under a sensitivity sweep (multi-scenario NPH,
   parameter grids, dose–response screens) and the OC table
   already lists IA/FA medians per scenario. A single plot from
   one cherry-picked scenario is misleading; one plot per
   scenario inflates the report.
3. **Ask** when neither rule clearly applies. One sentence is
   enough: *"Do you want milestone-time distributions in the
   report (single panel, faceted by scenario, or omitted)?"*

If the design has any binding early-stop rule, do **not** call
`summarizeMilestoneTime`; report the binding-interim expected
duration derived post-hoc from saved decision flags instead, and
explain in the report why a milestone-time plot is omitted.

If applicable, include Monte Carlo standard error estimates next to
each OC so the reader can judge precision (e.g., for a power estimate
`p` from `n` replicates, MCSE ≈ √(p(1−p)/n)).

### 8. Caveats and limitations

A short list of things the user should know:
- Dummy decision rules that need replacement before the design is
  finalized
- Stubs for combination/group-sequential/graphical tests
- Helper-derived literals that depend on assumed inputs (e.g.,
  Pearson correlation from `solveThreeStateModel`)
- Sample-size / runtime trade-offs in the production run
- Any deviations from the original user brief

Caveats that apply to a single section can also appear inline within
that section — duplicate placement is fine if it improves
auditability.

## Output format

Default: write the report as Markdown, render it to HTML alongside,
and open the HTML in the user's default browser when ready.

```r
Rscript -e 'markdown::mark_html("report.md", output = "report.html"); browseURL("report.html")'
```

`markdown::mark_html()` is what RStudio's Markdown Preview button
uses, so the rendered HTML matches the style the user is already
familiar with. The HTML is the user's primary view; the `.md` is
the source of truth for any edits.

Place the report in the per-trial output folder (see SKILL.md
"Output organization") with consistent filenames — `report.md` /
`report.html` is the suggested default.

If the user explicitly wants a different format (Quarto,
`rmarkdown::render` with a custom template, an internal corporate
template), ask early and use that instead. The default above is for
when the user has not specified.

## Editing this file

This file is intentionally policy-light. If your organization has
specific reporting requirements — required disclosures, naming
conventions, regulatory boilerplate, audit-trail formats — edit this
file to encode them. The agent will follow whatever this file says.
