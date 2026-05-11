"""Format and post the full A/B benchmark results — SKILL.md Steps 8 + 9.

Reads from a bench_dir already populated by prep_ab.sh + run_agents_ab.sh
+ evaluate.py:

    <bench-dir>/run_meta.json            eval_id, model, skill_*,
                                          blinded_map, tokens_a/b
    <bench-dir>/scoring/eval.json        assertions + prompt
    <bench-dir>/scoring/scores.json      per-candidate verdicts
    <bench-dir>/agent_A/run.json         num_turns, is_error, total_cost_usd
    <bench-dir>/agent_B/run.json         same
    <bench-dir>/agent_{A,B}/duration_sec wall-clock seconds

Writes:
    <bench-dir>/benchmark_comment_<skill>_<eval_id>.md

With --post, posts the comment to the linked GitHub issue (issue number
extracted from the trailing digits of eval_id, e.g. github-issue-60 → 60).
The body carries the <!-- BENCHMARK_COMPLETE: --> marker required by
SKILL.md's Phase Detection.

Usage:
    python3 post_results.py --bench-dir /tmp/benchmark_github-issue-60
    python3 post_results.py --bench-dir <dir> --post
    python3 post_results.py --bench-dir <dir> --asset-url <release-url> --post
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


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


def tally(assertions: list[dict]) -> tuple[int, int, int, float]:
    p = sum(1 for a in assertions if a.get("verdict") == "Pass")
    pa = sum(1 for a in assertions if a.get("verdict") == "Partial")
    f = sum(1 for a in assertions if a.get("verdict") == "Fail")
    total = max(p + pa + f, 1)
    return p, pa, f, (p + 0.5 * pa) / total


def fmt_minutes(secs: int | None) -> str:
    return f"{secs / 60:.1f}" if secs is not None else "?"


def fmt_cost(meta: dict | None) -> str:
    if not meta:
        return "?"
    c = meta.get("total_cost_usd")
    return f"${c:.4f}" if isinstance(c, (int, float)) else "?"


def fmt_turns(meta: dict | None) -> str:
    n = (meta or {}).get("num_turns")
    return str(n) if isinstance(n, int) else "?"


def fmt_err(meta: dict | None) -> str:
    e = (meta or {}).get("is_error")
    if e is False:
        return "None"
    if e is True:
        return "Yes"
    return "?"


def observations(score_a: float, score_b: float,
                 tokens_a: int, tokens_b: int) -> list[str]:
    bullets: list[str] = []
    diff = (score_a - score_b) * 100
    if abs(diff) < 5:
        bullets.append("Scores are comparable across the with-skill and "
                       "without-skill arms (within 5 percentage points).")
    elif diff > 0:
        bullets.append(f"With-skill scored {diff:.0f} percentage points "
                       "higher than without-skill.")
    else:
        bullets.append(f"Without-skill scored {-diff:.0f} percentage points "
                       "higher than with-skill.")
    if tokens_a and tokens_b:
        ratio = tokens_a / tokens_b if tokens_b else 0
        if ratio:
            bullets.append(
                f"With-skill used {tokens_a:,} tokens vs {tokens_b:,} "
                f"without-skill ({ratio:.1f}× ratio)."
            )
    return bullets


def verdict(score_a: float, score_b: float) -> str:
    diff = (score_a - score_b) * 100
    if abs(diff) < 5:
        return ("The skill produced comparable results to the no-skill "
                "baseline on this eval.")
    if diff > 0:
        return ("The skill improved on the no-skill baseline by "
                f"{diff:.0f} percentage points.")
    return ("The skill underperformed the no-skill baseline by "
            f"{-diff:.0f} percentage points on this eval.")


def compose_report(bench_dir: Path, asset_url: str) -> tuple[str, dict]:
    run_meta = json.loads((bench_dir / "run_meta.json").read_text())
    scores = json.loads((bench_dir / "scoring" / "scores.json").read_text())

    eval_id = run_meta["eval_id"]
    model = run_meta["model"]
    skill_name = run_meta["skill_name"]
    skill_sha = run_meta["skill_sha"]
    blinded_map = run_meta["blinded_map"]
    tokens_a = run_meta.get("tokens_a", 0)
    tokens_b = run_meta.get("tokens_b", 0)

    # blinded_map maps candidate_X → output_A/output_B. Invert to unblind.
    cand_for_arm = {v: k for k, v in blinded_map.items()}
    cand_a = cand_for_arm.get("output_A")
    cand_b = cand_for_arm.get("output_B")
    if not cand_a or not cand_b:
        sys.exit(f"Bad blinded_map in run_meta.json: {blinded_map!r}")

    arm_meta_a = read_json(bench_dir / "agent_A" / "run.json")
    arm_meta_b = read_json(bench_dir / "agent_B" / "run.json")
    dur_a = read_int(bench_dir / "agent_A" / "duration_sec")
    dur_b = read_int(bench_dir / "agent_B" / "duration_sec")

    a_assertions = scores.get(cand_a, {}).get("assertions", [])
    b_assertions = scores.get(cand_b, {}).get("assertions", [])
    pa, pap, paf, sa = tally(a_assertions)
    pb, pbp, pbf, sb = tally(b_assertions)

    # Pair assertions by text for the side-by-side breakdown.
    a_by_text = {a.get("text", ""): a for a in a_assertions}
    b_by_text = {a.get("text", ""): a for a in b_assertions}
    ordered_texts: list[str] = []
    seen: set[str] = set()
    for a in a_assertions + b_assertions:
        t = a.get("text", "")
        if t not in seen:
            seen.add(t)
            ordered_texts.append(t)
    breakdown_rows = [
        f"| {t} | {a_by_text.get(t, {}).get('verdict', '-')} "
        f"| {b_by_text.get(t, {}).get('verdict', '-')} |"
        for t in ordered_texts
    ]
    breakdown = "\n".join(breakdown_rows) or "| _(no assertions)_ | - | - |"

    run_date = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    obs_bullets = "\n".join(f"- {b}" for b in observations(sa, sb, tokens_a, tokens_b))
    artifact_line = (
        f"**Agent A Output:** [Download Agent A Archive]({asset_url})"
        if asset_url else "**Agent A Output:** _(archive not uploaded)_"
    )
    complete_marker = json.dumps(
        {"eval_id": eval_id, "model": model, "skill_sha": skill_sha},
        separators=(",", ":"),
    )

    body = f"""## Automated Benchmark Results — `{skill_name}`

### Run Metadata

| Field | Value |
|---|---|
| **Eval ID** | `{eval_id}` |
| **Run date** | {run_date} |
| **Model** | `{model}` |
| **Skill version** | `{skill_sha[:7]}` |
| **Triggered by** | Scheduled |

### Scorecard

| Metric | With Skill | Without Skill |
|---|---|---|
| **Score** | {sa:.2f} ({sa*100:.0f}%) | {sb:.2f} ({sb*100:.0f}%) |
| **Assertions** | {pa} Pass · {pap} Partial · {paf} Fail | {pb} Pass · {pbp} Partial · {pbf} Fail |
| **Skills loaded** | 1 | 0 |
| **Execution time** | {fmt_minutes(dur_a)} min | {fmt_minutes(dur_b)} min |
| **Token usage** | {tokens_a:,} | {tokens_b:,} |
| **Cost (USD)** | {fmt_cost(arm_meta_a)} | {fmt_cost(arm_meta_b)} |

### Key Observations

{obs_bullets}

### Verdict

{verdict(sa, sb)}

---

## Technical Details & Artifacts

<details>
<summary>View Assertion Breakdown, Code Artifacts, and Logs</summary>

### Assertion Breakdown

| Assertion | With Skill | Without Skill |
|---|---|---|
{breakdown}

### Debugging Information

#### Agent A (With Skill)
- **Total Turns:** {fmt_turns(arm_meta_a)}
- **Errors/Retries:** {fmt_err(arm_meta_a)}

#### Agent B (Without Skill)
- **Total Turns:** {fmt_turns(arm_meta_b)}
- **Errors/Retries:** {fmt_err(arm_meta_b)}

### Detailed Artifacts

{artifact_line}

</details>

---
<!-- BENCHMARK_COMPLETE: {complete_marker} -->
*Posted automatically by `benchmark-runner` · Repo: https://github.com/{os.environ.get("PHARMA_SKILLS_GITHUB_REPO", "RConsortium/pharma-skills")}*
"""
    summary = {
        "eval_id": eval_id, "model": model, "skill_name": skill_name,
        "skill_sha": skill_sha, "score_a": sa, "score_b": sb,
        "tokens_a": tokens_a, "tokens_b": tokens_b,
    }
    return body, summary


def issue_number(eval_id: str) -> str | None:
    m = re.search(r"(\d+)$", eval_id)
    return m.group(1) if m else None


def post_to_github(body_path: Path, repo: str, issue: str) -> str:
    cmd = ["gh", "issue", "comment", issue, "--repo", repo,
           "--body-file", str(body_path)]
    print("$ " + " ".join(cmd))
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(f"gh issue comment failed:\n{res.stderr}")
    return (res.stdout or "").strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench-dir", required=True, type=Path,
                    help="Bench directory produced by prep_ab.sh.")
    ap.add_argument("--asset-url", default="",
                    help="GitHub release asset URL for Agent A's archive "
                         "(included verbatim in the Artifacts section).")
    ap.add_argument("--post", action="store_true",
                    help="Post the comment to the linked GitHub issue.")
    ap.add_argument("--repo",
                    default=os.environ.get(
                        "PHARMA_SKILLS_GITHUB_REPO", "RConsortium/pharma-skills"),
                    help="OWNER/REPO target for --post.")
    args = ap.parse_args()

    bench_dir = args.bench_dir.resolve()
    if not bench_dir.is_dir():
        sys.exit(f"bench-dir does not exist: {bench_dir}")

    body, summary = compose_report(bench_dir, args.asset_url)

    out_name = f"benchmark_comment_{summary['skill_name']}_{summary['eval_id']}.md"
    out_path = bench_dir / out_name
    out_path.write_text(body, encoding="utf-8")
    print(f"Wrote {out_path}")

    comment_url = ""
    if args.post:
        issue = issue_number(summary["eval_id"])
        if not issue:
            print(f"WARNING: could not extract issue number from "
                  f"{summary['eval_id']!r} — skipping post", file=sys.stderr)
        else:
            comment_url = post_to_github(out_path, args.repo, issue) or \
                          f"https://github.com/{args.repo}/issues/{issue}"
            print(f"Posted to {args.repo} issue #{issue}")

    print()
    print(f"✓ Phase 2 complete — full benchmark posted for "
          f"{summary['eval_id']} ({summary['model']})")
    print(f"  • Score: With Skill {summary['score_a']*100:.0f}% · "
          f"Without Skill {summary['score_b']*100:.0f}%")
    if comment_url:
        print(f"  • Comment: {comment_url}")
    print(f"  • Tokens — A: {summary['tokens_a']:,} · B: {summary['tokens_b']:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
