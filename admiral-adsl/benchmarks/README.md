# Benchmarks

Each subdirectory contains one benchmark scenario for the `admiral-adsl` skill.

## Structure

Every benchmark follows this layout:

```
{benchmark-name}/
├── prompt.md       # Natural language prompt given to the agent
├── rubric.md       # Scoring criteria for evaluating agent output
├── input/          # SDTM input datasets (R scripts to generate from pharmaversesdtm)
└── expected/       # Expected output variables and values for correctness checks
```

## Planned Benchmarks

| Benchmark | What it tests | Status |
|---|---|---|
| `basic-two-arm` | Standard parallel-group study, complete data, all required ADSL variables | Planned |
| `multi-arm` | Three treatment arms, TRT01P/TRT01A distinction, numeric companion variables | Planned |
| `missing-dates` | Partial `--DTC` imputation in EX and DS; correct use of `date_imputation` | Planned |
| `early-discontinuation` | EOSSTT/DCSREAS derivation; subjects who did not complete the study | Planned |
| `screen-failure` | Subjects in DM who never received treatment; SAFFL = NA, not "N" | Planned |

## Running a Benchmark Manually

1. Give the agent the contents of `prompt.md` and `SKILL.md`
2. Execute the generated R code against the input datasets in `input/`
3. Score the output against `expected/` using the criteria in `rubric.md`

## Input Data

Inputs are generated from [`{pharmaversesdtm}`](https://pharmaverse.github.io/pharmaversesdtm/)
and [`{pharmaverseadam}`](https://pharmaverse.github.io/pharmaverseadam/) — publicly available,
CDISC-conformant datasets that any contributor can reproduce. Study-specific modifications
for edge case scenarios are applied within the `input/` scripts.
