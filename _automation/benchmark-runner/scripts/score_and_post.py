#!/usr/bin/env python3
"""
score_and_post.py — Automated scoring and GitHub posting for benchmark runs.

Launches a fast Claude Haiku scorer agent against the blinded candidate
outputs, formats the results into the standard benchmark report, and upserts
the comment on the originating GitHub issue.

Usage:
    python3 score_and_post.py \\
        --eval-id github-issue-21 \\
        --model claude-sonnet-4-6 \\
        --base-dir /tmp/benchmark_github-issue-21 \\
        --eval-case /tmp/eval_case_github-issue-21.json

Environment:
    GH_TOKEN or GITHUB_TOKEN   required for GitHub comment upsert
    SCORER_MODEL               override scorer model (default: claude-haiku-4-5-20251001)
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS_DIR = Path(__file__).resolve().parent

SCORER_MODEL = os.environ.get("SCORER_MODEL", "claude-haiku-4-5-20251001")
ALLOWED_TOOLS = "Bash,Read,Glob"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _read_text_files(directory: Path, max_bytes: int = 8000) -> dict[str, str]:
    """Return {filename: content} for readable text files, truncated to max_bytes each."""
    result = {}
    for p in sorted(directory.iterdir()):
        if p.is_file() and p.suffix.lower() not in {".png", ".jpg", ".docx", ".rds", ".xlsx", ".pdf"}:
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
                if len(text) > max_bytes:
                    text = text[:max_bytes] + f"\n... [truncated at {max_bytes} chars]"
                result[p.name] = text
            except Exception:
                pass
    return result


def _build_scorer_prompt(eval_case: dict, c1_files: dict, c2_files: dict) -> str:
    """Construct the prompt sent to the Haiku scorer."""
    assertions = eval_case.get("assertions", [])
    scoring_prompt = eval_case.get("_scoring_prompt", "Score the two candidates.")

    lines = [
        scoring_prompt,
        "",
        "## Files available under candidate_1/",
    ]
    for name, content in c1_files.items():
        lines += [f"\n### candidate_1/{name}", "```", content, "```"]

    lines += ["", "## Files available under candidate_2/"]
    for name, content in c2_files.items():
        lines += [f"\n### candidate_2/{name}", "```", content, "```"]

    lines += [
        "",
        "## Required output format",
        "",
        "Return a single JSON object (no markdown fences) with this exact schema:",
        "",
        json.dumps({
            "candidate_1": {
                "assertion_scores": {a: "Pass|Partial|Fail" for a in assertions},
                "notes": "brief qualitative notes",
            },
            "candidate_2": {
                "assertion_scores": {a: "Pass|Partial|Fail" for a in assertions},
                "notes": "brief qualitative notes",
            },
            "key_observations": ["bullet 1", "bullet 2", "bullet 3"],
            "verdict": "1-2 sentence overall verdict",
        }, indent=2),
        "",
        "Use only Pass, Partial, or Fail for each assertion score.",
        "Return ONLY the JSON object — no preamble, no explanation.",
    ]
    return "\n".join(lines)


def _run_scorer(prompt: str, scoring_dir: Path) -> dict:
    """Launch claude -p haiku with the scorer prompt and parse JSON output."""
    prompt_file = scoring_dir / "_scorer_prompt.txt"
    output_file = scoring_dir / "_scorer_run.json"
    prompt_file.write_text(prompt, encoding="utf-8")

    cmd = [
        "claude", "-p",
        "--model", SCORER_MODEL,
        "--allowedTools", ALLOWED_TOOLS,
        "--output-format", "json",
    ]
    with open(prompt_file, "rb") as stdin_f, open(output_file, "w") as stdout_f:
        result = subprocess.run(cmd, stdin=stdin_f, stdout=stdout_f, stderr=subprocess.PIPE)

    run_data = json.loads(output_file.read_text())
    raw_text = run_data.get("result", "")

    # The scorer is instructed to return raw JSON; strip any accidental fences
    raw_text = raw_text.strip()
    if raw_text.startswith("```"):
        raw_text = raw_text.split("```")[1]
        if raw_text.startswith("json"):
            raw_text = raw_text[4:]

    try:
        return json.loads(raw_text)
    except json.JSONDecodeError as exc:
        print(f"[scorer] WARNING: could not parse scorer JSON: {exc}", file=sys.stderr)
        print(f"[scorer] Raw output: {raw_text[:500]}", file=sys.stderr)
        return {}


def _compute_score(assertion_scores: dict) -> tuple[int, int, int, float]:
    """Return (passes, partials, fails, score_fraction)."""
    passes = sum(1 for v in assertion_scores.values() if v == "Pass")
    partials = sum(1 for v in assertion_scores.values() if v == "Partial")
    fails = sum(1 for v in assertion_scores.values() if v == "Fail")
    total = passes + partials + fails
    fraction = (passes + 0.5 * partials) / total if total else 0
    return passes, partials, fails, fraction


def _get_run_metadata(base_dir: Path) -> dict:
    """Extract timing and token metadata from agent run JSON files."""
    meta = {"tokens_a": "N/A", "tokens_b": "N/A", "time_a": "N/A", "time_b": "N/A",
            "turns_a": "N/A", "turns_b": "N/A", "error_a": "N/A", "error_b": "N/A"}
    for label in ("A", "B"):
        path = base_dir / f"agent_{label}" / f"agent_{label}_run.json"
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text())
            u = data.get("usage", {})
            total_tokens = u.get("input_tokens", 0) + u.get("output_tokens", 0)
            duration_min = round(data.get("duration_ms", 0) / 60000, 1)
            key = label.lower()
            meta[f"tokens_{key}"] = f"{total_tokens:,}" if total_tokens else "N/A"
            meta[f"time_{key}"] = f"{duration_min}m"
            meta[f"turns_{key}"] = data.get("num_turns", "N/A")
            is_err = data.get("is_error", False)
            result_text = data.get("result", "")
            if is_err:
                snippet = result_text[:120].replace("\n", " ")
                meta[f"error_{key}"] = snippet or "True"
            else:
                meta[f"error_{key}"] = "None"
        except Exception:
            pass
    return meta


def _format_report(
    eval_case: dict,
    model: str,
    scores: dict,
    meta: dict,
    blinded_map: dict,
    upload_url: str,
) -> str:
    """Build the full markdown benchmark report."""
    # Unblind: map candidate_1/2 back to With Skill / Without Skill
    # blinded_map = {"candidate_1": "output_A", "candidate_2": "output_B"}
    # output_A = With Skill, output_B = Without Skill
    c_skill = next((c for c, o in blinded_map.items() if o == "output_A"), "candidate_1")
    c_noskill = next((c for c, o in blinded_map.items() if o == "output_B"), "candidate_2")

    skill_scores = scores.get(c_skill, {}).get("assertion_scores", {})
    noskill_scores = scores.get(c_noskill, {}).get("assertion_scores", {})

    p_a, pt_a, f_a, frac_a = _compute_score(skill_scores)
    p_b, pt_b, f_b, frac_b = _compute_score(noskill_scores)

    assertions = eval_case.get("assertions", [])
    eval_id = eval_case.get("id", "unknown")
    skill_name = eval_case.get("_skill_name", "unknown")
    skill_sha = eval_case.get("_skill_sha", "")[:16]
    run_date = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    key_obs = scores.get("key_observations", [])
    verdict = scores.get("verdict", "")
    skill_notes = scores.get(c_skill, {}).get("notes", "")
    noskill_notes = scores.get(c_noskill, {}).get("notes", "")

    # Assertion breakdown table
    assertion_rows = ""
    for a in assertions:
        s_skill = skill_scores.get(a, "N/A")
        s_noskill = noskill_scores.get(a, "N/A")
        assertion_rows += f"| {a} | **{s_skill}** | **{s_noskill}** |\n"

    obs_bullets = "\n".join(f"- {o}" for o in key_obs) if key_obs else "- No observations recorded."

    return f"""## Automated Benchmark Results — `{skill_name}`

### Run Metadata

| Field | Value |
|---|---|
| **Eval ID** | `{eval_id}` |
| **Run date** | {run_date} |
| **Model** | `{model}` |
| **Skill version** | `{skill_sha}` |
| **Triggered by** | Scheduled/Manual |

### Scorecard

| Metric | With Skill | Without Skill |
|---|---|---|
| **Score** | {p_a + 0.5 * pt_a:.1f}/{len(assertions)} ({frac_a:.0%}) | {p_b + 0.5 * pt_b:.1f}/{len(assertions)} ({frac_b:.0%}) |
| **Assertions** | {p_a} Pass / {pt_a} Partial / {f_a} Fail | {p_b} Pass / {pt_b} Partial / {f_b} Fail |
| **Skills loaded** | 1 | 0 |
| **Execution time** | {meta["time_a"]} | {meta["time_b"]} |
| **Token usage** | {meta["tokens_a"]} | {meta["tokens_b"]} |

### Key Observations

{obs_bullets}

### Verdict

{verdict}

---

## Technical Details & Artifacts

<details>
<summary>View Assertion Breakdown, Code Artifacts, and Logs</summary>

### Assertion Breakdown

| Assertion | With Skill | Without Skill |
|---|---|---|
{assertion_rows}
### Debugging Information

#### Agent A (With Skill)
- **Total Turns:** {meta["turns_a"]}
- **Errors/Retries:** {meta["error_a"]}

#### Agent B (Without Skill)
- **Total Turns:** {meta["turns_b"]}
- **Errors/Retries:** {meta["error_b"]}

### Detailed Artifacts

**Detailed Outputs:** [Download Full Benchmark Archive (.zip)]({upload_url})

#### Agent A (With Skill) — Scorer notes
{skill_notes}

#### Agent B (Without Skill) — Scorer notes
{noskill_notes}

</details>

---
*Posted automatically by `benchmark-runner` · Repo: https://github.com/RConsortium/pharma-skills*
"""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--eval-id", required=True, help="e.g. github-issue-21")
    parser.add_argument("--model", required=True, help="API model ID used for the benchmark agents")
    parser.add_argument(
        "--base-dir",
        required=True,
        help="Benchmark working directory (contains agent_A/ and agent_B/)",
    )
    parser.add_argument(
        "--eval-case",
        required=True,
        help="Path to the eval case JSON saved by get_next_eval.py",
    )
    parser.add_argument(
        "--upload-url",
        default="",
        help="Direct download URL for the benchmark zip (optional)",
    )
    parser.add_argument(
        "--report-out",
        help="Write the markdown report to this path instead of a temp file",
    )
    args = parser.parse_args()

    base_dir = Path(args.base_dir)
    eval_case = json.loads(Path(args.eval_case).read_text())
    blinded_map = eval_case.get("_blinded_scoring_map", {"candidate_1": "output_A", "candidate_2": "output_B"})

    # ── Step 1: Set up blinded scoring directory ──────────────────────────
    scoring_dir = base_dir / "scoring"
    scoring_dir.mkdir(exist_ok=True)
    for candidate, output_label in blinded_map.items():
        src = base_dir / f"agent_{'A' if output_label == 'output_A' else 'B'}" / output_label
        dst = scoring_dir / candidate
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    print(f"[score_and_post] Blinded scoring dir ready: {scoring_dir}")

    # ── Step 2: Read text files from both candidates ──────────────────────
    c1_files = _read_text_files(scoring_dir / "candidate_1")
    c2_files = _read_text_files(scoring_dir / "candidate_2")
    print(f"[score_and_post] candidate_1: {list(c1_files)}")
    print(f"[score_and_post] candidate_2: {list(c2_files)}")

    # ── Step 3: Build scorer prompt and run Haiku scorer ──────────────────
    scorer_prompt = _build_scorer_prompt(eval_case, c1_files, c2_files)
    print(f"[score_and_post] Launching {SCORER_MODEL} scorer...")
    scores = _run_scorer(scorer_prompt, scoring_dir)

    if not scores:
        print("[score_and_post] ERROR: Scorer returned empty results.", file=sys.stderr)
        sys.exit(1)

    print("[score_and_post] Scorer complete.")

    # ── Step 4: Build upload URL ──────────────────────────────────────────
    upload_url = args.upload_url or (
        f"https://github.com/RConsortium/pharma-skills/releases/download/"
        f"benchmark-results/benchmark_results_{args.eval_id}.zip"
    )

    # ── Step 5: Format report ─────────────────────────────────────────────
    meta = _get_run_metadata(base_dir)
    report_md = _format_report(eval_case, args.model, scores, meta, blinded_map, upload_url)

    if args.report_out:
        report_path = Path(args.report_out)
    else:
        skill_name = eval_case.get("_skill_name", "skill")
        report_path = Path(tempfile.gettempdir()) / f"benchmark_comment_{skill_name}_{args.eval_id}.md"

    report_path.write_text(report_md, encoding="utf-8")
    print(f"[score_and_post] Report written to: {report_path}")

    # ── Step 6: Post to GitHub ─────────────────────────────────────────────
    issue_number = args.eval_id.replace("github-issue-", "")
    post_script = SCRIPTS_DIR / "post_issue_comment.py"

    result = subprocess.run(
        [
            sys.executable,
            str(post_script),
            issue_number,
            "--repo", "RConsortium/pharma-skills",
            "--body-file", str(report_path),
            "--model", args.model,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"[score_and_post] ERROR posting comment: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    print(f"[score_and_post] {result.stdout.strip()}")


if __name__ == "__main__":
    main()
