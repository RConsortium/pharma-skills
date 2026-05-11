#!/usr/bin/env bash
# Evaluate stage of the A/B benchmark — SKILL.md Steps 3, 4, 7, 8, 9.
# Archives Agent A output, blinded-scores both arms, formats the full
# report. GitHub upload/posting are opt-in.
#
# Usage:
#   evaluate_ab.sh <bench-dir> [--scorer-model M] [--upload] [--post]
#                              [--repo OWNER/REPO]
#
# Reads:  <bench-dir>/{run_meta.json, agent_A/, agent_B/}
# Writes: <bench-dir>/{benchmark_agent_a_*.zip, partial_comment.md,
#                       scoring/, benchmark_comment_*.md}

set -euo pipefail

bench_dir=""
scorer_model=""
do_upload=0
do_post=0
repo="${PHARMA_SKILLS_GITHUB_REPO:-RConsortium/pharma-skills}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scorer-model) scorer_model="$2"; shift 2 ;;
    --upload)       do_upload=1; shift ;;
    --post)         do_post=1; shift ;;
    --repo)         repo="$2"; shift 2 ;;
    -h|--help)      sed -n '2,16p' "$0"; exit 0 ;;
    *)
      [[ -z "$bench_dir" ]] || { echo "unexpected arg: $1" >&2; exit 2; }
      bench_dir="$1"; shift ;;
  esac
done
[[ -n "$bench_dir" && -d "$bench_dir" ]] || { echo "usage: evaluate_ab.sh <bench-dir> [flags]" >&2; exit 2; }

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
meta="$bench_dir/run_meta.json"
[[ -f "$meta" ]] || { echo "run_meta.json missing — run prep_ab.sh + run_agents_ab.sh first" >&2; exit 2; }

eval_id=$(python3 -c "import json; print(json.load(open('$meta'))['eval_id'])")
model=$(python3 -c "import json; print(json.load(open('$meta'))['model'])")
skill_name=$(python3 -c "import json; print(json.load(open('$meta'))['skill_name'])")
skill_sha=$(python3 -c "import json; print(json.load(open('$meta'))['skill_sha'])")
blinded_map=$(python3 -c "import json; print(json.dumps(json.load(open('$meta'))['blinded_map']))")
tokens_a=$(python3 -c "import json; print(json.load(open('$meta')).get('tokens_a', 0))")
tokens_b=$(python3 -c "import json; print(json.load(open('$meta')).get('tokens_b', 0))")
[[ -z "$scorer_model" ]] && scorer_model="$model"

log() { echo "[eval] $*"; }

# Materialize eval_case.json (with assertions) now that the agents have
# finished. prep_ab.sh stashed it OUTSIDE bench_dir so the agent — whose
# cwd is bench_dir/agent_X — couldn't reach it via `..`. Move the stash
# in, then fan out to each agent dir as eval.json so evaluate_ab.sh
# finds it.
bench_root="$(dirname "$bench_dir")"
stash="$bench_root/.benchmark_${eval_id}_eval_case.json"
eval_case="$bench_dir/eval_case.json"
if [[ -f "$stash" ]]; then
  mv "$stash" "$eval_case"
elif [[ ! -f "$eval_case" ]]; then
  log "WARNING: stash $stash missing — evaluate_ab.sh will fail to find eval_case.json"
fi

# Step 3 — archive Agent A output
log "step 3: archive Agent A output"
zip_path="$bench_dir/benchmark_agent_a_${eval_id}.zip"
( cd "$bench_dir" && zip -rq "$(basename "$zip_path")" \
    "agent_A/output_A/" "agent_A/run.json" 2>/dev/null \
    || zip -rq "$(basename "$zip_path")" "agent_A/run.json" )
asset_url="null"
if (( do_upload == 1 )); then
  if command -v gh >/dev/null 2>&1; then
    gh release view benchmark-results --repo "$repo" >/dev/null 2>&1 \
      || gh release create benchmark-results --repo "$repo" --prerelease \
           --title "Automated Benchmark Results" --notes "Rolling release."
    gh release upload benchmark-results "$zip_path" --repo "$repo" --clobber
    asset_url="https://github.com/$repo/releases/download/benchmark-results/$(basename "$zip_path")"
    log "  uploaded: $asset_url"
  else
    log "  --upload requested but gh not found; asset_url=null"
  fi
fi

# Step 4 — partial comment
log "step 4: partial comment"
issue_number=$(echo "$eval_id" | grep -oE '[0-9]+$' || true)
run_date=$(date -u +"%Y-%m-%dT%H:%MZ")
state=$(python3 -c "
import json
print(json.dumps({
    'eval_id': '$eval_id', 'model': '$model', 'skill_sha': '$skill_sha',
    'issue_number': int('${issue_number:-0}') or None,
    'blinded_map': json.loads('''$blinded_map'''),
    'agent_a_asset_url': None if '$asset_url' == 'null' else '$asset_url',
    'run_date': '$run_date', 'tokens_a': int('$tokens_a'),
}))
")
partial_md="$bench_dir/partial_comment.md"
cat > "$partial_md" <<EOF
## Automated Benchmark Results — \`$skill_name\` 🟡 In Progress

| Field | Value |
|---|---|
| **Eval ID** | \`$eval_id\` |
| **Run date** | $run_date |
| **Model** | \`$model\` |
| **Skill version** | \`${skill_sha:0:7}\` |
| **Phase** | 1 of 2 complete — Agent A finished |

<!-- BENCHMARK_PARTIAL: $state -->
EOF
if (( do_post == 1 )) && [[ -n "$issue_number" ]] && command -v gh >/dev/null 2>&1; then
  gh issue comment "$issue_number" --repo "$repo" --body-file "$partial_md"
  log "  posted partial comment to $repo#$issue_number"
fi

# Step 7 — blinded scoring
log "step 7: blinded scoring"
scoring="$bench_dir/scoring"
mkdir -p "$scoring"
python3 - "$blinded_map" "$bench_dir" "$scoring" <<'PY'
import json, shutil, sys
from pathlib import Path
bm = json.loads(sys.argv[1])
bench_dir = Path(sys.argv[2])
scoring_root = Path(sys.argv[3])
# Agents never see assertions: eval.json is not in agent_A/ or agent_B/.
# run_agents_ab.sh materializes bench_dir/eval_case.json from the stash
# after the run. score.py now scores both candidates in one call from
# the parent scoring dir, so stage eval.json once at scoring/eval.json
# and mirror each arm's output + run metadata into a blinded
# candidate_X/ subdir.
shutil.copy(bench_dir / "eval_case.json", scoring_root / "eval.json")
arm_dir = {"output_A": bench_dir / "agent_A", "output_B": bench_dir / "agent_B"}
def has_files(p):
    return p.exists() and any(p.iterdir())
for cand, arm in bm.items():
    a = arm_dir[arm]
    d = scoring_root / cand
    d.mkdir(parents=True, exist_ok=True)
    for fname in ("run.json", "duration_sec"):
        if (a / fname).exists():
            shutil.copy(a / fname, d / fname)
    if (d / "output").exists():
        shutil.rmtree(d / "output")
    # Agents sometimes write to agent_X/output/ (per prompt) and
    # sometimes to agent_X/output_A or agent_X/output_B; pick whichever
    # actually has content.
    src = next((p for p in (a / "output", a / arm) if has_files(p)), None)
    if src is not None:
        shutil.copytree(src, d / "output")
    else:
        (d / "output").mkdir()
PY
python3 "$scripts_dir/auto_run/evaluate.py" --bench-dir "$scoring" --scorer-model "$scorer_model" || true

# Steps 8 + 9 — compose full report (SKILL.md side-by-side format) and
# optionally post to the linked GitHub issue.
if (( do_post == 1 )); then
  log "steps 8+9: compose full report and post to $repo"
else
  log "steps 8+9: compose full report (skipping post — pass --post to enable)"
fi
post_args=(--bench-dir "$bench_dir" --repo "$repo")
[[ "$asset_url" != "null" ]] && post_args+=(--asset-url "$asset_url")
(( do_post == 1 )) && post_args+=(--post)
python3 "$scripts_dir/auto_run/post_results.py" "${post_args[@]}"

full_report="$bench_dir/benchmark_comment_${skill_name}_${eval_id}.md"

echo
echo "==== evaluate complete: $eval_id ($model) ===="
echo "  Archive:     $zip_path"
[[ "$asset_url" != "null" ]] && echo "  Asset URL:   $asset_url"
echo "  Partial:     $partial_md"
echo "  Full report: $full_report"
