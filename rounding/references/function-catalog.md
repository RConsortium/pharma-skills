# Function catalog (minimum search -- not the ceiling)

`scripts/scan-rounding-calls.R` walks R's parse tree rather than grepping text,
so a name in a comment or a string is never reported and a call split across
lines is still found. It classifies every hit into one of four labels. Carry
those labels into the report: they are what lets a reader separate reproducible
output from your reasoning.

## Reporting paths define scope

Scan from the repository root. Installed `R/` code is only one reporting
surface: executable chunks in vignettes, READMEs, and other `.Rmd`/`.qmd`/`.Rnw`
files are in scope when they calculate or prepare statistics for a table,
listing, figure annotation, or report file. They do not need to be called by an
export. Exclude layout/encoding math and ordinary tests with reasons, but do not
exclude reporting examples merely because they live under `vignettes/`.

## `catalog/quantize` -- rounded numeric out

`round()`, `signif()`, `ceiling()`, `floor()`, `trunc()`, `cards::round5()`,
`tidytlg::roundSAS()`, `janitor::round_half_up()`, `scrutiny::round_up()`,
`plyr::round_any()`.

## `catalog/display` -- formatted text out, rounds as a side effect

`formatC()`, `sprintf()`, `format()`, `prettyNum()`, `as.character()`,
`toString()`.

These are in scope precisely because they round without being asked to. Neither
`formatC()` nor `sprintf()` is half-away: `formatC(1.25, format = "f", digits =
1)` gives `"1.2"` where the policy requires `"1.3"`.

## `operator/quantize` -- quantizes with no function name at all

`%/%`. An expression such as `(x * 10) %/% 1 / 10` truncates to one decimal
while matching no name any catalog can list. A text search cannot find this;
the parse tree can.

## `operator/modulo` -- quantizes only in one idiom

`%%`. It quantizes in `x - x %% unit`, but far more often it extracts a key or
tests parity, so it is labelled separately rather than inflating the quantizer
count. Triage each one; most are not rounding.

## `wrapper` -- a user function that reaches a catalog call

The scanner resolves user-defined functions to a fixpoint, so
`report_x() -> pct_label() -> %/%` is reported even though only the innermost
step is a catalog name. Rounding is usually one or two calls removed from the
name you searched for.

## Excluded -- list in Coverage with file:line + reason, never score

Sites that cannot reach a report cell. The scanner excludes by enclosing
function name (`solver_*`, `plot_*`, `gg_*`, `theme_*`); everything else is
your triage, and every exclusion needs a stated reason. Common cases: character
or structural input rather than numeric, numerical tolerances, plot
coordinates, and code not reachable from a report entry point.

## What the scanner cannot see

Its own output says this, and the report's Limitations section must repeat it:

- Calls assembled at run time -- `do.call()`, `get()`, `match.fun()`, a format
  string built by `paste0()` or `glue()`. `do.call(sprintf, list(spec, x))`
  produces **zero** hits.
- S3/S4 dispatch to a method whose body rounds.
- Rounding inside a dependency you did not scan.

## Method

1. Run the scanner. Record every hit, including ones you later exclude. A file
   reported with `hits: 0` was scanned, not cleared.
2. Read the source for the paths above and label anything you add
   `exploratory`, so it stays distinguishable from scanner output.
3. Finding one `round()` never establishes coverage, and neither does a clean
   scanner run. State what you searched and what you could not.
