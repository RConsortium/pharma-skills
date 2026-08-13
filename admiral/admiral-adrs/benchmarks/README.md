# Benchmarks

Each subdirectory contains one benchmark scenario for the `admiral-adrs` skill.

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
| `recist-confirmed-bor` | Standard RECIST 1.1 BOR derivation using `rs_onco_recist`; CONFIRMED, BESTRESP, and ORR verification | Planned |
| `clinical-benefit-anchor` | Clinical benefit derivation with RANDDT vs per-subject first-assessment anchor — tests whether agent flags the ambiguity with `# REVIEW:` | Planned |
| `bicr-vs-investigator` | Dual-assessor scenario; tests whether agent derives separate PARAMCD sets for investigator and BICR assessments | Planned |
| `ne-propagation` | Subject with all-NE assessment schedule; tests correct NE BOR and that CONFIRMED = "N" not NA | Planned |

## Running a Benchmark Manually

1. Give the agent the contents of `prompt.md` and `SKILL.md`
2. Execute the generated R code against the input datasets in `input/`
3. Score the output against `expected/` using the criteria in `rubric.md`

## Existing GitHub Benchmark

Issue [#167](https://github.com/RConsortium/pharma-skills/issues/167) was run
against the `admiral-bds` skill before `admiral-adrs` existed. Re-running it
against this skill will establish the baseline improvement delta.

## Input Data

Inputs are generated from
[`{pharmaversesdtm}`](https://pharmaverse.github.io/pharmaversesdtm/) using
`rs_onco_recist` (8 subjects, 66 records, RECIST 1.1). Edge case scenarios are
applied within the `input/` scripts.
