#!/usr/bin/env bats
# R192, phase P152 (L1): vbw next (action run) and the loop's "a run of another
# session is open" stop name the holder by its display name: the list's current
# name for the lease's session (a /rename during the run shows at once), else the
# name vbw run start stored, else the first 8 characters of the id. The wording
# keeps "another session", "wait" and "vbw status" and never says to end the run.

load helper
load sessions-helper
load loop-helper

teardown() { vbw_teardown; }

as() { local s="$1"; shift; VBW_SESSION_ID="$s" run "$VBW" "$@" < /dev/null; }

fresh() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

@test "R192: vbw next in another session names the holder by name and says to wait" {
  fresh
  registry_entry 101 "$SESSION_A" "Payments work"
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start qa > /dev/null
  as "$SESSION_B" next --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.action == "run" and (.instruction | test("another session")) and (.instruction | test("Payments work")) and (.instruction | test("wait")) and (.instruction | test("vbw status"))'
  echo "$output" | jq -e '.instruction | test("run end|end the run|end it") | not'
  echo "$output" | jq -e --arg s "$SESSION_A" '.instruction | contains($s) | not'
}

@test "R192: a /rename during the run shows at once in vbw next; a closed chat keeps its stored name; no name gives 8 characters of the id" {
  fresh
  registry_entry 101 "$SESSION_A" "Payments work"
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start qa > /dev/null
  registry_entry 101 "$SESSION_A" "Checkout fix" 1792300090000
  as "$SESSION_B" next --json
  echo "$output" | jq -e '.instruction | test("Checkout fix") and (test("Payments work") | not)'
  rm "$(registry_dir)/101.json"
  as "$SESSION_B" next --json
  echo "$output" | jq -e '.instruction | test("Payments work")'
  VBW_SESSION_ID="$SESSION_A" "$VBW" run end > /dev/null
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start qa > /dev/null
  as "$SESSION_B" next --json
  echo "$output" | jq -e --arg s "$SESSION_A" '.instruction | test("01234567") and (contains($s) | not)'
}

@test "R192: a name with escape sequences reaches vbw next clean" {
  fresh
  registry_entry 101 "$SESSION_A" "$(printf 'Pay\033[31mments\007 work')"
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start qa > /dev/null
  as "$SESSION_B" next --json
  echo "$output" | jq -e '.instruction | test("Payments work") and (contains("\u001b") | not) and (contains("\u0007") | not)'
}

@test "R192: a run open in another session stops the loop naming the holder by name" {
  loop_project
  registry_entry 109 s9 "Night shift chat"
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s9 "$VBW" run start qa > /dev/null
  loop_next s1 > "$TEST_ROOT/step.json"
  [ "$(jq -r .action "$TEST_ROOT/step.json")" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  local reason
  reason=$(jq -r .reason "$TEST_ROOT/step.json")
  [[ "$reason" == *"another session"* && "$reason" == *"Night shift chat"* ]] || { echo "$reason"; false; }
}
