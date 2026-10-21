#!/usr/bin/env bats
# The predicted-vs-real run (docs/benchmark.md, "Predicted vs real"), offline
# parts only (L1): tools/baseline/predict-run.sh (stage pricing of transcripts,
# the per-model /cost reconciliation, the dry run, the run's preflight and
# measures, the report) and the follow-ups of tools/baseline/bench.sh, with stub
# claude, bench and l3. Nothing here calls a model.

load helper

TOOL="$BATS_TEST_DIRNAME/../tools/baseline/predict-run.sh"
BENCH="$BATS_TEST_DIRNAME/../tools/baseline/bench.sh"
SOLUTION="$BATS_TEST_DIRNAME/../tools/baseline/cases/fix-oneshot/solution.sh"
TEXT="The acceptance tests I ran on your result fail. Fix it."

# line ID MODEL TS USAGE [COMMAND]: one assistant transcript line.
line() {
  jq -cn --arg id "$1" --arg m "$2" --arg ts "$3" --argjson u "$4" --arg c "${5:-}" \
    '{type: "assistant", timestamp: $ts, message: {id: $id, model: $m, usage: $u,
      content: (if $c == "" then [] else [{type: "tool_use", input: {command: $c}}] end)}}'
}

# agent DIR NAME PHASE DESCRIPTION: a subagent transcript's meta file.
agent() {
  mkdir -p "$1/s1/subagents/workflows/wf_1"
  jq -cn --arg p "$3" --arg d "$4" '{workflowPhase: $p, description: $d}' > "$1/s1/subagents/workflows/wf_1/$2.meta.json"
}

# transcripts DIR: a session with every stage kind the pricing tells apart.
transcripts() {
  local d=$1 a="$1/s1/subagents/workflows/wf_1"
  mkdir -p "$a"
  # Main session: m1 written twice (one line per content block), 1-hour writes; m2 without the TTL breakdown.
  { line m1 claude-sonnet-5-5 2026-01-01T00:00:01Z \
      '{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_1h_input_tokens":1000,"ephemeral_5m_input_tokens":0},"cache_read_input_tokens":100000,"output_tokens":500}'
    line m1 claude-sonnet-5-5 2026-01-01T00:00:01Z \
      '{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_1h_input_tokens":1000,"ephemeral_5m_input_tokens":0},"cache_read_input_tokens":100000,"output_tokens":500}'
    line m2 claude-sonnet-5-5 2026-01-01T00:00:02Z '{"cache_creation_input_tokens":200,"output_tokens":100}'
  } > "$d/s1.jsonl"
  agent "$d" agent-b Build "dev P1.1"
  { line b1 claude-sonnet-5-5 2026-01-01T01:00:01Z '{"input_tokens":1000}' "vbw show plan P1.1"
    line b2 claude-sonnet-5-5 2026-01-01T01:00:02Z '{"output_tokens":1000}' 'vbw mutate P1.1 R1.1 "print nope" src/a.sh'
    line b3 claude-sonnet-5-5 2026-01-01T01:00:03Z '{"output_tokens":1000}' "vbw plan done P1.1"
  } > "$a/agent-b.jsonl"
  agent "$d" agent-p Plan lead
  line p1 claude-opus-5-5 2026-01-01T00:10:00Z '{"input_tokens":1000,"output_tokens":1000}' > "$a/agent-p.jsonl"
  agent "$d" agent-c Build "close run"
  # h2's prompt is over Haiku's 100,000-token line, so it pays the long-prompt prices.
  { line h1 claude-haiku-5-5 2026-01-01T01:10:00Z '{"input_tokens":1000,"output_tokens":1000}'
    line h2 claude-haiku-5-5 2026-01-01T01:10:01Z '{"cache_read_input_tokens":200000}'
  } > "$a/agent-c.jsonl"
  agent "$d" agent-x Verify "qa P1"
  line x1 claude-mystery-9 2026-01-01T01:20:00Z '{"output_tokens":5}' > "$a/agent-x.jsonl"
  # A workflow journal is not a transcript.
  line j1 claude-sonnet-5-5 2026-01-01T01:30:00Z '{"output_tokens":99999}' > "$a/journal.jsonl"
}

# prediction FILE: a small prediction in the committed file's shape.
prediction() {
  jq -n --arg text "$TEXT" '
    def r($l; $p; $h): {low: $l, point: $p, high: $h};
    def s: {total_usd: r(1; 2; 3), tokens: r(10; 20; 30), wall_minutes: r(1; 2; 3), user_inputs: r(0; 1; 2),
            first_fail_probability: 0.2, followups: r(0; 0; 1), correct_probability: 0.9, usd_per_correct: r(1; 2; 4)};
    {case: "non-ui-pipeline", model: "sonnet-5.5", profile: "balanced", effort: "default",
     followups: {max: 3, text: $text},
     sides: {vbw2: (s + {stages: {main: r(0.5; 1; 1.5), plan: r(0.1; 0.5; 0.9), unattributed: r(-0.1; 0; 0.1)}}),
             plain: (s + {total_usd: r(0.1; 0.2; 0.3), stages: {main: r(0.1; 0.2; 0.3), unattributed: r(-0.1; 0; 0.1)}})},
     ratio: r(5; 10; 15), ratio_per_correct: r(5; 10; 20)}' > "$1"
}

setup() {
  vbw_setup
  STUB="$PROJECT/stub"
  mkdir -p "$STUB/screens"
  export PREDICT_PRICES="$BATS_TEST_DIRNAME/../tools/baseline/prices.json"
}
teardown() { vbw_teardown; }

@test "stages: each request priced once at list price, by stage, mutation split from build, journal skipped" {
  transcripts "$PROJECT/t"
  run bash "$TOOL" stages "$PROJECT/t"
  [ "$status" -eq 0 ]
  # main: 10*2 + 1000*4 (1-hour write) + 100000*0.1 + 500*10, plus 200*2.5 (5-minute write) + 100*10, per million.
  [ "$(printf '%s' "$output" | jq -c '[.stages[] | [.stage, .requests, .usd]]')" = \
    '[["main",2,0.0205],["plan",1,0.024],["build",1,0.002],["mutation",2,0.02],["close",2,0.0106]]' ]
  [ "$(printf '%s' "$output" | jq -c '[.total.usd, .total.requests, .total.cache_write_1h, .total.cache_write_5m]')" = '[0.0771,8,1000,200]' ]
  [ "$(printf '%s' "$output" | jq -c '.unpriced')" = '{"requests":1,"models":["claude-mystery-9"]}' ]
}

@test "stages: --split counts what came after the first finish as followup; --newer keeps this run's files" {
  transcripts "$PROJECT/t"
  run bash "$TOOL" stages "$PROJECT/t" --split 2026-01-01T00:30:00Z
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '[.stages[] | [.stage, .usd]]')" = '[["main",0.0205],["plan",0.024],["followup",0.0326]]' ]
  touch "$PROJECT/started"
  touch -t 209901010000 "$PROJECT/t/s1.jsonl"
  run bash "$TOOL" stages "$PROJECT/t" --newer "$PROJECT/started"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c '[.stages[].stage]')" = '["main"]' ]
}

@test "stages: --cost spreads each model's /cost shortfall over that model's requests" {
  transcripts "$PROJECT/t"
  printf '%s\n' 'Total cost:            $0.12' 'Usage by model:' \
    '   claude-sonnet-5-5:  1.0k input, 2.6k output, 100.0k cache read, 1.2k cache write ($0.0500)' \
    '   claude-opus-5-5:  1.0k input, 1.0k output, 0 cache read, 0 cache write ($0.0500)' \
    '   claude-other-1:  1 input ($0.01)' > "$PROJECT/cost.txt"
  run bash "$TOOL" stages "$PROJECT/t" --cost "$PROJECT/cost.txt"
  [ "$status" -eq 0 ]
  # Sonnet priced 0.04252 over 5 requests: each carries 0.001496 more; Opus's one request carries all of its 0.026.
  [ "$(printf '%s' "$output" | jq -c '[.stages[] | [.stage, .usd, .adjusted_usd]]')" = \
    '[["main",0.0205,0.0235],["plan",0.024,0.05],["build",0.002,0.0035],["mutation",0.02,0.023],["close",0.0106,0.0106]]' ]
  [ "$(printf '%s' "$output" | jq -c '.cost_models_not_in_transcripts')" = '[{"model":"claude-other-1","usd":0.01}]' ]
}

@test "--dry-run prints each side's environment and command and starts nothing" {
  prediction "$PROJECT/p.json"
  printf '#!/usr/bin/env bash\ntouch "%s/bench-called"\n' "$STUB" > "$STUB/bench.sh"
  printf '#!/usr/bin/env bash\necho "9.9.9 (Claude Code)"\n' > "$STUB/claude"
  chmod +x "$STUB/claude"
  PREDICT_FILE="$PROJECT/p.json" PREDICT_BENCH="$STUB/bench.sh" PREDICT_CLAUDE="$STUB/claude" run bash "$TOOL" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude: 9.9.9 (Claude Code)"* ]]
  [[ "$output" == *"follow-ups: up to 3"*"$TEXT"* ]]
  [[ "$output" == *"--- plain (dry run: nothing is started)"* ]]
  [[ "$output" == *"BENCH_FOLLOWUPS=3"* ]]
  [[ "$output" == *"bash $STUB/bench.sh plain-ui sonnet-5.5 non-ui-pipeline 1"* ]]
  [[ "$output" == *"bash $STUB/bench.sh vbw2 sonnet-5.5 non-ui-pipeline 1"* ]]
  [ ! -e "$STUB/bench-called" ]
}

@test "run: refused before anything is spent without a fresh config, with scratch in the repository, or VBW first" {
  prediction "$PROJECT/p.json"
  printf '#!/usr/bin/env bash\ntouch "%s/bench-called"\n' "$STUB" > "$STUB/bench.sh"
  export PREDICT_FILE="$PROJECT/p.json" PREDICT_BENCH="$STUB/bench.sh" PREDICT_RESULTS="$PROJECT/results"
  run bash "$TOOL" run plain
  [ "$status" -eq 1 ]; [[ "$output" == *"PREDICT_CONFIG_DIR must name"* ]]
  mkdir -p "$PROJECT/cfg"; export PREDICT_CONFIG_DIR="$PROJECT/cfg"
  echo '{"hasCompletedOnboarding": false}' > "$PROJECT/cfg/.claude.json"
  run bash "$TOOL" run plain
  [ "$status" -eq 1 ]; [[ "$output" == *"onboarding not finished"* ]]
  echo '{"hasCompletedOnboarding": true}' > "$PROJECT/cfg/.claude.json"
  PREDICT_SCRATCH="$REPO_ROOT/tools" run bash "$TOOL" run plain
  [ "$status" -eq 1 ]; [[ "$output" == *"inside this repository"* ]]
  PREDICT_SCRATCH="$PROJECT/scratch" run bash "$TOOL" run vbw2
  [ "$status" -eq 1 ]; [[ "$output" == *"run the plain side first"* ]]
  echo '{"statusLine": {"type": "command"}}' > "$PROJECT/cfg/settings.json"
  PREDICT_SCRATCH="$PROJECT/scratch" run bash "$TOOL" run plain
  [ "$status" -eq 1 ]; [[ "$output" == *"not a fresh config"* ]]
  [ ! -e "$STUB/bench-called" ]
}

# stub_bench: a bench.sh that records its environment, seeds the workspace, a
# transcript (one tool call naming $STUB_CMD), a /cost screen and a record.
stub_bench() {
  cat > "$STUB/bench.sh" <<'EOF'
#!/usr/bin/env bash
side=$1 model=$2 case_name=$3 n=$4
env | grep -E '^(BENCH_|VBW_TEST_)' | sort > "$STUB_DIR/env.$side"
ws="$BENCH_SCRATCH/$side-$model-$case_name-$n"
mkdir -p "$ws"; touch "$ws.started"; ws=$(cd "$ws" && pwd -P)
enc=$(printf '%s' "$ws" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$BENCH_CONFIG_DIR/projects/$enc"
jq -cn --arg c "$STUB_CMD" '{type: "assistant", timestamp: "2026-01-01T00:00:01Z",
  message: {id: "a", model: "claude-sonnet-5-5", usage: {output_tokens: 1000},
            content: [{type: "tool_use", input: {command: $c}}]}}' > "$BENCH_CONFIG_DIR/projects/$enc/s.jsonl"
touch -t 209901010000 "$BENCH_CONFIG_DIR/projects/$enc/s.jsonl"
printf '%s\n' 'Total cost: $0.02' '   claude-sonnet-5-5:  1 input, 1.0k output ($0.0200)' > "$ws.cost.txt"
arm=${side%-ui}
mkdir -p "$BENCH_RUNS_DIR"
jq -n --arg arm "$arm" '{arm: $arm, pass: true, first_pass: false, first_finish_at: "2026-01-01T00:00:00Z",
  followups: 1, tokens: 1000, cost_usd: 0.02, user_inputs: 0}' > "$BENCH_RUNS_DIR/$arm-$model-$case_name-$n.json"
EOF
}

@test "run: each side's measures (version, wall time, stages reconciled with /cost, leak check), then the report" {
  prediction "$PROJECT/p.json"
  stub_bench
  printf '#!/usr/bin/env bash\necho "${STUB_VERSION:-9.9.9} (Claude Code)"\n' > "$STUB/claude"
  chmod +x "$STUB/claude"
  mkdir -p "$PROJECT/cfg"
  echo '{"hasCompletedOnboarding": true}' > "$PROJECT/cfg/.claude.json"
  export PREDICT_FILE="$PROJECT/p.json" PREDICT_BENCH="$STUB/bench.sh" PREDICT_CLAUDE="$STUB/claude" \
    PREDICT_RESULTS="$PROJECT/results" PREDICT_CONFIG_DIR="$PROJECT/cfg" PREDICT_SCRATCH="$PROJECT/scratch" STUB_DIR="$STUB"
  STUB_CMD="./logstat.sh logs/access.log" run bash "$TOOL" run plain
  [ "$status" -eq 0 ]
  grep -qx 'BENCH_FOLLOWUPS=3' "$STUB/env.plain-ui"
  grep -qx "BENCH_FOLLOWUP_TEXT=$TEXT" "$STUB/env.plain-ui"
  grep -qx "VBW_TEST_CLAUDE_CONFIG_DIR=$PROJECT/cfg" "$STUB/env.plain-ui"
  m="$PROJECT/results/plain-sonnet-5.5-non-ui-pipeline-1.measures.json"
  # The one request came after the first finish: followup, priced at 1000 output tokens.
  [ "$(jq -c '[.arm, .claude_version, .leak, (.wall_seconds | type), .main_cache_ttl, [.stages.stages[] | [.stage, .usd, .adjusted_usd]]]' "$m")" = \
    '["plain","9.9.9 (Claude Code)",false,"number","5m",[["followup",0.01,0.02]]]' ]
  STUB_VERSION=1.0.0 STUB_CMD="cat x" run bash "$TOOL" run vbw2
  [ "$status" -eq 1 ]; [[ "$output" == *"the plain side ran on 9.9.9"* ]]
  STUB_CMD="cat $REPO_ROOT/tools/baseline/projects/non-ui-pipeline/check.sh" run bash "$TOOL" run vbw2
  [ "$status" -eq 0 ]
  [ "$(jq '.leak' "$PROJECT/results/vbw2-sonnet-5.5-non-ui-pipeline-1.measures.json")" = true ]
  run bash "$TOOL" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"| main | \$1 (\$0.5 to \$1.5) | \$0 | no |"* ]]
  [[ "$output" == *"| total cost | \$0.2 (\$0.1 to \$0.3) | \$0.02 | no |"* ]]
  [[ "$output" == *"| hidden check at first finish | fails with probability 0.2 | failed | n/a |"* ]]
  [[ "$output" == *"| cost, VBW 2 over plain | 10 (5 to 15) | 1 | no |"* ]]
  # A measured stage the prediction did not list still gets its row.
  [[ "$output" == *"| followup | not predicted | \$0.02 | n/a |"* ]]
  [[ "$output" == *"leak check: plain false, VBW 2 true"* ]]
}

@test "the committed prediction: every field the report reads, points within ranges and adding up, the doc's totals" {
  p="$REPO_ROOT/tools/baseline/predictions/non-ui-pipeline.json"
  jq -e '
    def r: (.low | type) == "number" and .low <= .point and .point <= .high;
    (.followups.max == 3) and ([.ratio, .ratio_per_correct] | all(r))
    and ([.sides.vbw2, .sides.plain][] | (.stages | length > 0) and ([.stages[]] | all(r))
         and ([.total_usd, .tokens, .wall_minutes, .user_inputs, .followups, .usd_per_correct] | all(r))
         and (([.stages[].point] | add) - .total_usd.point | fabs < 0.005)
         and (.first_fail_probability | type) == "number" and (.correct_probability | type) == "number")' "$p" > /dev/null
  # The follow-up the prediction names is bench.sh's own default.
  [ "$(jq -r '.followups.text' "$p")" = "$TEXT" ]
  grep -qF "BENCH_FOLLOWUP_TEXT:-$TEXT}" "$BENCH"
  for side in vbw2 plain; do
    grep -qF "| **total** | **\$$(jq -r ".sides.$side.total_usd.point" "$p")** |" "$REPO_ROOT/docs/benchmark.md"
  done
}

# stub_l3: an l3 driver that logs every call, prints the next screen on wait
# (the last repeats), writes this run's transcript on start, prints a /cost
# screen once /cost was typed, and applies the solution when the follow-up is
# typed (STUB_FIXES=1).
stub_l3() {
  cat > "$STUB/l3.sh" <<EOF
#!/usr/bin/env bash
cmd=\$1; shift
echo "\$cmd \$*" >> "$STUB/calls"
case "\$cmd" in
  start)
    echo "\$2" > "$STUB/ws"
    enc=\$(printf '%s' "\$2" | sed 's/[^A-Za-z0-9]/-/g')
    mkdir -p "$PROJECT/config/projects/\$enc"
    echo '{"type":"assistant","message":{"id":"a","usage":{"input_tokens":5,"output_tokens":5}}}' > "$PROJECT/config/projects/\$enc/s.jsonl"
    touch -t 209901010000 "$PROJECT/config/projects/\$enc/s.jsonl" ;;
  type)
    [ "\$2" != "/cost" ] || touch "$STUB/cost"
    case "\$2" in *"acceptance tests I ran"*) [ -z "\${STUB_FIXES:-}" ] || (cd "\$(cat "$STUB/ws")" && bash "$SOLUTION") ;; esac ;;
  wait)
    if [ -e "$STUB/cost" ]; then echo "Total cost:            \\\$0.40"; exit 0; fi
    echo "Done." ;;
esac
exit 0
EOF
  printf '#!/usr/bin/env bash\necho ship\n' > "$STUB/next"
  chmod +x "$STUB/l3.sh" "$STUB/next"
  export BENCH_L3="$STUB/l3.sh" BENCH_NEXT="$STUB/next" BENCH_RUNS_DIR="$PROJECT/runs" \
    BENCH_SCRATCH="$PROJECT/scratch" BENCH_CONFIG_DIR="$PROJECT/config"
}

@test "bench follow-ups: a failed hidden check gets the follow-up in the same session, until it passes" {
  stub_l3
  BENCH_FOLLOWUPS=3 STUB_FIXES=1 run bash "$BENCH" plain-ui sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  r="$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json"
  [ "$(jq -c '[.pass, .first_pass, .followups, (.first_finish_at | test("^[0-9-]+T[0-9:]+Z$")), .cost_usd]' "$r")" = '[true,false,1,true,0.40]' ]
  [ "$(grep -c "^type bench-plain-sonnet-5-5-fix-oneshot-1 $TEXT\$" "$STUB/calls")" -eq 1 ]
  # Any question on screen is dismissed before the follow-up is typed.
  grep -B2 "^type bench-plain-sonnet-5-5-fix-oneshot-1 $TEXT" "$STUB/calls" | grep -q '^keys bench-plain-sonnet-5-5-fix-oneshot-1 Escape'
  # The /cost screen is kept beside the workspace for the per-model figures.
  grep -q 'Total cost' "$PROJECT/scratch/plain-ui-sonnet-5.5-fix-oneshot-1.cost.txt"
}

@test "bench follow-ups: at most BENCH_FOLLOWUPS, VBW gets them through /vbw:vibe, none when unset" {
  stub_l3
  BENCH_FOLLOWUPS=2 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.pass, .first_pass, .followups]' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json")" = '[false,false,2]' ]
  [ "$(grep -c "^type bench-sonnet-5-5-fix-oneshot-1 /vbw:vibe $TEXT\$" "$STUB/calls")" -eq 2 ]
  run bash "$BENCH" plain-ui sonnet-5.5 fix-oneshot 2
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.pass, has("followups"), has("first_pass")]' "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-2.json")" = '[false,false,false]' ]
  ! grep -q "acceptance tests I ran" <(grep 'fix-oneshot-2' "$STUB/calls")
  BENCH_FOLLOWUPS=x run bash "$BENCH" plain-ui sonnet-5.5 fix-oneshot 3
  [ "$status" -eq 2 ]
}
