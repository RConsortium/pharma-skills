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
| `basic-teae` | Standard TEAE derivation, complete data, all required ADAE variables | Planned |
| `sar-window` | Post-treatment window variation for SAEs; `end_window` annotation checking | Planned |
| `severity-mapping` | AESEV/AESEVN derivation; `case_when()` lookup; numeric companion variable | Planned |
| `pre-existing` | PREFL derivation from MH; exact-term vs body-system matching strategy | Planned |
| `smq-grouping` | SMQ and sponsor-defined grouping flags via `derive_vars_query()` | Planned |

## Running a Benchmark Manually

1. Give the agent the contents of `prompt.md` and `SKILL.md`
2. Execute the generated R code against the input datasets in `input/`
3. Score the output against `expected/` using the criteria in `rubric.md`

## Input Data

Inputs are generated from [`{pharmaversesdtm}`](https://pharmaverse.github.io/pharmaversesdtm/)
and [`{pharmaverseadam}`](https://pharmaverse.github.io/pharmaverseadam/) — publicly available,
CDISC-conformant datasets that any contributor can reproduce. Study-specific modifications
for edge case scenarios are applied within the `input/` scripts.

**Note on AETOXGR:** `pharmaversesdtm::ae` does not contain AETOXGR. Benchmarks that
require NCI CTCAE grading use synthetic data generated within the `input/` script.
