# Answer key -- `myanalysis` 0.1.0 fixture

Ground truth for the `rounding` skill benchmark. **Do not stage this file as an
input to a graded run.** It records what a correct report must contain, and was
verified by executing the fixture under R 4.6.1 (aarch64-apple-darwin25.4.0) on
2026-09-06.

Inputs staged for a run: `myanalysis/` (or `myanalysis-fixture.zip`) and
`precision-spec.yml`.

## Two different counts

The scanner reports **candidate call sites**; the report inventories **resolved
operations**. One resolved operation can appear as several candidates (a
wrapper call site plus the definition it reaches), which is why the numbers
differ. Both are correct; a report that conflates them is not.

Scanner (`Rscript scripts/scan-rounding-calls.R evals/fixtures/myanalysis`):

| Scanner field | Expected |
|---|---|
| `files_scanned` | 12 |
| `catalog/quantize` | 8 |
| `catalog/display` | 3 |
| `operator/quantize` | 1 |
| `operator/modulo` | 0 |
| `wrapper` | 11 |
| `excluded_by_context` | 4 |
| `total_hits` | 23 |
| `R/report-listing.R` | **hits: 0** -- the dynamic call is invisible to the scanner |

Report inventory: **14 in-scope rows** (one per operation-and-entry-path pair), **6 excluded hits**.

## In-scope rows

One row per **(operation, report entry path)**, as the benchmark asks. The same
site can carry different verdicts on different paths -- `R/render.R:5` is a
no-op where it receives an already-rounded value and is itself the rounding
step where it does not. Collapsing it to a single verdict is a wrong answer in
either direction. `--` means the rule does not apply to that operation.

| # | Site | Entry path | Tie | Stage | Display | Witness |
|---|---|---|---|---|---|---|
| 1 | `R/report-means.R:6` `round(mean(pct), 0)` | `report_means()` | **FAIL** | PASS | -- | mean `2.5` -> observed `2`, policy `3`; `-2.5` -> `-2` vs `-3` |
| 2 | `R/render.R:5` `formatC()` via `fixed_text()` | `report_means()` | PASS | -- | PASS | no-op: input is already an integer; `formatC(3,"f",0)` -> `"3"` |
| 3 | `R/report-change.R:6` `round_half_away(x, 1)` | `report_change()` | PASS | **FAIL** | -- | paired with #4; `x = c(1.25,1.25,1.75)` at 1dp: early `1.5` vs round-once `1.4` |
| 4 | `R/render.R:5` `formatC()` via `fixed_text()` | `report_change()` | **FAIL** | **FAIL** | PASS | this call performs the rounding: `formatC(1.25,"f",1)` -> `"1.2"`, policy `"1.3"` |
| 5 | `R/report-exposure.R:6` `round_half_away(sum(months), 2)` | `report_exposure()` | PASS | PASS | -- | ties map away from zero at 2dp |
| 6 | `R/render.R:13` `as.character(x)` via `render_cell()` | `report_exposure()` | -- | -- | **FAIL** | observed `"76"`, spec `exposure_total` requires `"76.00"` |
| 7 | `R/report-rates.R:6` `round_half_away(..., 2)` | `report_rates()` | PASS | PASS | -- | compliant quantizer |
| 8 | `R/render.R:5` `formatC()` via `fixed_text()` | `report_rates()` | PASS | -- | PASS | no-op on an already-rounded value; with #7 this is the fully compliant path |
| 9 | `R/report-counts.R:7` `round(pct, 0) >= threshold` | `report_counts()` | **FAIL** | **FAIL** | -- | a term at exactly 2.5% is dropped: `round(2.5,0)` is `2`, `2 >= 2.5` is `FALSE` while `2.5 >= 2.5` is `TRUE` |
| 10 | `R/rounding-helpers.R:18` `(x * 10) %/% 1 / 10` via `pct_label()` | `report_counts()` | **FAIL** | PASS | -- | truncation, not half-away: `2.25` -> `2.2`, policy `2.3` |
| 11 | `R/rounding-helpers.R:19` `paste0(n, "%")` via `pct_label()` | `report_counts()` | -- | -- | **FAIL** | `2.0` -> `"2%"`, spec `incidence_pct` requires `"2.0%"` |
| 12 | `R/rounding-helpers.R:10` `trunc(abs(x) * scale + 0.5)` | `round_half_away()`, allowlisted | **PASS** | -- | -- | `c(-2.5,-1.5,1.5,2.5)` -> `c(-3,-2,2,3)`; `c(-1.25,1.25)` -> `c(-1.3,1.3)`; `c(-0.125,0.125)` -> `c(-0.13,0.13)` |
| 13 | `R/report-listing.R:9` `do.call(sprintf, list(spec, x))` | `report_listing()` | **FAIL** | PASS | PASS | `sprintf("%.1f", 2.25)` -> `"2.2"`, policy `"2.3"`; `-2.25` -> `"-2.2"` vs `"-2.3"` |
| 14 | `R/render.R:5` `formatC()` via `fixed_text()` | `report_ci()` | **FAIL** | -- | **NOT ASSESSABLE** | `report_ci(1.25, 2.5, 1)` -> `"(1.2, 2.5)"`, policy `"(1.3, 2.5)"`; the spec has no entry for the risk-difference CI, so the required precision is unknown |

**Overall verdict: FAIL.** Rows 1, 4, 6, 9, 10, 11, 13 fail at least one rule;
row 3 fails on stage; row 14 is partly unassessable.

Row 14 is a judgment boundary, so grading is deliberately lenient there: a
report may mark Tie as FAIL (`formatC` is not half-away at any precision
tested) or as NOT ASSESSABLE, provided it names the absent spec entry and does
not assume a precision.

## Excluded hits (must appear in Coverage, must not be scored)

| Site | Reason |
|---|---|
| `R/render.R:18` `as.character(level)` in `stub_label()` | character/structural input, no numeric precision |
| `R/solver-utils.R:4` `round()` in `solver_tolerance()` | numerical tolerance, never displayed |
| `R/solver-utils.R:8` `signif()` in `solver_step()` | solver internal |
| `R/plot-scales.R:4` `round()` in `plot_axis_breaks()` | plot coordinates |
| `R/plot-scales.R:8` `ceiling()` in `plot_panel_width()` | plot layout |
| `vignettes/summary.Rmd:11` `round(demo, 1)` | vignette illustration, not reachable from a `report_*()` entry point |

## What each seeded case tests

| Case | Row | Tests |
|---|---|---|
| Tie method on a displayed statistic | 1 | the base case: `base::round()` is half-to-even |
| Early rounding before aggregation | 3, 4 | BR-002 stage; paired sites traced together |
| Early rounding before a row threshold | 9 | rounding changes which rows appear, not just their text |
| Trailing zeros dropped | 6, 11 | BR-003 is a string comparison, not a numeric one |
| Approved helper on the allowlist | 12 | a compliant path is reported as a reviewed PASS, not rewritten |
| Fully compliant helper + formatter | 7, 8 | no false finding on correct code |
| Quantization by `%/%`, no function name | 10 | a name-based grep cannot find this; the parse tree can |
| Dynamic `do.call(sprintf, ...)` | 13 | neither grep nor parse tree finds it -- only the exploratory pass does |
| Statistic absent from the spec | 14 | NOT ASSESSABLE instead of an invented precision |
| Same site, different verdict per path | 2, 4, 8, 14 |
| Solver / plot / vignette hits | excluded | scored as findings would be false positives |

## Probe evidence the report must embed

`Rscript scripts/probe-tie-behavior.R` under R 4.6.1 arm64 macOS:

- exact ties at 0 decimals: `base::round` differs from policy on 4 of 6
- pinned 1-decimal comparison: **6 of 10** `formatC` disagreements, **10 of 10**
  `round` disagreements
- negative zero: `formatC(-0.4, format="f", digits=0)` -> `"-0"`
- BR-002: round-once `1.4` vs early-rounded `1.5`
- BR-003: `as.character(76.00)` -> `"76"`

Per-precision runs are also required, because the fixture displays at 0, 1 and
2 decimals: `--digits 0`, `--digits 1`, `--digits 2`.

## Causes that must stay separate

The report must attribute `formatC` and `round` divergence to **two** causes --
tie mode and binary representation -- and must not compress them into a claim
that either function uses banker's rounding. At 0 decimals every `x.5` tie is
stored exactly, so tie mode acts alone; at 1 decimal most ties are not stored
exactly and the stored value decides the direction.
