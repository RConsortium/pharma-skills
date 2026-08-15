"""WRITER: turn a form plan (crf_spec.json) into an ODM v2.0 file. Plain, no AI.

Deterministic: same plan in -> identical file out.
    python3 emit_odm.py crf_spec.json rave.xml
    python3 emit_odm.py crf_spec.json rave.xml --explain   # narrate each step
"""
import sys, json
from lxml import etree

NS = "http://www.cdisc.org/ns/odm/v2.0"
XMLLANG = "{http://www.w3.org/XML/1998/namespace}lang"


def E(parent, tag, **attrs):
    """Add a child ODM element, set its attributes (skip None)."""
    el = etree.SubElement(parent, f"{{{NS}}}{tag}")
    for k, v in attrs.items():
        if v is not None:
            el.set(k, str(v))
    return el


def text(parent, tag, s):
    """Add an element that holds a piece of human-readable text."""
    el = E(parent, tag)
    tt = E(el, "TranslatedText", Type="text/plain"); tt.set(XMLLANG, "en"); tt.text = s
    return el


def build(spec, explain=False):
    def log(msg):
        if explain:
            print(msg)

    root = etree.Element(f"{{{NS}}}ODM", nsmap={None: NS})
    root.set("FileOID", spec["study"]["oid"] + ".CRF")
    root.set("FileType", "Snapshot")
    root.set("Granularity", "Metadata")          # = a blank form, no patient data
    root.set("ODMVersion", "2.0")
    root.set("CreationDateTime", spec["created"])
    log('[file]    <ODM ODMVersion="2.0" Granularity="Metadata"> (a blank form)')

    study = E(root, "Study", OID=spec["study"]["oid"],
              StudyName=spec["study"]["name"], ProtocolName=spec["study"]["protocol"])
    if spec["study"].get("description"):
        text(study, "Description", spec["study"]["description"])
    mdv = E(study, "MetaDataVersion", OID=spec["metadata_oid"], Name=spec["metadata_name"])
    log(f'[study]   {spec["study"]["oid"]} "{spec["study"]["name"]}" -> Study + Description + MetaDataVersion')

    # visits, each pointing at the forms collected at that visit
    log("[visits]")
    for v in spec["visits"]:
        se = E(mdv, "StudyEventDef", OID=v["oid"], Name=v["name"], Repeating="No", Type="Scheduled")
        refs = []
        for f in spec["forms"]:
            if v["oid"] in f["visits"]:
                E(se, "ItemGroupRef", ItemGroupOID=f["oid"], Mandatory="Yes")
                refs.append(f["oid"])
        log(f'  {v["oid"]:8} "{v["name"]}"  ->  StudyEventDef + {len(refs)} form refs: {", ".join(refs)}')

    # a form = a group of type "Form" pointing at its sections
    log("[forms]")
    for f in spec["forms"]:
        fd = E(mdv, "ItemGroupDef", OID=f["oid"], Name=f["name"], Type="Form", Repeating="No")
        for sec in f["sections"]:
            E(fd, "ItemGroupRef", ItemGroupOID=sec["oid"], Mandatory="Yes")
        log(f'  {f["oid"]:8} "{f["name"]}" (Form)  ->  {len(f["sections"])} section ref(s)')

    # a section = a group of type "Section" pointing at its fields
    log("[sections]")
    for f in spec["forms"]:
        for sec in f["sections"]:
            sd = E(mdv, "ItemGroupDef", OID=sec["oid"], Name=sec["name"], Type="Section",
                   Repeating=sec.get("repeating", "No"))
            for fld in sec["fields"]:
                E(sd, "ItemRef", ItemOID=fld["oid"], Mandatory="Yes")
            log(f'  {sec["oid"]:8} "{sec["name"]}" (Section)  ->  {len(sec["fields"])} field ref(s)')

    # one definition per field (child order matters: Description -> CodeListRef -> Alias)
    log("[fields]   (each: which tags got written)")
    for f in spec["forms"]:
        for sec in f["sections"]:
            for fld in sec["fields"]:
                it = E(mdv, "ItemDef", OID=fld["oid"], Name=fld["name"],
                       DataType=fld["type"], Length=fld.get("length"))
                made = ["ItemDef"]
                if fld.get("description"):
                    text(it, "Description", fld["description"]); made.append("Description")
                if fld.get("codelist"):
                    E(it, "CodeListRef", CodeListOID=fld["codelist"]); made.append(f"CodeListRef({fld['codelist']})")
                if fld.get("source") == "nci":
                    E(it, "Alias", Context="nci:cadsrCDE", Name=fld.get("cde"))
                    made.append(f"Alias(nci:cadsrCDE {fld.get('cde')})")
                elif fld.get("source") == "sponsor":
                    E(it, "Alias", Context="sponsor:custom", Name="no-NCI-CDE")
                    made.append("Alias(sponsor:custom)")
                log(f'  {fld["oid"]:16} "{fld["name"]}" {fld["type"]}({fld.get("length")}) '
                    f'[{fld.get("source")}]  ->  ' + " + ".join(made))

    # one definition per answer list (the NCI code rides on each choice via Alias)
    log("[codelists]")
    for cl in spec.get("codelists", []):
        cld = E(mdv, "CodeList", OID=cl["oid"], Name=cl["name"], DataType=cl["type"])
        n_codes = 0
        for item in cl["items"]:
            ci = E(cld, "CodeListItem", CodedValue=item["value"])
            text(ci, "Decode", item["decode"])
            if item.get("code"):
                E(ci, "Alias", Context="nci:ExtCodeID", Name=item["code"]); n_codes += 1
        log(f'  {cl["oid"]:14} "{cl["name"]}" {cl["type"]}  ->  {len(cl["items"])} items '
            f'({n_codes} with NCI codes): {", ".join(i["value"] for i in cl["items"])}')
    return root


def main():
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    spec = json.load(open(args[0]))
    out = args[1] if len(args) > 1 else "out.xml"
    root = build(spec, explain="--explain" in flags)
    etree.ElementTree(root).write(out, xml_declaration=True, encoding="UTF-8", pretty_print=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
