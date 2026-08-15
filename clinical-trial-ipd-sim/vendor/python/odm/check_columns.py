"""CHECK: the simulator's emitted CSV columns match the CRF frame (crf_picks.json), BOTH ways.

crf_picks.json (Step 2) is the contract the simulator (Steps 3-6) must emit. This catches drift
between the two EARLY -- right after the CSVs are produced, before calibration and the ODM fill --
and in BOTH directions:
  - a schema field the simulator never emitted (would be a silent blank column in the final ODM), and
  - a CSV column the schema never declared (only errors later, at the Step-7 ODM fill).
It also checks that the set of emitted CRF files matches the set of forms in the schema.
Deterministic, no AI. Run from the repo root with $PY.

    python3 check_columns.py {trial}_output/odm/crf_picks.json {trial}_output/crfs
"""
import sys, os, csv, glob, json

STRUCTURAL = {"USUBJID", "VISIT", "VISITLBL", "VISITNUM"}   # routing keys, not collected fields


def schema_forms(picks):
    """crf_picks -> {form_code: set(columns)}; column = trailing segment of each field OID."""
    return {f["oid"].split(".", 2)[2]: {fl["oid"].rsplit(".", 1)[1] for fl in f["fields"]}
            for f in picks["forms"]}


def csv_forms(crfs):
    """crfs dir -> {form_code: set(data columns)} (structural routing keys excluded)."""
    out = {}
    for path in glob.glob(os.path.join(crfs, "*_CRF_*.csv")):
        code = os.path.basename(path).split("_CRF_", 1)[1][:-4]
        with open(path, newline="") as fh:
            out[code] = set(next(csv.reader(fh), [])) - STRUCTURAL
    return out


def main():
    picks, crfs = json.load(open(sys.argv[1])), sys.argv[2]
    want, got = schema_forms(picks), csv_forms(crfs)

    problems = []
    for code in sorted(set(want) - set(got)):
        problems.append(f"form '{code}' in schema but no *_CRF_{code}.csv emitted")
    for code in sorted(set(got) - set(want)):
        problems.append(f"CSV *_CRF_{code}.csv emitted but form '{code}' not in schema")
    for code in sorted(set(want) & set(got)):
        if miss := want[code] - got[code]:
            problems.append(f"{code}: schema fields not emitted: {sorted(miss)}")
        if extra := got[code] - want[code]:
            problems.append(f"{code}: CSV columns not in schema: {sorted(extra)}")

    print(f"column check: {sys.argv[1]} <-> {crfs}")
    print(f"  {len(want)} schema forms, {len(got)} emitted CSVs")
    for p in problems:
        print("    " + p)
    if problems:
        print("RESULT: column drift -- fix before the ODM fill")
        sys.exit(1)
    print("RESULT: columns match (schema <-> CSVs)")
    sys.exit(0)


if __name__ == "__main__":
    main()
