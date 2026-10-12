#!/usr/bin/env bats
# R179 (P128; docs/loop.md, Where the loop stops): with the default ceiling the
# loop compares its spend with the ceiling before each step and stops before
# that step at or above it, or when the spend cannot be told; a workflow or
# proof already running is never killed (the loop stops once its result is
# recorded). --finish-item: once reached, the current item runs on to its ship
# and then the loop stops. --no-ceiling: no comparison. End of list: the loop
# stops after the last item's ship. vbw loop stop from any session stops the
# loop before its next step with the reason and the session. Anything the loop
# cannot do without the user (an action the loop does not know) stops it with
# the reason, the item and the step, recorded in the loop state. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }
reason() { jq -r .reason "$TEST_ROOT/step.json"; }
untouched() { jq -e '.milestone.title == "Next" and ([.requirements[] | select(.milestone == "M2")] | length) == 0' .vbw/record.json; }

@test "R179: default ceiling: at or above it the loop stops before the next step with that reason; under it the step runs" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 > /dev/null
  figures s1 7 3000 300
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"ceiling"* ]] && [[ "$(reason)" == *'$5'* ]] || { reason; false; }
  untouched
  jq -e '.loop.ended.reason | test("ceiling")' .vbw/record.json
  jq -e '.loop.items | all(.[]; .status == "waiting")' .vbw/record.json
  [ "$(step)" = stopped ]
  run "$VBW" loop status
  [[ "$output" == *"ended"* ]] && [[ "$output" == *"ceiling"* ]] || { echo "$output"; false; }
}

@test "R179: under the ceiling the loop goes on" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 > /dev/null
  figures s1 6.9 3000 300
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.milestone.title == "Visitors can read a greeting"' .vbw/record.json
}

@test "R179: when the spend cannot be told the loop stops before the step" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  no_figures
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"cannot tell"* ]] || { reason; false; }
  untouched
}

@test "R179: --finish-item: once reached, the item runs on to its ship and then the loop stops" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 --finish-item > /dev/null
  [ "$(step)" = plan ]
  figures s1 7 3000 300
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_build P2
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_prove
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"ceiling"* ]] || { reason; false; }
  jq -e '.milestone.id == "M2" and .milestone.status == "shipped"' .vbw/record.json
  jq -e '.loop.items[0].status == "shipped" and .loop.items[1].status == "waiting"' .vbw/record.json
  jq -e '.todos[] | select(.id == "T2") | .status == "open"' .vbw/record.json
}

@test "R179: --no-ceiling: no comparison, even with no figure at all" {
  no_figures
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
}

@test "R179: a stop asked from any session stops the loop before its next step, naming the user and the session" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  [ "$(step)" = stopped ]
  [[ "$(reason)" == *"stopped by the user"* ]] && [[ "$(reason)" == *"s9"* ]] || { reason; false; }
  untouched
  jq -e '.loop.ended.reason | test("s9")' .vbw/record.json
}

@test "R179: a workflow already running is never killed: the loop stops once the run has ended" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  figures s1 9 3000 300
  [ "$(step)" = run ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.lease != null and .loop.ended == null' .vbw/record.json
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  [ "$(step)" = stopped ]
  [[ "$(reason)" == *"ceiling"* ]] || { reason; false; }
}

@test "R179: an action the loop does not know stops it with the reason, the item and the step" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  rm -f tests/greet.sh
  [ "$(next_action)" = contract ]
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"T1"* ]] && [[ "$(reason)" == *"contract"* ]] || { reason; false; }
  jq -e '.loop.ended.reason | test("T1") and test("contract")' .vbw/record.json
  jq -e '.loop.items[0].status == "in_progress"' .vbw/record.json
}

@test "R179: a run open in another session stops the loop with the reason" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s9 "$VBW" run start qa > /dev/null
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"s9"* ]] || { reason; false; }
}
