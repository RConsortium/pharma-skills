"""CHECKER: prove a file is valid ODM v2.0. Plain programs, no AI, fail-closed.

Gate 1 - does it obey CDISC's official rulebook (the schema)?
Gate 2 - does every internal reference point at a real definition?
    python3 check_odm.py rave.xml          # exits non-zero if invalid
"""
import sys, os
from lxml import etree

HERE = os.path.dirname(os.path.abspath(__file__))
NS = "{http://www.cdisc.org/ns/odm/v2.0}"
SCHEMA = os.path.join(HERE, "xsd_v2", "ODM.xsd")     # the rules from official ODM repo: https://github.com/cdisc-org/DataExchange-ODM/tree/main/schema 


def gate1_rules(path):
    schema = etree.XMLSchema(etree.parse(SCHEMA))
    doc = etree.parse(path)
    if schema.validate(doc):
        return True, []
    return False, [f"line {e.line}: {e.message}" for e in schema.error_log]


def gate2_refs(path):
    doc = etree.parse(path)
    defined = {el.get("OID")
               for tag in ("StudyEventDef", "ItemGroupDef", "ItemDef", "CodeList")
               for el in doc.iter(NS + tag)}
    problems = []
    for tag, attr in (("ItemGroupRef", "ItemGroupOID"),
                      ("ItemRef", "ItemOID"),
                      ("CodeListRef", "CodeListOID")):
        for el in doc.iter(NS + tag):
            if el.get(attr) not in defined:
                problems.append(f"{tag} {attr}='{el.get(attr)}' -> no matching definition")
    return (not problems), problems


def main():
    path = sys.argv[1]
    ok1, e1 = gate1_rules(path)
    ok2, e2 = gate2_refs(path)
    print(f"Gate 1 (official ODM rules): {'PASS' if ok1 else 'FAIL'}")
    for e in e1: print("    " + e)
    print(f"Gate 2 (references resolve): {'PASS' if ok2 else 'FAIL'}")
    for e in e2: print("    " + e)
    if ok1 and ok2:
        print(f"RESULT: {path} is valid ODM v2.0")
        sys.exit(0)
    print(f"RESULT: {path} is NOT valid - build stops here")
    sys.exit(1)


if __name__ == "__main__":
    main()
