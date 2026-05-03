import json
import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNS_DIR = REPO_ROOT / "_automation" / "benchmark-runner" / "runs"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--eval-id", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--tokens-a", type=int, help="Tokens for Agent A")
    parser.add_argument("--tokens-b", type=int, help="Tokens for Agent B")
    parser.add_argument(
        "--start-ms",
        type=int,
        help=(
            "Agent launch wall-clock time in milliseconds since epoch. "
            "When provided, overrides the start_timestamp already in runs.json "
            "so duration reflects actual agent runtime, not eval-dispatch time."
        ),
    )
    parser.add_argument(
        "--end-ms",
        type=int,
        help=(
            "Agent completion wall-clock time in milliseconds since epoch. "
            "When provided, used instead of datetime.now() for end_timestamp."
        ),
    )
    args = parser.parse_args()

    manifest_path = RUNS_DIR / "runs.json"
    if not manifest_path.exists():
        print("Error: Manifest not found", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path, "r") as f:
        records = json.load(f)

    # Find the most recent "dispatched" record for this eval/model
    found = False
    for record in reversed(records):
        if (
            record.get("eval_id") == args.eval_id
            and record.get("model") == args.model
            and record.get("status") == "dispatched"
        ):
            record["status"] = args.status

            # End timestamp: prefer explicit --end-ms, fall back to now()
            if args.end_ms is not None:
                end_ts = args.end_ms / 1000.0
            else:
                end_ts = datetime.now(timezone.utc).timestamp()
            record["end_timestamp"] = end_ts

            # Start timestamp: prefer explicit --start-ms, fall back to
            # whatever get_next_eval.py stored (which is the dispatch time,
            # not the agent-launch time — can inflate duration by minutes).
            if args.start_ms is not None:
                record["start_timestamp"] = args.start_ms / 1000.0

            start = record.get("start_timestamp")
            if start:
                record["duration_sec"] = end_ts - start
                record["duration_min"] = round(record["duration_sec"] / 60, 1)

            if args.tokens_a is not None:
                record["tokens_a"] = args.tokens_a
            if args.tokens_b is not None:
                record["tokens_b"] = args.tokens_b

            found = True
            break

    if not found:
        print(
            f"Warning: No dispatched record found for {args.eval_id} and {args.model}",
            file=sys.stderr,
        )

    with open(manifest_path, "w") as f:
        json.dump(records, f, indent=2)

if __name__ == "__main__":
    main()
