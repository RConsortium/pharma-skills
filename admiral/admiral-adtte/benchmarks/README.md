# Benchmarks

Each subdirectory contains one benchmark scenario for the `admiral-adtte` skill.

## Structure

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
| `time-to-sae` | Time to first serious AE using AE domain; event filter, 30-day censoring window, CNSDTDSC CT | Planned |
| `censoring-hierarchy` | Multiple censoring sources with priority ordering; tests correct date selection when multiple dates available per subject | Planned |
| `multiple-params` | Two TTE parameters in one script (TTAE + TTAE3); tests reuse of censoring object and independent event definitions | Planned |
| `pfs-from-adrs` | Oncology PFS where event dates come from ADRS milestone assessments; tests cross-skill composition | Planned |

## Existing GitHub Benchmark

Issue [#166](https://github.com/RConsortium/pharma-skills/issues/166) was run
against `admiral-bds` before `admiral-adtte` existed (+21 pp). Re-running it
against this skill establishes the baseline improvement delta.

## Input Data

Inputs use [`{pharmaversesdtm}`](https://pharmaverse.github.io/pharmaversesdtm/)
`ae` and [`{pharmaverseadam}`](https://pharmaverse.github.io/pharmaverseadam/)
`adsl`. Edge case scenarios are applied within the `input/` scripts.
