---
name: clinical-trial-simulation
description: >
  Design and simulate clinical trials using the TrialSimulator R
  package and produce a QC-ready build-order-spine report that
  pairs each block of code with rationale, parameters, and
  operating characteristics.
metadata:
  version: 0.2.16
  trialsimulator_min_version: "1.18.4"
---

# TrialSimulator Skill

Help a biostatistician design and simulate a clinical trial using the
TrialSimulator R package, then write a readable report. This skill is
a thinking framework, a cached API reference, a TrialSimulator-specific
function catalog, and a report-writing guide. **It is not a script.**
You bring general engineering, programming, and biostatistics
knowledge; this skill adds what is specific to TrialSimulator.

## Loading announcement

Whenever this skill is loaded, the agent calls
`packageVersion("TrialSimulator")` (fast, local — no network) and
compares the installed version against
`metadata.trialsimulator_min_version` from the YAML frontmatter
above. The first line of the agent's first response reports the
result.

Three outcomes:

- **Installed ≥ required** — `clinical-trial-simulation v<metadata.version> loaded — TrialSimulator <ts_version>, R <r_version>`. Proceed.
- **Installed < required** — `clinical-trial-simulation v<metadata.version> loaded — TrialSimulator <ts_version> installed, **≥ <trialsimulator_min_version> required**. R <r_version>.` Then offer to update on the next turn: *"Want me to run `remotes::install_github('zhangh12/TrialSimulator')` now? (y/n)"* — on confirm, run it and re-check; on decline, stop until the user resolves. Do not begin any simulation work until the version requirement is met.
- **Not installed** — `clinical-trial-simulation v<metadata.version> loaded — TrialSimulator not installed. R <r_version>.` Offer to install: *"Want me to run `remotes::install_github('zhangh12/TrialSimulator')` now? (y/n)"*

Substitutions:

- `<metadata.version>` from this file's YAML frontmatter.
- `<trialsimulator_min_version>` from this file's YAML frontmatter.
- `<ts_version>` from `packageVersion("TrialSimulator")`.
- `<r_version>` from `R.version.string` (the `x.y.z` portion).

No network call fires on load. The only network use is the optional
remediation install on user confirmation.

After the announcement line, briefly greet the user and ask about
the trial setting — never ask what design type, discover it through
conversation (see "Two user modes" below).

## Files in this skill

- `SKILL.md` (this file) — framework, conversation principles, build order, workflow
- `references/building_blocks.md` — cached reference for `endpoint`, `arm`, `trial`, `milestone`, `listener`, `controller`, `regimen`, and the condition system
- `references/helpers.md` — catalog of TrialSimulator-provided functions (RNGs, parameter solvers, analysis wrappers, post-sim utilities), plus non-obvious gotchas
- `references/report.md` — how to write the simulation report (intentionally policy-light; organizations are encouraged to edit this file)

These files cache the most common things to save tokens. When confused
or when behavior contradicts these notes, consult `?<function>` in R
or the package's pkgdown site at
https://zhangh12.github.io/TrialSimulator/. Don't guess — the manual
is the source of truth.

## Package source

This skill targets a known-good baseline of TrialSimulator declared
in `metadata.trialsimulator_min_version` of the YAML frontmatter
above. **At load, only a local `packageVersion("TrialSimulator")`
check runs — no automatic `install_github`, no network call.** The
load-time check + offer/auto behavior is specified in "Loading
announcement".

If TrialSimulator is missing or below the minimum, the canonical
remediation is:

```r
remotes::install_github("zhangh12/TrialSimulator")
```

The agent offers to run this when the load-time check detects a
shortfall and only runs it on user confirmation. The user can also
update outside the session and reload the skill.

When bumping `metadata.version`, audit whether
`trialsimulator_min_version` also needs to move — e.g., if the
skill adopts a TS feature or fix landed in a newer release.

Surface three versions in §0 of the report: TrialSimulator, R, and
the skill. The agent looks each value up once before writing the
report and pastes the literal string into the §0 table. No R chunks,
no runtime lookup, no `readRDS`. Slight staleness on re-renders is
acceptable; the running environment is assumed stable.

## Package philosophy

TrialSimulator decouples a trial into a small set of independent
building blocks: endpoints, arms, the trial object, milestones, the
listener, the controller, and (optionally) regimens for treatment
switching. **A trial design — fixed, seamless, response-adaptive,
dose-ranging, platform, anything — is just a particular composition of
these blocks.** There is no "design type" object; there are only blocks
and how they combine.

Practical implication: do not pick a design template, then ask the
user to fill in parameters. Listen, identify what the user wants to
learn, identify which blocks are needed to answer it, then collect
the arguments those blocks need.

**A second principle the agent must internalize: the simulation
never actually stops a trial early.** Every replicate runs through
all milestones in chronological order, regardless of any "stopping"
rule. Early stopping is a post-hoc concept derived from decision
flags the user saves at adaptive milestones — see `helpers.md` for
the gotcha and the post-processing pattern. This decoupling is
intentional: one simulation scores multiple stopping rules without
re-running. It also means stopping-aware operating characteristics
(early-stop probability, expected duration / sample size accounting
for stopping) must be computed from saved flags, not from
`milestone_time_<final>` alone.

## Build order

Always assemble in this order. Each step depends on the previous.

```
1. endpoint()              — define each endpoint per arm × endpoint
2. arm()                   — one per treatment arm
   arm$add_endpoints()        — attach endpoints
3. trial()                 — sample size, duration, enroller, dropout, stratification
   regimen()                  — (optional) build a treatment-switching regimen
   trial$add_regimen()        — (optional) attach it; MUST precede add_arms
   trial$add_arms()           — attach arms with sample ratios
4. milestone() × M         — one per action point, in chronological order
5. listener()
   listener$add_milestones()
6. controller(trial, listener)
7. controller$run()
8. controller$get_output()    — retrieve simulation results
```

### Milestone ordering rule

Define milestones in chronological order of when they trigger. If two
milestones can trigger in either order, note it in a comment.

### Action function structure

Data is locked automatically at every milestone; `trial$get_locked_data()`
only **retrieves** the snapshot when the action needs to inspect it.
Typical shape for a non-`doNothing` action:

```r
action_<name> <- function(trial, ...) {
  # 1. (Optional) retrieve locked data
  data <- trial$get_locked_data(milestone_name = "<name>")

  # 2. Analysis — skip if not needed

  # 3. Adaptations — guarded trial$*() calls

  # 4. Save — at least one trial$save() per non-doNothing action
  trial$save(value = <value>, name = "<metric>")
}
```

Signature is `function(trial, ...)`. Use distinct `name`s across
`trial$save()` calls.

**Passing state between milestones — prefer `trial$save()` +
`trial$get_output()` for scalars.** When milestone A computes a
single value (number, flag, string, integer ID) that milestone B
needs to read, save it with `trial$save(value, name)` at A and
retrieve it at B with `trial$get_output()` (the in-progress
per-replicate row, sanctioned for use inside actions). This keeps
the value in the audit trail — it appears as a column in
`controller$get_output()` after the run, useful for post-hoc
analysis and report tables.

Reserve `trial$save_custom_data(..., overwrite = TRUE)` +
`trial$get(name)` for **non-tabular state**: a fitted model object,
a list, a data frame — anything that does not fit cleanly as a
column in the per-replicate output. See `helpers.md` gotchas for
the namespace and `overwrite = TRUE` rules.

## R6 method visibility — only use the documented public methods

TrialSimulator's classes (`Trials`, `Controllers`, `Endpoints`, `Arms`,
`Listeners`, `Milestones`, `Regimens`) are R6 classes. R6 forces all
public methods to be exported, but **only a curated subset is intended
for end users** — the rest are internal implementation details and
should not be called from user code or action functions, even if they
appear in tab-completion. The author flags this in the help docs (see
the user-method list at the top of
https://zhangh12.github.io/TrialSimulator/reference/Trials.html).

Use these and only these:

**`Trials`** (the `trial` argument inside actions). Group by purpose
— not all methods are equal. Reach for them only when the design
calls for that kind of operation.

- *Trial setup* (called once after `trial()`, before `$run()`):
  `$add_regimen(regimen)` (must precede `$add_arms`), `$add_arms(sample_ratio, ...)`
- *Data access in actions*: `$get_locked_data(milestone_name)`
- *Result plumbing in actions*:
  `$save(value, name, overwrite)` / `$bind(value, name)` / `$save_custom_data(value, name, overwrite)` / `$get(name)` / `$get_output(cols, simplify, tidy)`
- *Adaptive modifications, only inside action functions, only when
  the design adapts*:
  `$set_duration(duration)`, `$resize(n_patients)`,
  `$remove_arms(arms_name)`, `$update_sample_ratio(arm_names, sample_ratios)`,
  `$update_generator(arm_name, endpoint_name, generator, ...)`,
  `$add_arms(sample_ratio, ...)` (mid-trial; same method as setup, used
  for adaptive arm addition like dose-ranging, basket, or platform designs)
- *Combination test in actions, for seamless / dose-selection designs*:
  `$dunnettTest(formula, placebo, treatments, milestones, alternative,
  planned_info, ...)`, `$closedTest(dunnett_test, treatments, milestones,
  alpha, alpha_spending)`. Read the `adaptiveDesign` vignette for the
  worked example.

Do not reach for an adaptive method unless the user's design
explicitly involves that adaptation. A fixed design uses only the
setup methods, `$get_locked_data`, and the result-plumbing methods.

> When adding arms mid-trial, construct the new endpoint(s) and arm
> object inside the action function — `endpoint()`, `arm()`, and
> `arm$add_endpoints()` are not setup-only; they are the prerequisites
> of `$add_arms` and may be invoked anywhere a new arm is needed.

**`Controllers`** (the controller object):

- `$run(n, n_workers, plot_event, silent, dry_run)`, `$get_output(...)`

**Arm objects:** `$add_endpoints(...)` only.

**Listener objects:** `$add_milestones(...)` only.

If you find yourself wanting to call a method outside this list, you
almost certainly want a different building block instead. When in
doubt, check the help-doc method list — that is the contract.

## Conversation principles

### Two user modes

Detect from input shape, not content.

**Exploration mode** — user describes a setting in prose, may or may
not have a design in mind. Don't lock onto a design too fast. When
enough has accumulated, propose 2-3 candidate designs, contrast them
briefly, let the user pick. If the user has nothing to say, prompt
for orientation (therapeutic area, primary research question,
regulatory context, prior data) — a few anchors, not an
interrogation.

**Implementation mode** — user pastes a spec with parameters. Map
to building blocks, **explicitly call out unused inputs** ("you
mentioned X — I didn't use it; where does it fit?"), and ask for
missing pieces with one sentence of why each matters. Silently
dropping user-supplied information is a trust killer.

### Plain language during interaction

Every question to the user is collecting an argument value for a
building-block function — but ask in **clinical / statistical terms**,
not in package vocabulary. The same applies when *confirming* the
parameter table, the analysis plan, or the chosen design: describe
what the design *does*, not how the code implements it. A
biostatistician unfamiliar with TrialSimulator should be able to
follow the conversation with no R reference open.

| Avoid (package vocabulary) | Prefer (clinical / statistical terms) |
|---|---|
| "use `fitLogrank` for the OS test" | "OS is tested with a one-sided log-rank test" |
| "milestone fires at `enrollment(n=500, min_treatment_duration=6)`" | "the analysis is performed 6 months after the last patient is enrolled" |
| "we'll call `set_duration(54)` if pooled events < 220" | "the trial duration is extended from 48 to 54 months if pooled events at month 24 fall below 220" |
| "boundary z = 2.523 from `asOF` spending" | "interim efficacy boundary z = 2.523 (Lan-DeMets O'Brien-Fleming spending, IF = 0.71)" |
| "`StaggeredRecruiter` with `accrual_rate = data.frame(...)`" | "piecewise-constant accrual: 5/mo for the first 3 months, 15/mo for the next 3, then 25/mo until enrollment completes" |
| "the action saves `gate_pass`" | "the gate decision is recorded for each replicate" |
| "use `CorrelatedPfsAndOs2`" | "PFS and OS are modeled jointly via a Gumbel copula with Kendall's τ = 0.5 and exponential margins" |

Code-level vocabulary is appropriate in **three contexts only**:
implementation mode where the user pasted code, debugging an error
together, or the report itself (whose audience is a QC reviewer who
must verify the implementation). During design discovery, parameter
confirmation, and progress updates, default to clinical /
statistical language.

### Don't silently read referenced documents

When a prompt references an external SAP, protocol, or other
document, the prompt itself distills the relevant content — that
is the prompt-writer's job. **Do not silently read or fetch the
referenced document**: no unprompted `Read` on a local PDF, no
`WebFetch`, no `curl`. A long SAP can cost minutes of context and
time and may reintroduce ambiguity the prompt was written to
resolve.

If something the prompt does not cover would meaningfully change
the plan and the referenced document plausibly holds the answer,
**ask the user first**. Name the section or topic, explain why
reading it would help, and let the user choose: authorize a narrow
read, paraphrase from memory, or leave the value as `assumed` with
a default. Reading is on the table when the user authorizes it —
just never silently.

When the prompt itself explicitly tells the agent to consult the
source (e.g., "see Section 7.3 of the SAP for the boundary table"),
read narrowly to the cited section, then stop.

### First response is the plan

The agent's first substantive response — before any R execution,
derivation script, or simulation — is **the plan**, not the result.
Every prompt gets one. Aim to have it in the user's hands within a
couple of minutes; soft expectation.

The plan contains: a restate of the design; the §2 parameter table
v0 with `protocol` / `assumed` / `derived (pending)` tags per
`report.md`; a bullet list of intended supplements (or "no
supplements needed"); the `assumed` rows called out for
confirmation; and the next step with a rough time estimate.

**Implementation-mode caveat.** When the user says "skip the Q&A,"
the plan condenses to one paragraph (*"Implementation mode. Plan:
<N> supplements → main.R → sanity → production. Starting now."*)
but still posts. Skipping Q&A is not skipping visibility.

### Confirmation gates

Three confirmation points across a run, posted in this order:

1. **The plan** — see "First response is the plan" above. The first
   gate is the plan, not a complete parameter table; the table is
   v0 with `derived (pending)` rows for anything a supplement will
   resolve.
2. **The resolved parameter table.** After supplements have run and
   the `pending` rows are filled in, present the final parameter
   table. The user confirms the literals.
3. **The save plan.** For every operating characteristic the user
   asked about, show which value will be saved in which action
   function. Catches save ↔ OC mismatches that are expensive to fix
   post-simulation.

For implementation-mode prompts that say "skip Q&A," gates (2) and
(3) collapse into visible turn-by-turn progress (see "No silent
work" below) rather than explicit confirmation requests, but the
artifacts (resolved parameter table, save plan) still appear in
the conversation.

### No silent work

Each supplement and each validation round (sanity, calibration,
production) is its own visible turn — write, run, render are
separate announced turns, never bundled into a single silent
stretch. Tool calls expected to take more than ~60 seconds get a
one-line heads-up with a rough estimate before launching.

### Don't ask about internal workflow

Some choices are part of the agent's internal validation workflow
or have a single sensible default — they are not user-facing
decisions. Don't ask; just do.

- **Sanity → calibration → production.** This iteration is the
  agent's own testing protocol (see "Iteration and runtime"). The
  user doesn't decide whether to run a small sanity check before
  production — the agent does it as part of producing a working
  script. Don't ask.

  **Carve-out — calibration that produces cited literals.** If a
  calibration script computes a value that ends up in the §2
  parameter table, in `main.R` / `actions.R`, or anywhere else
  the report cites it, the script is a **citable artifact**, not
  internal workflow. It follows the supplement rule (see
  `report.md` "Derivations and supplements"): script in
  `scripts/derivations/`, rendered doc in `supplements/`,
  bidirectional cross-references with the main report. "Internal
  workflow" applies only to the testing iteration on `main.R`
  itself.
- **Seed.** `seed = NULL` (auto per-replicate, recorded in the
  output) is the correct default for simulation studies. Don't ask
  the user about it. Use a fixed integer seed only if the user
  explicitly asks for reproducibility of a specific replicate (e.g.,
  for debugging).
- **`silent = TRUE` on `trial()`, `listener()`, `controller$run()`.**
  Standard for production runs; don't ask.
- **`plot_event = FALSE` on `controller$run()`** when running multiple
  replicates. The package forces it off anyway when `n > 1`; don't
  ask.

## Code quality

- **Named arguments everywhere.** Never positional.
- **Inline parameter values at the call site; don't hoist them as
  named variables.** `endpoint(rate = log(2)/60)` over a hoisted
  `median_pfs_placebo <- 60` referenced thirty lines later. The
  package is designed so each block carries its parameters visibly
  — hoisting forces QC reviewers to scroll and chase definitions.
  Use a comment at the call site (or prose in the report) for any
  "why this value" context. **Exception**: structurally complex
  values (an `accrual_rate` data.frame, a piecewise `risk` table for
  `PiecewiseConstantExponentialRNG`) — define those immediately
  above the call that consumes them. Adjacent is fine; far away is
  not.
- **Prefer TrialSimulator-provided functions** over base R or external
  packages when both can do the job. See `helpers.md` for the
  catalog. The package's design intent is that you reach for its
  functions reflexively.
- **Runnable placeholders for unspecified decision rules.** When the
  user says "we'll decide based on data" without specifying the rule,
  write a small data-driven placeholder and label it: `# PLACEHOLDER:
  replace with actual rule`. Use the same `PLACEHOLDER` tag in the §2
  parameter table (see `report.md`). Guard against edge cases
  (`length() > 0` before `remove_arms`, etc.). A placeholder that
  runs is better than a TODO that blocks validation.
- **Comment action functions liberally.** Action functions encode
  the design's decision logic — the "why" of every threshold, fit,
  adaptation, and save call. Without comments, a QC reviewer has to
  reverse-engineer intent from variable names. At minimum comment:
  (a) the trigger the action runs at and the data lock it operates
  on, (b) the test / adaptation rule and why this choice, (c) what
  each `trial$save()` captures and which OC it feeds. Inline `#`
  comments next to the relevant lines are usually enough; don't
  hide everything in a header docstring.
## Testing and multiplicity

Two intertwined concerns: how to compute decision boundaries when a
hypothesis is tested under group-sequential design, and how to
control familywise error when more than one hypothesis is tested.

### Computing boundaries (group sequential)

For standard GSD with a single hypothesis (single endpoint, single
arm pair, alpha-spending function such as OBF / Pocock / asUser),
compute boundaries with **`rpact`** or **`gsDesign`** — ask the user
which they prefer (organizations often standardize on one; both are
regulator-trusted).

**First judge whether the boundary is constant across replicates.**
If the milestone trigger fixes the information fraction (e.g.,
"interim after N events" with planned final at M events → IF = N/M
is deterministic), the boundary is identical in every replicate:
compute ONCE in a separate `Rscript` step, present the result for
sign-off, and hardcode the literal into the action function (which
compares log-rank z or p against it). **Never call `rpact` /
`gsDesign` inside an action when the boundary is constant** — that
re-runs per replicate for nothing.

When the milestone trigger does not deterministically fix the
information fraction for every endpoint being tested (e.g., the
trigger is event-driven on OS but PFS is also tested at each
milestone), **standard regulatory practice is to use pre-specified
information fractions from the protocol** — not the realized
observed information. Pre-specified IFs are constant across
replicates, so the once-and-hardcode rule still applies; ask the
user for the protocol-specified IFs and compute each endpoint's
boundaries using them.

The one genuinely per-replicate case is **over-/under-running
adjustment at the final analysis**, where the protocol prescribes
recomputing the final boundary from the observed final information.
When required, the action calls the boundary tool per replicate at
the final milestone — accept the cost. For the interim and any
non-final milestone, pre-specified IFs apply.

The package's `GroupSequentialTest` class is still out of scope
until the author provides guidance; `rpact` / `gsDesign` is the
workaround.

### Multiplicity across hypotheses

**When more than one hypothesis is tested — multiple endpoints,
multiple arms, or both — surface the multiplicity question before
writing the action.** Don't silently default to per-test alpha.

Procedures, in roughly increasing complexity:

1. **Bonferroni split.** Simplest defensible default. Ask the user
   for the alpha share per hypothesis (e.g., 0.5% PFS + 2% OS for
   total α = 2.5%). If group sequential is also used per endpoint,
   the per-endpoint alpha is split across stages via that endpoint's
   own boundary calculation (see "Computing boundaries" above). The
   information fraction may or may not be event-driven per endpoint
   — a PFS interim triggered by event count vs. an OS interim
   triggered by enrollment time give different IFs. Custom alpha-
   spending functions may be needed; ask the user.

2. **Hierarchical / fixed-sequence (gatekeeping).** Endpoints in a
   pre-specified order; test each at full alpha; stop at the first
   non-rejection. Technically a special case of graphical testing
   but worth reaching for on its own when the order is clear.

3. **Graphical testing** (Maurer-Bretz). Alpha flows between
   hypotheses via a pre-specified transition graph. Use the built-in
   `GraphicalTesting` class. **Read the example in `?GraphicalTesting`
   or the pkgdown reference page before writing** — the API is
   concrete and easier to follow from a worked example than from
   prose. Pair with `trial$bind()` to accumulate per-stage stats
   across milestones and call `gt$test(stats)` once in the final
   action; see the `actionFunctions` vignette for the bind pattern.

4. **Built-in combination test for seamless / dose-selection
   designs** (`trial$dunnettTest` + `trial$closedTest`). The
   canonical use case: an arm-selection (dose-selection) interim
   feeds a confirmatory test combining stage-wise p-values across
   the surviving arm(s). **Read the `adaptiveDesign` vignette** for
   the worked example — it shows the formula, the `planned_info`
   data.frame layout, and how PFS + OS can be tested under one
   closed procedure with α split between them.

If none of these fit the user's design, ask for more details and
implement a custom procedure (weighted Hochberg, parallel
gatekeeping with logical restrictions, complex multi-population
designs, etc.).

## Error-handling stance

Read the message — TrialSimulator's are usually specific. Consult
`?<function>` for plain functions; for R6 methods on `Trials` /
`Controllers`, use `?Trials` / `?Controllers` (method-level `?` does
not work) or the pkgdown reference page. Vignettes live at
https://zhangh12.github.io/TrialSimulator/articles/. Don't disable a
check to make an error go away.

## Final step — open the main report

After the report and all supplements have been rendered, **open the
main report HTML in the user's default browser**:

```r
Rscript -e 'browseURL("runs/<trial_name>/report.html")'
```

This is the last announced turn of the run, not the user's
responsibility to remember. Only the main report opens; supplements
are linked from it. Full guidance in `report.md` §"Output format".

## Iteration and runtime

Validate iteratively: sanity at `n = 3-5` to catch real errors, a
short calibration at `n = 20-50` to estimate per-replicate cost, then
production at the size the operating characteristics require (1000+
for power; 10000+ for Type I error). Re-source the script between
runs rather than reusing a controller.

One TS-specific quirk: at very small `n`, stochastic milestone
triggers occasionally fail to fire in a replicate, producing errors
that look like code bugs but are sample-size artifacts. If the same
code succeeds at larger `n`, it's not a bug.

### Output organization

Create a dedicated folder for each simulation run, with R scripts in
a `scripts/` subfolder split by purpose:

```
runs/<trial_name>/
  scripts/
    main.R               ← building blocks: endpoint, arm, trial,
                            milestone, listener, controller, run, OC summary
    actions.R            ← action functions (omit if no non-doNothing actions)
    generators.R         ← custom generator functions (omit if none)
    helpers.R            ← helpers used by generators or actions (omit if none)
    boundaries.R         ← external boundary computation via rpact /
                            gsDesign (omit if not used). Run ONCE before
                            main.R; the literal results are hardcoded in
                            main.R or actions.R.
    derivations/         ← one R script per non-trivial pre-simulation
      <topic>.R             derivation (correlation fitting, NORTA
                            feasibility, landmark-to-piecewise, gate-
                            threshold calibration, etc.). Run ONCE
                            before main.R; literals hardcoded forward.
                            See report.md "Pre-simulation derivations
                            and supplements".
  supplements/           ← rendered supplement docs (one per
    <topic>.md              derivations/<topic>.R). Each cross-
    <topic>.html            referenced from §2 of report.md.
  output.rds             ← raw controller$get_output(), saved by main.R
  oc_summary.rds         ← post-processed OC list for the report, saved by main.R
  report.md              ← the main report
  report.html            ← rendered via markdown::mark_html
  milestone_times.png    ← embedded in the report ONLY when the milestone-time
                            precondition holds AND the decision tree in
                            report.md §7 selects "include". Omitted otherwise.
```

`scripts/derivations/` and `supplements/` are present only when the design has non-trivial pre-simulation derivations; omit when every derivation is trivial enough to stay inline in §2 of the main report.

`main.R` sources whichever sibling files exist:

```r
source("actions.R")
source("generators.R")   # only if it exists
source("helpers.R")      # only if it exists
```

Splitting keeps each file short enough to review at a glance and
makes "show me the action functions" trivial. Files that don't apply
to a given design (no custom generators, no helpers, no external
boundaries) should be omitted entirely — empty placeholders add
noise.

### Parallelism

**Default `n_workers = 1`** (single process). Most simulations in
this skill's typical territory — a few thousand replicates with
simple endpoints — finish in seconds single-process, and the script
is universally readable. Reach for `n_workers > 1` only when runtime
warrants it.

When `n_workers > 1` is used, pass per-call configuration through the
package's `...` mechanism: `trial(dropout = fn, my_arg = X)`,
`endpoint(generator = fn, my_arg = Y)`, `milestone(name, when,
action, my_arg = Z)`. The functions then receive their arguments via
their own signature. Don't reference script-level globals from
inside generators / dropout / enroller / action functions — `mirai`
workers don't share the script env and globals break. The `...`
pattern is also the idiomatic style in the package's vignettes.
Start at 2-4 workers on a laptop; requires the `mirai` package.
