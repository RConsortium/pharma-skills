#!/usr/bin/env bash
# run_agents.sh — Launch Agent A (with skill) and Agent B (without skill) in
# parallel, with rate-limit retry and precise wall-clock timestamp recording.
#
# Usage:
#   bash run_agents.sh <eval_id> <model> <base_dir>
#
# Arguments:
#   eval_id   e.g. github-issue-21
#   model     API model ID e.g. claude-sonnet-4-6
#   base_dir  directory created by the orchestrator, e.g. /tmp/benchmark_github-issue-21
#             Must already contain:
#               agent_A/prompt_A.txt
#               agent_B/prompt_B.txt
#
# Outputs written to base_dir:
#   agent_A/agent_A_run.json   — claude -p JSON result for Agent A
#   agent_B/agent_B_run.json   — claude -p JSON result for Agent B
#   run_timestamps.env         — AGENT_START_MS, AGENT_END_MS, EXIT_A, EXIT_B
#
# Environment:
#   CLAUDE_CODE_MAX_OUTPUT_TOKENS  default 64000
#   BENCHMARK_MAX_RETRIES          default 3
#   BENCHMARK_RETRY_WAIT_SEC       default 300 (5 min)
set -euo pipefail

EVAL_ID=${1:?  "Usage: run_agents.sh <eval_id> <model> <base_dir>"}
MODEL=${2:?}
BASE_DIR=${3:?}

MAX_TOKENS=${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-64000}
MAX_RETRIES=${BENCHMARK_MAX_RETRIES:-3}
RETRY_WAIT=${BENCHMARK_RETRY_WAIT_SEC:-300}
ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob"

# ---------------------------------------------------------------------------
# run_agent <label>
#   label: A or B
#   Runs claude -p from the agent's working directory. Retries on rate-limit.
#   Exits 0 on success, 1 on unrecoverable failure.
# ---------------------------------------------------------------------------
run_agent() {
  local label=$1
  local work_dir="${BASE_DIR}/agent_${label}"
  local prompt_file="${work_dir}/prompt_${label}.txt"
  local output_file="${work_dir}/agent_${label}_run.json"
  local attempt is_error result

  if [ ! -f "${prompt_file}" ]; then
    echo "[agent_${label}] ERROR: prompt file not found: ${prompt_file}" >&2
    return 1
  fi

  for attempt in $(seq 1 "${MAX_RETRIES}"); do
    echo "[agent_${label}] Attempt ${attempt}/${MAX_RETRIES} — $(date -u '+%H:%M:%SZ')"

    CLAUDE_CODE_MAX_OUTPUT_TOKENS="${MAX_TOKENS}" \
      cat "${prompt_file}" \
      | claude -p \
          --model "${MODEL}" \
          --allowedTools "${ALLOWED_TOOLS}" \
          --output-format json \
          2>&1 \
      > "${output_file}" || true   # capture non-zero exit; inspect JSON instead

    # Parse is_error and result from the JSON output
    is_error=$(python3 - "${output_file}" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("is_error", True))
except Exception:
    print(True)
PY
)
    result=$(python3 - "${output_file}" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("result", ""))
except Exception:
    print("")
PY
)

    if [ "${is_error}" = "False" ]; then
      echo "[agent_${label}] Completed successfully."
      return 0
    fi

    if echo "${result}" | grep -qi "hit your limit\|rate.limit\|too many requests"; then
      if [ "${attempt}" -lt "${MAX_RETRIES}" ]; then
        echo "[agent_${label}] Rate limited. Waiting ${RETRY_WAIT}s before retry..."
        sleep "${RETRY_WAIT}"
      else
        echo "[agent_${label}] Rate limited after ${MAX_RETRIES} attempts — giving up." >&2
        return 1
      fi
    else
      # Non-rate-limit error: log and abort immediately
      echo "[agent_${label}] Unexpected error (attempt ${attempt}): ${result:0:300}" >&2
      return 1
    fi
  done
}

# ---------------------------------------------------------------------------
# Main: launch both agents in parallel, record timestamps, save env file
# ---------------------------------------------------------------------------
AGENT_START_MS=$(python3 -c "import time; print(int(time.time() * 1000))")
echo "[run_agents] Launching Agent A and Agent B in parallel..."
echo "[run_agents] eval_id=${EVAL_ID}  model=${MODEL}  start=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

run_agent A &
PID_A=$!
run_agent B &
PID_B=$!

EXIT_A=0; EXIT_B=0
wait "${PID_A}" || EXIT_A=$?
wait "${PID_B}" || EXIT_B=$?

AGENT_END_MS=$(python3 -c "import time; print(int(time.time() * 1000))")
WALL_SEC=$(( (AGENT_END_MS - AGENT_START_MS) / 1000 ))

echo "[run_agents] Done. A=${EXIT_A} B=${EXIT_B}  wall=${WALL_SEC}s  end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Write timestamps for record_run_result.py
cat > "${BASE_DIR}/run_timestamps.env" <<EOF
AGENT_START_MS=${AGENT_START_MS}
AGENT_END_MS=${AGENT_END_MS}
EXIT_A=${EXIT_A}
EXIT_B=${EXIT_B}
WALL_SEC=${WALL_SEC}
EOF

# Extract token counts and call record_run_result.py
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENS_A=$(python3 - "${BASE_DIR}/agent_A/agent_A_run.json" <<'PY'
import json, sys
try:
    u = json.load(open(sys.argv[1])).get("usage", {})
    print(u.get("input_tokens", 0) + u.get("output_tokens", 0))
except Exception:
    print(0)
PY
)
TOKENS_B=$(python3 - "${BASE_DIR}/agent_B/agent_B_run.json" <<'PY'
import json, sys
try:
    u = json.load(open(sys.argv[1])).get("usage", {})
    print(u.get("input_tokens", 0) + u.get("output_tokens", 0))
except Exception:
    print(0)
PY
)

python3 "${SCRIPT_DIR}/record_run_result.py" \
  --eval-id "${EVAL_ID}" \
  --model "${MODEL}" \
  --status completed \
  --tokens-a "${TOKENS_A}" \
  --tokens-b "${TOKENS_B}" \
  --start-ms "${AGENT_START_MS}" \
  --end-ms "${AGENT_END_MS}"

echo "[run_agents] Recorded: tokens_A=${TOKENS_A} tokens_B=${TOKENS_B} duration=${WALL_SEC}s"

# Exit non-zero if either agent failed
if [ "${EXIT_A}" -ne 0 ] || [ "${EXIT_B}" -ne 0 ]; then
  echo "[run_agents] WARNING: one or both agents exited with error." >&2
  exit 1
fi
