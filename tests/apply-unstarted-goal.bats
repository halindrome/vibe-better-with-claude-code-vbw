#!/usr/bin/env bats
# R158 (docs/workflows.md): a full vbw apply may change the goal, the criteria
# or both of a phase that has not started (every plan still planned, no
# escalation); the record then holds the new goal and criteria and the phase's
# id, title, requirements and plans are unchanged. A full apply that changes the
# goal or criteria of a started phase is refused, naming the phase and saying to
# add a new phase for the further work. vbw apply --patch still refuses any
# phase change. L1.

load helper
load replan-helper
load fixture-helper

built_project() {
  vbw_setup
  replan_project
  # P1 has started; P2 has not.
  replan_start P1.1
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# rest PHASE: what must stay when only the goal or criteria change.
rest() { replan_part "{phase: (.phases[] | select(.id == \"$1\") | {id, title, reqs}), plans: [.plans[] | select(.phase == \"$1\") | {id, phase, title, reqs, files, after, tasks, status}]}"; }

@test "R158: a full apply that changes only the goal of a phase that has not started is accepted" {
  local before
  before=$(rest P2)
  replan_accepted full "$(replan_doc '(.phases[] | select(.id == "P2")).goal = "Customers get a receipt by mail"')"
  [ "$(replan_part '.phases[] | select(.id == "P2") | .goal')" = '"Customers get a receipt by mail"' ]
  [ "$(rest P2)" = "$before" ]
}

@test "R158: a full apply that changes only the criteria of a phase that has not started is accepted" {
  local before
  before=$(rest P2)
  replan_accepted full "$(replan_doc '(.phases[] | select(.id == "P2")).criteria = ["a receipt is shown", "a receipt is mailed"]')"
  [ "$(replan_part '.phases[] | select(.id == "P2") | .criteria')" = '["a receipt is shown","a receipt is mailed"]' ]
  [ "$(rest P2)" = "$before" ]
}

@test "R158: a full apply that changes both the goal and the criteria of a phase that has not started is accepted" {
  local before
  before=$(rest P2)
  replan_accepted full "$(replan_doc '(.phases[] | select(.id == "P2")) |= (.goal = "Receipts by mail" | .criteria = ["a receipt is mailed"])')"
  [ "$(replan_part '.phases[] | select(.id == "P2") | {goal, criteria}')" = '{"criteria":["a receipt is mailed"],"goal":"Receipts by mail"}' ]
  [ "$(rest P2)" = "$before" ]
}

@test "R158: a full apply that changes the goal of a started phase is refused, naming the phase and pointing to a new phase" {
  replan_refused full "$(replan_doc '(.phases[] | select(.id == "P1")).goal = "Customers pay twice"')"
  [[ "$output" == *"P1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"new phase"* ]] || { echo "$output"; false; }
}

@test "R158: a full apply that changes the criteria of a started phase is refused, naming the phase and pointing to a new phase" {
  replan_refused full "$(replan_doc '(.phases[] | select(.id == "P1")).criteria += ["a refund is possible"]')"
  [[ "$output" == *"P1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"new phase"* ]] || { echo "$output"; false; }
}

@test "R158: a full apply that omits a started phase's goal and criteria keeps them as recorded" {
  local before
  before=$(replan_part '.phases[] | select(.id == "P1") | {goal, criteria}')
  [ "$before" != '{"criteria":null,"goal":null}' ] || { echo "the fixture's P1 has no goal to keep"; false; }
  replan_accepted full "$(replan_doc '(.phases[] | select(.id == "P1")) |= del(.goal, .criteria)')"
  [ "$(replan_part '.phases[] | select(.id == "P1") | {goal, criteria}')" = "$before" ]
}

@test "R158: a phase with an escalation counts as started even when every plan is planned" {
  "$VBW" tier raise P2 deep "a test raised it" > /dev/null
  replan_refused full "$(replan_doc '(.phases[] | select(.id == "P2")).goal = "Customers get a receipt by mail"')"
  [[ "$output" == *"P2"* ]] || { echo "$output"; false; }
}

@test "R158: vbw apply --patch still refuses any phase change" {
  replan_refused patch "$(jq -nc '{phases: [{id: "P2", title: "Receipt", reqs: ["R2"], goal: "Receipts by mail"}]}')"
  [[ "$output" == *"phase"* ]] || { echo "$output"; false; }
}
