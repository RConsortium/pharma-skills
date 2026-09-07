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

Run the default once for the environment record, then `--digits N` for every
distinct precision the target displays. A witness at the wrong precision does
not test the site.

- 0 digits: `c(-2.5, -1.5, 1.5, 2.5)` -- policy `c(-3, -2, 2, 3)`.
- 1 digit: `c(-1.25, 1.25)` -- policy `c(-1.3, 1.3)`.
- 2 digits: `c(-0.125, 0.125)` -- policy `c(-0.13, 0.13)`.
- Negative zero: a small negative value formatted at the display precision must
  not yield `"-0"` or `"-0.0"`.

A decimal tie is stored exactly only when it is an odd multiple of
`1/2^(digits+1)`: `0.5` at 0 decimals, `0.25`/`0.75`/`1.25` at 1, `0.125` at 2.
Only at such a value is the outcome predictable from the source, because only
there is tie mode the sole cause. The probe generates its vectors from that
identity and prints `inputs_exactly_representable` so the claim is checkable.

The probe computes the policy column with its own dependency-free half-away
arithmetic, so BR-002 and BR-003 witnesses are producible on a machine with no
rounding package installed. That built-in is for generating evidence. It is not
the fix a report should recommend -- see below.

## FAIL signature

Executed witness showing policy value vs actual value with file:line, e.g.
base-R `2` vs policy `3` for input `2.5` (and `-2` vs `-3` for `-2.5`).

Formatting calls fail this rule too, and for two reasons at once. Report them
separately: `formatC(1.25, format = "f", digits = 1)` is `"1.2"` where the
policy requires `"1.3"`, and at one decimal `formatC()` and `round()` disagree
with each other because binary representation, not tie mode, decides most of
those inputs.

## Fix

A versioned numeric helper with a usage example: `tidytlg::roundSAS(x,
digits)`, `cards::round5(x, digits)`, or `janitor::round_half_up(x,
digits)`. Pin the version (`janitor >= 2.1.0` and `scrutiny >= 0.2.5`
carry precision fixes). Show the helper producing the full
positive/negative tie vector. If that package is not installed, demonstrate the
pattern with the probe's built-in half-away arithmetic, say so plainly, and
record that the package's own behavior at inexact ties was not confirmed here --
an unrun recommendation is the part of a report a reader is most likely to paste
straight into the codebase. A numeric helper alone is not a
trailing-zero fix -- see `br-003-display-precision.md`.
