# Rounding Skill

Verify rounding compliance -- ties away
from zero, round-once-at-display, fixed display precision with trailing zeros.

## What it does

Given a repo link or a local folder, the skill verifies rounding compliance:

BR-001: Values intended as exact decimal ties are rounded half away from zero. A displayed value is never a negative zero.

BR-002: Calculations use unrounded values; rounding occurs once, when the final result is prepared for display.

BR-003: Display precision is specified for each reported statistic and preserved, including trailing zeros.


## Usage

Give a repo link (the skill clones it first):

> "Verify rounding compliance of https://github.com/Merck/metalite.ae/tree/bdb23d472b16bc9dadbc774e64c5ca40321e9c6b"

Or give a local path:

> "Verify rounding compliance of ~/projects/myanalysis"


## Outputs

- `report.md` (inventory table + Coverage, Findings, Clean checks,
  Limitations, with embedded executed witnesses)

## Requirements

- R (>= 4.0) with `Rscript`; rounding packages under test as needed.
- No source edits, policy changes, or external posting.


## License

[MIT](LICENSE)
