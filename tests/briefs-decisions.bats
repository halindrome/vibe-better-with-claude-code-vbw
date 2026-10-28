#!/usr/bin/env bats
# T123: build and fix briefs carry the decisions recorded since the contract
# was approved, so a decision that corrects a plan mid-milestone reaches the Dev
# (2026-10-12: D291, D294-D296 never reached the Devs). The kernel lists them
# (vbw show decisions --since-approval: after the latest approval of the
# contract in the record); building.js and fixing.js name that command in every
# Dev and Docs prompt. L1: the kernel on a fixture project, and the workflows
# with stubbed agents (tests/helpers/run-workflow.js): no model runs.

load helper
load approve-choice-helper
load fixture-helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
CMD='vbw show decisions --since-approval'

built_project() {
  vbw_setup
  approve_choice_project
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "T123: --since-approval lists the decisions after the approval, none before it" {
  "$VBW" decide "use SQLite" > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" decide "store prices in cents" "rounding" > /dev/null
  "$VBW" decide "no guest checkout" > /dev/null
  vbw_run show decisions --since-approval
  [ "$status" -eq 0 ]
  [[ "$output" == *"store prices in cents"* ]] || false
  [[ "$output" == *"no guest checkout"* ]] || false
  [[ "$output" != *"use SQLite"* ]] || false
  [[ "$output" != *"Contract approved"* ]] || false
}

@test "T123: after a second approval only the decisions after it are listed; for a plan, after the latest approval that changed it" {
  "$VBW" approve > /dev/null
  "$VBW" decide "first correction" > /dev/null
  printf '{"plans": [{"id": "P1.1", "phase": "P1", "title": "Pay by card", "reqs": ["R1"], "files": ["src/pay.txt"]}]}' \
    | "$VBW" apply --patch > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" decide "second correction" > /dev/null
  vbw_run show decisions --since-approval
  [ "$status" -eq 0 ]
  [[ "$output" == *"second correction"* ]] || false
  [[ "$output" != *"first correction"* ]] || false
  # The second approval changed P1.1: its plan now holds the first correction.
  vbw_run show decisions --since-approval P1.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"second correction"* ]] || false
  [[ "$output" != *"first correction"* ]] || false
}

@test "#705: an approval that left a plan as it was keeps the decisions before it in that plan's list and its fixes'" {
  "$VBW" approve > /dev/null
  "$VBW" decide "revert the forced line; check C1 changes to match" > /dev/null
  # The decision itself changes a check, which needs an approval again; the plan is unchanged.
  printf 'grep -qx paid src/pay.txt # per the decision\n' > tests/pay.sh
  "$VBW" approve > /dev/null
  "$VBW" decide "second correction" > /dev/null
  jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  local id
  for id in P1.1 F1; do
    vbw_run show decisions --since-approval "$id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"revert the forced line"* ]] || { echo "$id: the decision before the re-approval is missing"; false; }
    [[ "$output" == *"second correction"* ]] || false
    [[ "$output" != *"Contract approved"* ]] || { echo "$id: an approval is listed as a decision"; false; }
  done
  vbw_run show decisions --since-approval P9
  [ "$status" -ne 0 ]
  [[ "$output" == *P9* ]] || false
}

@test "T123: with no decision since the approval it says so and succeeds" {
  "$VBW" decide "use SQLite" > /dev/null
  "$VBW" approve > /dev/null
  vbw_run show decisions --since-approval
  [ "$status" -eq 0 ]
  [[ "$output" != *"use SQLite"* ]] || false
  [ -n "$output" ]
}

@test "T123: before any approval it fails, naming that nothing was approved" {
  "$VBW" decide "use SQLite" > /dev/null
  vbw_run show decisions --since-approval
  [ "$status" -ne 0 ]
  [[ "$output" == *approv* ]] || false
}

@test "T123: an unknown decisions option is a usage error" {
  vbw_run show decisions --since
  [ "$status" -eq 2 ]
}

@test "T123: every Dev and Docs prompt of a build wave names the decisions-since-approval command" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/building.js" '{"plans":["P1.1","P1.2"],"docs":["P1.2"]}' '{}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e --arg c "$CMD" '[.calls[] | select(.opts.agentType == "vbw:dev" or .opts.agentType == "vbw:docs")]
    | length == 2 and any(.prompt | contains($c + " P1.1")) and any(.prompt | contains($c + " P1.2"))' > /dev/null
}

@test "T123: every Dev prompt of a fix round names the decisions-since-approval command" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/fixing.js" '{"groups":[["F1","F2"],["F3"]]}' '{}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e --arg c "$CMD" '[.calls[] | select(.opts.agentType == "vbw:dev")]
    | length == 2 and any(.prompt | contains($c + " F1 F2")) and any(.prompt | contains($c + " F3"))' > /dev/null
}

@test "T123: the Dev and Docs agents read those decisions as binding over the plan" {
  local f
  for f in dev docs; do
    grep -F -- "$CMD" "$PLUGIN_ROOT/agents/$f.md" | grep -qi plan || { echo "$f.md: no line on decisions since approval and the plan"; false; }
  done
}
