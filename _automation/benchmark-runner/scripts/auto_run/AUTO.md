# auto_run

## Run an eval end-to-end

Resolve the model from your agent's runtime context (the canonical API ID — e.g.
`claude-sonnet-4-6`, `claude-opus-4-7`, `gemini-3-pro-preview`) and pass it via
`--model`. Don't hardcode it.

```bash
MODEL="<canonical-model-id>"   # e.g. read from your agent's Runtime Context

# Step 1: prep 
bench_dir=$(_automation/benchmark-runner/scripts/auto_run/prep_ab.sh \
              --model "$MODEL")

# Step 2: run both agents 
_automation/benchmark-runner/scripts/auto_run/run_agents_ab.sh "$bench_dir"

```

Final report: `$bench_dir/benchmark_comment_<skill>_<eval-id>.md`.

The dispatcher dedups on `--model`, so the value must be the canonical API ID,
not a display name. Phase 2 reuses Phase 1's model from `run_meta.json`, so you
don't pass `--model` to `evaluate_ab.sh`.
