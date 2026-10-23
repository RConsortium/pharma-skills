# admiral-adpc

An agent skill for deriving ADaM Pharmacokinetic Concentrations Analysis
Datasets (ADPC, also called ADNCA) using the
[{admiral}](https://pharmaverse.github.io/admiral/) R package.

## Overview

ADPC is an ADaM BDS dataset with one record per PK concentration, dosing
record, or derived record. It carries nominal and actual times relative to the
first and most recent dose, so it can be passed directly to non-compartmental
analysis (NCA) tools such as {PKNCA}, and it is the starting point for
population PK datasets (ADPPK).

This skill encodes the workflow from admiral's `ad_adpc.R` template and
`pk_adnca` vignette, plus the CDISC conventions and QC annotations an
experienced admiral PK programmer applies — enabling an AI coding agent to
generate QC-ready R code from SDTM PC and EX and a completed ADSL.

## When to Use This Skill

Use `admiral-adpc` when you need to:

- Derive ADPC / ADNCA from SDTM PC and EX using R and admiral
- Derive nominal and actual relative times (NFRLT, AFRLT, NRRLT, ARRLT) with
  admiral functions instead of `difftime()` and `lag()`
- Expand dosing intervals into individual doses and match each sample to its
  previous and next dose
- Handle BLQ concentrations with derived `DTYPE` records
- Prepare PK concentration data for an NCA tool

## Inputs Required

| Input | Required | Description |
|---|---|---|
| PC | Yes | Concentrations, specimen, LLOQ, sampling datetime and timepoint |
| EX | Yes | Dose amount, frequency, start/end dates |
| ADSL | Yes | TRTSDT, TRTSDTM, treatment variables, population flags |
| VS | Optional | Baseline height and weight for covariates |
| ADaM ADPC spec | Yes | PARAMCD/PARAM, planned dose by arm, BLQ rule, analysis flags |
| Study context | Yes | Single or multiple dose, dosing frequency, sampling schedule |

## Outputs

- Executable R code following the admiral ADPC template step order
- Concentration (analyte) and DOSE records, with PARCAT1 = specimen
- NFRLT, AFRLT, NRRLT, ARRLT, MRRLT in hours, with FRLTU/RRLTU
- PCRFTDTM, ATPTREF, BASETYPE per reference dose; DOSEA, DOSEP, DOSEU
- BLQ imputations and pre-dose copies as `DTYPE` derived records
- ABLFL, BASE, CHG, ANL01FL, ANL02FL, ASEQ; HTBL, WTBL, BMIBL covariates
- `# REVIEW:` annotations at nominal time mapping, imputed dose times,
  never-dosed subjects, planned dose, BLQ rule and analysis flags
- Record-count printout and structural assertions for QC

On the CDISC pilot data, the skill's workflow reproduces
`pharmaverseadam::adpc` record for record.

## Skill Files

```
admiral-adpc/
├── SKILL.md                    # Core agent instructions and workflow
├── DESIGN.md                   # Scope, constraints, design decisions
├── README.md                   # This file
├── references/
│   └── pknca-handoff.md        # Passing ADPC to PKNCA for NCA
├── benchmarks/
│   └── README.md               # Where benchmarks are tracked
└── LICENSE
```

## Dependencies

```r
library(admiral)          # >= 1.4.0
library(dplyr)
library(lubridate)
library(stringr)

library(pharmaversesdtm)  # pc, ex, vs for benchmark runs
library(pharmaverseadam)  # adsl input; adpc reference output
```

## Relationship to Other Skills

```
admiral-adsl        ← subject-level foundation (must be derived first)
admiral-adpc        ← this skill (PK concentrations, NCA input)
admiral-adppk       ← planned: population PK, reuses ADPC time derivations
admiral-bds         ← general BDS findings (ADVS, ADLB)
```

ADSL must be derived before ADPC. NCA parameters (ADPP) are computed from ADPC
by an NCA tool such as {PKNCA}, not by this skill.

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` label at
https://github.com/RConsortium/pharma-skills/issues.

## References

- [admiral PK NCA and population PK vignette](https://pharmaverse.github.io/admiral/articles/pk_adnca.html)
- [CDISC ADaM Implementation Guide for NCA (ADNCA)](https://www.cdisc.org/standards/foundational/adam)
- [PKNCA](https://humanpred.github.io/pknca/)

## Author

Jeff Dickinson, Navitas Data Sciences
