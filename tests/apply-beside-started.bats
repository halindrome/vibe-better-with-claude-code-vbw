#!/usr/bin/env bats
# R157 (docs/workflows.md): a re-plan can add a new phase for more work on a
# requirement that a started phase already covers, through a full vbw apply or
# vbw apply --add. The started phase keeps its id, title, requirements, goal,
# criteria, tier, tier reasons, predicted tier and escalations, and each of its
# plans that has started keeps its phase, requirements, files, order, tasks and
# status. A re-plan that drops or changes a started plan is still refused,
# naming the plan. A phase has started when one of its plans is no longer
# planned or it has an escalation. L1.

load helper
load replan-helper
load fixture-helper

built_project() {
  vbw_setup
  replan_project
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# The new phase P3: more work on R1, with its own plan.
P3_PHASE='{"id": "P3", "title": "Pay again", "reqs": ["R1"], "goal": "Customers pay with a saved card", "criteria": ["a saved card pays"], "tier": "standard"}'
P3_PLAN='{"id": "P3.1", "phase": "P3", "title": "Saved card", "reqs": ["R1"], "files": ["src/d.txt"], "after": [], "tasks": ["card"]}'

# The full document: the milestone as planned, plus P3.
full_doc() { replan_doc ".phases += [$P3_PHASE] | .plans += [$P3_PLAN]"; }
# The --add document: P3 alone.
add_doc() { jq -nc --argjson ph "$P3_PHASE" --argjson pl "$P3_PLAN" '{phases: [$ph], plans: [$pl], checks: []}'; }

# kept: the started phase P1 and its started plan P1.1, every field the
# requirement names.
kept() {
  replan_part '{phase: (.phases[] | select(.id == "P1") | {id, title, reqs, goal, criteria, tier, reasons, predicted, escalations}),
    plan: (.plans[] | select(.id == "P1.1") | {phase, reqs, files, after, tasks, status})}'
}

@test "R157: a full apply that keeps a started phase and adds a new phase for its requirement is accepted" {
  replan_start P1.1
  replan_accepted full "$(full_doc)"
  [ "$(replan_part '[.phases[] | select(.id == "P3") | .reqs]')" = '[["R1"]]' ]
  [ "$(replan_part '[.plans[] | select(.id == "P3.1") | .status]')" = '["planned"]' ]
}

@test "R157: vbw apply --add with a new phase for a requirement a started phase covers is accepted" {
  replan_start P1.1
  replan_accepted add "$(add_doc)"
  [ "$(replan_part '[.phases[] | select(.id == "P3") | .reqs]')" = '[["R1"]]' ]
}

@test "R157: after a full apply the started phase and its started plan keep every field" {
  replan_start P1.1
  "$VBW" tier raise P1 deep "a test raised it" > /dev/null
  local before
  before=$(kept)
  replan_part '.phases[] | select(.id == "P1") | .escalations | length == 1' | grep -qx true
  replan_accepted full "$(full_doc)"
  [ "$(kept)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(kept)"; false; }
}

@test "R157: after vbw apply --add the started phase and its started plan keep every field" {
  replan_start P1.1
  "$VBW" tier raise P1 deep "a test raised it" > /dev/null
  local before
  before=$(kept)
  replan_accepted add "$(add_doc)"
  [ "$(kept)" = "$before" ] || { printf 'before: %s\nafter:  %s\n' "$before" "$(kept)"; false; }
}

@test "R157: a phase with an escalation and no started plan counts as started, and keeps its tier and escalations beside the new phase" {
  "$VBW" tier raise P1 deep "a test raised it" > /dev/null
  local before
  before=$(replan_part '.phases[] | select(.id == "P1") | {tier, predicted, escalations}')
  replan_accepted full "$(full_doc)"
  [ "$(replan_part '.phases[] | select(.id == "P1") | {tier, predicted, escalations}')" = "$before" ]
  [ "$(replan_part '[.phases[] | select(.id == "P3") | .reqs]')" = '[["R1"]]' ]
}

@test "R157: a re-plan that drops a started plan is refused, naming the plan" {
  replan_start P1.1
  replan_refused full "$(full_doc | jq -c '.plans |= map(select(.id != "P1.1")) | (.plans[] | select(.id == "P1.2")).after = []')"
  [[ "$output" == *"P1.1"* ]] || { echo "$output"; false; }
}

@test "R157: a re-plan that changes a started plan is refused, naming the plan" {
  replan_start P1.1
  replan_refused full "$(full_doc | jq -c '(.plans[] | select(.id == "P1.1")).files += ["src/extra.txt"]')"
  [[ "$output" == *"P1.1"* ]] || { echo "$output"; false; }
}
