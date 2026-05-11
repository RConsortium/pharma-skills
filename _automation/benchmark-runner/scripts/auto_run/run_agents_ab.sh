#!/usr/bin/env bash
# Run-agents stage of the A/B benchmark — SKILL.md Steps 2 (run) and 6.
# Invokes claude on each prepped bench dir and records token usage.
#
# Usage:
#   run_agents_ab.sh <bench-dir> [--model M]
#
# Reads:
#   <bench-dir>/run_meta.json   (model defaults to value here)
#   <bench-dir>/agent_A/prompt.txt
#   <bench-dir>/agent_B/prompt.txt
#
# Writes:
#   <bench-dir>/agent_A/run.json, agent_B/run.json, run_meta.json (tokens)

set -euo pipefail

bench_dir=""
model_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model_override="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *)
      [[ -z "$bench_dir" ]] || { echo "unexpected arg: $1" >&2; exit 2; }
      bench_dir="$1"; shift ;;
  esac
done
[[ -n "$bench_dir" && -d "$bench_dir" ]] || { echo "usage: run_agents_ab.sh <bench-dir> [--model M]" >&2; exit 2; }

runners_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(dirname "$runners_dir")"
meta="$bench_dir/run_meta.json"
[[ -f "$meta" ]] || { echo "run_meta.json missing — run prep_ab.sh first" >&2; exit 2; }

eval_id=$(python3 -c "import json; print(json.load(open('$meta'))['eval_id'])")
if [[ -n "$model_override" ]]; then
  model="$model_override"
else
  model=$(python3 -c "import json; print(json.load(open('$meta'))['model'])")
fi

log() { echo "[run] $*"; }
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-64000}"

count_tokens() {
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    u = d.get('usage') or {}
    print(int(u.get('input_tokens', 0)) + int(u.get('cache_creation_input_tokens', 0)) + int(u.get('output_tokens', 0)))
except Exception:
    print(0)
" "$1"
}

log "starting Agent A (with skill) and Agent B (without skill) in parallel"

bash "$runners_dir/run_claude.sh" "$bench_dir/agent_A" "$model" \
  > "$bench_dir/agent_A/runner.log" 2>&1 &
pid_a=$!

bash "$runners_dir/run_claude.sh" "$bench_dir/agent_B" "$model" \
  > "$bench_dir/agent_B/runner.log" 2>&1 &
pid_b=$!

wait "$pid_a" || true
wait "$pid_b" || true

tokens_a=$(count_tokens "$bench_dir/agent_A/run.json")
tokens_b=$(count_tokens "$bench_dir/agent_B/run.json")
log "Agent A tokens: $tokens_a"
log "Agent B tokens: $tokens_b"

python3 "$scripts_dir/record_run_result.py" \
  --eval-id "$eval_id" --model "$model" \
  --status completed --tokens-a "$tokens_a" --tokens-b "$tokens_b" || true

# Persist tokens for the evaluate stage.
python3 - "$meta" "$tokens_a" "$tokens_b" "$model" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
m["tokens_a"] = int(sys.argv[2])
m["tokens_b"] = int(sys.argv[3])
m["model"] = sys.argv[4]
json.dump(m, open(sys.argv[1], "w"), indent=2)
PY



# echo
# echo "==== agents complete: $eval_id ($model) ===="
# echo "  next: evaluate_ab.sh $bench_dir"
