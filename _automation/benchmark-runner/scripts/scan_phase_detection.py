#!/usr/bin/env python3
"""
Parses a saved MCP issue_read result file and checks BENCHMARK_PARTIAL/COMPLETE state.

Usage:
    python3 scan_phase_detection.py <result_file> <eval_id> <model> <skill_sha>

Outputs one of:
    COMPLETE    - has a BENCHMARK_COMPLETE for this model+sha
    PARTIAL     - has unmatched BENCHMARK_PARTIAL(s) but no later COMPLETE
    UNDONE      - no benchmark markers at all
    UNKNOWN     - could not parse file
"""
import json, re, sys
from pathlib import Path

def scan(path: str, eval_id: str, model: str, skill_sha: str) -> str:
    raw = Path(path).read_text(encoding="utf-8")
    # The MCP result can be plain JSON or a JSON object wrapping a 'text' field.
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        # Try extracting from a text field
        m = re.search(r'"text"\s*:\s*"(.*?)"(?=\s*[,}])', raw, re.DOTALL)
        if not m:
            return "UNKNOWN"
        try:
            data = json.loads(m.group(1).replace('\\"', '"').replace('\\n', '\n'))
        except Exception:
            return "UNKNOWN"

    # data can be a list of comment objects or a dict with a list inside
    if isinstance(data, list):
        comments = data
    elif isinstance(data, dict):
        # Try common wrappers
        for key in ("comments", "data", "items", "nodes"):
            if key in data and isinstance(data[key], list):
                comments = data[key]
                break
        else:
            comments = [data]
    else:
        return "UNKNOWN"

    partial_re  = re.compile(r'BENCHMARK_PARTIAL:\s*({.*?})\s*-->', re.DOTALL)
    complete_re = re.compile(r'BENCHMARK_COMPLETE:\s*({.*?})\s*-->', re.DOTALL)

    # Build chronological list of events
    events = []
    for c in comments:
        body = c.get("body", "")
        created = c.get("created_at", "")
        cid = c.get("id", "")
        for m in partial_re.finditer(body):
            try:
                state = json.loads(m.group(1))
            except Exception:
                continue
            if (state.get("eval_id") == eval_id
                    and state.get("model") == model
                    and state.get("skill_sha") == skill_sha):
                events.append(("PARTIAL", created, cid))
        for m in complete_re.finditer(body):
            try:
                state = json.loads(m.group(1))
            except Exception:
                continue
            if (state.get("eval_id") == eval_id
                    and state.get("model") == model
                    and state.get("skill_sha") == skill_sha):
                events.append(("COMPLETE", created, cid))

    if not events:
        return "UNDONE"

    # Sort by created_at (ISO strings sort lexically)
    events.sort(key=lambda x: x[1])

    # If the last event is COMPLETE → done
    if events[-1][0] == "COMPLETE":
        return "COMPLETE"

    # If the last event is PARTIAL (no later COMPLETE) → Phase 2 needed
    return "PARTIAL"


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: {} <result_file> <eval_id> <model> <skill_sha>".format(sys.argv[0]))
        sys.exit(1)
    result = scan(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    print(result)
