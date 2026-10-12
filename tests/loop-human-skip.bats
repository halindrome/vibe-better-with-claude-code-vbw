#!/usr/bin/env bats
# R179 (P128; docs/loop.md): a [human] requirement at the accept step is
# skipped by the loop (vbw req skip), never accepted or rejected on the user's
# behalf; the ship moves it to the next milestone (D256), and the report lists
# it as waiting for the user's judgment. L1.

load helper
load loop-helper

setup() {
  loop_project
  "$VBW" todo add "[human] The greeting feels friendly" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop start T3 --no-ceiling > /dev/null
}
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }

@test "R179: the loop skips a [human] requirement at accept, ships with it moved on, and the report says it waits for the user" {
  [ "$(step)" = plan ]
  local q
  q=$(item_req "The greeting feels friendly")
  [ -n "$q" ]
  jq -nc --arg q "$q" '{phases: [{id: "P2", title: "Friendly", reqs: [$q], goal: "A friendly greeting", criteria: ["it feels friendly"]}],
    plans: [{id: "P2.1", phase: "P2", title: "Friendly", reqs: [$q], files: ["src/greet.txt"], after: [], tasks: ["write a friendly greeting"]}],
    checks: []}' | "$VBW" apply > /dev/null
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_build P2
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_prove
  [ "$(step)" = qa ] || { cat "$TEST_ROOT/step.json"; false; }
  "$VBW" qa record P2 pass "$(jq -r .detail.tier "$TEST_ROOT/step.json")" > /dev/null
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e --arg q "$q" '.requirements[] | select(.id == $q) | .status == "open" and .skipped == true and .later == true' .vbw/record.json || { jq .requirements .vbw/record.json; false; }
  jq -e '.milestone.status == "shipped"' .vbw/record.json
  jq -e --arg q "$q" '[.fixes[] | select(.req == $q)] | length == 0' .vbw/record.json
  jq -e '.loop.items[0].status == "shipped"' .vbw/record.json
  [ -f .vbw/loop-report.md ]
  grep -qi 'waiting' .vbw/loop-report.md
  grep -q "$q" .vbw/loop-report.md
  grep -q 'The greeting feels friendly' .vbw/loop-report.md
}

@test "R179: the loop never accepts or rejects on the user's behalf: no acceptance, no rejection, no fix from a rejection" {
  [ "$(step)" = plan ]
  local q
  q=$(item_req "The greeting feels friendly")
  jq -nc --arg q "$q" '{phases: [{id: "P2", title: "Friendly", reqs: [$q], goal: "A friendly greeting", criteria: ["it feels friendly"]}],
    plans: [{id: "P2.1", phase: "P2", title: "Friendly", reqs: [$q], files: ["src/greet.txt"], after: [], tasks: ["write a friendly greeting"]}],
    checks: []}' | "$VBW" apply > /dev/null
  step > /dev/null
  loop_build P2
  step > /dev/null
  loop_prove
  step > /dev/null
  "$VBW" qa record P2 pass "$(jq -r .detail.tier "$TEST_ROOT/step.json")" > /dev/null
  [ "$(next_action)" = accept ]
  step > /dev/null
  jq -e --arg q "$q" '[.requirements[] | select(.id == $q) | .status] == ["open"]' .vbw/record.json
  jq -e --arg q "$q" '[.fixes[] | select(.req == $q)] | length == 0' .vbw/record.json
  jq -e --arg q "$q" '.requirements[] | select(.id == $q) | .skipped == true' .vbw/record.json
}
