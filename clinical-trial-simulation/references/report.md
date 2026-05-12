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

## Tone and voice

The report is reviewed by a biostatistician for QC and audit. Write
in **formal, third-person prose**:

- No second person (no "you", no "we"). State what the design does
  or what the simulation observed, not what the reader should think.
- No colloquial connectors ("note that", "of course", "obviously",
  "for what it's worth", "as expected"). State results directly.
- No editorializing in the narrative. Interpretation belongs in
  §7's "Interpretation" subsection or §8 "Limitations" — clearly
  separated from the parameter and result statements.
- Numbers are reported with explicit units and Monte Carlo standard
  error (MCSE) where applicable. Avoid hedging modifiers like
  "approximately" inside numeric tables; state the number, then
  state precision separately (MCSE, IQR, range).
- Decisions and assumptions made by the agent are flagged
  explicitly with the controlled-vocabulary tags in §2 (`inferred`,
  `derived`, etc.). Do not bury them in narrative.
- Code blocks are verbatim from the script — no paraphrase. Prose
  around code is descriptive, not explanatory commentary
  ("`fitLogrank(...)` is called to test the OS endpoint at look 2"
  — not "we run a log-rank test here because…").
- Avoid "the user", "the team", "we", "I". When attribution is
  necessary, say "the protocol specifies", "the SAP requires", or
  cite the relevant tag from §2's Source/Notes column.

The skill files themselves are written informally for the agent's
benefit; that informality must not propagate to the report output.

## Structure: build-order spine

Mirror the build order in the report. The agent assembled the
simulation block by block; the report walks the reader through the
same sequence. Each section pairs (a) the relevant code snippet,
(b) a short paragraph explaining what was implemented and the
parameters used, (c) caveats inline if any.

```
   Table of Contents                  — clickable links to every section below
0. Resource Utilization              — session tokens, cost, software versions
0.5 Output Files and Reproduction    — file tree + reproduction recipe
1. Design Rationale                  — context, alternatives considered, choices
2. Design Parameters                 — single source of truth (table)
2.5 Decision Boundary Derivation     — only if external tools (rpact /
                                       gsDesign / multcomp / ...) were used
3. Treatment Arms and Endpoints      — per arm: endpoint(...) calls +
                                       arm() + add_endpoints(), bundled
4. Trial Configuration               — n, duration, accrual, dropout, stratification
5. Milestones                        — per milestone (trigger + what fires)
6. Milestone Actions                 — per action (full body verbatim);
                                       analysis, adaptation, and saves
7. Operating Characteristics         — results mapped to research questions
8. Limitations and Assumptions       — placeholders, stubs, helper-dependencies,
                                       known biases (e.g., conditional estimands)
```

The build-order sections that have a clear *design* meaning (3-7)
each pair a code block with explanation. **The listener and the
`controller(...) / controller$run()` calls are plumbing — omit them
from the report.** They are identical across designs and add noise to
the audit trail.

### Table of Contents (required)

Every report begins with a clickable ToC after the H1 title and
before §0. Use GFM anchors (`markdown::mark_html` generates them).
Include every section that exists in this report and nest §7
subsections when present. Use a bold `**Table of Contents**` label
(not an H2) so the ToC does not list itself.

### Code style in the report

Code blocks in the report are for review, not just illustration. Two
rules:

- **One statement per line.** Never chain with `;`. A reviewer must
  be able to scan the code block top to bottom and comment on
  individual lines.
- **Show the code as it actually appears in the script** — same
  variable names, same arguments, same line breaks. The report is
  the script narrated, not a paraphrase.

### 0. Resource Utilization (at the very top of the report)

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
| TrialSimulator version | required; read from `oc_summary$ts_version` (written by `main.R` per SKILL.md §"Package source") — never hardcode the literal in the report |
| R version | required; read from `oc_summary$r_version` |

### 0.5 Output Files and Reproduction

This section has two visible sub-parts in the rendered report — a
**File tree** and a **Reproduction** block. Both must be present;
label them with bold inline headings as shown in the worked example
below so the reviewer immediately sees which artifact lists what
exists and which one tells them how to rebuild it.

**File tree.** Each entry is `name` + `size` + brief description.
Sizes are useful as a quick sanity check (a 0-byte `output.rds`
signals a failed run; the rds size also conveys dimensionality).
Filenames must match the `Output organization` section of `SKILL.md`
exactly. Files that don't apply to a given design are omitted, not
shown empty (no `actions.R` if no non-doNothing actions; no
`boundaries.R` if no external boundary tool; etc.).

**Reproduction.** A short block of `Rscript` calls answering "if I
delete the .rds files, can I recover them?" The bold `**Reproduction:**`
label sits immediately above the shell block (not at the top of the
section) so the reviewer sees the label and the commands together.
Order matters: boundaries first (if used) since they emit the literals
that `main.R` hardcodes; then `main.R` to regenerate the simulation
output; then the HTML re-render. Adapt the recipe to the files that
exist for this run.

**Worked example:**

**File tree:**

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

Convention for the two `.rds` files:

- **`output.rds`** is the raw per-replicate matrix returned by
  `controller$get_output()`. One row per replicate, all auto-saved
  milestone columns and all `trial$save()` columns present. Large,
  reproduction artifact, not consumed directly by the report.
- **`oc_summary.rds`** is the post-processed list of operating
  characteristics that the report reads. Whatever summary the report
  cites (power, P(stop) per stage, MCSE, binding-aware expected
  duration, `ts_version`, `r_version`, …) is computed in `main.R`
  *after* the simulation and saved here. The report never recomputes
  from `output.rds` — that would couple report rendering to the raw
  schema and defeat the audit trail.

**Reproduction:**

```sh
Rscript scripts/boundaries.R          # once, to confirm boundary literals
Rscript scripts/main.R                # regenerates output.rds, oc_summary.rds
Rscript -e 'markdown::mark_html("report.md", output = "report.html")'
```

### 1. Design Rationale

A short paragraph (3–6 sentences) describing the reasoning that led
to this design.

- **Exploration mode:** state the alternatives that were considered
  and the basis for each being set aside (e.g., "alpha allocation
  alternatives 0.0125/0.0125, 0.005/0.020, and 0.015/0.010 were
  evaluated; 0.015/0.010 was selected to weight PFS, the
  earlier-maturing endpoint"). The visible reasoning trail is part
  of the audit record.
- **Implementation mode:** restate the protocol brief in the
  report's own words so the protocol writer can verify the
  interpretation against the source document.

### 2. Design Parameters

A single table that is the source of truth for every value used in
the simulation. Subsequent sections reference this table rather than
restating numbers.

**Required columns: three.** Every row must populate all three.

| Column | What goes here |
|---|---|
| **Parameter** | Short name of the parameter, in clinical/statistical terms (not the R variable name unless they happen to match). |
| **Value** | The exact value used in the simulation (number, expression, distribution + parameters, data.frame literal, helper-derived literal). |
| **Source / Notes** | Where the value came from. Pick the most specific applicable category from the controlled vocabulary below. |

**Source / Notes — controlled vocabulary** (use one; combine with a short justification when needed):

- **`protocol`** — copied verbatim from the protocol or user-supplied specification.
- **`protocol (derived)`** — protocol-specified in clinical terms, mechanically converted to a TS-compatible form. The conversion must be shown, e.g. *"15% dropout by mo 50 → `rate = -log(0.85)/50`"*.
- **`assumed`** — not specified by the protocol; a default value was selected. The default and its basis must be stated in one phrase, e.g. *"assumed — 6-month ORR readout typical of solid-tumor trials"*. **Assumed values require explicit confirmation before the production simulation is executed.**
- **`derived`** — computed from other parameters in this table or from a helper function. The computation must be cited, e.g. *"derived: `solveThreeStateModel(median_pfs=7, median_os=15, corr=0.68) → h01 = 0.0750`"*, or *"derived from `boundaries.R` (rpact)"*.
- **`software default`** — a default prescribed by the package or skill convention (e.g., `seed = NULL`, `silent = TRUE`, `plot_event = FALSE`). No rationale required.
- **`PLACEHOLDER`** — a decision rule, combination test, or boundary marked for replacement before design finalization. Must be prominently flagged in the table (bold + `PLACEHOLDER:` prefix) and listed again in §8.

Always include rows for: endpoint distribution parameters per arm, readout times for non-TTE endpoints, correlation structure (and the generator implementing it), sample size, duration, accrual schedule, dropout, stratification factors, milestone trigger thresholds, and any helper-derived literals.

**Worked example:**

| Parameter | Value | Source / Notes |
|---|---|---|
| N (1:1) | 500 | protocol |
| Accrual | uniform 20/mo (`StaggeredRecruiter`, `accrual_rate = data.frame(end_time=Inf, piecewise_rate=20)`) | protocol |
| Dropout | exponential, `rate = -log(0.85)/50 = 0.003250` | protocol (derived): "15% by mo 50" |
| ORR readout | 6 mo | assumed — first response assessment typical for solid-tumor trials; confirm before production |
| PFS — control | `rexp(rate = log(2)/20)` | protocol |
| PFS — treatment, 6-mo delay scenario | `PiecewiseConstantExponentialRNG(risk = data.frame(end_time=c(6,1000), piecewise_risk=c(log(2)/20, 0.55*log(2)/20)))` | derived from protocol NPH specification; `tail_end = 1000` per package convention |
| GSD efficacy bounds (z) | (3.0204, 2.3762, 2.0303) at IF (0.49, 0.75, 1.00) | derived from `boundaries.R` (rpact, asOF, alpha=0.024) |
| D_total | 269 events | derived from `boundaries.R` (rpact, 90% power assumption) |
| Combination test alpha allocation | equal split | PLACEHOLDER — replace with the protocol's pre-specified allocation |
| Seed | `NULL` (auto per replicate) | software default |

The `PLACEHOLDER` tag in the Source / Notes column is the single signal — do not also wrap the Value column with a `**PLACEHOLDER:**` prefix. One tag, one column.

### 2.5 Decision Boundary Derivation (only if external tools were used)

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

### 3. Treatment Arms and Endpoints

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

### 4. Trial Configuration

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
  at the trigger (analysis, adaptation, data lock, saves — whatever
  applies), and when in the trial it is expected to fire (cite
  expected milestone time from the calibration run if available).

The full bodies of the action functions go in §6, not here. Keep §5
focused on triggers and high-level intent so a reviewer can scan the
trial timeline without reading code.

### 6. Milestone Actions

Action functions are the work performed at each milestone — they may
analyze locked data, adapt the trial (`$resize`, `$update_generator`,
`$remove_arms`, `$add_arms`, `$set_duration`), save flags and
diagnostics, or do nothing (`doNothing`). This section documents all
of it.

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
  a placeholder for a combination/group-sequential test, flag it
  prominently using the `PLACEHOLDER` tag (same vocabulary as §2).**
- **Adaptation** — which `trial$*()` methods are called, with the
  rule. **If a placeholder rule, flag it as `# PLACEHOLDER: replace
  with actual rule` in the code and as `PLACEHOLDER` in the §2 row
  that captures the rule.**
- **What gets saved** — each `trial$save()` mapped to which
  operating characteristic it supports.

The narrative annotates the code block; it does not replace it.

### 7. Operating Characteristics

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

### 8. Limitations and Assumptions

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
