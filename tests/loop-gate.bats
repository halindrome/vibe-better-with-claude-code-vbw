#!/usr/bin/env bats
# R179 (P128; docs/loop.md): the Stop hook gate (vbw auto gate) drives the
# cycle in the loop's own session. While a loop is on in this session, the
# gate blocks the stop with the next loop step (as the autonomous gate does
# today), never counts the loop's steps against settings.autonomy_cap, asks for
# nothing while this session's proof runs in the background, and lets the
# session stop once the loop reports done or stopped. In any other session the
# gate ignores the loop. L1.

load helper
load loop-helper

setup() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
}
teardown() {
  [ -z "${BG_PID:-}" ] || kill "$BG_PID" 2> /dev/null || true
  vbw_teardown
}

# gate SESSION: what the Stop hook prints for that session.
gate() { jq -nc --arg s "$1" '{hook_event_name: "Stop", session_id: $s, stop_hook_active: false}' | "$VBW" auto gate; }

@test "R179: in the loop's session the gate blocks the stop with the next loop step and never spends an autonomy step" {
  "$VBW" config set autonomy_cap 1 > /dev/null
  run gate s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.decision == "block" and (.reason | startswith("VBW loop")) and (.reason | test("T1")) and (.reason | test("plan")) and (.reason | test("/vbw:vibe")) and (has("systemMessage") | not)' \
    || { echo "$output"; false; }
  # The step was taken: the item's milestone is open.
  jq -e '.milestone.title == "Visitors can read a greeting"' .vbw/record.json
  [ ! -f .vbw/runtime/auto.s1.json ]
  # Even with the autonomous gate armed in the same session, the loop's steps are not counted against the cap.
  "$VBW" auto on s1 > /dev/null
  run gate s1
  printf '%s' "$output" | jq -e '.decision == "block" and (.reason | startswith("VBW loop"))' || { echo "$output"; false; }
  run gate s1
  printf '%s' "$output" | jq -e '.decision == "block" and (.reason | test("autonomy_cap") | not)' || { echo "$output"; false; }
  [ "$(jq -r .steps .vbw/runtime/auto.s1.json)" = 0 ]
}

@test "R179: while this session's proof runs in the background the gate asks for nothing" {
  sleep 30 &
  BG_PID=$!
  printf '%s\n' "$BG_PID" > .vbw/runtime/proving.s1
  run gate s1
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  jq -e '.milestone.title == "Next"' .vbw/record.json
}

@test "R179: once the loop reports stopped or done the gate lets the session stop, with one message, then nothing" {
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  run gate s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '(.systemMessage | test("VBW loop")) and (.systemMessage | test("stopped by the user")) and (has("decision") | not)' || { echo "$output"; false; }
  jq -e '.loop.ended != null' .vbw/record.json
  run gate s1
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R179: in any other session the gate ignores the loop" {
  local before
  before=$(record_sum)
  run gate s9
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
  [ "$(record_sum)" = "$before" ]
  # Today's autonomous gate still works there, and takes no loop step.
  "$VBW" auto on s9 > /dev/null
  run gate s9
  printf '%s' "$output" | jq -e 'has("decision") or has("systemMessage")' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.. | strings] | any(test("VBW loop")) | not' || { echo "$output"; false; }
  jq -e '.milestone.title == "Next" and .loop.items[0].status == "waiting"' .vbw/record.json
}

@test "R179 (F171): the gate hands its own session to the loop step: a run this session opened is its own, and the loop goes on" {
  run gate s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  run gate s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.ended == null' .vbw/record.json || { echo "$output"; jq .loop.ended .vbw/record.json; false; }
  [[ "$output" != *"another session"* ]] || { echo "$output"; false; }
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
}
