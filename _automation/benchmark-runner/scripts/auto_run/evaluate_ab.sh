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
src = {
    "output_A": (bench_dir / "agent_A" / "output_A", bench_dir / "agent_A" / "eval.json"),
    "output_B": (bench_dir / "agent_B" / "output_B", bench_dir / "agent_B" / "eval.json"),
}
for cand, arm in bm.items():
    out_src, eval_src = src[arm]
    d = scoring_root / cand
    d.mkdir(parents=True, exist_ok=True)
    shutil.copy(eval_src, d / "eval.json")
    if (d / "output").exists():
        shutil.rmtree(d / "output")
    if out_src.exists():
        shutil.copytree(out_src, d / "output")
    else:
        (d / "output").mkdir()
PY
for cand in candidate_1 candidate_2; do
  python3 "$scripts_dir/evaluate.py" --bench-dir "$scoring/$cand" --scorer-model "$scorer_model" || true
done

unblind_a=$(python3 -c "import json; m=json.loads('''$blinded_map'''); print([k for k,v in m.items() if v=='output_A'][0])")
unblind_b=$(python3 -c "import json; m=json.loads('''$blinded_map'''); print([k for k,v in m.items() if v=='output_B'][0])")
report_a="$scoring/$unblind_a/report.md"
report_b="$scoring/$unblind_b/report.md"

# Step 8 — full report
log "step 8: full report"
full_report="$bench_dir/benchmark_comment_${skill_name}_${eval_id}.md"
{
  cat <<EOF
## Automated Benchmark Results — \`$skill_name\`

| Field | Value |
|---|---|
| **Eval ID** | \`$eval_id\` |
| **Run date** | $run_date |
| **Model** | \`$model\` |
| **Skill version** | \`${skill_sha:0:7}\` |

### Token Usage

| Arm | Tokens |
|---|---|
| With Skill (A) | $tokens_a |
| Without Skill (B) | $tokens_b |

### Arm A — With Skill

EOF
  [[ -f "$report_a" ]] && cat "$report_a" || echo "_(no report — scoring failed)_"
  cat <<EOF

---

### Arm B — Without Skill

EOF
  [[ -f "$report_b" ]] && cat "$report_b" || echo "_(no report — scoring failed)_"
  cat <<EOF

---
<!-- BENCHMARK_COMPLETE: {"eval_id":"$eval_id","model":"$model","skill_sha":"$skill_sha"} -->
*Posted by \`evaluate_ab.sh\` · skill: \`$skill_name\`*
EOF
} > "$full_report"

# Step 9 — full results comment
log "step 9: full results comment"
if (( do_post == 1 )) && [[ -n "$issue_number" ]] && command -v gh >/dev/null 2>&1; then
  gh issue comment "$issue_number" --repo "$repo" --body-file "$full_report"
  log "  posted full report to $repo#$issue_number"
fi

echo
echo "==== evaluate complete: $eval_id ($model) ===="
echo "  Archive:     $zip_path"
[[ "$asset_url" != "null" ]] && echo "  Asset URL:   $asset_url"
echo "  Partial:     $partial_md"
echo "  Full report: $full_report"
