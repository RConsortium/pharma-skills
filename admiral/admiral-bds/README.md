# admiral-bds

An agent skill for deriving ADaM Basic Data Structure (BDS) findings datasets
using the [{admiral}](https://pharmaverse.github.io/admiral/) R package and
the pharmaverse ecosystem.

## Overview

BDS datasets provide the analytic structure for findings — measurements recorded
at multiple timepoints per subject per parameter. This skill covers ADVS (vital
signs) and ADLB (laboratory values), the two most universally required BDS
datasets in clinical study submissions.

The skill encodes the workflow, function selection logic, and CDISC conventions
for deriving AVAL, BASE, CHG, PCHG, ABLFL, ANL01FL, and the full supporting
variable set — enabling an AI coding agent to generate QC-ready, submission-
traceable R code from SDTM inputs and an ADaM BDS specification.

## When to Use This Skill

Use `admiral-bds` when you need to:

- Derive ADVS or ADLB from SDTM VS or LB domains
- Generate standard BDS variables (PARAM, ADT, ADY, AVISIT, AVAL, BASE, CHG)
- Flag baseline records (ABLFL) and derive change from baseline
- Assign analysis visits (AVISIT, AVISITN) from a spec-driven visit map
- Derive reference range indicators (ANRIND, BNRIND) for ADLB
- Produce code structured for human QC review and regulatory submission

## Prerequisites

ADSL must be completed before running this skill. Treatment dates (TRTSDT,
TRTEDT) and population flags (SAFFL, ITTFL) from ADSL are merged into BDS
datasets and are required for baseline flagging and analysis flag derivations.

## Inputs Required

| Input | Required | Description |
|---|---|---|
| VS (for ADVS) or LB (for ADLB) | Yes | SDTM source domain |
| ADSL | Yes | Subject-level dataset with TRTSDT, TRTEDT, population flags |
| ADaM BDS spec | Yes | Parameter list, visit map, baseline definition, analysis flag rules |
| Study context | Yes | Baseline window definition, ANL01FL criteria per SAP |

## Outputs

- Executable R code for ADVS or ADLB derivation using admiral functions
- Parameter assignment from spec-driven lookup table
- Date derivation (ADT, ADTF, ADY) using `derive_vars_dt()` and `derive_vars_dy()`
- Visit assignment (AVISIT, AVISITN) from spec-driven visit map
- Baseline flagging (ABLFL) using `restrict_derivation()` + `derive_var_extreme_flag()`
- Baseline values (BASE, BASEC) using `derive_var_base()`
- Change from baseline (CHG, PCHG) using `derive_var_chg()` / `derive_var_pchg()`
- Normal range variables for ADLB (ANRLO, ANRHI, ANRIND, BNRIND)
- `# REVIEW:` annotations at every protocol-specific decision point
- Programmatic assertions for dataset uniqueness and required variables

## Skill Files

```
admiral-bds/
├── SKILL.md                          # Core agent instructions and workflow
├── DESIGN.md                         # Scope, constraints, design decisions
├── README.md                         # This file
├── references/
│   └── bds-conventions.md            # BDS variable conventions and structure
├── benchmarks/
│   └── README.md                     # Benchmark index and instructions
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
library(pharmaversesdtm)  # VS, LB SDTM datasets
library(pharmaverseadam)  # ADVS, ADLB reference outputs for benchmarks
```

## Scope and Limitations

**In scope:**
- ADVS derivation from SDTM VS
- ADLB derivation from SDTM LB, including normal range and reference range indicators
- Single baseline definition per parameter (BASETYPE not required)
- Spec-driven visit lookup

**Out of scope (initial release):**
- ADEG, ADRS, ADEF, ADEX, ADTTE (see planned follow-on skills)
- Date-driven visit windowing (ADY-range-based AVISIT)
- Multiple baseline types (BASETYPE)
- CTCAE toxicity grading beyond ADLB
- Therapeutic-area-specific admiral extensions

## Relationship to Other Skills

```
admiral/
├── SKILL.md              ← shared conventions
├── admiral-adsl/         ← derive this first; provides TRTSDT, TRTEDT, flags
├── admiral-bds/          ← this skill (ADVS, ADLB)
└── admiral-adae/         ← planned (adverse events, OCCDS)
```

## Evaluation Criteria

Agent output is evaluated against the following dimensions:

| Dimension | What is assessed |
|---|---|
| **Correctness** | AVAL, BASE, CHG, PCHG values match reference output |
| **admiral idioms** | `restrict_derivation()` for ABLFL; `derive_var_base()` not manual join |
| **CDISC conformance** | ABLFL/ANL01FL `"Y"`/`NA`; date imputation direction; study day convention |
| **QC readiness** | `# REVIEW:` at baseline window, ANL01FL, visit map, ANRIND |
| **Completeness** | Required BDS variables present; uniqueness assertion present |

## References

- [admiral ADVS vignette](https://pharmaverse.github.io/admiral/articles/advs.html)
- [admiral ADLB vignette](https://pharmaverse.github.io/admiral/articles/adlb.html)
- [CDISC ADaMIG v1.3 — BDS](https://www.cdisc.org/standards/foundational/adam)
- [pharmaverse examples — BDS](https://pharmaverse.github.io/examples/)

## Author

Jeff Dickinson, Navitas Data Sciences
Admiral Core Team member
