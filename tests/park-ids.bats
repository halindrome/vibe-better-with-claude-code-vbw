#!/usr/bin/env bats
# T163 (docs/loop.md, Parking; docs/proof.md, scope): a park keeps the ids it
# frees. Its commits carry VBW-Plan, VBW-Req and VBW-Fix trailers for good, so
# the next phase, requirement and fix never take a parked one's number; and the
# proof's scope check does not judge commits a park undid, whose changes are
# gone (the loop's T94 park freed P146 and R190, T102 took them, and today's
# P146 plans were blamed for T94's undone commits). L1: the kernel on the loop
# fixture, the park reached as the loop reaches it.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }

# park_t1: T1 planned as P2 (R2, C2), built, broken, escalated twice: parked,
# its commits reverted. Then the next milestone starts.
park_t1() {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 50 > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  loop_break P2
  [ "$(step)" = prove ]
  loop_prove
  [ "$(step)" = fix ]
  edit_record '(.fixes[] | select(.id == "F1")).status = "escalated"'
  [ "$(step)" = fix ]
  edit_record '(.fixes[] | select(.id == "F1")).status = "escalated"'
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.loop.items[0].status == "parked" and (.loop.items[0].reverts | length) == 2' .vbw/record.json
  "$VBW" milestone start "Again" > /dev/null
}

@test "T163: the parked milestone keeps the phase, requirement and fix ids it freed" {
  park_t1
  jq -e '.parked[0].ids == ["P2", "R2", "F1"]' .vbw/record.json || { jq .parked .vbw/record.json; false; }
}

@test "T163: after a park the next phase, requirement and fix take new numbers" {
  park_t1
  [ "$("$VBW" next --json < /dev/null | jq -r .next_phase)" = 3 ]
  "$VBW" spec add auto "Visitors can read a greeting" > /dev/null
  jq -e '[.requirements[].id] | index("R3") != null and index("R2") == null' .vbw/record.json \
    || { jq .requirements .vbw/record.json; false; }
  printf 'grep -qx hello src/greet.txt\n' > tests/greet.sh
  jq -nc '{phases: [{id: "P3", title: "Greeting", reqs: ["R3"], goal: "A greeting exists", criteria: ["it says hello"]}],
    plans: [{id: "P3.1", phase: "P3", title: "Greeting", reqs: ["R3"], files: ["src/greet.txt"], after: [], tasks: ["write hello"]}],
    checks: [{id: "C9", req: "R3", run: ["sh", "tests/greet.sh"], files: ["tests/greet.sh"]}],
    rules: [{req: "R3", text: "it says hello", check: "C9"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  loop_build P3
  loop_break P3
  loop_prove
  jq -e '[.fixes[] | select(.req == "R3") | .id] == ["F2"]' .vbw/record.json || { jq .fixes .vbw/record.json; false; }
}

@test "T163: commits a park undid are not judged by a later plan that reuses their plan id" {
  park_t1
  "$VBW" spec add auto "Visitors can read a farewell" > /dev/null
  local q
  q=$(item_req "Visitors can read a farewell")
  printf 'grep -qx bye src/bye.txt\n' > tests/bye.sh
  # A record from before T163 handed P2 out again: the new P2.1 owns only src/bye.txt.
  jq -nc --arg q "$q" '{phases: [{id: "P2", title: "Farewell", reqs: [$q], goal: "A farewell exists", criteria: ["it says bye"]}],
    plans: [{id: "P2.1", phase: "P2", title: "Farewell", reqs: [$q], files: ["src/bye.txt"], after: [], tasks: ["write bye"]}],
    checks: [{id: "C9", req: $q, run: ["sh", "tests/bye.sh"], files: ["tests/bye.sh"]}],
    rules: [{req: $q, text: "it says bye", check: "C9"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'bye\n' > src/bye.txt
  "$VBW" commit P2.1 "feat(bye): bye" > /dev/null
  run "$VBW" prove < /dev/null
  [[ "$output" == *"scope ok"* ]] || { echo "$output"; false; }
  jq -e '(.evidence.scope // []) | length == 0' .vbw/record.json
}

@test "T163: a commit undone by hand, not by a park, is still judged" {
  park_t1
  "$VBW" spec add auto "Visitors can read a farewell" > /dev/null
  local q
  q=$(item_req "Visitors can read a farewell")
  printf 'grep -qx bye src/bye.txt\n' > tests/bye.sh
  jq -nc --arg q "$q" '{phases: [{id: "P3", title: "Farewell", reqs: [$q], goal: "A farewell exists", criteria: ["it says bye"]}],
    plans: [{id: "P3.1", phase: "P3", title: "Farewell", reqs: [$q], files: ["src/bye.txt"], after: [], tasks: ["write bye"]}],
    checks: [{id: "C9", req: $q, run: ["sh", "tests/bye.sh"], files: ["tests/bye.sh"]}],
    rules: [{req: $q, text: "it says bye", check: "C9"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'x\n' > src/stray.txt
  git add src/stray.txt
  git commit -q -m "feat(bye): stray" -m "VBW-Plan: P3.1"
  git revert --no-edit HEAD > /dev/null
  printf 'bye\n' > src/bye.txt
  "$VBW" commit P3.1 "feat(bye): bye" > /dev/null
  run "$VBW" prove < /dev/null
  [[ "$output" == *"(P3.1) changed src/stray.txt, which is not in the plan"* ]] || { echo "$output"; false; }
}
