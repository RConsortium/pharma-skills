# Graphical testing (Maurer-Bretz) — `GraphicalTesting`

Read this only when graphical testing is the chosen multiplicity
procedure (see "Multiplicity across hypotheses" in `SKILL.md` for when to
choose it over Bonferroni / hierarchical / the seamless combination test).

`GraphicalTesting` is an R6 class: a weighted transition graph where, when
a hypothesis is rejected, its alpha flows to the others per the graph,
with per-hypothesis group-sequential alpha spending across analyses. It is
driven from inside action functions.

## Constructor

```r
gt <- GraphicalTesting$new(alpha, transition, alpha_spending,
                           planned_max_info, hypotheses = NULL, silent = FALSE)
```

| Arg | Notes |
|-----|-------|
| `alpha` | numeric vector — initial **one-sided** alpha per hypothesis; `sum(alpha)` = one-sided FWER (e.g. 0.025). Consistent with the "test one-sided, always" rule in `SKILL.md`. |
| `transition` | square matrix, one row/col per hypothesis; diagonal all 0; each row sums to 1 (alpha flows out) or 0 (sink). |
| `alpha_spending` | character vector, one per hypothesis: `"asOF"`, `"asP"`, or `"asUser"` (see below). |
| `planned_max_info` | integer vector — planned max information at each hypothesis's final analysis: **events** for tte, **non-missing entries** for non-tte. Drives information fractions. See below. |
| `hypotheses` | character names; must match the `hypotheses` column in `stats` exactly. |

### Alpha spending — only two are native; use `"asUser"` for the rest

The class natively supports only **`"asOF"`** (O'Brien-Fleming) and
**`"asP"`** (Pocock-type). For **any other** spending function —
Kim-DeMets / gamma family, Hwang-Shih-DeCani, or a custom shape — do not
approximate with asOF/asP. Instead:

1. Compute the cumulative alpha-spend with **`rpact`** or **`gsDesign`** for
   that hypothesis's information fractions.
2. Set its `alpha_spending` entry to `"asUser"` and feed the cumulative
   spend through the `alpha_spent` column of `stats` (increasing, `= 1` at
   the final stage).

This makes the package cover essentially any spending function, including
custom ones. Entries may be mixed across hypotheses (e.g. some `"asOF"`,
some `"asUser"`).

### `planned_max_info` — confirm how it is determined

For a multi-endpoint trial the planned max information per hypothesis
(events for tte, non-missing readouts for non-tte) is often not known in
closed form and may need a **pilot simulation** to estimate its average.
This is a modeling choice: **confirm the method with the user before
implementing.** They may have protocol numbers in mind, prefer an
analytic value, or want a specific pilot setup. Do not silently pick one.

## Feeding results — `gt$test(stats)`

`stats` is a data.frame with **one row per (hypothesis × stage actually
tested)**:

| Column | Notes |
|--------|-------|
| `order` | integer stage label; rows sharing an `order` are tested together off the same locked data. **Omit** a hypothesis's row at stages where it is not tested. |
| `hypotheses` | name, matching the constructor. |
| `p` | nominal **one-sided** p-value for that hypothesis at that stage. Use a `fit*()` wrapper when it is the right test; under adaptation or a user-specified analysis the p-value may be computed another way. Whatever the source, ensure it is correctly **one-sided** before feeding it in. |
| `info` | observed events / non-missing entries at that test. |
| `is_final` | logical; `TRUE` at that hypothesis's last stage. |
| `max_info` | planned max (`= planned_max_info` at interims); **update to observed at the final stage** — observed information can exceed the plan, which the class otherwise rejects. |
| `alpha_spent` | cumulative spent proportion, **only** for `"asUser"` hypotheses; `NA` otherwise (omit the column entirely if no hypothesis uses `"asUser"`). |

## Simulation pattern — follow this exactly

This is the only sanctioned way to drive `GraphicalTesting` in a
TrialSimulator simulation. **Implement it exactly as below — do not invent
any other arrangement.** Graphical testing is subtle and a plausible-looking
alternative will silently corrupt the family-wise error rate.

**Why the construction site matters.** A `controller$run(n = ...)` executes
each milestone's *action function once per replicate*, but everything at
*script level* (the `endpoint`/`arm`/`trial`/`milestone` objects) is built
**once** and shared by all replicates. The graph is **per-replicate state**:
it must therefore live inside the action functions, never at script level.

Forbidden — these are the tempting wrong turns; do **not** do any of them:

- **Do not construct `gt` at script level / once globally** (the way
  endpoints and arms are built). A single graph shared across replicates
  carries rejections and spent alpha from one replicate into the next and
  destroys the FWER. `gt` must be constructed **inside** the action of the
  first GTP milestone, so a fresh graph is built every replicate.
- **Do not build a new `gt` at later milestones.** After the first, you must
  resume the *same* graph via `trial$get(...)` — a fresh graph there loses
  the earlier rejections and alpha propagation.
- **Do not carry the graph with `trial$bind()`** — it stores tabular rows,
  not graph state. Use `trial$save_custom_data` / `trial$get`.
- **Do not defer all testing to the final action** when an interim decision
  drives an adaptation — test at each milestone.
- **Do not hand-roll** the alpha propagation or boundaries — use the class.
- **Do not bake testing into endpoint generators.**

Steps:

1. **Construct `gt` fresh inside the action of the first milestone where any
   GTP endpoint is tested** — unconditionally, every replicate. This is what
   keeps replicates independent. Do **not** call `gt$reset()`; a fresh
   object per replicate makes it unnecessary.
2. At each testing milestone, assemble that stage's `stats` rows and call
   `gt$test(stats)` immediately, then read `gt$get_current_decision()`.
   Three things must be set correctly, **per hypothesis** (not per
   milestone):
   - **`p`** — one-sided (see the schema); compute it the right way for the
     analysis (a `fit*()` wrapper when it fits; otherwise the user's
     specified analysis), then ensure it is one-sided.
   - **`is_final`** — `TRUE` for any hypothesis reaching its **last** test
     at this milestone. A hypothesis tested only once is `is_final = TRUE`
     at that single analysis, even at an interim; one still being tested
     later is `FALSE`. The flag is per hypothesis, so a single `stats` may
     mix `TRUE` and `FALSE` rows.
   - **`max_info`** — planned (`planned_max_info`) while a hypothesis is
     still continuing, but the **observed** information at its final test
     (observed can exceed planned, which the class otherwise rejects).
3. Persist the object: `trial$save_custom_data(gt, "gt", overwrite = TRUE)`
   — **never** `trial$bind()` (it carries tabular rows, not graph state).
4. At the next milestone, `gt <- trial$get("gt")`, test that stage's stats,
   read the decision. Repeat until no hypothesis remains to be tested.
5. Save the decision in **every** action that tests, under **stage-specific
   names** (next section).

`trial$save_custom_data` stores an in-memory reference (no serialization),
so this is cheap. Testing per stage is equivalent to one batch call and
~1.3× faster than rebuilding the graph each milestone.

## Reading and saving decisions

- `gt$get_current_decision()` → named vector of `"reject"`/`"accept"` over
  all hypotheses. Save the per-hypothesis reject flags with `trial$save()`
  so power and rejection patterns can be scored post-simulation.
- `gt$get_current_testing_results()` → per-hypothesis detail (observed p,
  max allocated alpha, decision, stage, spending function).

Save the decision in **every** action that tests, under **stage-specific
names** — `trial$save()` errors on a duplicate name, and distinct names
keep each milestone's decision as its own column for post-simulation
scoring (interim vs final rejection rates). Note the persisted graph is
cumulative: a hypothesis rejected at an interim is still `"reject"` in
`get_current_decision()` at the final stage.

For the canonical example of graph behavior (alpha propagation as
hypotheses are rejected), read `?GraphicalTesting`. The example below
shows the piece that help page does not: driving the graph across
milestones inside action functions.

## Worked example — testing across milestones

Two analyses, two hypotheses. **PFS matures early and is tested only at the
interim** (so it is `is_final = TRUE` there, and its `max_info` is the
observed PFS events — its final analysis); **OS is tested at both the
interim (`is_final = FALSE`) and the final (`is_final = TRUE`)**. Note how a
single `stats` mixes `is_final` per hypothesis, and PFS is simply absent
from the final `stats`.

```r
hs  <- c('pfs','os'); alp <- c(0.0125, 0.0125)          # one-sided, FWER 0.025
tr  <- matrix(c(0,1,1,0), 2, 2); asf <- c('asOF','asOF')
mx  <- c(pfs = 120L, os = 90L)                          # planned max events

action_interim <- function(trial, ...) {
  ld <- trial$get_locked_data('interim')
  fp <- fitLogrank(Surv(pfs, pfs_event) ~ arm, placebo='control', data=ld, alternative='less')
  fo <- fitLogrank(Surv(os,  os_event)  ~ arm, placebo='control', data=ld, alternative='less')
  ip <- as.integer(round(fp$info)); io <- as.integer(round(fo$info))
  stats <- data.frame(
    order      = 1L,
    hypotheses = c('pfs', 'os'),
    p          = c(fp$p, fo$p),
    info       = c(ip, io),
    is_final   = c(TRUE, FALSE),        # pfs done here; os continues
    max_info   = c(ip, mx['os'])        # pfs: observed (its final); os: planned
  )
  gt <- GraphicalTesting$new(alp, tr, asf, mx, hs, silent = TRUE)  # fresh, per replicate
  gt$test(stats)
  trial$save_custom_data(gt, 'gt', overwrite = TRUE)              # persist (not bind)
  d <- gt$get_current_decision()                                  # also drives any adaptation
  trial$save(unname(d['pfs'] == 'reject'), 'pfs_rej')            # pfs decided once, here
  trial$save(unname(d['os']  == 'reject'), 'os_rej_interim')
}

action_final <- function(trial, ...) {
  ld <- trial$get_locked_data('final')
  fo <- fitLogrank(Surv(os, os_event) ~ arm, placebo='control', data=ld, alternative='less')
  io <- as.integer(round(fo$info))
  stats <- data.frame(                  # only os; pfs is NOT re-included
    order = 2L, hypotheses = 'os', p = fo$p,
    info = io, is_final = TRUE, max_info = io   # observed at its final test
  )
  gt <- trial$get('gt')                                            # resume same graph
  gt$test(stats)
  d <- gt$get_current_decision()                                  # reflects interim + final
  trial$save(unname(d['os'] == 'reject'), 'os_rej_final')
}
```

## Gotchas

- `p` must be **one-sided** and `alpha` is the one-sided budget. Use the
  `fit*()` wrappers when they fit the analysis, but the user may specify a
  different p-value computation (e.g. under adaptation) — the agent's job
  is to ensure whatever is fed in is properly one-sided.
- One graph per replicate (construct fresh at the first GTP milestone).
- `planned_max_info` must be whole numbers > 0; update `max_info` to
  observed at each hypothesis's final stage.
- For non-asOF/asP spending, never approximate — compute via rpact/gsDesign
  and feed through `"asUser"` + `alpha_spent`.
