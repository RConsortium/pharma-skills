---
name: gsdose
description: >
  Design and analyze inferentially seamless phase 2/3 adaptive trials with dose
  selection in the phase 2 part — multi-arm multi-stage (MAMS) group sequential
  designs for oncology survival endpoints — using the R package gsDose (Zhang & Jin
  2025): inverse normal combination tests across pre/post dose-selection cohorts,
  Dunnett-based closed testing across dose arms, and alpha-spending efficacy
  boundaries. The skill guides the user through a structured Q&A that collects
  every required input one question at a time, then computes and reports.
  Triggers on: inferentially seamless or seamless phase 2/3 design,
  adaptive phase 2/3, dose selection at interim, multi-arm multi-stage survival
  trial, combination test, Dunnett closed testing, adaptive dose dropping with
  group sequential boundaries, or any mention of gsDose.
---

## Bundled Resources

| File | What it contains | When to read |
|------|-----------------|--------------|
| `examples.md` | The vignette's worked example end to end: w derivation, h, design boundaries, IA2/IA3 testing and closed-testing decisions | After collecting inputs, before writing any R code — it is the canonical usage pattern |
| `scripts/compute_w_weights.R` | Derives cohort-1 stage weights (w) from expected events via gsDesign2, per the gsDose vignette | Q10 option B — write a config JSON and run it (step A2) |
| `scripts/compute_boundary.R` | Computes efficacy (+ optional futility) boundaries via gsDose::gsBoundary from a config JSON | Step A5 (both workflows) |
| `scripts/gsdose_report_template.py` | Word report (Design Assumptions, IA Plan, Efficacy Boundaries, + Closed Testing when present) from the results JSONs — zero hardcoded values | Workflow A step A6 / B step B4 |
| `scripts/compute_test.R` | Combination test + Dunnett closed testing via gsDose::combTest at the current analysis | Workflow B step B2 |

Do NOT read these files upfront. Read them only when you reach the corresponding step.

**References** (cite these when the user asks about the methodology):
- Methods paper: Zhang, E. P. & Jin, M. (2025). *A Multi-Arm Multi-Stage Group
  Sequential Phase 2/3 Design with Dose Selection for Oncology Trials.*
  Statistics in Biopharmaceutical Research, 18(3), 333–340.
  doi:[10.1080/19466315.2025.2539831](https://doi.org/10.1080/19466315.2025.2539831)
- Package: [github.com/eric-zhang16/gsDose](https://github.com/eric-zhang16/gsDose)
  (R package `gsDose`; install via `remotes::install_github("eric-zhang16/gsDose")`)

---

## Workflow

**Session map:** Q1–Q12 (shared trunk, below) → A1–A5 (boundary computation,
both workflows) → then workflow A finishes with A6–A7, while workflow B continues
with B-Q1–B-Q4 (observed-data intake) and B1–B4 (test, decision, report).

1. **Scope check** — confirm the request is a seamless phase 2/3 MAMS design with
   dose selection and a survival endpoint. Out-of-scope requests (standard GSD
   without dose selection) belong to the group-sequential-design skill.
2. **Collect inputs** — ask the questions in the AskUserQuestion section below,
   one at a time, starting with the installation check (Q1). Q2 selects the
   workflow (A: boundaries, B: combination test + closed testing).

**Pacing — one artifact per turn.** Writing a config/script, running it, and
writing the report are separate turns; don't bundle them into one response.

### Boundary calculation (both workflows, after Q12; workflow A stops at A7)

A1. **Create the output folder** `output/gsdose_{indication}_{YYYYMMDD}/`
    (indication from Q2b) with two subfolders: `deliverables/` (what the user
    hands to reviewers: report, results JSON, reproduction script) and
    `supporting/` (configs and script copies — the reproducibility trail).

A2. **Stage weights, if derived (Q10 = B):** write the w-weights config JSON
    (schema in the header of `scripts/compute_w_weights.R`) and run:
    `Rscript scripts/compute_w_weights.R <out>/supporting/w_config.json <out>/supporting/w_results.json`
    This yields `w`, expected cohort-1/cohort-2 events, and expected analysis
    times. Show the user the w matrix and confirm (per Q10).

A3. **Assemble per-stage events:**
    - Design stage (Q8 = A): `d` = planned events (Q9), `d2` = `d_cohort2` from
      A2 (and `d1` = `d_cohort1`).
    - Underway (Q8 = B): `d` and `d2` run only up to the CURRENT analysis —
      actual totals and actual cohort-2 events per occurred look. The expected FA
      events enter as `planD`, never as a row of `d` (see the vignette: at IA3,
      d = c(270, 430) with s = 3, planD = 520).

A4. **Write the boundary config** `<out>/supporting/gsdose_boundary_config.json` — schema in
    the header of `scripts/compute_boundary.R`. Put every design assumption the
    report needs in `meta` (disease, endpoints, k_dose_arms, randomization_ratio,
    n1_per_arm, n2_per_arm, total_N, ctrl_median, hr, dropout_rate,
    enroll_duration); the report reads ONLY from the results JSON — never type a
    design value into the report.

A5. **Compute boundaries:**
    `Rscript scripts/compute_boundary.R <out>/supporting/gsdose_boundary_config.json <out>/deliverables/gsdose_results.json`
    One endpoint entry per endpoint (Q6); efficacy always, futility when Q12 = B.

A6. **Generate the Word report:**
    `python scripts/gsdose_report_template.py <out>/deliverables`
    produces `deliverables/gsdose_report.docx` with: 1. Design Assumptions,
    2. Interim/Final Analysis Plan, 3. Efficacy Boundaries.

A6b. **Write the reproduction script** `<out>/deliverables/gsdose_reproduce.R` — a
    SELF-CONTAINED R script that reproduces every reported number with direct
    gsDose calls and the actual design values inlined (follow the patterns in
    `examples.md`: w derivation if Q10 = B, h, gsBoundary per endpoint, and — in
    workflow B — combTest). No JSON reading, no dependence on the bundled
    scripts: a reviewer should be able to read and run this one file.
    **Run it once and check its printed boundaries (and test statistics) match
    `gsdose_results.json` before delivering; fix any mismatch first.**

A7. **Deliver** — copy the bundled scripts used into `supporting/`, report the
    path, and summarize the boundaries (Z and nominal p per analysis) in chat.

Output structure:

```
output/gsdose_{indication}_{YYYYMMDD}/
├── deliverables/
│   ├── gsdose_report.docx                # combined result summary (Word)
│   ├── gsdose_results.json               # combined result summary (JSON;
│   │                                     #   workflow B merges test results in)
│   └── gsdose_reproduce.R                # standalone script reproducing all numbers
└── supporting/
    ├── w_config.json / w_results.json    # only when Q10 = B
    ├── gsdose_boundary_config.json / gsdose_test_config.json
    └── (copies of the bundled scripts used)
```

### Workflow B — combination test + closed testing (continues after A5)

Runs only when Q2 = B (and Q8 = B). Uses the boundary computed at the actual
event counts (A5's `gsdose_results.json`) as `zbound` at the current stage.

**Observed-data intake — ask in this order, same format rules as the trunk.**
B-Q1 (the selected dose) is trial-level: one answer, the same for every endpoint.
B-Q2–B-Q4 are PER ENDPOINT — when more than one endpoint is tested (Q6), collect
them for one endpoint at a time, like the trunk's per-endpoint questions.

B-Q1. **Selected dose.** "Which dose arm was selected at the dose-selection
analysis? (1 to K, in the same order as the dose arms from Q3.)" Validate it is
one of the K arms. This is `sid`.

B-Q2. **Cohort-1 z statistics (z1).** "For each dose arm versus control, what is
the cohort-1 standardized log-rank z statistic at each testing analysis that has
occurred — including the dropped dose arms? Their cohort-1 patients keep
contributing events after dose selection." Lay it out as a table: rows = testing
analyses so far, columns = all K dose arms vs control. This is the z1 matrix
(cumulative, per stage).

B-Q3. **Cohort-1 events per arm (d1).** "And the cohort-1 number of events for
each dose-arm-vs-control comparison at each of those analyses (all dose arms and
control, cumulative)." Same table shape as B-Q2. **Validation:** each arm's
events must be non-decreasing across stages; if an arm has no new events at a
stage, warn that gsDose excludes it from the Dunnett test at that stage.

B-Q4. **Cohort-2 z statistic (z2).** "What is the cohort-2 standardized log-rank
z statistic for the selected dose versus control at the current analysis?"
One number.

**Compute steps:**

B1. **Write the test config** `<out>/supporting/gsdose_test_config.json` (schema
    in the header of `scripts/compute_test.R`): the endpoint name (must match the
    results JSON), current stage k, the w matrix (row k is used), h, z1, d1, z2,
    sid, ratio (Q4b), and `zbound` = the current stage's efficacy bound from
    `deliverables/gsdose_results.json` (plus `z_lower` if Q12 added a futility bound).

B2. **Run the test:**
    `Rscript scripts/compute_test.R <out>/supporting/gsdose_test_config.json <out>/deliverables/gsdose_results.json`
    This calls `combTest` (Dunnett-based closed testing across all intersection
    hypotheses containing the selected dose) and MERGES the results into
    `gsdose_results.json` under the endpoint's `test` field — the bundle keeps
    one combined results file. Per intersection it records: Dunnett Z (cohort 1),
    cohort-2 Z, combination Z, and reject vs `zbound`.

B3. **Conclude by closed testing:** the selected dose's hypothesis is rejected
    iff ALL intersections containing it are rejected. The script writes the
    decision sentence; state it plainly to the user (efficacy claim, or trial
    continues). If a futility bound exists, report whether the individual
    hypothesis's combination Z crossed it (informational — stopping for futility
    is the sponsor's call).

B4. **Report:** `python scripts/gsdose_report_template.py <out>/deliverables` — regenerates
    the ONE combined Word report; endpoints carrying test results get
    "4. Combination Test and Closed Testing". Extend `gsdose_reproduce.R` with
    the combTest call and observed data (A6b), verify it reproduces the test
    statistics, then deliver as A7.

---

## AskUserQuestion

Collect design parameters by asking **ONE question at a time**. Wait for the user's
response before moving to the next question. Always present options and let the
user choose; the only defaults are the ones a question itself defines.

### AskUserQuestion Format

- **Write for a smart 16-year-old.** Plain English, no jargon, no R function names,
  no implementation details.
- **Use concrete examples and analogies.**
- **Always offer lettered options.** A) ... B) ... C) ... — never mark one as
  recommended or default.
- **Keep it short.** One question, one paragraph max of context.
- **Present options neutrally.** Do not invent defaults or recommendations of your
  own; only mark a default where the question itself defines one (e.g., Q5).

### Questions (ask in this order)

1. **Setup check.** "Before we design the trial: is the gsDose R package installed
   on this machine? It's distributed from GitHub, not CRAN."
   - A) Yes — it's installed
   - B) No, or not sure — please check for me (and install it if it's missing)

   **On any answer, verify before proceeding** — do not take "yes" on faith:
   run `Rscript -e 'cat(as.character(packageVersion("gsDose")))'`. If this fails and
   the user chose B (or A was wrong), install from the GitHub repo and re-verify:

   ```r
   remotes::install_github("eric-zhang16/gsDose")
   ```

   If installation fails (no internet, no remotes, build error), report the exact
   error and stop — every later step depends on this package. Do not continue to
   Q2 until `packageVersion("gsDose")` succeeds.

2. **Workflow.** "What do you want to do in this session?"
   - A) **Calculate group sequential boundaries** — derive the efficacy boundaries
     for the trial from the alpha spending plan
   - B) **Perform the analysis at an interim/final that has occurred** — compute
     the boundary at the actual event counts, then the combination test statistics
     and the closed testing

   Both workflows share ALL the questions below (Q3–Q12): workflow B does not skip
   the alpha/spending questions, because the boundary must be recomputed at the
   actual information fraction before testing — the design-stage boundary is not
   reused. Workflow B additionally requires that at least one analysis has
   occurred (Q8 = B); if the user picks B but says "design stage" at Q8, point out
   the mismatch and resolve it before continuing. After the boundary step,
   workflow A stops and workflow B continues with the observed-data intake.

   2b. **Disease / indication.** "What disease and treatment line is this trial
   for? (e.g., '1L melanoma', '2L NSCLC')" — free text, one line. It names the
   output folder and appears in the report header.

3. **Number of dose arms.** "How many dose arms will the trial start with — not
   counting the control arm? **Note: only ONE dose arm will be selected at the
   dose-selection analysis** — that single dose continues with the control to the
   end of the trial, and the others stop enrolling."
   - A) 2 dose arms
   - B) 3 dose arms
   - C) 4 dose arms
   - D) Other — specify

   If the user wants to carry more than one dose forward, that design is outside
   this skill's scope (gsDose supports selecting exactly one dose) — say so
   plainly and stop rather than improvising.

4. **Per-arm sample sizes before/after dose selection.** "How many patients per arm
   will be enrolled in each dose arm (1) before dose selection and (2) after dose
   selection? These can be the expected numbers at the design stage, or the actual
   counts if enrollment has already happened."
   - n1 = patients per arm enrolled before dose selection: ___
   - n2 = patients per arm enrolled after dose selection: ___

   4b. **Randomization ratio.** "How are patients split between each dose arm and
   the control arm? Give the ratio as dose : control."
   - A) 1 : 1 — equal numbers in each dose arm and control
   - B) Other — specify (e.g., 2 : 1)

   Record the ratio r = n_dose / n_control; it is also the `ratio` argument used
   later in the analysis.

   **Consistency check + total confirmation (do both before moving on):**
   - The control arm sizes implied by the ratio are `n1 / r` (cohort 1) and
     `n2 / r` (cohort 2). If either is not a whole number, or the user has
     mentioned control-arm or total counts that disagree, flag the inconsistency
     and resolve it with the user (adjust n1/n2 or the ratio) before continuing.
   - Then confirm the implied total. With K dose arms (from Q3) plus control
     enrolling before selection, and only the selected dose plus control after:

     `Total N = K × n1 + n1/r  +  n2 + n2/r`   (for r = 1: `(K+1) × n1 + 2 × n2`)

     Present it like: "With a __:__ randomization ratio, that implies a total of
     ___ patients: ___ before dose selection (K dose arms × n1 + control n1/r)
     and ___ after (selected dose n2 + control n2/r). Is that right?"
     If the user says no, find out which input is off and correct it.

5. **Cohort weights (h).** "Your trial has two groups of patients: those enrolled
   before the dose is selected (cohort 1) and those enrolled after (cohort 2).
   When we combine their results into one test, we need to decide how much weight
   each cohort's evidence carries. How do you want to set these weights?"
   - A) **Based on sample size (default)** — each cohort's weight reflects how many
     patients per arm it contributes. If n1 patients per arm are enrolled before
     dose selection and n2 after, the weights are
     `h = c(sqrt(n1/(n1+n2)), sqrt(n2/(n1+n2)))`.
   - B) **Custom weights** — specify your own pair of weights for cohort 1 and
     cohort 2.

   **Validation:** the squared weights must sum to 1 (`h[1]^2 + h[2]^2 == 1`).
   If the user gives custom weights that don't satisfy this, show the discrepancy
   and ask whether to rescale them (preserving their ratio) or re-enter.
   If A, derive `h` directly from Q4's answers:
   `h = c(sqrt(n1/(n1+n2)), sqrt(n2/(n1+n2)))`. Show the user the resulting
   numeric weights.

6. **Endpoints.** "What survival endpoint(s) will the trial test? These are
   time-to-event outcomes — for example, how long patients live overall (OS) or
   how long before the disease progresses (PFS)."
   - A) Overall survival (OS) only
   - B) Progression-free survival (PFS) only
   - C) Both PFS and OS
   - D) Other / different combination — specify

   **If more than one endpoint:** handle them ONE AT A TIME. Enumerate them for
   the user ("We'll set up PFS first, then OS"), then ask all remaining
   endpoint-specific questions for the first endpoint before starting the second.
   Never interleave two endpoints' questions in the same pass.

*(Questions from here on are asked PER ENDPOINT — complete them for one endpoint
before starting the next, per Q6.)*

7. **Number of analyses (per endpoint).** "For [endpoint]: how many times will this
   endpoint be formally tested? Count every interim look plus the final analysis —
   but **do NOT count the dose-selection interim**: only analyses where this
   endpoint is statistically tested count here."
   - A) Final analysis only — no interim
   - B) 1 interim + final (2 analyses total)
   - C) 2 interims + final (3 analyses total)
   - D) Other — specify the number of interims

   Record the total number of stages for this endpoint; it sets the length of the
   stage-wise weight vector (w) and the boundary computation later.

8. **Trial stage — have any interim analyses already happened? (per endpoint)**
   "For [endpoint]: where does the trial stand right now?"
   - A) **Design stage** — none of the analyses have occurred yet
   - B) **Some analyses have already occurred** — the trial is underway and one or
     more interim looks have been done

   **If B, explain this clearly to the user before collecting numbers:** two
   different event counts are needed, because they do different jobs:
   - the **actual number of events** observed at each analysis that has occurred —
     these determine both the alpha spent at those looks (via the actual
     information fraction) and the correlations between the test statistics;
   - the **expected (planned) number of events at the final analysis** — this is
     the denominator the information fractions (and hence the alpha allocation)
     are computed against.

   Only those two are required; Q9 collects them.

   **If A (design stage):** only the expected number of events is needed — it is
   used for both the alpha allocation and the correlations.

9. **Number of events at each analysis (per endpoint).** "For [endpoint]: how many
   events are targeted at each analysis? Give one number per analysis — IA1, IA2,
   ..., and the final analysis. **Count only events from the selected dose arm and
   the control arm** (both cohorts combined) — events in the dose arms that get
   dropped are NOT part of these counts."

   *(If Q8 = B — some analyses already occurred)* Required: the **actual**
   cumulative events at each analysis that has occurred — the total AND how many
   of them came from cohort 2 (patients enrolled after dose selection) — plus the
   **expected** events at the final analysis (the denominator for information
   fractions). The actual totals set the alpha spent (actual information
   fraction = actual events / expected FA events); the cohort split sets the
   correlations. E.g.:

   | Analysis | Events (total) | of which cohort 2 |
   |----------|----------------|-------------------|
   | IA1 (occurred) | actual: ___ | actual: ___ |
   | IA2 (occurred) | actual: ___ | actual: ___ |
   | FA             | expected: ___ | — (not needed) |

   **Validation:** cohort-2 events cannot exceed the total at any analysis, and
   both columns must be non-decreasing across analyses.

   Planned events for future IAs (if any remain before FA) are optional — ask for
   them only if the user wants projected boundaries for those future looks now;
   they are not needed to test at the current stage.

   *(If Q8 = A — design stage)* The planned events per analysis, one per look.

   **Validation:**
   - The number of entries must equal the number of analyses from Q7.
   - Event counts must be strictly increasing across analyses (IA1 < IA2 < ... < FA),
     for planned and actual alike; the package requires non-decreasing cumulative
     events. Flag and resolve any violation.
   - Events cannot exceed the number of patients at risk implied by Q4's sample
     sizes; sanity-check and query anything that looks off.

10. **Stage weights (w) for cohort 1 (per endpoint).** "When [endpoint] is tested at
   a later analysis, the cohort 1 results are built up in pieces: the data up to the
   first test, plus the new data accrued between each pair of analyses. Pre-specified
   weights control how these pieces are combined. A natural way to set them is in
   proportion to the number of cohort-1 events expected to accrue in each interval.
   Do you have weights in mind, or should we derive them from expected events?"
   - A) **I have my own weights** — provide the w vector for each analysis
   - B) **No preference — derive from expected events (default)** — we'll walk
     through the assumptions and compute them

   **w is pre-specified.** If the trial is already underway (Q8 = B) and the user
   derives w here, the inputs (10b–10d and the planned events) must be the
   ORIGINAL design-stage assumptions, not estimates updated from the observed
   data — say this explicitly before collecting 10b.

   **Validation (either path):** at each analysis the squared weights must sum to 1,
   and at the first testing stage all weight is on the data up to that stage
   (w = (1, 0, ..., 0)). If custom weights fail this, show the discrepancy and ask
   to rescale or re-enter.

   *(If B — walk through these one at a time, then compute):*

   10b. **Control median survival.** "What is the assumed median survival for the
   control arm, in months?" (Also ask: "Any annual dropout rate to assume, or
   none?" — if none, use 0.)

   10c. **Hazard ratio.** "What hazard ratio do you assume versus control? **This
   single HR is assumed to apply to ALL dose arms** — it's used to project expected
   events (for the stage weights now, and for per-dose-arm event projections at
   the design stage later)." (One number. Because the weights are pre-specified,
   this assumption affects efficiency, not type I error control — a reasonable
   common HR is fine even when the true dose–response differs across arms.)

   10d. **Enrollment assumptions.** "How do patients enroll over time? Give the
   enrollment as pieces: how long each period lasts (months) and the enrollment
   rate (patients/month) during it — **counting only patients in the selected dose
   arm and the control arm** (the arms that get dropped are excluded, matching how
   the events are counted in Q8). Then tell me which leading portion of that ramp
   is cohort 1 (enrolled before dose selection)." Sanity-check against Q4: the
   ramp total should match `(n1 + n1/r) + (n2 + n2/r)` (selected dose + control,
   both cohorts), and the cohort-1 portion should match `n1 + n1/r`; flag
   discrepancies.

   **Then compute:** run `scripts/compute_w_weights.R` (uses gsDesign2's
   `expected_time()` + `expected_event()`, following the gsDose vignette): for each
   analysis, find the calendar time when total planned events (Q9) are reached,
   compute cohort-1's expected events at that time, and set the weights as square
   roots of the incremental event fractions. Show the user the resulting w matrix
   (rows = analyses, columns = increments) alongside the expected cohort-1 events,
   and confirm before proceeding.

*(Q11–Q12 are shared by BOTH workflows: they define the spending plan that
workflow A reports and workflow B re-evaluates at the actual event counts.)*

11. **Alpha and spending function for the efficacy (upper) bound (per endpoint).**

    11a. "What one-sided significance level (alpha) is assigned to [endpoint]?
    In most phase 3 trials the total is 0.025 one-sided."
    - A) 0.025 (one-sided)
    - B) Other — specify

    **If more than one endpoint is tested (Q6):** the alpha entered here is this
    endpoint's assigned share. After collecting it for every endpoint, check that
    the shares sum to the intended total (e.g., PFS 0.005 + OS 0.020 = 0.025);
    if they don't, show the discrepancy and ask the user to correct it.

    11b. "How should that alpha be spread across the analyses for the efficacy
    bound? This controls how hard it is to declare success at early looks.
    **gsDose supports exactly two spending functions — these are the only two
    options:**"
    - A) **O'Brien-Fleming spending** — very strict early, close to the full alpha
      by the final analysis (`sf = 'OF'`)
    - B) **Hwang-Shih-DeCani spending** — a family tuned by one parameter gamma
      (`sf = 'HSD'`, `sfpar = gamma`)

    If the user asks for any other spending function (Pocock, Kim-DeMets, custom),
    explain it isn't supported by the package and offer the closest available
    choice (HSD with a suitable gamma approximates several common shapes — e.g.,
    gamma near 1 is Pocock-like); do not improvise an unsupported function.

    *(If B)* 11c. "What gamma value? More negative = more conservative early
    (gamma near -4 behaves like O'Brien-Fleming); gamma around 1 spends much more
    alpha early (Pocock-like)." Record it as `sfpar` — it is required with HSD
    and ignored with OF.

    11d. **Alpha sensitivity display (optional).** "Do you want the boundaries
    shown for any additional alpha levels, side by side, as a sensitivity view?
    (A common SAP convention — e.g., alpha = 0.021, 0.024 and 0.025 in one table.)"
    - A) No — just the assigned alpha
    - B) Yes — list the additional alpha level(s)

    Record them as `alpha_sensitivity` in the boundary config. Each extra alpha
    gets its own Efficacy/Futility column pair in the report's boundary table.
    When a futility bound is enabled, each sensitivity column spends 1 − that
    alpha with the same futility spending function. These columns are display
    only — the assigned alpha (11a) remains the testing basis.

12. **Futility (lower) bound (per endpoint).** "Do you also want a futility
    boundary — a line below which the trial would stop early for lack of benefit?"
    - A) No — efficacy bound only
    - B) Yes — add a futility bound

    *(If B, explain how gsDose builds it before asking 12b):* the lower bound uses
    the same spending machinery as the efficacy bound — the same two spending
    functions (OF or HSD) are the only options — but it spends a chosen total
    probability **under the null hypothesis** on the "no-benefit" side across the
    analyses. It is not a beta-spending rule (nothing is computed under the
    alternative), and there is no fixed-z futility option. The package convention
    is to spend the complement of alpha (1 − alpha) with a conservative
    Hwang-Shih-DeCani function (gamma = −6): under no treatment effect, the trial
    then crosses the futility bound at some stage with probability 1 − alpha.

    12b. "Use the conventional specification, or customize?"
    - A) **Conventional** — total spend = 1 − alpha, `sf = 'HSD'`, `sfpar = -6`
    - B) **Customize** — choose the total probability to spend, the spending
      function (OF, or HSD with a gamma), on the same two-option menu as 11b

    Compute it with `gsBoundary(..., alpha = <total spend>, bt = 'lower')`, reusing
    the same w, h, d, d2, s, planD inputs as the efficacy bound.

The trunk ends at Q12. Workflow B's observed-data intake (B-Q1–B-Q4) is defined
in the Workflow section above and is asked after the boundary step (A5).

