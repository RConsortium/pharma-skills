"""SEARCH: find candidate NCI standard fields for a query (the picker's tool).

Queries the BM25 full-text index inside ../parsed_forms/nci.duckdb. Deterministic, no AI.
    python3 search_nci.py "neutrophil count" [k]
"""
import sys, os
import duckdb

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "..", "parsed_forms", "nci.duckdb")

_con = None


def conn():
    """One read-only connection, reused (safe for many concurrent readers)."""
    global _con
    if _con is None:
        _con = duckdb.connect(DB, read_only=True)
        _con.execute("LOAD fts;")
    return _con


def search(query, k=10):
    # k=1.5 matches bm25s; b=0.25 (low length-penalty) suits our wide doc-length
    # spread (1..173 wordings/CDE) -- best top-1 without losing top-5. See README.
    rows = conn().execute(
        """SELECT kind, id, ver, name, datatype, codelist_id, score FROM (
               SELECT kind, id, ver, name, datatype, codelist_id,
                      fts_main_search_doc.match_bm25(doc_id, ?, k := 1.5, b := 0.25) AS score
               FROM search_doc)
           WHERE score IS NOT NULL ORDER BY score DESC LIMIT ?""",
        [query, k]).fetchall()
    return [{"score": round(float(s), 2), "kind": kind, "id": cid, "ver": ver,
             "name": name, "datatype": dt, "codelist_id": clid}
            for kind, cid, ver, name, dt, clid, s in rows]


def main():
    query = sys.argv[1]
    k = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    print(f'query: "{query}"')
    for r in search(query, k):
        tag = (f'{r["id"]}v{r["ver"]}' if r["id"] else "(no-cde)") if r["kind"] == "cde" else "(informal)"
        cl = f'  codelist={r["codelist_id"]}' if r.get("codelist_id") else ""
        print(f'  {r["score"]:6.2f}  {tag:14}  {r["name"]}{cl}')


if __name__ == "__main__":
    main()
