#!/usr/bin/env bats
# R190, phase P146 (L1): a proof (vbw prove, and the proof inside vbw fix done)
# is a step of kind proof in the step history, steps.json in the clone's git
# folder, whose parts are the checks and test files it really ran. A proof that
# reused every result ran nothing and is not recorded, so it never teaches VBW
# a false zero. A missing or unwritable history never fails a proof. A note left
# by an ended run is removed by the next proof.

load helper
load step-helper

setup() {
  vbw_setup
  step_project
}
teardown() { vbw_teardown; }

# last KIND: the newest step of KIND in the history.
last() { jq -c --arg k "$1" '[.steps[] | select(.kind == $k)] | last' "$STEPS"; }

@test "R190: a proof is a step of kind proof whose parts are the checks it really ran" {
  step_edit '.plans[].status = "done" | .checks = [{id: "C1", req: "R1", run: ["true"]}, {id: "C2", req: "R1", run: ["true"]}, {id: "C3", req: "R1", run: ["true"]}]'
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq '[.steps[] | select(.kind == "proof")] | length' "$STEPS")" -eq 1 ] || { cat "$STEPS"; false; }
  last proof | jq -e '.parts == 3 and (.run | type == "string") and (.seconds | type == "number")' || { cat "$STEPS"; false; }
}

@test "R190: a proof that reused every result ran nothing and adds no step" {
  step_edit '.plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): done"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"checks: 0 ran"* ]] || { echo "$output"; false; }
  [ "$(jq '[.steps[] | select(.kind == "proof")] | length' "$STEPS")" -eq 1 ] || { cat "$STEPS"; false; }
}

@test "R190: the proof inside vbw fix done is recorded as a proof step" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fix"
  "$VBW" approve > /dev/null
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"checks: 1 ran"* ]] || { echo "$output"; false; }
  last proof | jq -e '.parts == 1' || { cat "$STEPS"; false; }
}

@test "R190: a missing or unwritable history never fails a proof" {
  mkdir -p tests
  printf 'cat src/a.txt > /dev/null\n' > tests/reads-a.sh
  step_edit '.plans[].status = "done" | .checks = [{id: "C1", req: "R1", run: ["sh", "tests/reads-a.sh"], files: ["tests/reads-a.sh"]}]'
  git add -A && git commit -q -m "chore(vbw): done"
  "$VBW" approve > /dev/null
  rm -f "$STEPS"
  mkdir -p "$STEPS"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *proved* ]]
  rmdir "$STEPS"
  printf 'paid\n' >> src/a.txt
  git add src/a.txt && git commit -q -m "feat(pay): change a"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  last proof | jq -e '.parts == 1' || { cat "$STEPS"; false; }
}

@test "R190: a note left by an ended run is removed by the next proof" {
  "$VBW" run start build P1.1 > /dev/null
  cp "$NOTE" "$TEST_ROOT/old-note.json"
  "$VBW" run end > /dev/null
  step_edit '.plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): done"
  "$VBW" approve > /dev/null
  cp "$TEST_ROOT/old-note.json" "$NOTE"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$NOTE" ] || { cat "$NOTE"; false; }
}
