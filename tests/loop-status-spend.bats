#!/usr/bin/env bats
# R178 (P127; docs/loop.md): vbw loop status shows the loop's spend so far (the
# sum over known sessions of the current figures minus the loop's baseline,
# computed the way a milestone's total is: a session first seen later counts
# from its first figure, a figure that fell below its baseline counts whole),
# the ceiling, and one word: under, reached, or cannot tell (no figure seen).
# cannot tell counts as reached for the stop rule unless the loop runs with
# --no-ceiling. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

loop_json() { "$VBW" loop status --json < /dev/null; }

@test "R178: the spend is the sum over known sessions of the current figures minus the baseline, like a milestone's total" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 > /dev/null
  figures s1 2.5 1200 130
  loop_json | jq -e '.spend == {usd: 0.5, in: 200, out: 30, sessions: 1} and .word == "under"' || { loop_json; false; }
  run "$VBW" loop status
  [[ "$output" == *'$0.50'* ]] && [[ "$output" == *"under"* ]] && [[ "$output" == *'$5'* ]] || { echo "$output"; false; }
  # A session first seen after the start counts from its first figure, whole.
  figures s2 1 500 50
  loop_json | jq -e '.spend == {usd: 1.5, in: 700, out: 80, sessions: 2} and .word == "under"' || { loop_json; false; }
  # A figure that fell below its baseline (a restarted session) counts whole.
  figures s1 1.5 600 60
  loop_json | jq -e '.spend.usd == 2.5 and .spend.in == 1100 and .word == "under"' || { loop_json; false; }
}

@test "R178: at or above the ceiling the word is reached" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  figures s1 7 3000 300
  loop_json | jq -e '.spend.usd == 5 and .word == "reached"' || { loop_json; false; }
  run "$VBW" loop status
  [[ "$output" == *"reached"* ]] && [[ "$output" == *'$5.00'* ]] || { echo "$output"; false; }
  figures s1 9 3000 300
  loop_json | jq -e '.word == "reached"'
}

@test "R178: with no figure seen the word is cannot tell, which counts as reached under a ceiling" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  no_figures
  loop_json | jq -e '.spend == null and .word == "cannot tell"' || { loop_json; false; }
  run "$VBW" loop status
  [[ "$output" == *"cannot tell"* ]] && [[ "$output" == *"reached"* ]] && [[ "$output" == *"vbw statusline on"* ]] || { echo "$output"; false; }
}

@test "R178: with --no-ceiling the status shows the spend or cannot tell, and no ceiling to compare with" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  figures s1 3 1500 150
  loop_json | jq -e '.spend.usd == 1 and .ceiling == null and .word == null' || { loop_json; false; }
  run "$VBW" loop status
  [[ "$output" == *'$1.00'* ]] && [[ "$output" != *"reached"* ]] && [[ "$output" != *"under"* ]] || { echo "$output"; false; }
  no_figures
  run "$VBW" loop status
  [[ "$output" == *"cannot tell"* ]] && [[ "$output" != *"reached"* ]] || { echo "$output"; false; }
}

@test "R178: status with no loop says so and exits 0" {
  run "$VBW" loop status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"no loop"* ]] || { echo "$output"; false; }
  "$VBW" loop status --json < /dev/null | jq -e '.on == false'
}
