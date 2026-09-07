# BR-001 -- Tie method

## Rule

Values intended as exact decimal ties round half away from zero
(`2.5 -> 3`, `-2.5 -> -3`, SAS-compatible). A displayed value is never a
negative zero (`-0`, `-0.0`).

## Why R code fails this rule

Two distinct causes -- report them separately, never as one blanket claim:

1. **Tie mode.** `base::round()` rounds to nearest even at a true tie:
   `round(c(-2.5, -1.5, 1.5, 2.5), 0)` gives `c(-2, -2, 2, 2)`.
2. **Binary representation.** Most decimal ties are not stored exactly
   (e.g. `2.05` sits just below the intended tie), so the outcome follows
   the stored value, not the printed one. Source inspection alone cannot
   predict every direction -- the executed probe is the evidence.

## Probe vectors (run `scripts/probe-tie-behavior.R`)

- 0 digits: `c(-2.5, -1.5, 1.5, 2.5)` -- policy `c(-3, -2, 2, 3)`.
- 1 digit: `c(-1.25, 1.25)` -- policy `c(-1.3, 1.3)`.
- 2 digits: `c(-0.125, 0.125)` -- policy `c(-0.13, 0.13)`.
- Negative zero: `formatC(-0.5, digits = 0, format = "f")` must not yield
  `"-0"`.

## FAIL signature

Executed witness showing policy value vs actual value with file:line, e.g.
base-R `2` vs policy `3` for input `2.5` (and `-2` vs `-3` for `-2.5`).

## Fix

A versioned numeric helper with a usage example: `tidytlg::roundSAS(x,
digits)`, `cards::round5(x, digits)`, or `janitor::round_half_up(x,
digits)`. Pin the version (`janitor >= 2.1.0` and `scrutiny >= 0.2.5`
carry precision fixes). Show the helper producing the full
positive/negative tie vector. A numeric helper alone is not a
trailing-zero fix -- see `br-003-display-precision.md`.
