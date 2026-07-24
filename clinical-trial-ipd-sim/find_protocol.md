# Protocol acquisition — find-protocol

Step 1 reads the trial's **Schedule of Activities and CRF frame from the full protocol**, so it needs
a real protocol document. The protocol is obtained in exactly one of two ways, and is **never fetched
from the open web**:

1. **User-supplied.** If the user provided a protocol PDF, use it. (Preferred.)
2. **find-protocol.** Otherwise run the vendored `find_protocol.py`, which turns an NCT ID into that
   trial's full protocol PDF taken **strictly** from the public HuggingFace dataset
   [`trialdesignbench/source`](https://huggingface.co/datasets/trialdesignbench/source) — nothing from
   ClinicalTrials.gov, NEJM, or anywhere else.

If neither yields a protocol, **STOP and ask the user for one. Do not continue, and do not try to fetch
a protocol from the web.**

## Run it

The finder ships **inside this skill** (vendored), so it runs with no external skill dependency:

```bash
python3 vendor/python/find_protocol/find_protocol.py <NCT_ID> --out-dir <output>/intake
```

Use a `python3` that has `duckdb` / `requests` / `pypdf` installed (see `vendor/python/requirements.txt`
— the same interpreter the ODM step uses). It prints one JSON line on stdout and sets an exit code. The
verified PDF, when found, lands at `<output>/intake/<NCT>_protocol.pdf`.

## Branch on the result

| Result | `found` | exit | What to do |
|---|---|---|---|
| Verified full protocol PDF at `pdf_path` | `true` | 0 | Use `pdf_path` as the protocol input; continue to Step 2. |
| NCT not in the dataset, or only a SAP (no full protocol) | `false` | 1 | **STOP — ask the user for the protocol.** Do NOT web-fetch. |
| Operational error (bad NCT, network, parquet unavailable) | absent/`false` | 2 | Could not decide — **STOP and ask the user** (or retry). Never treat as "no protocol exists"; never web-fetch. |

Branch on `found` for the answer; use the exit code only to tell a proven "not in dataset" (1) apart
from "couldn't tell" (2). **Either non-zero outcome means the same thing: stop and ask the user — do
not fall back to the web.**

Why the rule is strict: the protocol is the trial's ground truth for the CRF frame and SoA. A wrong or
web-scraped document silently corrupts every downstream step (coverage, DAG, params, gates), so the
skill accepts a protocol **only** from the user or from this verified dataset, and otherwise halts. The
verification (git-LFS pointer guard, `%PDF-` magic bytes, `pypdf` opens, >1 page) lives in the vendored
`find_protocol.py`.
