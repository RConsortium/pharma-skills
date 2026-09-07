# Rounding compliance report -- <package> <version/commit>

Target: <repo link or folder path>
Environment: <R.version.string; rounding package versions>
Policy: <tie policy and version>; Entry points: <e.g. report_*()>

## Inventory (one row per in-scope operation)

| # | File:line | Report entry path | Resolved function (ns/method/class/ver) | Precision spec | Executed witness | Tie | Stage | Display | Overall | Recommendation |
|---|-----------|-------------------|------------------------------------------|----------------|------------------|-----|-------|---------|---------|----------------|
| 1 | R/...:NN  | report_x() -> f() | base::round, ...                         | 0 digits, ...  | code + output    | FAIL| ...   | ...     | FAIL    | ...            |

Overall is FAIL if any rule fails, NOT ASSESSABLE if none fails and at
least one is uncheckable, else PASS. Compliant helper-plus-formatter paths
pass with evidence and are not rewritten.

## Coverage

- Files examined: <N> (list or glob)
- Scan output: <paste scripts/scan-rounding-calls.R stdout>
- Catalog candidates: <K> (every match incl. excluded)
- In-scope rows: <N-in> (all present, none missing)
- Excluded hits: <M> (solver_*/plot_*/out-of-reach, each file:line + reason;
  never scored)

## Findings (FAIL rows only -- file:line, policy-vs-actual witness, fix witness)

## Clean checks (PASS rows with evidence, not rewritten)

## Limitations (NOT ASSESSABLE rows, unchecked rules, binary-representation
caveats)

## Witness log (paste scripts/probe-tie-behavior.R stdout)
