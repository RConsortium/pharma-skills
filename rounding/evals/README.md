# `rounding` benchmark

Test cases for the `rounding` skill, per `LIFECYCLE.md` phase 3 and the
criteria in [`RConsortium/pharma-skills` issue
#208](https://github.com/RConsortium/pharma-skills/issues/208).

## Contents

| Path | What it is |
|---|---|
| `evals.json` | Test prompts and assertions |
| `fixtures/myanalysis/` | Seeded R package: the audit target |
| `fixtures/precision-spec.yml` | Approved display-precision spec and allowlist |
| `fixtures/ANSWER-KEY.md` | Verified ground truth -- **never stage as a run input** |
| `fixtures/build-fixture.sh` | Produces `myanalysis-fixture.zip` from the source tree |

## The fixture

`myanalysis` 0.1.0 is a synthetic package. It is not a real analysis package
and must not be used for reporting. It seeds one case per behavior the skill
has to get right, and two the scanner deliberately cannot see:

- tie method on a displayed statistic, and on a row-inclusion threshold
- early rounding before aggregation (paired sites)
- trailing zeros dropped, at two different sites
- a compliant helper-plus-formatter path that must not be rewritten
- an allowlisted approved helper
- quantization by `%/%` with no function name (parse tree finds it, grep cannot)
- a `do.call(sprintf, ...)` call the parse tree cannot find either
- a statistic absent from the precision spec, which must be NOT ASSESSABLE
- `solver_*`, `plot_*` and vignette hits that must not be scored

Verified under R 4.6.1 (aarch64-apple-darwin25.4.0) on 2026-09-06. Re-verify
`ANSWER-KEY.md` before using it in another environment.

## Running

```bash
# Answer-key counts for the scanner
Rscript scripts/scan-rounding-calls.R evals/fixtures/myanalysis

# Witnesses at each precision the fixture displays
Rscript scripts/probe-tie-behavior.R
Rscript scripts/probe-tie-behavior.R --digits 1
Rscript scripts/probe-tie-behavior.R --digits 2
```
