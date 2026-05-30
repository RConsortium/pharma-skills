# admiral-adae

An agent skill for deriving ADaM Adverse Events Analysis Datasets (ADAE) using
the [{admiral}](https://pharmaverse.github.io/admiral/) R package and the
pharmaverse ecosystem.

## Overview

ADAE is an ADaM dataset of type OCCDS (Occurrence Data Structure). It contains
one record per adverse event per subject and is the primary dataset for safety
analysis in clinical trial submissions. It supports treatment-emergent adverse
event (TEAE) summaries, severity and causality analysis, serious adverse event
tables, and MedDRA-coded output for regulatory reporting.

This skill encodes the workflow, function selection logic, and CDISC conventions
that an experienced admiral programmer applies when building ADAE — enabling an
AI coding agent to generate QC-ready, audit-traceable R code from SDTM AE and
a completed ADSL dataset.

## When to Use This Skill

Use `admiral-adae` when you need to:

- Derive an ADAE dataset from SDTM AE (and supporting domains) using R and admiral
- Generate the treatment-emergent adverse event flag (TRTEMFL) and its date
  infrastructure (ASTDT, AENDT, ASTDY, AENDY)
- Derive severity, seriousness, causality, and outcome variables following CDISC
  ADaM conventions
- Produce code structured for human QC review and regulatory submission
- Apply the `"Y"`/`NA` flag convention correctly across all ADAE flag variables

## Inputs Required

| Input | Required | Description |
|---|---|---|
| AE | Yes | One record per AE per subject; subject spine for ADAE |
| ADSL | Yes | Provides TRTSDT, TRTEDT, TRT01P/A, population flags |
| MH | No | Medical history — if PREFL (pre-existing condition flag) in scope |
| CM | No | Concomitant medications — if linked causality flags in scope |
| ADaM ADAE spec | Yes | Variable list, derivation rules, TEAE window definition, grading rules |
| Study context | Yes | TEAE post-treatment window (days), SMQ scope, severity scale (CTCAE vs sponsor) |

## Outputs

- Executable R code using admiral functions following pharmaverse idioms
- Derivations for ASTDT/AENDT (with imputation flags), ASTDY/AENDY, TRTEMFL,
  AESEV/AESEVN, AESER, AESDTH, AEOUT, AEREL/AERELN, AEACN
- Optional: PREFL from MH, AMAXSEVFL using `restrict_derivation()`, SMQ grouping
  flags via `derive_vars_query()`
- `# REVIEW:` annotations at every protocol-specific decision point (TEAE window,
  causality mapping, SMQ membership, severity ordering)
- Programmatic assertions (AE non-empty, required variables present, row count
  preserved after merge)
- Dataset and variable attribute application via `{xportr}` and `{metacore}`

## Skill Files

```
admiral-adae/
├── SKILL.md                          # Core agent instructions and workflow
├── DESIGN.md                         # Scope, constraints, design decisions
├── README.md                         # This file
├── references/
│   ├── admiral-adae-functions.md     # Function selection guide for ADAE
│   └── adae-conventions.md           # CDISC ADAE variable and CT conventions
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

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` and `eval` labels at
https://github.com/RConsortium/pharma-skills/issues.

## Evaluation Criteria

Agent output is evaluated against the following dimensions:

| Dimension | What is assessed |
|---|---|
| **Correctness** | Key variable values match expected output (TRTEMFL, ASTDT, AENDT, AESEV, AESER) |
| **admiral idioms** | Correct function selection — `derive_var_trtemfl()` not manual date comparison; `derive_vars_dt()` not `as.Date()` |
| **CDISC conformance** | Flag convention (`"Y"`/`NA` not `"N"`), imputation flags retained, one record per AE per subject |
| **QC readiness** | `# REVIEW:` comments at protocol-specific points (TEAE window, causality CT, SMQ lists), assertions present |
| **Completeness** | Required variables present, ADSL merged selectively, dataset attributes applied |

## Scope and Limitations

**In scope:**
- Standard ADAE derivation for parallel-group studies
- TEAE flag derivation using `derive_var_trtemfl()`
- Severity, seriousness, causality, and outcome variables from AE SDTM
- Pre-existing condition flag (PREFL) from MH
- Maximum severity flag (AMAXSEVFL) using `restrict_derivation()`
- SMQ/grouping flag derivation via `derive_vars_query()`
- SDTM inputs following CDISC SDTMIG conventions
- R implementation using admiral

**Out of scope:**
- Non-ADAE ADaM datasets (see `admiral-adsl`, `admiral-adtte`, `admiral-bds`)
- SAS implementation
- Therapeutic-area-specific extensions (`{admiralonco}`, `{admiralvaccine}`)
- Highly complex multi-arm crossover TEAE attribution
- Integrated summary of safety across multiple studies

## Relationship to Other Skills

This skill is the second in a planned family of admiral ADaM derivation skills:

```
admiral-adsl        ← subject-level foundation (must be derived first)
admiral-adae        ← this skill (adverse events, OCCDS)
admiral-adtte       ← time-to-event (BDS-TTE)
admiral-adex        ← exposure (BDS)
admiral-bds         ← general BDS (findings, efficacy)
```

ADSL must be derived before ADAE. TRTSDT, TRTEDT, and population flags from
ADSL are required for TEAE derivation and are merged onto every AE record.

## References

- [admiral documentation](https://pharmaverse.github.io/admiral/)
- [admiral ADAE vignette](https://pharmaverse.github.io/admiral/articles/adae.html)
- [CDISC ADaMIG v1.3](https://www.cdisc.org/standards/foundational/adam)
- [pharmaverse examples — ADAE](https://pharmaverse.github.io/examples/)
- [xportr documentation](https://atorus-research.github.io/xportr/)

## Contributing

Benchmark additions and refinements to SKILL.md are welcome. Please open an
issue before submitting a PR to discuss the proposed change. See the repo-level
[LIFECYCLE.md](../LIFECYCLE.md) for the skill development process.

## Author

Jeff Dickinson, Navitas Data Sciences
Admiral Core Team member
