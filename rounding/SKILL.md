---
name: rounding
description: >
  Audit R code that prepares clinical-report statistics for SAS-compatible
  rounding compliance (ties away from zero, round-once-at-display,
  fixed display precision with trailing zeros). Use this skill whenever the
  user asks to review, check, verify, or fix rounding in R code,
  mentions SAS rounding, half-away-from-zero,
  display precision, trailing zeros, early rounding, or names round(),
  formatC(), sprintf(), format(), signif(), prettyNum(), cards::round5,
  tidytlg::roundSAS, or janitor::round_half_up in a CSR/TLF/report context --
  even if they don't say the word "rounding".
license: MIT
metadata:
  author: Pharma Skills community
  version: "0.2"
  rules-version: "BR-001/002/003 v1.0"
---

# Rounding compliance review 

Advisory review only. Find candidates, reproduce behavior with executed code,
and draft findings for a named human to classify. Do not edit source, change
policy, approve a classification, or post an external issue.

## Bundled resources

| File | What it contains | When to use |
|------|-----------------|-------------|
| `references/br-001-tie-method.md` | Tie rule, FAIL signature, versioned-helper fix | Step 4, when BR-001 is in scope |
| `references/br-002-rounding-stage.md` | Stage rule, FAIL signature, remove-early-rounding fix | Step 4, when BR-002 is in scope |
| `references/br-003-display-precision.md` | Display rule, FAIL signature, fixed-character fix | Step 4, when BR-003 is in scope |
| `references/function-catalog.md` | In-scope/excluded functions, wrapper search | Step 2 |
| `references/worked-example-metalite.md` | metalite.ae v0.1.4 answer key | Steps 3 and 5, to calibrate coverage and probes |
| `scripts/scan-rounding-calls.R` | First-pass file inventory + catalog scan | Step 2; its output is never complete coverage |
| `scripts/probe-tie-behavior.R` | Fixed tie/stage/display witnesses + environment | Step 5, embed stdout |
| `assets/report-template.md` | `report.md` structure | Step 6 |

Do NOT read or run these upfront. Use each only when the step directs.

## Procedure

1. **Confirm inputs.** Target (repo link or a local folder, read-only), precision spec per reported
   statistic, tie policy and entry points (defaults: half away from zero), and the `report.md` path. 
   A rule the request is silent on is `NOT ASSESSABLE` -- do not invent it.
2. **Scan (first pass only).** Read `references/function-catalog.md`, run
   `scripts/scan-rounding-calls.R`, preserve the output -- then infer where
   else rounding can hide: the script never clears a file. Label each
   candidate `catalog` or `exploratory`.
3. **Trace and triage.** From each entry point follow package-local calls.
   Keep reachable operations as rows; move the rest to Coverage as excluded
   with reasons. Trace paired sites (early rounding + downstream display or
   decision) together.
4. **Resolve against the rules.** For each row state namespace, method/class,
   and version, then read the matching `references/br-00x-*.md` for the FAIL
   signature and fix.
5. **Prove.** Run `scripts/probe-tie-behavior.R` and embed its stdout in the
   report, plus per-finding before/after witnesses. Unexecuted claims are not
   evidence.
6. **Verdict and write.** Per row: Tie / Stage / Display as `PASS` / `FAIL` /
   `NOT ASSESSABLE`; Overall is `FAIL` if any rule fails, `NOT ASSESSABLE`
   if none fails and at least one is uncheckable, else `PASS`. Compliant
   helper-plus-formatter paths pass -- do not rewrite them. Complete
   `assets/report-template.md` as `report.md`, the only deliverable.

## Stop and escalate

Stop when the rule version, precision, tie intent, source, or comparison
behavior is unresolved, files are unreadable, a script fails, or a documented
conflicting convention exists. Record the blocker and stop.

## When NOT to use this skill

Do not use for non-numeric reports, statistical-method validation,
or independent QC replacement. If the user only wants "why do
R and SAS differ in rounding" explained, answer directly. If stage or precision
are out of scope, name the unchecked rules instead of narrowing silently.
