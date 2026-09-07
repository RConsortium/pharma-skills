# Rounding compliance report -- <package> <version/commit>

Target: [<repo link pinned to commit>](<url>) or folder path: <path>
Environment: <R.version.string; rounding package versions>
Policy: <tie policy and version>;
Status: **Draft for review.** No source was changed and nothing was posted.
Verdict: **<PASS / FAIL / NOT ASSESSABLE>** (FAIL if any row fails, NOT ASSESSABLE if none fails and at least one is uncheckable, else PASS).

## Summary

| Site | What | Tie | Stage | Display | Overall |
|------|------|-----|-------|---------|---------|
| R/...:NN | <formatter + digits> | <PASS/FAIL> | <PASS/FAIL> | <PASS/FAIL> | <PASS/FAIL> |

Fix (advisory): <one-line helper + formatter + neg-zero guard>

## Appendix

### A. Coverage
- Scanned <N> R files; <K> catalog hits, <N-in> in-scope. Excluded (never scored): <file:line + reason each>.

### B. Evidence (executed)
- <policy-vs-actual witnesses, e.g. formatC(2.5)="2" vs "3", "-0" vs never "-0"; stage round-once and trailing-zero checks>

### C. Limitations
- <missing specs, binary-representation caveats, uninstalled helpers, untraced paths>

### D. Witness log
- <paste scripts/probe-tie-behavior.R stdout, trimmed to key lines>
