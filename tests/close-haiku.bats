#!/usr/bin/env bats
# R186 (docs/workflows.md, workflow part, L1): the step that closes each run
# (the agent labelled "close run", and the fixing workflow's own "fix done"
# agent when no session is given) runs on Haiku in every profile, whatever
# args.models.lead says, while every other Lead job keeps the Lead's model. The
# closing step is otherwise unchanged: agent type, label, answer format, the
# profile's lead.close effort and the order of its commands. When it stops, the
# exact commands to run by hand are logged; when it answers wrongly, vbw next
# still asks for the missing work, because it reads the record. The runtime is
# stubbed (tests/helpers/run-workflow-all.js): no model runs.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow-all.js"
WF="$PLUGIN_ROOT/workflows"
PROFILES="$PLUGIN_ROOT/lib/profiles.json"
EFFORTS="$PLUGIN_ROOT/lib/efforts.json"
CLOSERS="building verifying fixing planning mapping"
OK='{"ended":true,"recorded":true,"report":"all recorded; run ended","fixdone":"ran","closed":["F1","F2"],"open":[]}'
DONE='{"status":"done","summary":"s","notes":[],"verdict":"pass","checks":[]}'
GENERIC='{"findings":["a"],"map":"m","picks":[],"hypotheses":[],"answer":"a","confidence":"high","root_cause":"r","evidence":"e","rejected":[],"fix":"f","unknowns":[],"status":"fixed","summary":"s","files":[],"commit":"c","regression_test":"t","notes":[]}'
REQS='[{"id":"R1","proof":"auto","text":"x"}]'
TABLE='{"lead":{"plan":"lead.plan","close":"lead.close"},"dev":{"build":"dev.build","fix":"dev.fix"}}'

setup() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# responses CLOSE: every agent answers as a finished one; the closing agent answers CLOSE (JSON or null).
responses() {
  jq -nc --argjson g "$GENERIC" --argjson d "$DONE" --argjson k "$1" \
    '{"*": ($g + $d), "close run": $k, "fix done": $k, "architect (decide)": {decisions: []},
      "architect (scope)": {phases: [{id: "P1", title: "t", reqs: ["R1"], goal: "g", criteria: ["c"]}], notes: []},
      "lead": {applied: true, summary: "s", blockers: [], choices: []}}'
}

# args WF EXTRA: the workflow's own arguments with a session, merged with EXTRA (a JSON object).
args() {
  local base
  case "$1" in
    building) base='{"plans":["P1.1"]}' ;;
    verifying) base='{"phases":["P1"],"tier":"standard"}' ;;
    fixing) base='{"groups":[["F1","F2"]]}' ;;
    planning) base=$(jq -nc --argjson r "$REQS" '{requirements: $r}') ;;
    mapping) base='{}' ;;
  esac
  jq -nc --argjson b "$base" --argjson x "$2" '$b + {session: "s"} + $x'
}

# wf WF EXTRA [CLOSE]: the stubbed run's JSON.
wf() { node "$RUN" "$WF/$1.js" "$(args "$1" "$2")" "$(responses "${3:-$OK}")"; }

# closes_on_haiku WF MODELS: the run's closing calls exist and all ask for haiku.
closes_on_haiku() {
  local out
  out=$(wf "$1" "$(jq -nc --argjson m "$2" '{models: $m}')") || { echo "$1: $out"; return 1; }
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")] | length >= 1 and all(.[]; .opts.model == "haiku")' > /dev/null \
    || { echo "$1 with models $2:"; printf '%s' "$out" | jq -c '[.calls[] | {label: .opts.label, model: .opts.model}]'; return 1; }
}

@test "R186: in all five workflows the close run step asks for haiku in every profile, whatever models.lead says" {
  local p w models
  for p in quality balanced budget; do
    models=$(jq -c --arg p "$p" '.[$p]' "$PROFILES")
    [ "$(printf '%s' "$models" | jq -r '.lead')" != haiku ]
    for w in $CLOSERS; do closes_on_haiku "$w" "$models"; done
  done
}

@test "R186: a model.lead the user set with vbw config never reaches the closing step" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local m w models
  for m in claude-opus-5-5 sonnet fable; do
    "$VBW" config set model.lead "$m" > /dev/null
    models=$("$VBW" config models < /dev/null)
    [ "$(printf '%s' "$models" | jq -r '.lead')" = "$m" ] || { echo "$models"; vbw_teardown; false; }
    for w in $CLOSERS; do closes_on_haiku "$w" "$models" || { vbw_teardown; false; }; done
  done
  vbw_teardown
}

@test "R186: the fixing workflow's own fix done step, used when no session is given, runs on haiku too" {
  local out
  out=$(node "$RUN" "$WF/fixing.js" '{"groups":[["F1"]],"models":{"lead":"opus","dev":"sonnet"}}' "$(responses "$OK")")
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "fix done")] | length == 1 and .[0].opts.model == "haiku"
    and .[0].opts.agentType == "vbw:lead"' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")] | length == 0' || { echo "$out"; false; }
}

@test "R186: every other Lead job keeps the Lead's model: planning's plan step uses models.lead" {
  local m out
  for m in opus sonnet claude-opus-5-5; do
    out=$(wf planning "$(jq -nc --arg m "$m" '{models: {architect: "opus", lead: $m}}')")
    printf '%s' "$out" | jq -e --arg m "$m" '[.calls[] | select(.opts.label == "lead")] | length == 1 and .[0].opts.model == $m
      and .[0].opts.agentType == "vbw:lead"' || { echo "$m: $out"; false; }
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")] | length == 1 and .[0].opts.model == "haiku"' || { echo "$m: $out"; false; }
  done
  # With no Lead model given, the plan step still inherits the session's model, as before.
  out=$(wf planning '{}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "lead")][0].opts | has("model") | not' || { echo "$out"; false; }
}

@test "R186: a test reads each workflow: no closing call takes its model from models.lead" {
  local w lines
  for w in $CLOSERS; do
    lines=$(grep -nE "label: '(close run|fix done)'" "$WF/$w.js") || { echo "$w.js has no closing call"; false; }
    if printf '%s\n' "$lines" | grep -q 'models\.lead'; then
      echo "$w.js: a closing call takes its model from models.lead:"
      printf '%s\n' "$lines"
      false
    fi
  done
}

@test "R186: the closing step is otherwise unchanged: agent type, label, answer format and effort" {
  local w out
  for w in $CLOSERS; do
    out=$(wf "$w" "$(jq -nc --argjson t "$TABLE" '{effort: $t, models: {lead: "opus"}}')")
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")] | length >= 1 and all(.[]; .opts
      | .agentType == "vbw:lead" and .effort == "lead.close"
        and (keys - ["agentType", "label", "schema", "model", "effort"] == [])
        and (.schema.required | index("ended") != null and index("recorded") != null and index("report") != null))' \
      || { echo "$w: $out"; false; }
  done
  out=$(wf fixing "$(jq -nc --argjson t "$TABLE" '{effort: $t}')")
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].opts.schema.required
    | index("fixdone") != null and index("closed") != null and index("open") != null' || { echo "$out"; false; }
  out=$(node "$RUN" "$WF/fixing.js" "$(jq -nc --argjson t "$TABLE" '{groups: [["F1"]], effort: $t}')" "$(responses "$OK")")
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "fix done")][0].opts
    | .agentType == "vbw:lead" and .effort == "lead.close" and .model == "haiku"
      and (.schema.required | index("fixdone") != null and index("closed") != null and index("open") != null and index("report") != null)' \
    || { echo "$out"; false; }
}

@test "R186: on Haiku the closing step gets the profile's own lead.close effort, in every profile" {
  local p w out want
  for p in quality balanced budget; do
    want=$(jq -r --arg p "$p" '.[$p].lead.close' "$EFFORTS")
    [ -n "$want" ] && [ "$want" != null ]
    for w in $CLOSERS; do
      out=$(wf "$w" "$(jq -nc --arg p "$p" --slurpfile e "$EFFORTS" --slurpfile m "$PROFILES" '{effort: $e[0][$p], models: $m[0][$p]}')")
      printf '%s' "$out" | jq -e --arg want "$want" '[.calls[] | select(.opts.label == "close run")] | length >= 1
        and all(.[]; .opts.model == "haiku" and .opts.effort == $want)' || { echo "$p $w: $out"; false; }
    done
  done
}

@test "R186: the closing step runs the same commands in the same order: fix done, then run confirm, then run end" {
  local out
  out=$(wf fixing '{"models":{"lead":"opus"}}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].prompt
    | (index("VBW_SESSION_ID=s vbw fix done F1 F2")) as $f | (index("VBW_SESSION_ID=s vbw run confirm F1 F2")) as $c
    | (index("VBW_SESSION_ID=s vbw run end")) as $e
    | $f != null and $c != null and $e != null and $f < $c and $c < $e' || { echo "$out"; false; }
  local w
  for w in building verifying; do
    out=$(wf "$w" '{"models":{"lead":"opus"}}')
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].prompt
      | (index("vbw run confirm")) as $c | (index("vbw run end")) as $e | $c != null and $e != null and $c < $e
        and (contains("vbw fix done") | not)' || { echo "$w: $out"; false; }
  done
}

@test "R186: when the closing agent stops without answering, every workflow logs the exact commands to run by hand" {
  local out
  out=$(wf building '{"plans":["P1.1","P1.2"],"models":{"lead":"opus"}}' null)
  printf '%s' "$out" | jq -e '(.logs | join("\n")) | contains("VBW_SESSION_ID=s vbw run confirm P1.1 P1.2") and contains("VBW_SESSION_ID=s vbw run end")' || { echo "$out"; false; }
  out=$(wf verifying '{"models":{"lead":"opus"}}' null)
  printf '%s' "$out" | jq -e '(.logs | join("\n")) | contains("VBW_SESSION_ID=s vbw run confirm P1") and contains("VBW_SESSION_ID=s vbw run end")' || { echo "$out"; false; }
  out=$(wf fixing '{"models":{"lead":"opus"}}' null)
  printf '%s' "$out" | jq -e '[.logs[] | select(contains("run by hand"))] | any(.[];
    (index("VBW_SESSION_ID=s vbw fix done F1 F2")) as $f | (index("VBW_SESSION_ID=s vbw run confirm F1 F2")) as $c
    | (index("VBW_SESSION_ID=s vbw run end")) as $e | $f != null and $c != null and $e != null and $f < $c and $c < $e)' || { echo "$out"; false; }
  out=$(wf planning '{"models":{"lead":"opus"}}' null)
  printf '%s' "$out" | jq -e '.logs | any(contains("run by hand: VBW_SESSION_ID=s vbw run end"))' || { echo "$out"; false; }
  out=$(wf mapping '{"models":{"lead":"opus"}}' null)
  printf '%s' "$out" | jq -e '.logs | any(contains("run by hand: VBW_SESSION_ID=s vbw run end"))' || { echo "$out"; false; }
  out=$(node "$RUN" "$WF/fixing.js" '{"groups":[["F1"]],"models":{"lead":"opus"}}' "$(responses null)")
  printf '%s' "$out" | jq -e '.logs | any(contains("run by hand: vbw fix done F1"))' || { echo "$out"; false; }
}

@test "R186: a closing agent that wrongly says everything was recorded changes nothing: vbw next asks for the missing plan again" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# P\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf 'true\n' > tests/c.sh
  printf '%s' '{"phases":[{"id":"P1","title":"t","reqs":["R1"],"goal":"g","criteria":["c"],"tier":"standard"}],
    "plans":[{"id":"P1.1","phase":"P1","title":"a","reqs":["R1"],"files":["a.txt"],"tasks":["x","y","z"]},
             {"id":"P1.2","phase":"P1","title":"b","reqs":["R1"],"files":["b.txt"],"tasks":["x","y","z"]}],
    "checks":[{"id":"C1","req":"R1","run":["sh","tests/c.sh"],"files":["tests/c.sh"]}],
    "rules":[{"req":"R1","text":"r","check":"C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore: plan"
  "$VBW" approve < /dev/null > /dev/null
  VBW_SESSION_ID=s "$VBW" run start build P1.1 P1.2 < /dev/null > /dev/null
  # Only P1.1 was recorded; the closing agent answers that everything was.
  jq '(.plans[] | select(.id == "P1.1") | .status) = "done"' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  local wrong out
  wrong='{"ended":true,"recorded":true,"report":"all recorded; run ended"}'
  out=$(node "$RUN" "$WF/building.js" '{"plans":["P1.1","P1.2"],"session":"s","models":{"lead":"opus"}}' "$(responses "$wrong")")
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].opts.model == "haiku"' || { echo "$out"; vbw_teardown; false; }
  # What the closing agent ran: the run's end.
  VBW_SESSION_ID=s "$VBW" run end < /dev/null > /dev/null
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "build" and .detail.plans == ["P1.2"]' || { echo "$output"; vbw_teardown; false; }
  vbw_teardown
}
