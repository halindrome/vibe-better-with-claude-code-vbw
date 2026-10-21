#!/usr/bin/env bats
# R111 (docs/proof.md, D260): QA verdicts and shipping accept a proof whose
# checks and commands ran or were reused under the read-list rule. They refuse,
# without changing the record, only a proof that skipped part of the work: one
# in which the quick command stood in for the test command. vbw next asks for
# vbw prove --full before QA or shipping only then, and QA agents are given the
# test command's own result, never the quick command's. L1.

load helper
load fixture-helper

setup_file() { fixture_build shop gate_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# gate_project: the project every test starts from, built once per file.
gate_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  # Each command prints which one ran, so the result a QA agent is given can be told apart.
  printf 'echo "$1 ok"\n' > tests/cmd.sh
  git add tests/cmd.sh && git commit -q -m "chore: project command"
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan "done" P1.1 > /dev/null
  "$VBW" prove > /dev/null
}

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# with_quick: the project gets an approved test command and an approved quick command.
with_quick() {
  edit_record '.commands = {test: ["sh","tests/cmd.sh","full-suite"], quick: ["sh","tests/cmd.sh","quick-suite"]}'
  "$VBW" approve > /dev/null
}

# partial: a plain proof in which the approved quick command stands in for the test command.
partial() {
  "$VBW" prove > /dev/null || return 1
  jq -e '.evidence.commands | has("quick") and (has("test") | not)' .vbw/record.json > /dev/null
}

# reused: a proof that reused results (only VBW's own record changed since the last one).
reused() {
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  "$VBW" prove > /dev/null || return 1
  jq -e '.evidence.full == false and any(.evidence.checks[]; .reused == true)' .vbw/record.json > /dev/null
}

@test "R111: vbw qa record refuses a proof in which the quick command stood in for the test command, changes nothing, and says to run vbw prove --full" {
  with_quick
  partial
  local before
  before=$(shasum .vbw/record.json)
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"the last proof was partial: run vbw prove --full, then record the verdict again"* ]] || { echo "$output"; false; }
  [ "$(shasum .vbw/record.json)" = "$before" ]
}

@test "R111: the refusal for code that changed since the proof still applies first" {
  with_quick
  partial
  printf 'paid\nmore\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "fix(pay): more"
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"the code changed since the last proof"* ]] || { echo "$output"; false; }
}

@test "R111: vbw ship refuses a proof in which the quick command stood in, changes nothing, and says to run vbw prove --full" {
  with_quick
  "$VBW" prove --full > /dev/null
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = ship ] || { echo "$output"; false; }
  partial
  local before
  before=$(shasum .vbw/record.json)
  vbw_run ship
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]] || { echo "$output"; false; }
  [ "$(shasum .vbw/record.json)" = "$before" ]
}

@test "R111: before QA, vbw next asks for a full proof when the quick command stood in, and --json marks it" {
  with_quick
  partial
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "prove" and .detail.full == true and (.instruction | contains("Run vbw prove --full"))' \
    || { echo "$output"; false; }
  vbw_run next
  [[ "$output" == *"Run vbw prove --full"* ]]
}

@test "R111: before shipping, vbw next asks for a full proof when the quick command stood in" {
  with_quick
  "$VBW" prove --full > /dev/null
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  partial
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "prove" and .detail.full == true and (.instruction | contains("vbw prove --full"))' \
    || { echo "$output"; false; }
}

@test "R111: with a full proof, vbw next goes on to QA and does not mark the detail as full" {
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "qa" and (.detail.full // false) == false' || { echo "$output"; false; }
}

@test "R111: a proof that reused results is accepted: vbw next goes on to QA, vbw qa record records the verdict and vbw ship ships" {
  reused
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "qa" and (.detail.full // false) == false' || { echo "$output"; false; }
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"vbw prove --full"* ]] || { echo "$output"; false; }
  jq -e '.phases[0].qa.result == "pass"' .vbw/record.json
  reused
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = ship ] || { echo "$output"; false; }
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R111: a refused verdict, then vbw prove --full, then the verdict is recorded" {
  with_quick
  partial
  jq -e '.evidence.full == false' .vbw/record.json
  vbw_run qa record P1 pass standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]]
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.phases[0].qa.result == "pass"' .vbw/record.json
}

@test "R111: a proof recorded before the full flag existed counts as full" {
  edit_record 'del(.evidence.full)'
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R111: the test-command result QA agents are given comes from the full proof, never from the quick command" {
  with_quick
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "qa" and (.round.suite.tail | contains("full-suite")) and (.round.suite.tail | contains("quick-suite") | not)' \
    || { echo "$output"; false; }
}
