"""find-protocol: NCT ID -> the trial's FULL protocol PDF, strictly from the
HuggingFace dataset `trialdesignbench/source` (never the ClinicalTrials.gov CDN).

How the dataset is laid out (all verified live):
  - `data/tdr.parquet` is the table. Each row has a `#` index, an `NCT ID`
    cell (sometimes several NCTs comma-joined), and a `Paper Link` DOI.
  - Documents live in `documents/<folder>/protocol.pdf`, where <folder> is the
    DOI from `Paper Link` with '/' replaced by '_'. This join is exact (1641/1641).
  - PDFs are git-LFS. You MUST fetch them via the `resolve/main/` URL, which
    follows LFS and returns the real bytes. The `raw/main/` URL returns a ~130-byte
    text POINTER, and `blob/` returns an HTML page -- those are the "blank / one-pager"
    traps this script guards against.

Contract:
  python3 find_protocol.py NCT01234567 [--out-dir DIR]
  -> writes <out-dir>/<NCT>_protocol.pdf and prints one JSON line to stdout.
  Exit 0 = found (verified full PDF). Exit 1 = proven not-found (NCT absent, or
  no full protocol in the dataset). Exit 2 = operational error (couldn't decide).

Run under a python3 that has duckdb, requests, pypdf installed
(see ../requirements.txt; the same interpreter the ODM step uses).
"""
import argparse, json, os, re, sys, tempfile, time

import duckdb
import requests
from pypdf import PdfReader

BASE = "https://huggingface.co/datasets/trialdesignbench/source/resolve/main"
PARQUET_URL = f"{BASE}/data/tdr.parquet"
REQUIRED_COLS = ["#", "NCT ID", "Paper Link", "Study Protocol Link"]
MIN_PAGES = 2  # a real protocol is dozens of pages; >1 rejects blanks/one-pagers


def out(found, nct, pdf_path=None, pages=None, reason=None, candidates=None, code=0):
    """Print one JSON line and exit. code: 0 found, 1 proven-false, 2 error."""
    print(json.dumps({"found": found, "nct": nct, "pdf_path": pdf_path,
                       "pages": pages, "reason": reason,
                       "candidates_considered": candidates or []}))
    sys.exit(code)


def normalize_nct(raw):
    """'nct04078568', ' NCT 04078568 ', '04078568' -> 'NCT04078568'; else None."""
    s = re.sub(r"\s+", "", raw or "").upper()
    if re.fullmatch(r"\d{8}", s):
        s = "NCT" + s
    return s if re.fullmatch(r"NCT\d{8}", s) else None


def doi_to_folder(paper_link):
    """DOI url -> document folder name (only '/' -> '_'; dots/parens/hyphens kept)."""
    doi = (paper_link or "").strip()
    doi = re.sub(r"^https?://(dx\.)?doi\.org/", "", doi, flags=re.I).rstrip("/")
    return doi.replace("/", "_") if doi else None


def http_get(url, dest=None, timeout=60, tries=3):
    """GET with small retry. Returns (status, path_or_bytes). Raises on network death."""
    last = None
    for attempt in range(tries):
        try:
            r = requests.get(url, timeout=timeout, stream=bool(dest))
            if dest:
                if r.status_code == 200:
                    with open(dest, "wb") as fh:
                        for chunk in r.iter_content(65536):
                            fh.write(chunk)
                return r.status_code, dest
            return r.status_code, r.content
        except requests.RequestException as e:
            last = e
            time.sleep(1.5 * (attempt + 1))
    raise last


def fetch_and_gate(folder, tmpdir):
    """Fetch documents/<folder>/protocol.pdf and hard-gate it.
    Returns (result, path, pages). result 'ok' means path is a verified full PDF."""
    url = f"{BASE}/documents/{folder}/protocol.pdf"
    dest = os.path.join(tmpdir, f"{folder}.pdf")
    try:
        status, _ = http_get(url, dest=dest)
    except requests.RequestException:
        return "network_error", None, None
    if status == 404:
        return "http_404", None, None           # protocol genuinely absent (e.g. SAP-only)
    if status != 200:
        return f"http_{status}", None, None
    with open(dest, "rb") as fh:
        head = fh.read(5)
    if head.startswith(b"version"):
        return "lfs_pointer", None, None         # wrong endpoint served the LFS pointer
    if head != b"%PDF-":
        return "not_pdf", None, None             # e.g. an HTML page
    try:
        pages = len(PdfReader(dest).pages)
    except Exception:
        return "unparseable", None, None
    if pages < MIN_PAGES:
        return "one_pager", None, pages
    return "ok", dest, pages


def main():
    ap = argparse.ArgumentParser(description="NCT ID -> full protocol PDF from HF trialdesignbench/source")
    ap.add_argument("nct", help="an NCT ID, e.g. NCT04078568")
    ap.add_argument("--out-dir", default=".", help="directory to write <NCT>_protocol.pdf into (default: cwd)")
    args = ap.parse_args()

    nct = normalize_nct(args.nct)
    if not nct:
        out(False, args.nct, reason="bad_nct", code=2)

    with tempfile.TemporaryDirectory() as tmp:
        # 1. Download the table.
        parquet = os.path.join(tmp, "tdr.parquet")
        try:
            status, _ = http_get(PARQUET_URL, dest=parquet, timeout=30)
        except requests.RequestException:
            out(False, nct, reason="network_error", code=2)
        if status != 200:
            out(False, nct, reason="parquet_unavailable", code=2)

        con = duckdb.connect()
        cols = {c[0] for c in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{parquet}')").fetchall()}
        if not set(REQUIRED_COLS) <= cols:
            out(False, nct, reason="parquet_unavailable", code=2)  # schema drift

        # 2. Split-aware match: NCT ID cells can be comma-joined (up to 5 NCTs).
        rows = con.execute(
            f'''SELECT "#", "Paper Link", "Study Protocol Link"
                FROM read_parquet('{parquet}')
                WHERE list_contains(
                        list_transform(string_split("NCT ID", ','), x -> upper(trim(x))), ?)
                ORDER BY ("Study Protocol Link" IS NULL), "#"''',   # protocol-bearing rows first
            [nct]).fetchall()
        if not rows:
            out(False, nct, reason="nct_not_in_table", code=1)     # the explicit "return false"

        # 3. Try each candidate; stop at the first verified full PDF.
        candidates, reached_hf = [], False
        seen_folders = set()
        os.makedirs(args.out_dir, exist_ok=True)
        for row_idx, paper_link, _sap in rows:
            folder = doi_to_folder(paper_link)
            if not folder or folder in seen_folders:
                continue
            seen_folders.add(folder)
            result, path, pages = fetch_and_gate(folder, tmp)
            candidates.append({"row": row_idx, "folder": folder, "result": result})
            if result != "network_error":
                reached_hf = True
            if result == "ok":
                final = os.path.join(args.out_dir, f"{nct}_protocol.pdf")
                try:
                    os.replace(path, final)
                except OSError:
                    out(False, nct, reason="io_error", candidates=candidates, code=2)
                out(True, nct, pdf_path=os.path.abspath(final), pages=pages,
                    candidates=candidates, code=0)

        # 4. No candidate verified.
        if reached_hf:
            # We reached HF and every protocol was absent/invalid -> proven false.
            out(False, nct, reason="no_full_protocol_available", candidates=candidates, code=1)
        # Only network failures -> we never proved absence.
        out(False, nct, reason="network_error", candidates=candidates, code=2)


if __name__ == "__main__":
    main()
