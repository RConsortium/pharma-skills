#!/usr/bin/env python3
"""
scan_phase_detection.py — Phase Detection helper for benchmark-runner.

Two modes:

  SINGLE (default): classify one issue from one saved MCP result file.
    python3 scan_phase_detection.py <result_file> <eval_id> <model> <skill_sha>
    Prints: COMPLETE | PARTIAL | UNDONE | UNKNOWN

  BATCH (--scan-dir): classify all issues whose MCP result files are stored
  in a directory (one file per issue, named <eval_id>.json), then write a
  structured phase-detection cache file for get_next_eval.py to consume.
    python3 scan_phase_detection.py \\
        --scan-dir /tmp/phase_detection/ \\
        --model claude-sonnet-4-6 \\
        --skill-sha b5ede6a... \\
        [--write-cache /tmp/phase_detection_cache.json]

  The cache file format consumed by get_next_eval.py --phase-detection-cache:
    {
      "scan_time": "ISO8601",
      "model": "claude-sonnet-4-6",
      "skill_sha": "b5ede6a...",
      "statuses": {
        "github-issue-2":  "PARTIAL",
        "github-issue-21": "COMPLETE",
        "github-issue-23": "PARTIAL",
        "github-issue-128": "UNDONE"
      },
      "partial_details": {
        "github-issue-23": {
          "oldest_partial_at": "2026-05-27T19:04:39Z",
          "oldest_partial_id": 4557791868,
          "state": { ... }
        }
      }
    }
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# Core classification logic
# ---------------------------------------------------------------------------

def _parse_comments(raw: str) -> list[dict]:
    """Parse comment list from a saved MCP issue_read result file."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        # Try extracting the inner JSON string from a {text: "..."} wrapper
        m = re.search(r'"text"\s*:\s*"(.*?)"(?=\s*[,}])', raw, re.DOTALL)
        if not m:
            return []
        try:
            data = json.loads(m.group(1).replace('\\"', '"').replace('\\n', '\n'))
        except Exception:
            return []

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("comments", "data", "items", "nodes"):
            if key in data and isinstance(data[key], list):
                return data[key]
        return [data]
    return []


_PARTIAL_RE  = re.compile(r'BENCHMARK_PARTIAL:\s*({.*?})\s*-->', re.DOTALL)
_COMPLETE_RE = re.compile(r'BENCHMARK_COMPLETE:\s*({.*?})\s*-->', re.DOTALL)


def classify_issue(
    comments: list[dict],
    eval_id: str,
    model: str,
    skill_sha: str,
) -> dict:
    """
    Classify a single issue's comment thread.

    Returns a dict with at minimum:
      {"status": "COMPLETE" | "PARTIAL" | "UNDONE"}

    For PARTIAL, also includes:
      {"oldest_partial_at": ISO8601, "oldest_partial_id": int, "state": {...}}
    """
    events = []
    for c in comments:
        body    = c.get("body", "")
        created = c.get("created_at", "")
        cid     = c.get("id", 0)

        for m in _PARTIAL_RE.finditer(body):
            try:
                state = json.loads(m.group(1))
            except Exception:
                continue
            if (state.get("eval_id") == eval_id
                    and state.get("model") == model
                    and state.get("skill_sha") == skill_sha):
                events.append(("PARTIAL", created, cid, state))

        for m in _COMPLETE_RE.finditer(body):
            try:
                state = json.loads(m.group(1))
            except Exception:
                continue
            if (state.get("eval_id") == eval_id
                    and state.get("model") == model
                    and state.get("skill_sha") == skill_sha):
                events.append(("COMPLETE", created, cid, {}))

    if not events:
        return {"status": "UNDONE"}

    events.sort(key=lambda x: x[1])

    if events[-1][0] == "COMPLETE":
        return {"status": "COMPLETE"}

    # Last event is PARTIAL — find the oldest one after the last COMPLETE
    last_complete_time = ""
    for etype, created, cid, _ in events:
        if etype == "COMPLETE":
            last_complete_time = created

    orphaned = [
        (etype, created, cid, state)
        for etype, created, cid, state in events
        if etype == "PARTIAL" and created > last_complete_time
    ]

    oldest = orphaned[0]
    return {
        "status": "PARTIAL",
        "oldest_partial_at": oldest[1],
        "oldest_partial_id": oldest[2],
        "state": oldest[3],
    }


def classify_file(
    path: str,
    eval_id: str,
    model: str,
    skill_sha: str,
) -> dict:
    """Load a saved MCP result file and classify it."""
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        return {"status": "UNKNOWN", "error": str(e)}

    comments = _parse_comments(raw)
    if not comments and raw.strip():
        # Non-empty file but no parseable comments — may be an empty array "[]"
        # or a genuinely empty issue.  Treat as UNDONE rather than UNKNOWN.
        pass

    return classify_issue(comments, eval_id, model, skill_sha)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _single_mode(args: argparse.Namespace) -> None:
    result = classify_file(args.result_file, args.eval_id, args.model, args.skill_sha)
    print(result["status"])


def _batch_mode(args: argparse.Namespace) -> None:
    scan_dir = Path(args.scan_dir)
    if not scan_dir.is_dir():
        print(f"Error: --scan-dir {scan_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    statuses: dict[str, str] = {}
    partial_details: dict[str, dict] = {}

    # Each file is named <eval_id>.json  (e.g. github-issue-23.json)
    for result_file in sorted(scan_dir.glob("*.json")):
        eval_id = result_file.stem  # strip .json
        info = classify_file(str(result_file), eval_id, args.model, args.skill_sha)
        statuses[eval_id] = info["status"]
        if info["status"] == "PARTIAL":
            partial_details[eval_id] = {
                "oldest_partial_at": info.get("oldest_partial_at"),
                "oldest_partial_id": info.get("oldest_partial_id"),
                "state":             info.get("state", {}),
            }
        print(f"  {eval_id:30s} → {info['status']}", file=sys.stderr)

    cache = {
        "scan_time":      datetime.now(timezone.utc).isoformat(),
        "model":          args.model,
        "skill_sha":      args.skill_sha,
        "statuses":       statuses,
        "partial_details": partial_details,
    }

    if args.write_cache:
        out = Path(args.write_cache)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(cache, indent=2), encoding="utf-8")
        print(f"[scan_phase_detection] Cache written to {out}", file=sys.stderr)
    else:
        print(json.dumps(cache, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)

    sub = parser.add_subparsers(dest="mode")

    # --- single mode (positional args, backward-compatible) ---
    parser.add_argument("result_file", nargs="?", help="Saved MCP result file (single mode)")
    parser.add_argument("eval_id",     nargs="?", help="e.g. github-issue-23 (single mode)")
    parser.add_argument("model",       nargs="?", help="e.g. claude-sonnet-4-6 (single mode)")
    parser.add_argument("skill_sha",   nargs="?", help="Full 64-char skill SHA (single mode)")

    # --- batch mode flags ---
    parser.add_argument("--scan-dir",   help="Directory of <eval_id>.json MCP result files (batch mode)")
    parser.add_argument("--model",      dest="model_flag",     help="Model (batch mode)")
    parser.add_argument("--skill-sha",  dest="skill_sha_flag", help="Skill SHA (batch mode)")
    parser.add_argument("--write-cache", metavar="PATH",
                        help="Write JSON cache to this path (batch mode; prints to stdout if omitted)")

    args = parser.parse_args()

    if args.scan_dir:
        # batch mode
        if not args.model_flag or not args.skill_sha_flag:
            parser.error("--scan-dir requires --model and --skill-sha")
        args.model     = args.model_flag
        args.skill_sha = args.skill_sha_flag
        _batch_mode(args)
    else:
        # single mode
        if not all([args.result_file, args.eval_id, args.model, args.skill_sha]):
            parser.error("Single mode requires: result_file eval_id model skill_sha")
        _single_mode(args)


if __name__ == "__main__":
    main()
