# admiral-adrs

An agent skill for deriving ADaM Tumor Response Analysis Datasets (ADRS) using
the [{admiral}](https://pharmaverse.github.io/admiral/) and
[{admiralonco}](https://pharmaverse.github.io/admiralonco/) R packages.

## Overview

ADRS is an ADaM dataset that contains tumor response assessments derived from
SDTM RS domain data following RECIST criteria. It is the primary dataset for
oncology efficacy analysis: overall response rate (ORR), confirmed ORR, best
overall response (BOR), and clinical benefit rate (CBR).

This skill encodes the workflow, function selection logic, and CDISC conventions
that an experienced admiralonco programmer applies when building ADRS — enabling
an AI coding agent to generate QC-ready, audit-traceable R code from SDTM RS
and a completed ADSL dataset.

## When to Use This Skill

Use `admiral-adrs` when you need to:

- Derive an ADRS dataset from SDTM RS using R, admiral, and admiralonco
- Implement RECIST 1.1 confirmed response (CR/PR ≥28 days apart)
- Derive Best Overall Response (BOR) with correct NE propagation and hierarchy
- Derive clinical benefit (durable SD/PR/CR ≥42 days from a reference date)
- Produce code structured for human QC review and regulatory submission
- Verify confirmed ORR ≤ unconfirmed ORR with programmatic assertions

## Inputs Required

| Input | Required | Description |
|---|---|---|
| RS | Yes | One record per tumor assessment per subject (RSSTRESC: CR/PR/SD/PD/NE) |
| ADSL | Yes | Provides TRTSDT, RANDDT, treatment labels, population flags |
| ADaM ADRS spec | Yes | PARAMCD/PARAM mapping, confirmation window, clinical benefit definition |
| Study context | Yes | RECIST version, assessor (investigator vs BICR), confirmation window, clinical benefit anchor |

## Outputs

- Executable R code using admiralonco functions following pharmaverse idioms
- Five standard ADRS parameters: OVRLRESP, RSP, CONFIRMED, BESTRESP, CBRESPFL
- `# REVIEW:` annotations at every protocol-specific decision point:
  confirmation window (`ref_confirm`), NE handling (`missing_as_ne`), clinical
  benefit anchor (`reference_date`, `ref_start_window`), PARAMCD/PARAM mapping
- Programmatic verification: confirmed vs unconfirmed ORR comparison printed,
  `stopifnot(confirmed_n <= unconfirmed_n)` assertion, PD-never-confirmed check
- Structural assertions: required parameter coverage, uniqueness per subject ×
  PARAMCD, required variable presence

## Skill Files

```
admiral-adrs/
├── SKILL.md          # Core agent instructions and workflow
├── DESIGN.md         # Scope, constraints, design decisions
├── README.md         # This file
├── benchmarks/
│   └── README.md     # Planned benchmark scenarios
└── LICENSE
```

## Dependencies

```r
# Core
library(admiral)        # >= 1.2.0
library(admiralonco)    # >= 1.0.0
library(dplyr)
library(lubridate)

# Test data
library(pharmaversesdtm)  # rs_onco_recist for benchmark runs
library(pharmaverseadam)  # reference ADaM outputs
```

## Key Gotchas

**pharmaversesdtm:** The plain `rs` object is no longer exported. Use
`rs_onco_recist` for test data.

**Flag convention exception:** `CONFIRMED` and `CBRESPFL` use `"Y"`/`"N"`,
not `"Y"`/`NA` — this is the admiralonco contract for these response-existence
parameters. Do not recode.

**DOMAIN removal timing:** Remove DOMAIN from RS in Step 2, before any
`derive_param_*()` call, not in the final `select()`.

## Benchmarks

Benchmarks are tracked as GitHub issues with the `benchmark` and `eval` labels at
https://github.com/RConsortium/pharma-skills/issues.

## Relationship to Other Skills

```
admiral-adsl        ← subject-level foundation (must be derived first)
admiral-adrs        ← this skill (tumor response, RECIST)
admiral-adtte       ← time-to-event (PFS often uses ADRS milestone dates)
admiral-adae        ← adverse events (OCCDS)
admiral-bds         ← general BDS findings (ADVS, ADLB)
```

ADSL must be derived before ADRS. RANDDT and TRTSDT from ADSL are required for
clinical benefit and study day derivation.

## References

- [admiralonco documentation](https://pharmaverse.github.io/admiralonco/)
- [admiralonco ADRS vignette](https://pharmaverse.github.io/admiralonco/articles/adrs.html)
- [CDISC ADaMIG v1.3](https://www.cdisc.org/standards/foundational/adam)
- [RECIST 1.1 guidelines](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3107559/)
- [pharmaverse examples — ADRS](https://pharmaverse.github.io/examples/)

## Author

Jeff Dickinson, Navitas Data Sciences
