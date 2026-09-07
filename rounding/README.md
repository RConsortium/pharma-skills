# Rounding Skill

Audit R code that prepares clinical-report statistics against a stated rounding
policy: ties away from zero, round once at display, fixed display precision
with trailing zeros.

## What it does

Given a pinned R source tree and an approved display-precision specification,
the skill inventories every operation that can change a displayed number or a
number that decides which rows appear, proves what each one does with executed
witnesses, and drafts a report for a named rule owner to classify.

BR-001: Values intended as exact decimal ties are rounded half away from zero. A displayed value is never a negative zero.

BR-002: Calculations use unrounded values; rounding occurs once, when the final result is prepared for display.

BR-003: Display precision is specified for each reported statistic and preserved, including trailing zeros.

It is an advisory drafting aid, not a QC replacement. It changes no source,
approves no classification, and posts nothing.

## Usage

Give a pinned repo link or a local path, plus the precision spec:

> "Audit rounding compliance of https://github.com/Merck/metalite.ae/tree/bdb23d472b16bc9dadbc774e64c5ca40321e9c6b against precision-spec.yml. Entry points are the `tlf_*()` functions; I'm the rule owner."

> "Verify rounding compliance of ~/projects/myanalysis using specs/precision.yml"

If a repo link is given, clone it at the pinned commit into a scratch directory
first and audit the working tree read-only.

## Inputs

- Pinned source tree and the report entry points
- Display-precision spec per reported statistic
- Tie policy and version, and the comparison helper the rule owner selected
- The rule owner's name
- Optional allowlist of sites already classified

## Outputs

- `report.md` (inventory table + Coverage, Findings, Clean checks, Limitations,
  decisions required, with embedded executed witnesses)

## Requirements

- R (>= 4.0) with `Rscript`. The scripts are base-R only; a half-away package
  (`cards`, `tidytlg`, `janitor`) is cross-checked when installed but is not
  required to produce witnesses.
- No source edits, policy changes, or external posting.

## Benchmark

`evals/` holds the benchmark for this skill: a seeded fixture package
(`evals/fixtures/myanalysis`), its approved precision spec, and the verified
`ANSWER-KEY.md`. See `evals/README.md`.

## License

[MIT](LICENSE)
