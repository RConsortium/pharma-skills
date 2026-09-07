# Rounding compliance report -- <package> <version/commit>

Target: [<repo link pinned to commit>](<url>) or folder path: <path>
Environment: <R.version.string; rounding package versions>
Policy: <tie policy and version; e.g. half away from zero 2.5->3, rule owner: Name>
Status: **Draft for review.** No source was changed and nothing was posted.
Verdict: **<PASS / FAIL / NOT ASSESSABLE>** (FAIL if any row fails, NOT ASSESSABLE if none fails and at least one is uncheckable, else PASS).

## Summary

One row per (operation, entry path). Overall is FAIL if any rule fails.

| # | Site | Entry path | Tie | Stage | Display | Overall | Witness (before → after) |
|---|------|------------|-----|-------|---------|---------|--------------------------|
| 1 | R/...:NN `func()` | `report_*()` | PASS/FAIL/NOT ASSESSABLE | PASS/FAIL/NOT ASSESSABLE | PASS/FAIL/--/NOT ASSESSABLE | PASS/FAIL/NOT ASSESSABLE | policy `X` vs actual `Y`; fix `Z` |
| … | … | … | … | … | … | … | … |

Fix (advisory): <one-line helper + formatter + neg-zero guard, e.g. `tidytlg::roundSAS(x, digits)` + `formatC(..., format="f")`>

## Appendix A. Coverage

- Scanned <N> R files (`R/`, `vignettes/`, etc.); <K> catalog hits, <in-scope> in-scope rows, <excluded> excluded.
- Full scanner output pasted (do not summarize -- paste verbatim).
- Excluded (never scored), each with file:line + reason:
  - `R/...:NN` — reason (e.g. inside `solver_*()`, plot coordinates, character input, not reachable from `report_*()`)
- Note: `R/report-listing.R` reports `hits: 0`; that is a scan result (dynamic `do.call` invisible to parse tree), not a clearance. Label any `exploratory` sites you add by reading the source.

## Appendix B. Evidence (executed)

For each row, two witnesses:

- **Before** -- observed value vs policy value at the site's own precision.
- **After** -- recommended fix producing the policy value.

Example row:

- Tie: `base::round(2.5, 0)` → `2` vs policy `3`; `tidytlg::roundSAS(2.5, 0)` → `3` ✓
- Stage: `x=c(1.25,1.25,1.75)` at 1dp early-rounded `1.5` vs round-once `1.4`
- Display: `as.character(76.00)` → `"76"` vs spec `exposure_total` requires `"76.00"`; `formatC(76, format="f", digits=2)` → `"76.00"` ✓
- Neg-zero: `formatC(-0.4, format="f", digits=0)` → `"-0"` must never occur

Attribute `formatC`/`sprintf` divergence to two causes (tie mode + binary representation); do not claim either uses banker's rounding.

## Appendix C. Limitations

- Missing inputs: <which rule/row is NOT ASSESSABLE and what is missing, e.g. `report_ci()` has no entry in `precision-spec.yml`>
- Blind spots: dynamic dispatch (`do.call`, `get`, `match.fun`), S3/S4 methods, dependency internals
- Uninstalled helpers: <which versioned helper was recommended but not installed; whether built-in half-away arithmetic was used to demonstrate the pattern>
- Untraced paths: <any entry path not fully traced>

## Appendix D. Witness log

Paste `scripts/probe-tie-behavior.R` stdout verbatim (include the default run + each `--digits N` run). Must include `R.version.string` and package versions. Unexecuted claims are not evidence.

```
<paste stdout here>
```

## Decisions Required (for the rule owner)

List each `FAIL` / `NOT ASSESSABLE` row and the classification the owner must make. No approval is recorded here.
