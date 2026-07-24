"""USE + ASSEMBLE: crf_picks.json -> crf_spec.json, by reading the real NCI library.

crf_picks.json is the source (the AI's per-field picks); crf_spec.json is a generated
build artifact -- regenerate it, don't hand-edit. The picks file lists the form/section
structure and, per field, EITHER one picked NCI catalog id ("cde") OR a custom
definition ("custom"). This script looks each picked id up in ../parsed_forms/nci.duckdb
(indexed point lookups) and copies its real name, type, length and answer list.
Deterministic, no AI (picking happened upstream).

    python3 build_spec.py crf_picks.json crf_spec.json
"""
import sys, os, json
import duckdb

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "..", "parsed_forms", "nci.duckdb")

DT = {"CHARACTER": "text", "ALPHANUMERIC": "text", "DATE": "date", "TIME": "time"}


def map_type(c):
    """caDSR datatype -> ODM DataType."""
    dt = (c.get("datatype") or "").upper()
    if dt == "NUMBER":
        return "float" if c.get("dec") not in (None, "0", 0) else "integer"
    return DT.get(dt, "text")


def split_pick(s):
    """'6343385v1.0' -> ('6343385', '1.0'). caDSR ids are not unique without the version."""
    pid, _, ver = s.partition("v")
    return pid, ver


def fetch_cdes(con, keys):
    """Point-look up picked CDEs by (id, version) -- the only unique key for a CDE."""
    if not keys:
        return {}
    cols = ["id", "ver", "name", "datatype", "dec", "maxlen", "def", "codelist_id"]
    ph = ",".join(["(?,?)"] * len(keys))
    rows = con.execute(f"SELECT {','.join(cols)} FROM cdes WHERE (id,ver) IN ({ph})",
                       [x for k in keys for x in k]).fetchall()
    return {(r[0], r[1]): dict(zip(cols, r)) for r in rows}


def fetch_cls(con, ids):
    """Codelist answer-item lists keyed by id (cl_ hashes are unique)."""
    ids = [i for i in set(ids) if i]
    if not ids:
        return {}
    ph = ",".join(["?"] * len(ids))
    rows = con.execute(f"SELECT id, items FROM codelists WHERE id IN ({ph})", ids).fetchall()
    return {r[0]: r[1] for r in rows}


def main():
    req = json.load(open(sys.argv[1]))
    out = sys.argv[2] if len(sys.argv) > 2 else "crf_spec.json"
    con = duckdb.connect(DB, read_only=True)

    picks = [split_pick(fl["cde"]) for f in req["forms"] for fl in f["fields"] if "cde" in fl]
    cdes = fetch_cdes(con, picks)
    cls = fetch_cls(con, [cdes[k].get("codelist_id") for k in cdes])

    spec = {k: req[k] for k in ("study", "metadata_oid", "metadata_name", "created", "visits")}
    spec["forms"], codelists = [], {}

    for f in req["forms"]:
        fields = []
        for fl in f["fields"]:
            if "cde" in fl:                                   # picked NCI field -> copy from library
                c = cdes.get(split_pick(fl["cde"])) or sys.exit(f"CDE {fl['cde']} not in parsed_forms")
                fld = {"oid": fl.get("oid") or ("IT." + c["id"]), "name": c["name"], "type": map_type(c),
                       "length": c.get("maxlen"), "description": c.get("def"),
                       "source": "nci", "cde": f"{c['id']}v{c['ver']}"}
                clid = c.get("codelist_id")
                if clid and clid in cls:
                    fld["codelist"] = oid = "CL." + clid
                    codelists.setdefault(oid, {
                        "oid": oid, "name": c["name"], "type": "text",
                        "items": [{"value": it.get("value"),
                                   "decode": it.get("label") or it.get("value"),
                                   "code": it.get("code")} for it in cls[clid]]})
            else:                                             # custom field -> use as given
                cu = fl["custom"]
                fld = {"oid": fl["oid"], "name": cu["name"], "type": cu["type"],
                       "length": cu.get("length"), "description": cu.get("description"),
                       "source": "sponsor"}
                if "codelist" in cu:
                    fld["codelist"] = cu["codelist"]["oid"]
                    codelists.setdefault(cu["codelist"]["oid"], cu["codelist"])
            fields.append(fld)
        spec["forms"].append({"oid": f["oid"], "name": f["name"], "visits": f["visits"],
                              "sections": [{"oid": f["section_oid"], "name": f["section_name"],
                                            "repeating": f.get("repeating", "No"),
                                            "fields": fields}]})
    spec["codelists"] = list(codelists.values())

    json.dump(spec, open(out, "w"), indent=2)
    allf = [x for f in spec["forms"] for s in f["sections"] for x in s["fields"]]
    nci = sum(x["source"] == "nci" for x in allf)
    print(f"wrote {out}: {len(spec['forms'])} forms, {len(allf)} fields "
          f"({nci} NCI-backed, {len(allf)-nci} custom), {len(spec['codelists'])} answer-lists")


if __name__ == "__main__":
    main()
