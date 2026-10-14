#!/usr/bin/env bats
# R188 (docs/workflows.md, workflow part, L1): the step that closes each run
# (the agent labelled "close run", and the fixing workflow's own "fix done"
# agent when no session is given) runs on the Lead's model again: the model the
# workflow is given as args.models.lead, in all five workflows that close a run
# and in every profile, as before D369 (superseded by the owner's choice of
# 2026-10-14). With no Lead model given, the closing agents are sent no model
# and inherit the session's; they never fall back to Haiku. Everything else
# about the closing step stays as it was: agent type, labels, answer schemas,
# the profile's lead.close effort, the order of its commands and its error
# paths. No other agent's model changes. The runtime is stubbed
# (tests/helpers/run-workflow-all.js): no model runs.

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

setup() { command -v node > /dev/null 2>&1 || { echo "node is needed to run the workflows"; return 1; }; }

# responses CLOSE: every agent answers as a finished one; the closing agents answer CLOSE (JSON or null).
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

# closes_on WF MODELS: the run's closing calls exist and each is sent MODELS.lead as its model.
closes_on() {
  local out
  out=$(wf "$1" "$(jq -nc --argjson m "$2" '{models: $m}')") || { echo "$1: $out"; return 1; }
  printf '%s' "$out" | jq -e --argjson m "$2" '[.calls[] | select(.opts.label == "close run")]
    | length >= 1 and all(.[]; .opts.model == $m.lead)' > /dev/null \
    || { echo "$1 with models $2:"; printf '%s' "$out" | jq -c '[.calls[] | {label: .opts.label, model: .opts.model}]'; return 1; }
}

@test "R188: no workflow keeps a CLOSE_MODEL constant or a hard-coded haiku for its closing step" {
  run grep -rn 'CLOSE_MODEL' "$WF"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  local w lines
  for w in $CLOSERS; do
    lines=$(grep -nE "label: '(close run|fix done)'" "$WF/$w.js") || { echo "$w.js has no closing call"; false; }
    if printf '%s\n' "$lines" | grep -qi 'haiku'; then
      echo "$w.js: a closing call names haiku:"
      printf '%s\n' "$lines"
      false
    fi
  done
}

@test "R188: in all five workflows the close run agent is sent args.models.lead: opus, sonnet, a full model id, and haiku when the user chose it" {
  local m w
  for m in opus sonnet claude-opus-5-5 haiku; do
    for w in $CLOSERS; do closes_on "$w" "$(jq -nc --arg m "$m" '{architect: "opus", lead: $m, dev: "sonnet", qa: "sonnet", scout: "sonnet", debugger: "sonnet", docs: "sonnet"}')"; done
  done
}

@test "R188: in every profile the close run agent is sent that profile's Lead model" {
  local p w models
  for p in quality balanced budget; do
    models=$(jq -c --arg p "$p" '.[$p]' "$PROFILES")
    for w in $CLOSERS; do closes_on "$w" "$models"; done
  done
}

@test "R188: a model.lead the user set with vbw config reaches the closing step" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local m w models
  for m in claude-opus-5-5 sonnet haiku; do
    "$VBW" config set model.lead "$m" > /dev/null
    models=$("$VBW" config models < /dev/null)
    [ "$(printf '%s' "$models" | jq -r '.lead')" = "$m" ] || { echo "$models"; vbw_teardown; false; }
    for w in $CLOSERS; do closes_on "$w" "$models" || { vbw_teardown; false; }; done
  done
  vbw_teardown
}

@test "R188: without a session, vbw:fixing's own fix done agent is sent args.models.lead, like the close run agent" {
  local m out
  for m in opus sonnet claude-opus-5-5 haiku; do
    out=$(node "$RUN" "$WF/fixing.js" "$(jq -nc --arg m "$m" '{groups: [["F1"]], models: {lead: $m, dev: "sonnet"}}')" "$(responses "$OK")")
    printf '%s' "$out" | jq -e --arg m "$m" '[.calls[] | select(.opts.label == "fix done")] | length == 1
      and .[0].opts.model == $m and .[0].opts.agentType == "vbw:lead"' || { echo "$m: $out"; false; }
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")] | length == 0' || { echo "$out"; false; }
    out=$(wf fixing "$(jq -nc --arg m "$m" '{models: {lead: $m, dev: "sonnet"}}')")
    printf '%s' "$out" | jq -e --arg m "$m" '[.calls[] | select(.opts.label == "close run")] | length == 1 and .[0].opts.model == $m' \
      || { echo "$m: $out"; false; }
  done
}

@test "R188: with no Lead model, or an empty one, the closing agents are sent no model at all, never haiku" {
  local w out x
  for x in '{}' '{"models":{}}' '{"models":{"lead":""}}' '{"models":{"dev":"sonnet"}}'; do
    for w in $CLOSERS; do
      out=$(wf "$w" "$x")
      printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")] | length >= 1 and all(.[]; .opts | has("model") | not)' \
        || { echo "$w with $x: $out"; false; }
    done
    out=$(node "$RUN" "$WF/fixing.js" "$(jq -nc --argjson x "$x" '{groups: [["F1"]]} + $x')" "$(responses "$OK")")
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "fix done")] | length == 1 and all(.[]; .opts | has("model") | not)' \
      || { echo "fixing without a session, $x: $out"; false; }
  done
}

@test "R188: the closing step is otherwise unchanged: agent type, labels, answer schemas and the profile's lead.close effort" {
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
  out=$(node "$RUN" "$WF/fixing.js" "$(jq -nc --argjson t "$TABLE" '{groups: [["F1"]], effort: $t, models: {lead: "opus"}}')" "$(responses "$OK")")
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "fix done")][0].opts
    | .agentType == "vbw:lead" and .effort == "lead.close" and .model == "opus"
      and (keys - ["agentType", "label", "schema", "model", "effort"] == [])
      and (.schema.required | index("fixdone") != null and index("closed") != null and index("open") != null and index("report") != null)' \
    || { echo "$out"; false; }
}

@test "R188: in every profile the closing step gets the profile's own lead.close effort beside the Lead's model" {
  local p w out want
  for p in quality balanced budget; do
    want=$(jq -r --arg p "$p" '.[$p].lead.close' "$EFFORTS")
    [ -n "$want" ] && [ "$want" != null ]
    for w in $CLOSERS; do
      out=$(wf "$w" "$(jq -nc --arg p "$p" --slurpfile e "$EFFORTS" --slurpfile m "$PROFILES" '{effort: $e[0][$p], models: $m[0][$p]}')")
      printf '%s' "$out" | jq -e --arg want "$want" --slurpfile m "$PROFILES" --arg p "$p" '[.calls[] | select(.opts.label == "close run")]
        | length >= 1 and all(.[]; .opts.model == $m[0][$p].lead and .opts.effort == $want)' || { echo "$p $w: $out"; false; }
    done
  done
}

@test "R188: the closing step runs the same commands in the same order: fix done, then run confirm, then run end" {
  local out w
  out=$(wf fixing '{"models":{"lead":"opus"}}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].prompt
    | (index("VBW_SESSION_ID=s vbw fix done F1 F2")) as $f | (index("VBW_SESSION_ID=s vbw run confirm F1 F2")) as $c
    | (index("VBW_SESSION_ID=s vbw run end")) as $e
    | $f != null and $c != null and $e != null and $f < $c and $c < $e' || { echo "$out"; false; }
  for w in building verifying; do
    out=$(wf "$w" '{"models":{"lead":"opus"}}')
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].prompt
      | (index("vbw run confirm")) as $c | (index("vbw run end")) as $e | $c != null and $e != null and $c < $e
        and (contains("vbw fix done") | not)' || { echo "$w: $out"; false; }
  done
}

@test "R188: error: when the closing agent stops without answering, every workflow logs the exact commands to run by hand" {
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

@test "R188: error: a closing agent that answers recorded=false or ended=false has its report logged" {
  local w out bad
  for bad in '{"ended":true,"recorded":false,"report":"P1.1 not recorded","fixdone":"ran","closed":["F1","F2"],"open":[]}' \
    '{"ended":false,"recorded":true,"report":"run end failed","fixdone":"ran","closed":["F1","F2"],"open":[]}'; do
    for w in building verifying fixing; do
      out=$(wf "$w" '{"models":{"lead":"opus"}}' "$bad")
      printf '%s' "$out" | jq -e --argjson b "$bad" '[.calls[] | select(.opts.label == "close run")][0].opts.model == "opus"
        and (.logs | any(contains($b.report)))' || { echo "$w with $bad: $out"; false; }
    done
  done
  bad='{"ended":true,"recorded":false,"report":"P1 has no plans"}'
  for w in planning mapping; do
    out=$(wf "$w" '{"models":{"lead":"opus"}}' "$bad")
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].opts.model == "opus"
      and (.logs | any(contains("P1 has no plans")))' || { echo "$w: $out"; false; }
  done
}

@test "R188: no other agent's model changes: the Lead plans on models.lead, every other role keeps its profile's model" {
  local m out
  for m in opus sonnet claude-opus-5-5; do
    out=$(wf planning "$(jq -nc --arg m "$m" '{models: {architect: "opus", lead: $m}}')")
    printf '%s' "$out" | jq -e --arg m "$m" '[.calls[] | select(.opts.label == "lead")] | length == 1 and .[0].opts.model == $m
      and .[0].opts.agentType == "vbw:lead"' || { echo "$m: $out"; false; }
  done
  # With no Lead model given, the plan step still inherits the session's model.
  out=$(wf planning '{}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "lead")][0].opts | has("model") | not' || { echo "$out"; false; }
  # Balanced: every vbw:lead call on opus, the Architect on opus, every other agent on sonnet.
  local models w
  models=$(jq -c '.balanced' "$PROFILES")
  printf '%s' "$models" | jq -e '.lead == "opus" and .architect == "opus" and .dev == "sonnet" and .qa == "sonnet"' || { echo "$models"; false; }
  for w in building verifying fixing planning; do
    out=$(wf "$w" "$(jq -nc --argjson m "$models" '{models: $m}')")
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.agentType == "vbw:lead") | .opts.model] | length >= 1 and all(. == "opus")' || { echo "$w: $out"; false; }
    printf '%s' "$out" | jq -e '[.calls[] | select(.opts.agentType != "vbw:lead" and .opts.agentType != "vbw:architect") | .opts.model]
      | all(. == "sonnet")' || { echo "$w: $out"; false; }
  done
}
