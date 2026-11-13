# gsDose Skill for Claude Code

A [Claude Code](https://claude.ai/code) skill for **inferentially seamless phase 2/3
adaptive designs with dose selection in the phase 2 part** — multi-arm multi-stage
(MAMS) group sequential trials where one dose is selected at an interim and patients
from before and after dose selection are combined in the confirmatory inference.
Built on the R package [gsDose](https://github.com/eric-zhang16/gsDose)
(Zhang & Jin 2025, doi:10.1080/19466315.2025.2539831).

**The skill's core is a structured Q&A**: it walks the user through the design
one question at a time (Q1–Q12, plus an observed-data intake at an analysis) —
collecting dose arms, sample sizes, cohort and stage weights, events, alpha
spending and futility choices with validation and plain-English explanations at
each step — then runs the gsDose calculations and delivers a standardized output
bundle. Users don't need to know the package API; they need to know their trial.

**Status: v0.1** — both workflows implemented and benchmarked: the bundled
scripts and the end-to-end eval reproduce the package vignette's results exactly
(design boundaries 2.963/2.267/2.029; IA3 boundary 2.224 with all four
intersection hypotheses rejected).

## What It Does

Given an oncology trial scenario with a survival endpoint and multiple dose arms,
this skill:

1. **Collects inputs** — dose arms, selection timing and rule, HR assumptions,
   alpha/power, spending function, number of looks
2. **Computes boundaries** — group sequential efficacy boundaries via `gsBoundary()`
3. **Combines cohorts** — inverse normal combination test (`combTest()`) across
   patients enrolled before and after dose selection
4. **Controls multiplicity** — Dunnett-based closed testing across dose arms
   (`combDunnett()`)
5. **Reports** — a structured output folder with the result summary in Word and JSON (design assumptions, analysis plan, boundaries, and the closed-testing decision when an analysis is performed) plus a standalone `gsdose_reproduce.R` that re-derives every reported number

## Requirements

### R (>= 4.0)
- `gsDose` — this package (GitHub)
- [`gsDesign`](https://cran.r-project.org/package=gsDesign) — spending functions (sfHSD, sfLDOF)
- [`gsDesign2`](https://cran.r-project.org/package=gsDesign2) — expected events/timing for deriving stage weights
- [`mvtnorm`](https://cran.r-project.org/package=mvtnorm) — multivariate normal probabilities
- [`jsonlite`](https://cran.r-project.org/package=jsonlite) — config/result I/O for bundled scripts

### Python (>= 3.8)
- [`python-docx`](https://pypi.org/project/python-docx/) — Word report generation

## Installation

Copy the `gsdose-skill/` folder into your project's `.claude/skills/` directory and
install the R dependencies:

```r
install.packages(c("gsDesign", "mvtnorm"))
remotes::install_github("eric-zhang16/gsDose")
```

## Usage

- Type `/gsdose`, or
- Describe the task naturally, e.g.:

> "Design a seamless phase 2/3 trial with 3 dose arms vs control, OS endpoint,
> dose selection at 40% information, O'Brien-Fleming-like spending"

## Skill File Reference

| File | Purpose |
|------|---------|
| `SKILL.md` | Main entry point — structured Q&A (Q1–Q12, B-Q1–B-Q4) and both workflows |
| `examples.md` | The package vignette's worked example, end to end |
| `scripts/compute_w_weights.R` | Cohort-1 stage weights (w) from expected events (gsDesign2) |
| `scripts/compute_boundary.R` | Efficacy/futility boundaries via gsDose::gsBoundary |
| `scripts/compute_test.R` | Combination test + Dunnett closed testing (gsDose::combTest) |
| `scripts/gsdose_report_template.py` | Word report generator (reads the results JSONs) |
| `evals/` | Evaluation scenarios |

Files are read lazily — only loaded when the workflow reaches the corresponding step.

## License

[MIT](LICENSE)
