# Function catalog (minimum search -- not the ceiling)

## Quantizing (rounded numeric out)

`round()`, `signif()`, `cards::round5()`, `tidytlg::roundSAS()`,
`janitor::round_half_up()`, `scrutiny::round_up()`, `ceiling()`,
`floor()`, `trunc()`.

## Display and conversion (formatted text out -- rounds as a side effect)

`formatC()`, `sprintf()`, `format()`, `prettyNum()`, `as.character()`,
`paste0()`-wrapped numerics.

## Excluded -- list in Coverage with file:line + reason, never score

`solver_*()` internals; `plot_*()` and plot-coordinate `round()` calls.

## Method

1. Run `scripts/scan-rounding-calls.R` as a first pass; record file:line
   plus the source expression for every match, including later exclusions.
   A file with no matches is not cleared.
2. Infer where rounding hides beyond literal names: wrapper and helper
   functions (e.g. `R/rounding-helpers.R`), custom `round_*` utilities, S3/S4
   methods and generics, `do.call`/`get` dispatch, format strings assembled
   by `paste`/`paste0`/`glue`, and implicit numeric-to-text coercion in
   table builders. Rounding is often one call removed from the name above.
3. Label each candidate `catalog` or `exploratory`. Finding one `round()`
   never establishes coverage, and neither does a clean scanner run.
