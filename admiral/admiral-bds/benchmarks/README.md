# Benchmarks

Each subdirectory contains one benchmark scenario for the `admiral-bds` skill.

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

| Benchmark | Dataset | What it tests | Status |
|---|---|---|---|
| `advs-basic` | ADVS | SBP, DBP, pulse; ABLFL, BASE, CHG, ANL01FL; spec-driven visit map | Planned |
| `adlb-basic` | ADLB | Chemistry panel; ANRLO, ANRHI, ANRIND, BNRIND | Planned |
| `adlb-ctcae` | ADLB | CTCAE toxicity grade derivation; ATOXGR, BTOXGR | Planned |
| `advs-missing-dates` | ADVS | Partial VSDTC imputation; correct ADT and ADTF | Planned |
| `advs-triplicate` | ADVS | Multiple records per visit; DTYPE = "AVERAGE" pattern | Planned |

## Running a Benchmark Manually

1. Give the agent the contents of `prompt.md`, `SKILL.md`, and the parent `../SKILL.md`
2. Execute the generated R code against the input datasets in `input/`
3. Score the output against `expected/` using the criteria in `rubric.md`

## Input Data

Inputs are generated from [`{pharmaversesdtm}`](https://pharmaverse.github.io/pharmaversesdtm/)
and [`{pharmaverseadam}`](https://pharmaverse.github.io/pharmaverseadam/) — publicly available,
CDISC-conformant datasets that any contributor can reproduce. Study-specific modifications
for edge case scenarios are applied within the `input/` scripts.
