#!/usr/bin/env bats
# R191 (F251, F252; L1): the proof's unit names in vbw next --json are built by
# one jq process whatever the unit count, and are the names the proof itself
# runs (held checks and unapproved project commands left out); the road names
# the kind of piece that lacks a basis ('proofs', 'QA checks'), also when the
# piece is part of the usual fix rounds.

load helper
load step-helper
load road-helper

setup() {
  vbw_setup
  export TZ=Europe/Zurich
}
teardown() { vbw_teardown; }

# shim_jq: a jq on PATH that logs each start to $TEST_ROOT/jq.log.
shim_jq() {
  mkdir -p "$TEST_ROOT/shim"
  local real
  real=$(command -v jq)
  printf '#!/bin/sh\necho "$*" >> "%s/jq.log"\nexec "%s" "$@"\n' "$TEST_ROOT" "$real" > "$TEST_ROOT/shim/jq"
  chmod +x "$TEST_ROOT/shim/jq"
  : > "$TEST_ROOT/jq.log"
}

many_checks() {
  local i f='.checks = ['
  for ((i = 1; i <= $1; i++)); do f="$f{id: \"C$i\", req: \"R1\", run: [\"true\"]},"; done
  step_edit "${f%,}]"
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
}

jq_starts() {
  : > "$TEST_ROOT/jq.log"
  PATH="$TEST_ROOT/shim:$PATH" "$VBW" next --json > "$TEST_ROOT/next.json"
  grep -c -F -e '. + [$n]' -e '$names + ' "$TEST_ROOT/jq.log" || true
}

@test "F251: the jq processes started for a proof's units do not grow with the unit count" {
  step_project
  step_edit '.plans[].status = "done"'
  many_checks 5
  shim_jq
  small=$(jq_starts)
  jq -e '.step.kind == "proof" and .step.parts == 5' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
  many_checks 30
  big=$(jq_starts)
  jq -e '.step.kind == "proof" and .step.parts == 30' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
  [ "$big" -le "$small" ] || { echo "5 units: $small name-building jq starts, 30 units: $big"; false; }
}

# units_of: step_proof_units' answer and the proof's own names (prove_unit_names), for the
# record as it is now, one JSON array per line.
units_of() {
  bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"; . "$VBW_LIB/consent.sh"; . "$VBW_LIB/contract.sh"
    . "$VBW_LIB/steps.sh"; . "$VBW_LIB/cmd-prove.sh"
    vbw_require_project
    r=$(record_read)
    step_proof_units "$r" 0
    proofreuse_plan "$r" 0; testfiles_plan "$r" 0; CHECK_HELD=$(contract_held "$r"); prove_unit_names "$r"' _ "$PLUGIN_ROOT"
}

@test "F251: a project command without the user's approval is left out of the units vbw next --json counts, as in the proof itself" {
  step_project
  step_edit '.plans[].status = "done" | .checks = [{id: "C1", req: "R1", run: ["true"]}, {id: "C2", req: "R1", run: ["true"]}]'
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
  # A command added after the approval: its argv has no recorded consent.
  step_edit '.commands = ((.commands // {}) + {lint: ["true", "unapproved"]})'
  local out
  out=$(units_of)
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = '["check:C1","check:C2"]' ] || { echo "$out"; false; }
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = "$(printf '%s\n' "$out" | sed -n 2p)" ] || { echo "$out"; false; }
}

# done_project: road_project with every plan done and every check passing in
# the evidence, the road history in place.
done_project() {
  road_project
  road_hist
  outcomes_seed deep 1 2 2 5
  step_edit '.plans[].status = "done" | .requirements |= map(if .id == "R1" or .id == "R2" then .status = "proven" else . end)
    | .evidence = {at: "2026-01-01T00:00:00Z", contract: ("a" * 64), tree: ("b" * 40), passed: true, scope: [], commands: {},
      checks: {C1: {status: "pass", exit: 0, seconds: 1, tail: ""}, C2: {status: "pass", exit: 0, seconds: 1, tail: ""}}}'
}

@test "F252: only QA left, fix and QA history present, fewer than 3 proofs timed: the missing kind is proofs" {
  done_project
  jq 'del(.steps[] | select(.kind == "proof"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  road_of | jq -e '.end == null and .say == "no milestone end time yet (VBW has timed fewer than 3 proofs here)"' || { road_of; false; }
}

@test "F252: no QA history for a phase that stands QA-passed with a failing check: the missing kind is QA checks, not fix rounds" {
  road_project
  road_hist
  outcomes_seed deep 1 2 2 5
  step_edit '.plans[].status = "done"'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" qa record P1 pass deep > /dev/null
  "$VBW" qa record P2 pass standard > /dev/null
  step_edit '.evidence.checks.C1.status = "fail" | .evidence.passed = false'
  jq 'del(.steps[] | select(.kind == "qa"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  "$VBW" next --json | jq -e '.qa.standing | index("P1") != null' || { "$VBW" next --json | jq -c .qa; false; }
  road_of | jq -e '.end == null and .say == "no milestone end time yet (VBW has timed fewer than 3 QA checks here)"' || { road_of; false; }
}
