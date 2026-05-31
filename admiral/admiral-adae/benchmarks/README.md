# Benchmarks

Each subdirectory contains one benchmark scenario for the `admiral-adae` skill.

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
| `basic-teae` | Standard parallel-group study; TRTEMFL derivation from ASTDT and TRTSDT | Planned |
| `serious-ae` | AESER/AESEV derivation; SAE flag logic and missing severity imputation | Planned |
| `duration-vars` | ADURN/ADURU calculation; handling of ongoing AEs with missing AEENDTC | Planned |
| `meddra-coding` | AEDECOD/AEBODSYS merge from ADAE spec; MedDRA hierarchy variables | Planned |

## Running a Benchmark Manually

1. Give the agent the contents of `prompt.md` and `SKILL.md`
2. Execute the generated R code against the input datasets in `input/`
3. Score the output against `expected/` using the criteria in `rubric.md`

## Input Data

Inputs are generated from [`{pharmaversesdtm}`](https://pharmaverse.github.io/pharmaversesdtm/)
and [`{pharmaverseadam}`](https://pharmaverse.github.io/pharmaverseadam/) — publicly available,
CDISC-conformant datasets that any contributor can reproduce. Study-specific modifications
for edge case scenarios are applied within the `input/` scripts.
