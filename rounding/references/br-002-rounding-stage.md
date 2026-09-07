# BR-002 -- Rounding stage (v1.0, illustrative, not an industry standard)

## Rule

Calculations use unrounded values; rounding occurs once, when the final
result is prepared for display. No early quantization before aggregation,
filtering, or threshold decisions.

## Failure patterns

- Rounding inputs before `mean()`/`sum()` and then displaying: early-rounded
  display `1.5` vs round-once display `1.4` for `x <- c(1.25, 1.25, 1.75)`
  at one decimal.
- Rounding a percentage before a row-inclusion threshold: the rounded value,
  not the true value, decides whether the row appears (e.g. `round(2.5)` is
  `2`, so a `>= 2.5` threshold wrongly excludes it).

## Tracing

Trace paired sites together: the early call plus its downstream display or
decision call form one finding. A call judged alone is not a stage verdict.

## FAIL signature

Executed before/after witness for identical inputs with both file:lines,
e.g. early-rounded `1.5` vs round-once `1.4`.

## Fix

Remove the early quantization and demonstrate aggregation from unrounded
inputs. Do not "fix" by swapping the rounding function -- the stage, not
the function, is the defect.
