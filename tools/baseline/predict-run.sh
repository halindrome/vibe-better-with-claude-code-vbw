#!/usr/bin/env bash
# The predicted-vs-real run (docs/benchmark.md, "Predicted vs real: method and
# prediction"): one run per side of one multi-requirement project, measured
# stage by stage and compared with the prediction committed before the runs.
#
#   predict-run.sh --dry-run [ARM]          print what the run of ARM (plain|vbw2, default both) would do; calls no model
#   predict-run.sh run ARM                  run one side through bench.sh (plain-ui or vbw2): costs model money
#   predict-run.sh stages DIR [--newer FILE] [--split TIME] [--cost FILE]
#                                           tokens and dollars per stage of the session transcripts in DIR (main
#                                           session and subagents), priced with prices.json; --newer keeps the files
#                                           newer than FILE, --split counts what comes after TIME (ISO UTC) as
#                                           followup, --cost reconciles each model with a saved /cost screen
#   predict-run.sh report                   the prediction against the measured runs, stage by stage
#
# The prediction is tools/baseline/predictions/CASE.json; its case, model, follow-up text and limit drive the run.
# A run needs PREDICT_CONFIG_DIR (a fresh Claude Code config directory, logged in, onboarding done, no plugins)
# and PREDICT_SCRATCH (the workspace parent, outside this repository, so no parent directory holds the hidden
# checks or this repository's instructions). The plain side runs first: VBW writes its status line and
# workflows settings into the config directory, and the plain side must start from the untouched one.
# PREDICT_RESULTS (default tools/baseline/results/predicted) holds the records and measures; a contributed run
# uses a folder of its own under it.
#
# Test seams: PREDICT_BENCH (bench.sh), PREDICT_CLAUDE (claude, for --version only), PREDICT_FILE,
# PREDICT_RESULTS, PREDICT_PRICES.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BENCH="${PREDICT_BENCH:-$HERE/bench.sh}"
CLAUDE="${PREDICT_CLAUDE:-claude}"
PREDICTION="${PREDICT_FILE:-$HERE/predictions/non-ui-pipeline.json}"
RESULTS="${PREDICT_RESULTS:-$HERE/results/predicted}"
PRICES="${PREDICT_PRICES:-$HERE/prices.json}"

usage() { sed -n '6,13p' "$0" >&2; exit 2; }
die() { echo "predict-run: $*" >&2; exit 1; }

pred() { jq -r "$1" "$PREDICTION"; }

# Stage of one transcript file: main for the session itself; a subagent's stage
# from its .meta.json (the workflow phase that ran it).
stage_of() {
  local f=$1 meta
  case "$f" in */subagents/*) ;; *) echo main; return 0 ;; esac
  meta="${f%.jsonl}.meta.json"
  [ -f "$meta" ] || { echo subagent; return 0; }
  jq -r 'if (.description // "") == "close run" then "close"
         else (.workflowPhase // "") as $p
           | if $p == "Decide" or $p == "Scope" or $p == "Plan" then "plan"
             elif $p == "Scout" or $p == "Merge" then "map"
             elif $p == "Build" then "build"
             elif $p == "Verify" then "qa"
             elif $p == "Fix" or $p == "Investigate" or $p == "Diagnose" then "fix"
             elif $p == "Recommend" then "recommend"
             elif $p == "Research" or $p == "Answer" then "research"
             elif $p == "" then "subagent"
             else ($p | ascii_downcase) end end' "$meta"
}

# The billed requests of one transcript, one JSON object per line, tagged with
# its stage. In a build transcript, every request from the first `vbw mutate`
# on is the mutation step (the code-breaking check, its strengthening and the
# plan's close).
requests_of() {
  local f=$1 stage
  stage=$(stage_of "$f")
  jq -sc --arg stage "$stage" '
    [ .[] | select(.type == "assistant" and (.message.usage != null))
      | {id: (.message.id // .uuid), model: (.message.model // ""), ts: (.timestamp // ""), u: .message.usage,
         mut: ([.message.content[]? | select(.type == "tool_use") | (.input.command // "")
                | test("(^|[^A-Za-z0-9_-])vbw[^|;&]* mutate ")] | any)} ]
    | unique_by(.id) | sort_by(.ts)
    | (map(.mut) | index(true)) as $m
    | to_entries[]
    | .value + {stage: (if $stage == "build" and $m != null and .key >= $m then "mutation" else $stage end)}
    | del(.mut)' "$f"
}

# cost_by_model FILE: {model: usd} from the per-model lines of a saved /cost
# screen ("claude-sonnet-5-5:  1.2k input, ... ($0.55)"); {} without the file.
cost_by_model() {
  if [ -z "$1" ] || [ ! -f "$1" ]; then echo '{}'; return 0; fi
  jq -Rn '[inputs | capture("(?<m>claude-[a-z0-9-]+)[^:]*:.*[(][$](?<u>[0-9]+([.][0-9]+)?)[)]")? ]
          | map({key: .m, value: (.u | tonumber)}) | from_entries' < "$1"
}

# stages DIR [--newer FILE] [--split TIME] [--cost FILE]
stages() {
  local dir=${1:-} newer="" split="" cost="" f
  [ -d "$dir" ] || die "no transcript directory: ${dir:-(none)}"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --newer) newer=${2:?}; shift 2 ;;
      --split) split=${2:?}; shift 2 ;;
      --cost) cost=${2:?}; shift 2 ;;
      *) usage ;;
    esac
  done
  local files=()
  while IFS= read -r -d '' f; do
    if [ -n "$newer" ] && [ ! "$f" -nt "$newer" ]; then continue; fi
    files[${#files[@]}]="$f"
  done < <(find "$dir" -name '*.jsonl' ! -name 'journal.jsonl' -print0)
  for f in ${files[@]+"${files[@]}"}; do requests_of "$f"; done \
    | jq -s --slurpfile p "$PRICES" --arg split "$split" --slurpfile bymodel <(cost_by_model "$cost") -f "$HERE/stages.jq"
}

# The bench.sh arm of a side: plain runs in the interactive app (plain-ui).
side_of() { if [ "$1" = plain ]; then echo plain-ui; else echo vbw2; fi; }

# The record bench.sh writes for ARM on the prediction's case.
record_of() {
  local arm=$1
  printf '%s/%s-%s-%s-1.json\n' "$RESULTS" "$arm" "$(pred .model)" "$(pred .case)"
}

workspace_of() {
  local arm=$1 side
  side=$(side_of "$arm")
  printf '%s/%s-%s-%s-1\n' "$PREDICT_SCRATCH" "$side" "$(pred .model)" "$(pred .case)"
}

transcripts_of() {
  local ws enc
  ws=$(cd "$1" && pwd -P)
  enc=$(printf '%s' "$ws" | sed 's/[^A-Za-z0-9]/-/g')
  printf '%s/projects/%s\n' "$PREDICT_CONFIG_DIR" "$enc"
}

# preflight ARM: everything a run needs, checked before anything is spent.
preflight() {
  local arm=$1 cfg scratch
  [ -f "$PREDICTION" ] || die "no prediction: $PREDICTION"
  cfg=${PREDICT_CONFIG_DIR:-}
  scratch=${PREDICT_SCRATCH:-}
  [ -n "$cfg" ] && [ -d "$cfg" ] || die "PREDICT_CONFIG_DIR must name a fresh Claude Code config directory"
  [ -f "$cfg/.claude.json" ] || die "$cfg has no .claude.json: log in once and finish onboarding in it"
  jq -e '.hasCompletedOnboarding == true' "$cfg/.claude.json" > /dev/null 2>&1 \
    || die "$cfg: onboarding not finished (its dialogs would take the driver's keys)"
  [ ! -f "$cfg/CLAUDE.md" ] || die "$cfg has a user CLAUDE.md; a fresh config has none"
  if [ -f "$cfg/plugins/installed_plugins.json" ] \
      && jq -e '(.plugins // {}) | length > 0' "$cfg/plugins/installed_plugins.json" > /dev/null 2>&1; then
    die "$cfg has plugins installed; a fresh config has none"
  fi
  [ -n "$scratch" ] || die "PREDICT_SCRATCH must name a directory outside this repository"
  mkdir -p "$scratch"
  scratch=$(cd "$scratch" && pwd -P)
  case "$scratch/" in "$(cd "$ROOT" && pwd -P)/"*) die "PREDICT_SCRATCH is inside this repository: $scratch" ;; esac
  if [ "$arm" = vbw2 ] && [ ! -f "$RESULTS/$(basename "$(record_of plain)" .json).measures.json" ]; then
    die "run the plain side first: VBW changes the config directory's settings"
  fi
  if [ "$arm" = plain ] && [ -f "$cfg/settings.json" ] \
      && jq -e '.statusLine != null' "$cfg/settings.json" > /dev/null 2>&1; then
    die "$cfg/settings.json has a status line: not a fresh config (did a VBW session run in it?)"
  fi
}

# The environment and command of one side, one per line (what --dry-run prints and run executes).
plan_of() {
  local arm=$1 side
  side=$(side_of "$arm")
  printf 'BENCH_RUNS_DIR=%s\n' "$RESULTS"
  printf 'BENCH_SCRATCH=%s\n' "${PREDICT_SCRATCH:-(PREDICT_SCRATCH)}"
  printf 'BENCH_CONFIG_DIR=%s\n' "${PREDICT_CONFIG_DIR:-(PREDICT_CONFIG_DIR)}"
  printf 'VBW_TEST_CLAUDE_CONFIG_DIR=%s\n' "${PREDICT_CONFIG_DIR:-(PREDICT_CONFIG_DIR)}"
  printf 'BENCH_FOLLOWUPS=%s\n' "$(pred .followups.max)"
  printf 'BENCH_FOLLOWUP_TEXT=%s\n' "$(pred .followups.text)"
  printf 'bash %s %s %s %s 1\n' "$BENCH" "$side" "$(pred .model)" "$(pred .case)"
}

dry_run() {
  local arms=${1:-"plain vbw2"} a
  [ -f "$PREDICTION" ] || die "no prediction: $PREDICTION"
  local committed="not in this repository"
  case "$PREDICTION" in
    "$ROOT"/*) committed=$(git -C "$ROOT" log -1 --format=%cI -- "$PREDICTION" 2> /dev/null || true)
      [ -n "$committed" ] || committed="not committed" ;;
  esac
  echo "prediction: $PREDICTION (committed: $committed)"
  echo "case: $(pred .case); model: $(pred .model); profile: $(pred .profile); effort: $(pred .effort)"
  echo "claude: $("$CLAUDE" --version 2> /dev/null || echo 'not found')"
  echo "follow-ups: up to $(pred .followups.max), each typed when the hidden check fails at a finish: $(pred .followups.text)"
  for a in $arms; do
    case "$a" in plain | vbw2) ;; *) usage ;; esac
    echo "--- $a (dry run: nothing is started)"
    plan_of "$a"
    echo "then: the measures (wall time, Claude Code version, stages from the transcripts) into $RESULTS/$(basename "$(record_of "$a")" .json).measures.json"
  done
}

# Did any tool call of the session touch the hidden checks or their solutions?
# They live under tools/ of this repository; VBW's own plugin/ paths are expected.
leaked() {
  local dir=$1 f
  while IFS= read -r -d '' f; do
    if jq -se --arg tools "$ROOT/tools" '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
          | (.input | tostring) | (contains($tools) or contains("tools/baseline") or contains("solution.sh"))] | any' \
        "$f" > /dev/null 2>&1; then
      echo true; return 0
    fi
  done < <(find "$dir" -name '*.jsonl' ! -name 'journal.jsonl' -print0)
  echo false
}

run_arm() {
  local arm=$1 side t0 t1 rec ws dir version split out
  case "$arm" in plain | vbw2) ;; *) usage ;; esac
  preflight "$arm"
  side=$(side_of "$arm")
  version=$("$CLAUDE" --version 2> /dev/null || echo unknown)
  if [ "$arm" = vbw2 ]; then
    local other
    other=$(jq -r '.claude_version' "$RESULTS/$(basename "$(record_of plain)" .json).measures.json")
    [ "$other" = "$version" ] || die "Claude Code is $version; the plain side ran on $other"
  fi
  mkdir -p "$RESULTS"
  t0=$(date +%s)
  BENCH_RUNS_DIR="$RESULTS" BENCH_SCRATCH="$PREDICT_SCRATCH" BENCH_CONFIG_DIR="$PREDICT_CONFIG_DIR" \
    VBW_TEST_CLAUDE_CONFIG_DIR="$PREDICT_CONFIG_DIR" \
    BENCH_FOLLOWUPS="$(pred .followups.max)" BENCH_FOLLOWUP_TEXT="$(pred .followups.text)" \
    bash "$BENCH" "$side" "$(pred .model)" "$(pred .case)" 1
  t1=$(date +%s)
  rec=$(record_of "$arm")
  [ -f "$rec" ] || die "bench.sh wrote no record: $rec"
  ws=$(workspace_of "$arm")
  dir=$(transcripts_of "$ws")
  split=$(jq -r '.first_finish_at // ""' "$rec")
  out="$RESULTS/$(basename "$rec" .json).measures.json"
  { if [ -n "$split" ]; then stages "$dir" --newer "$ws.started" --cost "$ws.cost.txt" --split "$split"
    else stages "$dir" --newer "$ws.started" --cost "$ws.cost.txt"; fi; } \
    | jq --arg v "$version" --argjson wall "$((t1 - t0))" --argjson leak "$(leaked "$dir")" \
        --slurpfile r "$rec" \
        '{arm: $r[0].arm, claude_version: $v, wall_seconds: $wall, leak: $leak,
          main_cache_ttl: (if ([.stages[] | select(.stage == "main") | .cache_write_1h] | add // 0) > 0 then "1h" else "5m" end),
          record: $r[0], stages: .}' > "$out.tmp"
  mv "$out.tmp" "$out"
  echo "predict-run: wrote $out" >&2
}

report() {
  local plain vbw
  plain="$RESULTS/$(basename "$(record_of plain)" .json).measures.json"
  vbw="$RESULTS/$(basename "$(record_of vbw2)" .json).measures.json"
  [ -f "$plain" ] && [ -f "$vbw" ] || die "both sides must have run: $plain, $vbw"
  jq -nr --slurpfile pr "$PREDICTION" --slurpfile p "$plain" --slurpfile v "$vbw" -f "$HERE/predict-report.jq"
}

case "${1:-}" in
  --dry-run) [ $# -le 2 ] || usage; dry_run "${2:-}" ;;
  run) [ $# -eq 2 ] || usage; run_arm "$2" ;;
  stages) shift; stages "$@" ;;
  report) [ $# -eq 1 ] || usage; report ;;
  *) usage ;;
esac
