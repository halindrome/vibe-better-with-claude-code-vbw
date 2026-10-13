#!/usr/bin/env bats
# R181 (docs/proof.md): a run of vbw prove, vbw fix done or vbw check whose
# units waited for a computer-wide slot ends its output with one line naming
# the total time they waited and the limit:
#   waited N s for other VBW runs on this computer (limit L of C cores)
# (under a minute the time is in seconds; with an unreadable core count the
# parenthesis reads "(limit 1, as this computer's core count could not be
# read)"). A run that never waited prints no such line, so the output of an
# unshared run is unchanged. L1: another project holds the only slot (2 cores:
# limit 1) while the run starts (tests/machine-helper.bash).

load helper
load machine-helper

setup() { machine_setup; }

teardown() { machine_teardown; }

WAITED_RE='^waited ([0-9]+) s for other VBW runs on this computer \(limit 1 of 2 cores\)$'

# hold SECONDS: project B holds the only slot for SECONDS; HOLDER is its vbw.
hold() {
  machine_project "$OTHER" B 1 "$1"
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  HOLDER=$BG_PID
  wait_starts 1 B-
}

# last_lines OUTPUT: its last two lines, in WAITED (the last) and BEFORE.
last_lines() {
  WAITED=$(printf '%s\n' "$1" | tail -n 1)
  BEFORE=$(printf '%s\n' "$1" | tail -n 2 | head -n 1)
}

# waited_ok MIN MAX [RE]: the last line matches RE (default WAITED_RE), its time from MIN to MAX seconds.
waited_ok() {
  local re="${3:-$WAITED_RE}"
  [[ "$WAITED" =~ $re ]] || { echo "last line: $WAITED"; return 1; }
  [ "${BASH_REMATCH[1]}" -ge "$1" ] && [ "${BASH_REMATCH[1]}" -le "$2" ] || { echo "waited ${BASH_REMATCH[1]} s, want $1 to $2"; return 1; }
}

@test "R181: vbw prove whose unit waited ends with the waited line, after its verdict" {
  cores 2
  machine_project "$PROJECT" A 1 0
  hold 5
  run within 60 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 || { echo "$output"; false; }
  [ "$BEFORE" = proved ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'for other VBW runs')" = 1 ]
  wait_ok "$HOLDER"
}

@test "R181: vbw check whose unit waited ends with the waited line, after its results" {
  cores 2
  machine_project "$PROJECT" A 1 0
  hold 5
  run within 60 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 || { echo "$output"; false; }
  [[ "$BEFORE" == "C1 pass "* ]] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R181: vbw fix done whose unit waited ends with the waited line, after its fixes" {
  cores 2
  machine_project "$PROJECT" A 1 0
  hold 5
  run within 60 "$VBW" fix "done" F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 || { echo "$output"; false; }
  [ "$BEFORE" = "F1 fixed: vbw prove decides" ] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R181: with an unreadable core count the waited line names limit 1 and why" {
  cores none
  machine_project "$PROJECT" A 1 0
  hold 5
  run within 60 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  last_lines "$output"
  waited_ok 1 15 "^waited ([0-9]+) s for other VBW runs on this computer \\(limit 1, as this computer's core count could not be read\\)\$" || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R181: a run that never waited prints no waited line: prove, check and fix done output is unchanged" {
  cores 4
  machine_project "$PROJECT" A 2 0 "$(peek_check C3 "$CLAUDE_CONFIG_DIR/vbw/slots.json")"
  run within 60 "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed 's/ [0-9]*s$/ Ns/')" = "$(printf 'C1 pass Ns\nC2 pass Ns\nC3 pass Ns')" ] || { echo "$output"; false; }
  run within 60 "$VBW" fix "done" F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"for other VBW runs"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "F1 fixed: vbw prove decides" ] || { echo "$output"; false; }
  run within 60 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"for other VBW runs"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = proved ] || { echo "$output"; false; }
  # The store was in force (a unit saw it), and still nothing was said.
  seen_store
}
