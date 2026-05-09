#!/usr/bin/env bash
# Example agent runner — runs `claude -p` against a prepared bench_dir.
#
# This is NOT part of the benchmark infra. It's an example of how a
# developer might invoke their own agent against the prompt that
# prepare.py laid down. Swap this out for any other agent (GPT, Cursor,
# a local model, a hand-written script) — the only contract with the
# infra is: write the agent's outputs into <bench_dir>/output/.
#
# Usage: run_claude.sh <bench_dir> <model>
#   bench_dir — directory containing prompt.txt + input/ + output/
#   model     — claude model id (e.g. claude-sonnet-4-6)
#
# Writes (into bench_dir):
#   run.json       — full claude -p JSON output (consumed by render_report.py)
#   duration_sec   — wall-clock seconds
#   output/...     — whatever the agent wrote (the actual benchmark artifact)
set -euo pipefail

bench_dir="$1"
model="$2"
ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob"

start=$(date +%s)
(
  cd "$bench_dir"
  claude -p \
    --model "$model" \
    --allowedTools "$ALLOWED_TOOLS" \
    --output-format json \
    < prompt.txt \
    > run.json
) || echo "[run_claude] claude exited non-zero" >&2
end=$(date +%s)

echo $((end - start)) > "$bench_dir/duration_sec"
echo "[run_claude] $bench_dir done in $((end - start))s"
