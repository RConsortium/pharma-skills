"""Insert ODM v2.0 ClinicalData (the simulated patients) INTO an already-built CRF template.

The earlier step (build_spec.py -> emit_odm.py) emits a valid blank ODM CRF template
(Granularity="Metadata"). This reads THAT template, derives the form/section/field/visit
structure from its own metadata, inserts a ClinicalData block built from the {TRIAL}_CRF_*.csv
files, flips Granularity to "All", and writes the result. The template's metadata is reused
verbatim -- we only add data. In ODM v2.0 a value is the TEXT of a child <Value> element
(there is no @Value attribute). Validate the output with check_odm.py.

    python emit_clinicaldata.py rave_crf.xml crfs_dir out.xml
"""
import sys, os, csv, glob
from collections import defaultdict
from lxml import etree

NS = "{http://www.cdisc.org/ns/odm/v2.0}"
STRUCTURAL = {"USUBJID", "VISIT", "VISITLBL", "VISITNUM"}     # keys, not collected data items


def E(parent, tag, **attrs):
    """Add a child ODM element, set its attributes (skip None)."""
    el = etree.SubElement(parent, NS + tag)
    for k, v in attrs.items():
        if v is not None:
            el.set(k, str(v))
    return el


def main():
    template, crfs = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else "rave_odm.xml"

    root = etree.parse(template, etree.XMLParser(remove_blank_text=True)).getroot()
    study_oid = root.find(NS + "Study").get("OID")
    mdv_oid = root.find(f"{NS}Study/{NS}MetaDataVersion").get("OID")
    nct = study_oid.split(".", 1)[1]                         # ST.{NCT}

    # --- derive the structure straight from the template's own metadata ---
    visit_order = [se.get("OID") for se in root.iter(NS + "StudyEventDef")]
    form_visits = defaultdict(list)                          # form OID -> [StudyEventDef OID...]
    for se in root.iter(NS + "StudyEventDef"):
        for ref in se.findall(NS + "ItemGroupRef"):          # StudyEventDef refs point at forms
            form_visits[ref.get("ItemGroupOID")].append(se.get("OID"))

    form_section = {}                                        # form OID -> section OID (one per form)
    sec_repeating, sec_cols = {}, {}                         # section OID -> Repeating / {column: ItemOID}
    for ig in root.iter(NS + "ItemGroupDef"):
        if ig.get("Type") == "Form":
            form_section[ig.get("OID")] = ig.findall(NS + "ItemGroupRef")[0].get("ItemGroupOID")
        elif ig.get("Type") == "Section":
            sec_repeating[ig.get("OID")] = ig.get("Repeating", "No")
            sec_cols[ig.get("OID")] = {r.get("ItemOID").rsplit(".", 1)[1]: r.get("ItemOID")
                                       for r in ig.findall(NS + "ItemRef")}

    forms = {}                                               # form_code (CSV stem) -> info
    for form_oid, sec_oid in form_section.items():
        forms[form_oid.split(".", 2)[2]] = {                 # FO.{NCT}.{FORM} -> FORM
            "oid": form_oid, "section_oid": sec_oid,
            "repeating": sec_repeating.get(sec_oid, "No"),
            "cols": sec_cols.get(sec_oid, {}),
            "fixed_visit": form_visits[form_oid][0] if form_visits.get(form_oid) else None,
        }

    # --- read the CSVs: data[subject][visit_oid][form_code] = list of {col: value} ---
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for form_code, info in forms.items():
        matches = glob.glob(os.path.join(crfs, f"*_CRF_{form_code}.csv"))
        if not matches:
            sys.exit(f"missing CSV for form {form_code} in {crfs}")
        with open(matches[0], newline="") as fh:
            reader = csv.DictReader(fh)
            unknown = [c for c in reader.fieldnames if c not in STRUCTURAL and c not in info["cols"]]
            if unknown:
                sys.exit(f"{form_code}: CSV columns absent from template {unknown} -- regenerate the CRF")
            for row in reader:
                visit_oid = f"SE.{nct}.{row['VISIT']}" if row.get("VISIT") else info["fixed_visit"]
                cells = {c: v for c, v in row.items()
                         if c not in STRUCTURAL and c in info["cols"] and v not in (None, "")}
                if cells:
                    data[row["USUBJID"]][visit_oid][form_code].append(cells)

    # --- insert ClinicalData into the template (metadata untouched) ---
    root.set("Granularity", "All")
    cd = E(root, "ClinicalData", StudyOID=study_oid, MetaDataVersionOID=mdv_oid)
    n_subj = n_item = 0
    for subj in sorted(data):
        sd = E(cd, "SubjectData", SubjectKey=subj); n_subj += 1
        for visit_oid in visit_order:
            if visit_oid not in data[subj]:
                continue
            ev = E(sd, "StudyEventData", StudyEventOID=visit_oid)
            for form_code, rows in data[subj][visit_oid].items():
                info = forms[form_code]
                fg = E(ev, "ItemGroupData", ItemGroupOID=info["oid"])
                repeating = info["repeating"] != "No" or len(rows) > 1
                for i, cells in enumerate(rows, 1):
                    sg = E(fg, "ItemGroupData", ItemGroupOID=info["section_oid"],
                           ItemGroupRepeatKey=str(i) if repeating else None)
                    for col, val in cells.items():
                        E(sg, "ItemData", ItemOID=info["cols"][col]).append(_value(val))
                        n_item += 1

    etree.ElementTree(root).write(out, xml_declaration=True, encoding="UTF-8", pretty_print=True)
    print(f"wrote {out}: {n_subj} subjects, {n_item} item values, Granularity=All")


def _value(s):
    el = etree.Element(NS + "Value")
    el.text = s
    return el


if __name__ == "__main__":
    main()
