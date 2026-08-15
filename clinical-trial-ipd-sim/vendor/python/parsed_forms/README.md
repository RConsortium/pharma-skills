# NCI caDSR CDE index — `nci.duckdb`

Pre-built, read-only DuckDB index of NCI caDSR Common Data Elements. The ODM step
(`../odm/build_spec.py`, `../odm/search_nci.py`) queries this file to bind CRF fields to
standard CDEs and to search for candidate CDEs by plain-language description.

- **File:** `nci.duckdb`
- **Size:** 67,383,296 bytes (~64 MiB)
- **sha256:** `b4d4edf78e1161d4e0dfa964bd28e7a62e8953097eafe8d34a1fbc9c7fd0f1c3` (also in `nci.duckdb.sha256`)
- **Tables:** `cdes` (43,325 rows — the linked CDE catalog), `codelists` (8,007 rows — deduped
  answer sets), `search_doc` (74,771 rows — one BM25 document per CDE, with a DuckDB FTS index).

## Provenance
Built once from the NCI caDSR FTP XML export by the parsing pipeline in the main repo
(`nci-crf/parsing_functions/` — parse → dedup → build_duckdb). That build pipeline is **out of
scope for this skill**: the index ships pre-built and is never rebuilt here.

## Why it's vendored here
`search_nci.py` and `build_spec.py` resolve the DB by a fixed relative path
(`os.path.join(HERE, "..", "parsed_forms", "nci.duckdb")`), so it must sit exactly one level up
from the `odm/` scripts. Keeping it here means the vendored Python needs zero edits.

## Large-binary note (for the RConsortium PR)
This is a 64 MiB binary. The core R engine, gates, and all non-ODM tests run **without** it — only
the ODM build/fill and `search_nci` steps need it. If a reviewer prefers not to carry the blob in
git, use `../../../scripts/fetch_nci_db.R` to fetch + checksum-verify it on first use from a pinned
release asset, or track it via Git LFS. Either way it is not required for `agentskills validate`.
