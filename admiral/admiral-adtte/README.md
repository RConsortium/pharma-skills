# admiral-adtte

An agent skill for deriving ADaM Time-to-Event Analysis Datasets (ADTTE) using
the [{admiral}](https://pharmaverse.github.io/admiral/) R package.

## Overview

ADTTE is an ADaM dataset of type BDS-TTE (Basic Data Structure — Time to Event).
It contains one record per subject per TTE parameter and supports survival
analysis: Kaplan-Meier curves, log-rank tests, Cox proportional hazards models,
and restricted mean survival time. It is used across all therapeutic areas
wherever time-to-event endpoints are specified.

This skill encodes the workflow, function selection logic, and CDISC conventions
that an experienced admiral programmer applies when building ADTTE — enabling an
AI coding agent to generate QC-ready, audit-traceable R code from SDTM event
domains and a completed ADSL dataset.

## When to Use This Skill

Use `admiral-adtte` when you need to:

- Derive an ADTTE dataset from SDTM AE, DS, or CE domains using R and admiral
- Define event and censoring conditions using `event_source()` / `censor_source()`
- Derive AVAL in days with correct CDISC ≥1 day convention
- Annotate protocol-specific decisions (event definition, censoring window,
  CNSDTDSC terminology) with `# REVIEW:` comments
- Produce code structured for human QC review and regulatory submission

## Inputs Required

| Input | Required | Description |
|---|---|---|
| AE / DS / CE | Yes | Event source domain — depends on endpoint type |
| ADSL | Yes | Provides TRTSDT, TRTEDT, population flags |
| ADaM ADTTE spec | Yes | Event definition, censoring hierarchy, PARAMCD/PARAM, CNSDTDSC CT |
| Study context | Yes | Post-treatment window, censoring date priority, analysis population |

## Outputs

- Executable R code using admiral `derive_param_tte()` with named source objects
- AVAL in days (≥1, using `derive_vars_duration()` with `add_one = TRUE`)
- CNSR as integer 0/1, CNSDTDSC and EVNTDESC populated per CDISC convention
- `# REVIEW:` annotations at event filter, censoring date, CNSDTDSC CT, PARAMCD/PARAM
- Event/censor count printout for QC verification
- Structural assertions: CNSR ∈ {0,1}, AVAL ≥ 1, CNSDTDSC/EVNTDESC non-missing,
  uniqueness per USUBJID × PARAMCD, required variable coverage

## Skill Files

```
admiral-adtte/
├── SKILL.md          # Core agent instructions and workflow
├── DESIGN.md         # Scope, constraints, design decisions
├── README.md         # This file
├── benchmarks/
│   └── README.md     # Planned benchmark scenarios
└── LICENSE
```

## Dependencies

```r
library(admiral)          # >= 1.2.0
library(dplyr)
library(lubridate)

library(pharmaversesdtm)  # ae, ds for benchmark runs
library(pharmaverseadam)  # adsl reference
```

## Relationship to Other Skills

```
admiral-adsl        ← subject-level foundation (must be derived first)
admiral-adrs        ← tumor response (RECIST) — provides milestone dates for oncology PFS ADTTE
admiral-adtte       ← this skill (time-to-event, all therapeutic areas)
admiral-adae        ← adverse events (OCCDS)
admiral-bds         ← general BDS findings (ADVS, ADLB)
```

ADSL must be derived before ADTTE. For oncology PFS endpoints where the event
date is derived from tumor response milestones, derive ADRS first and use its
output as an event source.

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` and `eval` labels at
https://github.com/RConsortium/pharma-skills/issues.

The existing [#166](https://github.com/RConsortium/pharma-skills/issues/166)
benchmark ran against `admiral-bds` before this skill existed (+21 pp). Re-running
it against `admiral-adtte` will establish the improvement delta.

## References

- [admiral ADTTE vignette](https://pharmaverse.github.io/admiral/articles/adtte.html)
- [CDISC ADaMIG BDS-TTE v1.0](https://www.cdisc.org/standards/foundational/adam)
- [pharmaverse examples — ADTTE](https://pharmaverse.github.io/examples/)

## Author

Jeff Dickinson, Navitas Data Sciences
