"""Score + render reports for a two-arm benchmark workspace.

Given a $BENCH_DIR laid out as:

    bench_dir/
    ├── eval.json
    ├── candidate_1/
    │   ├── output/        ← one arm's outputs (anonymized)
    │   ├── run.json       ← optional, claude -p style metadata
    │   └── duration_sec   ← optional, wall-clock seconds
    └── candidate_2/
        └── ...

this:
  1. Runs score.py once over both candidates → bench_dir/scores.json
  2. Runs render_report.py per candidate → bench_dir/<candidate>/report.md

Usage:
    python3 evaluate.py --bench-dir scoring/ --scorer-model claude-sonnet-4-6
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
CANDIDATES = ("candidate_1", "candidate_2")


def run(cmd: list[str]) -> None:
    print("$ " + " ".join(str(c) for c in cmd), flush=True)
    res = subprocess.run(cmd)
    if res.returncode != 0:
        sys.exit(f"Step failed: {cmd[0:2]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench-dir", required=True, type=Path,
                    help="Parent scoring dir with eval.json + candidate_1/ + candidate_2/.")
    ap.add_argument("--scorer-model", required=True,
                    help="Model used to run the scorer (e.g. claude-sonnet-4-6).")
    args = ap.parse_args()

    bench_dir = args.bench_dir.resolve()

    run(["python3", str(SCRIPTS / "score.py"),
         "--bench-dir", str(bench_dir), "--model", args.scorer_model])

    for cand in CANDIDATES:
        run(["python3", str(SCRIPTS / "render_report.py"),
             "--bench-dir", str(bench_dir),
             "--candidate", cand,
             "--model", args.scorer_model])

    print("\nReports:")
    for cand in CANDIDATES:
        print(f"  {bench_dir / cand / 'report.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
