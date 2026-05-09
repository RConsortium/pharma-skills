#!/usr/bin/env bash
# Prep stage of the A/B benchmark — SKILL.md Steps 0, 1, and the prep
# portion of Steps 2/6. Stages two bench dirs ready for the agent runner.
#
# Usage:
#   prep_ab.sh <eval-id> [--model M] [--runner-id R]
#                        [--bench-root DIR] [--skip-preflight]
#
# Output:
#   <bench-root>/benchmark_<eval-id>/
#     ├── eval_case.json     full dispatcher payload
#     ├── agent_A/           bench dir + prompt = _skill_content + _prompt_a
#     │   ├── eval.json, input/, output/, prompt.txt
#     │   └── <bundled resources from skill dir>
#     └── agent_B/           bench dir + prompt = _prompt_b (no skill)
#
# After running this, invoke run_agents_ab.sh on the bench dir.

set -euo pipefail

eval_id=""
model="claude-sonnet-4-6"
runner_id=""
bench_root="/tmp"
skip_preflight=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)          model="$2"; shift 2 ;;
    --runner-id)      runner_id="$2"; shift 2 ;;
    --bench-root)     bench_root="$2"; shift 2 ;;
    --skip-preflight) skip_preflight=1; shift ;;
    -h|--help)        sed -n '2,18p' "$0"; exit 0 ;;
    *)
      [[ -z "$eval_id" ]] || { echo "unexpected arg: $1" >&2; exit 2; }
      eval_id="$1"; shift ;;
  esac
done
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$bench_root"

log() { echo "[prep] $*" >&2; }

# Step 0 — R env preflight
if (( skip_preflight == 0 )); then
  log "step 0: R env preflight"
  bash "$scripts_dir/setup_r_env.sh"
fi

# Step 1 — dispatch. If --eval-id was given, pin it; otherwise let
# get_next_eval.py pick the next pending eval for this model.
log "step 1: dispatch (model=$model${eval_id:+, eval=$eval_id})"
dispatch_args=(--model "$model")
[[ -n "$eval_id" ]] && dispatch_args+=(--priority-issue "$eval_id")
[[ -n "$runner_id" ]] && dispatch_args+=(--runner-id "$runner_id")
dispatch_out=$(python3 "$scripts_dir/get_next_eval.py" "${dispatch_args[@]}")
if [[ "$dispatch_out" == STATUS:\ UP_TO_DATE* ]]; then
  log "no pending evals for $model — nothing to do"
  exit 0
fi

# Resolve eval_id from the dispatcher payload (canonical source).
eval_id=$(printf '%s' "$dispatch_out" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
bench_dir="$bench_root/benchmark_${eval_id}"
mkdir -p "$bench_dir"
eval_json="$bench_dir/eval_case.json"
printf '%s' "$dispatch_out" > "$eval_json"
log "  selected: $eval_id"

# Persist run metadata for downstream stages.
python3 - "$eval_json" "$bench_dir/run_meta.json" "$model" <<'PY'
import json, sys
case = json.load(open(sys.argv[1]))
meta = {
    "eval_id": case["id"],
    "model": sys.argv[3],
    "skill_name": case["_skill_name"],
    "skill_sha": case["_skill_sha"],
    "blinded_map": case["_blinded_scoring_map"],
}
json.dump(meta, open(sys.argv[2], "w"), indent=2)
PY

# Step 2 prep — Agent A bench dir (with skill)
log "step 2 (prep): Agent A bench dir"
agent_a="$bench_dir/agent_A"
python3 "$scripts_dir/auto_run/prepare.py" --bench-dir "$agent_a" --mode bench --eval-id "$eval_id"

log "  staging _bundled_resources"
python3 - "$eval_json" "$agent_a" <<'PY'
import json, sys
from pathlib import Path
case = json.load(open(sys.argv[1]))
agent_dir = Path(sys.argv[2])
for rel, content in (case.get("_bundled_resources") or {}).items():
    if rel == "SKILL.md":
        continue
    dest = agent_dir / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding="utf-8")
PY

python3 - "$eval_json" "$agent_a/prompt.txt" <<'PY'
import json, sys
case = json.load(open(sys.argv[1]))
open(sys.argv[2], "w", encoding="utf-8").write(case["_skill_content"] + "\n\n" + case["_prompt_a"])
PY

# Step 6 prep — Agent B bench dir (without skill)
log "step 6 (prep): Agent B bench dir"
agent_b="$bench_dir/agent_B"
python3 "$scripts_dir/auto_run/prepare.py" --bench-dir "$agent_b" --mode bench --eval-id "$eval_id"
python3 - "$eval_json" "$agent_b/prompt.txt" <<'PY'
import json, sys
case = json.load(open(sys.argv[1]))
open(sys.argv[2], "w", encoding="utf-8").write(case["_prompt_b"])
PY

{
  echo
  echo "==== prep complete: $eval_id ===="
  echo "  next: run_agents_ab.sh $bench_dir"
} >&2

# Final stdout line is the bench_dir path — captured by callers.
echo "$bench_dir"
