"""Score two anonymized benchmark candidates against an eval's assertions.

Reads:
    $BENCH_DIR/eval.json                  (native eval format)
    $BENCH_DIR/candidate_1/                (one arm's artifacts — anonymized)
    $BENCH_DIR/candidate_2/                (other arm's artifacts — anonymized)

Writes:
    $BENCH_DIR/score_prompt.txt           (synthesized scorer prompt)
    $BENCH_DIR/score_run.json             (raw `claude -p` output)
    $BENCH_DIR/scores.json
        {
          "candidate_1": {
            "assertions": [
              {"text": "...", "verdict": "Pass|Partial|Fail", "notes": "..."},
              ...
            ],
            "notes": "..."
          },
          "candidate_2": {...}
        }

Synthesizes the scoring prompt from the eval's prompt + expected_output +
assertions, runs `claude -p` once with cwd = $BENCH_DIR so both candidate
subdirs are directly visible, and parses the scorer's JSON response.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

CANDIDATES = ("candidate_1", "candidate_2")


def build_scoring_prompt(eval_case: dict) -> str:
    assertions = eval_case.get("assertions", [])
    bullets = "\n".join(f"- {a}" for a in assertions)
    return (
        "Score two anonymized benchmark candidates against the rubric below. "
        "Do not infer which candidate used a skill. Score only the artifacts "
        "available under `candidate_1/` and `candidate_2/`.\n\n"
        f"Task prompt:\n{eval_case.get('prompt', '')}\n\n"
        f"Expected output:\n{eval_case.get('expected_output', '')}\n\n"
        f"Assertions:\n{bullets}\n\n"
        "Respond with a JSON object only, no prose, with this shape:\n"
        '{"candidate_1": {"assertions": [{"text": "<assertion>", '
        '"verdict": "Pass|Partial|Fail", "notes": "<short reason>"}, ...], '
        '"notes": "<overall notes>"}, '
        '"candidate_2": {"assertions": [...], "notes": "..."}}\n'
        "Do not mention or infer treatment labels."
    )


def empty_arm(eval_case: dict, reason: str) -> dict:
    return {
        "assertions": [
            {"text": a, "verdict": "Fail", "notes": reason}
            for a in eval_case.get("assertions", [])
        ],
        "notes": "",
    }


def run_scorer(eval_case: dict, bench_dir: Path, model: str) -> dict:
    # Run the scorer with cwd = bench_dir (= scoring/). candidate_1/ and
    # candidate_2/ are already siblings to eval.json there, so the scorer
    # can read each candidate's artifacts directly. eval.json is also
    # passed via prompt (its disk presence is redundant but harmless),
    # and run.json/duration_sec are visible — blinding is preserved by
    # the candidate_X anonymization, not by hiding token counts.
    prompt = build_scoring_prompt(eval_case)
    (bench_dir / "score_prompt.txt").write_text(prompt, encoding="utf-8")

    with open(bench_dir / "score_prompt.txt", "rb") as fin, \
         open(bench_dir / "score_run.json", "wb") as fout:
        subprocess.run(
            ["claude", "-p", "--model", model,
             "--allowedTools", "Read,Glob",
             "--output-format", "json"],
            cwd=bench_dir, stdin=fin, stdout=fout, stderr=subprocess.PIPE,
        )

    score_run = json.loads((bench_dir / "score_run.json").read_text())
    raw = score_run.get("result", "")
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if not m:
        fallback = empty_arm(eval_case, "scorer returned no JSON")
        fallback["notes"] = raw[:500]
        return {cand: fallback for cand in CANDIDATES}

    parsed = json.loads(m.group(0))
    # Normalize: ensure both arms are present even if the scorer dropped one.
    for cand in CANDIDATES:
        if cand not in parsed or not isinstance(parsed[cand], dict):
            parsed[cand] = empty_arm(eval_case, f"scorer omitted {cand}")
    return parsed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench-dir", required=True, type=Path)
    ap.add_argument("--model", required=True, help="Scorer model id.")
    args = ap.parse_args()

    eval_case = json.loads((args.bench_dir / "eval.json").read_text())
    scores = run_scorer(eval_case, args.bench_dir, args.model)
    out = args.bench_dir / "scores.json"
    out.write_text(json.dumps(scores, indent=2), encoding="utf-8")
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
