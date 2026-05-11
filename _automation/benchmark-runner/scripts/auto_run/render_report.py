"""Render one anonymized candidate's scorecard from a two-arm scores.json.

Reads from $BENCH_DIR (the parent scoring dir):
    eval.json                       (required — shared across candidates)
    scores.json                     (required — produced by score.py;
                                     keyed by "candidate_1" / "candidate_2")
    <candidate>/run.json            (optional — claude -p style metadata)
    <candidate>/duration_sec        (optional — wall-clock seconds)
    <candidate>/archive_url.txt     (optional)

Writes: $BENCH_DIR/<candidate>/report.md
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

GITHUB_REPO = os.environ.get("PHARMA_SKILLS_GITHUB_REPO", "RConsortium/pharma-skills")
TEMPLATE = Path(__file__).resolve().parent / "report_template.md"
CANDIDATES = ("candidate_1", "candidate_2")


def tally(assertions: list[dict]) -> tuple[int, int, int, float]:
    p = sum(1 for a in assertions if a.get("verdict") == "Pass")
    pa = sum(1 for a in assertions if a.get("verdict") == "Partial")
    f = sum(1 for a in assertions if a.get("verdict") == "Fail")
    total = max(p + pa + f, 1)
    return p, pa, f, (p + 0.5 * pa) / total


def tokens_of(result: dict | None) -> int | str:
    if not result:
        return "?"
    u = result.get("usage") or {}
    n = int(u.get("input_tokens", 0)) + int(u.get("output_tokens", 0))
    return n if n else "?"


def cost_of(result: dict | None) -> str:
    if not result:
        return "?"
    c = result.get("total_cost_usd")
    return f"${c:.4f}" if isinstance(c, (int, float)) else "?"


def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def read_int(path: Path) -> int | None:
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def fmt_minutes(secs: int | None) -> str:
    return f"{secs / 60:.1f}m" if secs is not None else "?"


def render(bench_dir: Path, candidate: str, model: str) -> str:
    eval_case = json.loads((bench_dir / "eval.json").read_text())
    all_scores = json.loads((bench_dir / "scores.json").read_text())
    scores = all_scores.get(candidate) or {}

    cand_dir = bench_dir / candidate
    run_meta = read_json(cand_dir / "run.json")
    duration = read_int(cand_dir / "duration_sec")
    url_file = cand_dir / "archive_url.txt"
    artifact_url = url_file.read_text().strip() if url_file.exists() else ""

    assertions = scores.get("assertions", [])
    p, pa, f, score = tally(assertions)

    rows = [
        f"| {a.get('text', '')} | {a.get('verdict', '-')} | {a.get('notes', '')} |"
        for a in assertions
    ]
    breakdown = "| Assertion | Verdict | Notes |\n|---|---|---|\n" + "\n".join(rows)

    artifact_link = (
        f"[Download Full Benchmark Archive (.zip)]({artifact_url})"
        if artifact_url else "_Upload skipped — no archive URL_"
    )

    return TEMPLATE.read_text().format(
        skill=(eval_case.get("target_skills") or ["?"])[0],
        eval_id=eval_case.get("id", "?"),
        run_date=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        model=model,
        score=score, pct=score * 100,
        p=p, pa=pa, f=f,
        duration=fmt_minutes(duration),
        tokens=tokens_of(run_meta),
        cost=cost_of(run_meta),
        breakdown=breakdown,
        turns=(run_meta or {}).get("num_turns", "?"),
        err=(run_meta or {}).get("is_error", "None"),
        artifact_link=artifact_link,
        repo=GITHUB_REPO,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench-dir", required=True, type=Path,
                    help="Parent scoring dir (contains scores.json + candidate_X/).")
    ap.add_argument("--candidate", required=True, choices=CANDIDATES,
                    help="Which candidate to render.")
    ap.add_argument("--model", required=True, help="Scorer model id (recorded in report).")
    args = ap.parse_args()

    report = render(args.bench_dir, args.candidate, args.model)
    out = args.bench_dir / args.candidate / "report.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(report, encoding="utf-8")
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
