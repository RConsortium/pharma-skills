# sdtm-oak

An agent skill for deriving CDISC SDTM domains from raw EDC/eCRF data using
the [{sdtm.oak}](https://pharmaverse.github.io/sdtm.oak/) pharmaverse R package.

## What It Does

Given a raw clinical dataset and a controlled terminology specification, this
skill produces executable, submission-ready R code that:

1. **Sets up oak ID variables** — calls `generate_oak_id_vars()` to add the
   join keys required by all downstream derivation functions
2. **Selects the right algorithm** — chooses among `assign_no_ct()`,
   `assign_ct()`, `hardcode_ct()`, `hardcode_no_ct()`, and `assign_datetime()`
   based on whether each variable has CT and whether the value comes from raw
   data or is hardcoded
3. **Derives ISO 8601 dates** — uses `assign_datetime()` with the correct
   `raw_fmt` for the source data; never `as.Date()` or string manipulation
4. **Applies CT recoding** — loads and validates a CT spec, then applies the
   correct codelist per variable via `assign_ct()` or `hardcode_ct()`
5. **Handles conditional derivations** — uses `condition_add()` to scope
   derivations to record subsets without manual `filter()`/`mutate()` patterns
6. **Derives study-level variables** — adds sequence numbers via `derive_seq()`,
   study days via `derive_study_day()`, and baseline flags via `derive_blfl()`
   for findings domains
7. **Places `# REVIEW:` annotations** — marks every protocol-specific decision
   point (date formats, CT codelist selection, baseline visit definition,
   reference date choice) for QC review

## Supported Domains

| Domain class | Examples | Pattern |
|---|---|---|
| Events | AE, CM, MH, DS | Single raw form → SDTM domain |
| Interventions | EX, SU | Single raw form → SDTM domain |
| Findings | VS, LB, EG | Per-test stacking with `bind_rows()` |
| Supplemental | SUPPAE, SUPPVS, … | `generate_sdtm_supp()` after main domain |

## Structure

```
sdtm-oak/
├── SKILL.md              ← Workflow, algorithm selection guide, QC rules
├── README.md             ← This file
├── LICENSE               ← MIT
└── references/
    └── oak-functions.md  ← Full function signatures and parameter descriptions
```

## Dependencies

```r
library(sdtm.oak)   # >= 0.2.0
library(dplyr)
library(tibble)
```

## References

- [sdtm.oak documentation](https://pharmaverse.github.io/sdtm.oak/)
- [CDISC SDTM Implementation Guide](https://www.cdisc.org/standards/foundational/sdtm)
- [pharmaverse](https://pharmaverse.org/)
