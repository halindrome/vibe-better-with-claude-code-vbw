#!/usr/bin/env bats
# R178 (P127; docs/loop.md): vbw loop stop, from the session that started the
# loop or from any other session of the project, marks the loop as stopping
# with the time and the session; vbw loop status then says so. Stop with no
# loop on says so and exits 0; a second stop ends the stopping loop (D322). The loop state is
# read from the record, never guessed from a session file, so the kernel's loop
# step (vbw loop next) sees the stop before its next step. L1.

load helper
load loop-helper

setup() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
}
teardown() { vbw_teardown; }

@test "R178: stop from the session that started the loop marks it stopping with the time and the session" {
  run env VBW_SESSION_ID=s1 "$VBW" loop stop
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.stopping.session == "s1" and (.loop.stopping.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' .vbw/record.json \
    || { jq .loop .vbw/record.json; false; }
  run "$VBW" loop status
  [[ "$output" == *"stopping"* ]] && [[ "$output" == *"s1"* ]] || { echo "$output"; false; }
  "$VBW" loop status --json < /dev/null | jq -e '.stopping.session == "s1"'
}

@test "R178: stop from any other session of the project works the same and names that session" {
  run env VBW_SESSION_ID=s9 "$VBW" loop stop
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.stopping.session == "s9" and .loop.session == "s1"' .vbw/record.json
  run "$VBW" loop status
  [[ "$output" == *"stopping"* ]] && [[ "$output" == *"s9"* ]] || { echo "$output"; false; }
}

@test "R178: stop with no loop on says so and exits 0; a second stop ends the stopping loop (D322)" {
  local before
  edit_record 'del(.loop)'
  git add .vbw/record.json && git commit -q -m "chore(test): no loop"
  before=$(project_sum)
  run "$VBW" loop stop
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"no loop"* ]] || { echo "$output"; false; }
  [ "$(project_sum)" = "$before" ]
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop stop > /dev/null
  run env VBW_SESSION_ID=s9 "$VBW" loop stop
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # A second stop ends the stopping loop (F170): the stop that asked is kept, the end is recorded.
  jq -e '.loop.stopping.session == "s1" and .loop.ended != null' .vbw/record.json
}

@test "R178: the stop is read from the record: the loop step of the session running the loop answers stopped before its next step" {
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  run loop_next s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "stopped" and (.reason | test("stopped by the user")) and (.reason | test("s9"))' || { echo "$output"; false; }
  # Nothing else happened: no milestone opened, no requirement added.
  jq -e '.milestone.title == "Next" and ([.requirements[] | select(.milestone == "M2")] | length) == 0' .vbw/record.json
}

@test "R178: a stop asked while the loop's own session has a run open is seen once that run has ended" {
  "$VBW" spec add auto "Visitors can read a greeting" > /dev/null
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  VBW_SESSION_ID=s1 "$VBW" loop next --json > /dev/null < /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  run loop_next s1
  printf '%s' "$output" | jq -e '.action == "run"' || { echo "$output"; false; }
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  run loop_next s1
  printf '%s' "$output" | jq -e '.action == "stopped" and (.reason | test("s9"))' || { echo "$output"; false; }
}

@test "R178: vbw loop stop --help changes nothing" {
  local before
  before=$(project_sum)
  run "$VBW" loop stop --help
  [ "$status" -eq 0 ]
  [[ "$output" == "usage: vbw loop"* ]]
  [ "$(project_sum)" = "$before" ]
}

@test "R178 (F170): a second stop while the loop is still stopping ends it at once, with the report: the way out when the loop's session is gone" {
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  run env VBW_SESSION_ID=s9 "$VBW" loop stop
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"ended now"* ]] || { echo "$output"; false; }
  jq -e '.loop.ended != null and (.loop.ended.reason | test("second vbw loop stop"))' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  [ -f .vbw/loop-report.md ]
  [ -z "$(git status --porcelain -- .vbw)" ] || { git status --porcelain; false; }
  run "$VBW" loop stop
  [[ "$output" == *"no loop is on"* ]] || { echo "$output"; false; }
  run "$VBW" loop status
  [[ "$output" == *"ended"* ]] || { echo "$output"; false; }
}
