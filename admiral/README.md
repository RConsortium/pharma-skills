# admiral skill family

Agent skills for deriving ADaM datasets using the [{admiral}](https://pharmaverse.github.io/admiral/)
R package and the pharmaverse ecosystem.

## Skills

| Skill | Dataset type | ADaM IG class | Status |
|---|---|---|---|
| [admiral-adsl](admiral-adsl/) | Subject-Level Analysis Dataset | ADSL | Available |
| [admiral-bds](admiral-bds/) | BDS Findings (ADVS, ADLB) | BDS | Available |
| admiral-adae | Adverse Events | OCCDS | Planned |
| admiral-adtte | Time to Event | BDS-TTE | Planned |

## Structure

```
admiral/
├── SKILL.md              ← Shared conventions (library setup, date rules,
│                           flag conventions, QC patterns, skill routing)
├── README.md             ← This file
├── admiral-adsl/         ← Subject-level skill
│   ├── SKILL.md
│   ├── DESIGN.md
│   ├── README.md
│   ├── references/
│   └── benchmarks/
└── admiral-bds/          ← BDS findings skill (ADVS, ADLB)
    ├── SKILL.md
    ├── DESIGN.md
    ├── README.md
    ├── references/
    └── benchmarks/
```

## Shared conventions

The parent `SKILL.md` documents conventions that apply across all admiral child
skills:

- Library setup and pipe style (`|>`, `exprs()`)
- Date derivation rules — always use `derive_vars_dt()`, never `as.Date()` on `--DTC`
- Flag variable convention — `"Y"` or `NA`, never `"N"`
- `DOMAIN` variable removal before `derive_vars_merged()` calls
- `# REVIEW:` annotation requirements at protocol-specific decision points
- `stopifnot()` assertions for structural uniqueness

## Dataset dependency

ADSL must be derived before any other ADaM dataset. Population flags (SAFFL,
ITTFL) and treatment dates (TRTSDT, TRTEDT) from ADSL are merged into all
downstream BDS, OCCDS, and TTE datasets.

## Dependencies

```r
library(admiral)          # >= 1.2.0
library(dplyr)
library(lubridate)
library(metacore)
library(xportr)
library(pharmaversesdtm)  # SDTM input datasets for benchmarks
library(pharmaverseadam)  # Reference ADaM outputs for benchmarks
```

## References

- [admiral documentation](https://pharmaverse.github.io/admiral/)
- [CDISC ADaMIG v1.3](https://www.cdisc.org/standards/foundational/adam)
- [pharmaverse examples](https://pharmaverse.github.io/examples/)
