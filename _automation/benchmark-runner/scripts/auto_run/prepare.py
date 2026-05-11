"""Prepare a single-arm benchmark workspace from an eval definition.

Two modes:

  --mode bench --eval-id <id>      Read _automation/evals/<id>.json directly.
                                   For developers picking a specific task.

  --mode issue --model <model>     Call get_next_eval.py to dispatch the next
                                   pending eval (CI/scheduled use). The
                                   dispatched eval is written into bench_dir/.

In both modes the output layout is identical:

    bench_dir/
    ├── eval.json     ← native eval (with _skill_* metadata in issue mode)
    ├── prompt.txt    ← what to feed the agent
    ├── input/        ← shared input files (copied from eval.files)
    └── output/       ← developer fills this with their agent's outputs

The agent invocation is *not* part of this script. After preparing, run
whatever agent you want against `prompt.txt` (working dir = bench_dir),
then run `evaluate.py --bench-dir <dir>` to score.

Usage:
    python3 prepare.py --bench-dir bench_74/ --mode bench --eval-id github-issue-74
    python3 prepare.py --bench-dir bench_next/ --mode issue --model claude-sonnet-4-6
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
EVALS_DIR = REPO_ROOT / "evals"
SCRIPTS = Path(__file__).resolve().parent


def load_eval_bench(eval_id: str) -> dict:
    path = EVALS_DIR / f"{eval_id}.json"
    if not path.exists():
        sys.exit(f"No such eval: {path}")
    return json.loads(path.read_text())


def load_eval_issue(model: str, runner_id: str | None) -> dict | None:
    cmd = ["python3", str(SCRIPTS / "get_next_eval.py"), "--model", model]
    if runner_id:
        cmd += ["--runner-id", runner_id]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(f"get_next_eval.py failed:\n{res.stderr}")
    out = res.stdout.strip()
    if out.startswith("STATUS: UP_TO_DATE"):
        return None
    return json.loads(out)


def build_prompt(eval_case: dict, input_aliases: list[str]) -> str:
    parts: list[str] = []
    if eval_case.get("language"):
        parts.append(f"Use {eval_case['language']} for this task.")
    parts.append(eval_case["prompt"])
    if input_aliases:
        listing = ", ".join(f"`{a}`" for a in input_aliases)
        parts.append(f"Input file(s) are staged in the `input/` directory: {listing}")
    parts.append(
        "Save all generated files into a directory named `output/` in your "
        "working directory."
    )
    return "\n\n".join(parts)


def stage_inputs(eval_case: dict, input_dir: Path) -> list[str]:
    input_dir.mkdir(parents=True, exist_ok=True)
    aliases: list[str] = []
    for idx, fpath_str in enumerate(eval_case.get("files") or [], start=1):
        src = Path(fpath_str)
        if not src.is_absolute():
            src = (REPO_ROOT / src).resolve()
        ext = src.suffix.lower() or ".dat"
        alias = f"input_{idx:03d}{ext}"
        shutil.copy(src, input_dir / alias)
        aliases.append(alias)
    return aliases


def write_workspace(eval_case: dict, bench_dir: Path) -> None:
    bench_dir.mkdir(parents=True, exist_ok=True)
    (bench_dir / "output").mkdir(exist_ok=True)
    aliases = stage_inputs(eval_case, bench_dir / "input")
    prompt = build_prompt(eval_case, aliases)
    (bench_dir / "prompt.txt").write_text(prompt, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench-dir", required=True, type=Path)
    ap.add_argument("--mode", required=True, choices=("bench", "issue"))
    ap.add_argument("--eval-id", help="Eval id (required for --mode bench).")
    ap.add_argument("--model", help="Model id (required for --mode issue).")
    ap.add_argument("--runner-id", help="Runner id passed to get_next_eval.py (issue mode).")
    args = ap.parse_args()

    if args.mode == "bench":
        if not args.eval_id:
            sys.exit("--eval-id is required for --mode bench")
        eval_case = load_eval_bench(args.eval_id)
    else:  # issue
        if not args.model:
            sys.exit("--model is required for --mode issue")
        eval_case = load_eval_issue(args.model, args.runner_id)
        if eval_case is None:
            print("STATUS: UP_TO_DATE")
            return 0

    write_workspace(eval_case, args.bench_dir)

    print(f"Prepared {args.bench_dir} (eval_id={eval_case.get('id', '?')})")
    print(f"Next: run any agent in {args.bench_dir} against prompt.txt,")
    print(f"      writing outputs to output/, then run evaluate.py.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
