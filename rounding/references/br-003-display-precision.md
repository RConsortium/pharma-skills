# BR-003 -- Display precision

## Rule

Display precision is specified per reported statistic and preserved as
fixed-width character text, including trailing zeros. `76.00` is not `76`
or `76.0`.

## What does not pass

Numeric equality (`76 == 76.00` is `TRUE`) and default console printing.
Compare strings, not numbers: `formatC(76, format = "f", digits = 2)` must
give exactly `"76.00"`.

## FAIL signature

Observed string vs spec string with file:line, e.g. `"76"` where the spec
requires `"76.00"`.

## Fix

Fixed character output with a demonstrated example: `formatC(x, format =
"f", digits = 2)`, `sprintf("%.2f", x)`, or `tidytlg::roundSAS(...,
as_char = TRUE)`. A numeric-only helper is not accepted as a
trailing-zero fix. If the precision spec has no entry for the statistic,
the verdict is `NOT ASSESSABLE` -- state what is missing, do not invent it.
