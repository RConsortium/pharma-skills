# admiral-adsl

An agent skill for deriving ADaM Subject-Level Analysis Datasets (ADSL) using
the [{admiral}](https://pharmaverse.github.io/admiral/) R package and the
pharmaverse ecosystem.

## Overview

ADSL is the foundational ADaM dataset required for every clinical study
regulatory submission. It contains one record per subject and provides
subject-level population flags, treatment variables, demographic information,
disposition, and key dates that are merged into all other ADaM datasets.

This skill encodes the workflow, function selection logic, and CDISC conventions
that an experienced admiral programmer applies when building ADSL — enabling an
AI coding agent to generate QC-ready, audit-traceable R code from SDTM inputs
and an ADaM specification.

## When to Use This Skill

Use `admiral-adsl` when you need to:

- Derive an ADSL dataset from SDTM domains using R and admiral
- Generate standard subject-level variables (treatment dates, disposition
  status, demographic groupings, population flags)
- Produce code that is structured for human QC review and regulatory submission
- Apply CDISC ADaM conventions correctly (flag values, date imputation, study
  day calculation, dataset attributes)

## Inputs Required

| Input | Required | Description |
|---|---|---|
| DM | Yes | Subject spine — one record per USUBJID |
| EX | Yes | Exposure — treatment dates and dose |
| DS | Yes | Disposition — end of study status, reason for discontinuation |
| MH | No | Medical history — if protocol-required flags needed |
| VS | No | Vital signs — if HEIGHTBL, WEIGHTBL, BMIBL in scope |
| ADaM ADSL spec | Yes | Variable list, derivation rules, grouping cut-points |
| Study context | Yes | Treatment arm names, population flag definitions per SAP |

## Outputs

- Executable R code using admiral functions following pharmaverse idioms
- Derivations for standard ADSL variables including treatment dates, planned
  and actual treatment, disposition, baseline demographics, and population flags
- `# REVIEW:` annotations at every protocol-specific decision point
- Programmatic assertions (one record per USUBJID, required variables present)
- Dataset and variable attribute application via `{xportr}` and `{metacore}`

## Skill Files

```
admiral/
├── SKILL.md                          # Shared conventions (parent)
└── admiral-adsl/
    ├── SKILL.md                      # Core agent instructions and workflow
    ├── DESIGN.md                     # Scope, constraints, design decisions
    ├── README.md                     # This file
    ├── references/
    │   ├── admiral-functions.md      # Function selection guide
    │   └── adsl-conventions.md       # CDISC variable and CT conventions
    ├── benchmarks/
    │   ├── basic-two-arm/            # Simple parallel-group study
    │   ├── multi-arm/                # Three or more treatment arms
    │   ├── missing-dates/            # Partial --DTC imputation
    │   ├── early-discontinuation/    # Subjects who did not complete
    │   └── screen-failure/           # Subjects who never received treatment
    └── LICENSE
```

## Dependencies

```r
# Core
library(admiral)          # >= 1.2.0
library(dplyr)
library(lubridate)

# Metadata and submission
library(metacore)
library(xportr)

# Test data
library(pharmaversesdtm)  # SDTM input datasets for benchmarks
library(pharmaverseadam)  # Reference ADaM outputs for benchmarks
```

## Running Benchmarks

Each benchmark directory contains:

- `input/` — SDTM datasets (derived from `pharmaversesdtm` or study-specific)
- `prompt.md` — The natural language prompt given to the agent
- `expected/` — Expected output variables and values for evaluation
- `rubric.md` — Scoring criteria for evaluating agent output

To run a benchmark manually:

1. Give the agent the contents of `prompt.md` and the SKILL.md
2. Execute the generated R code against the input datasets
3. Compare output against `expected/` using the criteria in `rubric.md`

## Evaluation Criteria

Agent output is evaluated against the following dimensions:

| Dimension | What is assessed |
|---|---|
| **Correctness** | Key variable values match expected output (TRTSDT, TRTEDT, SAFFL, EOSSTT) |
| **admiral idioms** | Correct function selection — `derive_vars_merged()` not `slice()`, `derive_vars_dy()` not manual subtraction |
| **CDISC conformance** | Flag convention (`"Y"`/`NA` not `"N"`), date imputation direction, one record per USUBJID |
| **QC readiness** | `# REVIEW:` comments at protocol-specific points, derivation comments, assertions present |
| **Completeness** | Required variables present, dataset attributes applied |

## Scope and Limitations

**In scope:**
- Standard ADSL derivation for parallel-group and simple crossover studies
- Single-period treatment variables (TRT01P/TRT01A pattern)
- SDTM inputs following CDISC SDTMIG conventions
- R implementation using admiral

**Out of scope:**
- Non-ADSL ADaM datasets (see planned follow-on skills: `admiral-adae`,
  `admiral-adtte`, `admiral-bds`)
- SAS implementation
- Therapeutic-area-specific extensions (`{admiralonco}`, `{admiralvaccine}`)
- Highly complex crossover designs with four or more periods
- Integrated analysis across multiple studies

## Relationship to Other Skills

This skill is the first in a planned family of admiral ADaM derivation skills:

```
admiral/
├── SKILL.md          ← shared conventions (parent)
├── admiral-adsl/     ← this skill (subject-level foundation)
├── admiral-bds/      ← BDS findings: ADVS, ADLB
└── admiral-adae/     ← adverse events, OCCDS (planned)
```

ADSL must be derived before any other ADaM dataset, as population flags and
treatment variables from ADSL are merged into all downstream datasets.

## References

- [admiral documentation](https://pharmaverse.github.io/admiral/)
- [admiral ADSL vignette](https://pharmaverse.github.io/admiral/articles/adsl.html)
- [CDISC ADaMIG v1.3](https://www.cdisc.org/standards/foundational/adam)
- [pharmaverse examples — ADSL](https://pharmaverse.github.io/examples/)
- [xportr documentation](https://atorus-research.github.io/xportr/)

## Contributing

Benchmark additions and refinements to SKILL.md are welcome. Please open an
issue before submitting a PR to discuss the proposed change. See the repo-level
[LIFECYCLE.md](../../LIFECYCLE.md) for the skill development process.

## Author

Jeff Dickinson, Navitas Data Sciences  
Admiral Core Team member
