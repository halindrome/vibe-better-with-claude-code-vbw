#!/usr/bin/env bats
# R181 (docs/proof.md): slots of a run that is gone come back. A run killed
# outright (its process no longer exists) leaves slots the next run to look at
# the store takes over; a run interrupted with Ctrl-C gives them back at once;
# the store's short lock (slots.lock, holding its owner's pid in slots.lock/pid)
# is taken over when its owner process is gone. When the store cannot be
# written (a read-only folder, or the Claude Code sandbox refusing writes
# outside the project) or is damaged, vbw prove, vbw fix done and vbw check
# still run to the end with only check_jobs as their cap, their results
# unaffected, and say so once, in one plain line naming why; a damaged store
# is left as it is. L1: unit commands log their start and end to $LOG
# (tests/machine-helper.bash).

load helper
load machine-helper

setup() { machine_setup; }

teardown() { machine_teardown; }

@test "R181: the slot of a run killed outright is taken over by the next run" {
  cores 2
  machine_project "$OTHER" B 1 30
  machine_project "$PROJECT" A 1 0 "$(peek_check C2 "$CLAUDE_CONFIG_DIR/vbw/slots.json")"
  local pb
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_starts 1 B-
  kill -KILL "$pb"
  wait "$pb" 2> /dev/null || true
  run within 20 "$VBW" check C2 C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  seen_store
  # A's units ran while the dead run's orphaned command still ran.
  [ -z "$(end_line B-C1)" ] || { echo "A waited for the dead run's command to end"; show; false; }
  # The dead run's slot was taken over for good: nothing is left in the store.
  [ ! -e "$CLAUDE_CONFIG_DIR/vbw/slots.json" ] || { cat "$CLAUDE_CONFIG_DIR/vbw/slots.json"; false; }
}

@test "R181: a run interrupted with Ctrl-C ends and gives its slot back at once" {
  cores 2
  machine_project "$OTHER" B 2 30 "$(peek_check C3 "$CLAUDE_CONFIG_DIR/vbw/slots.json")"
  machine_project "$PROJECT" A 1 0
  local pb i
  # Ctrl-C reaches the whole foreground process group: B runs in a group of its own.
  (cd "$OTHER" && exec perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec { $ARGV[0] } @ARGV or die' "$VBW" check C3 C1 C2) \
    > "$TEST_ROOT/b.out" 2>&1 < /dev/null 3>&- &
  pb=$!
  wait_starts 1 B-
  kill -s INT -- "-$pb"
  for ((i = 0; i < 100; i++)); do kill -0 "$pb" 2> /dev/null || break; sleep 0.1; done
  ! kill -0 "$pb" 2> /dev/null || { echo "vbw still running 10 s after Ctrl-C"; show; false; }
  wait "$pb" 2> /dev/null || true
  seen_store
  # Given back by the interrupted run itself, before any other run looked.
  [ ! -e "$CLAUDE_CONFIG_DIR/vbw/slots.json" ] || { echo "slots left after Ctrl-C:"; cat "$CLAUDE_CONFIG_DIR/vbw/slots.json"; false; }
  run within 20 "$VBW" check C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
}

@test "R181: the store's lock is taken over when its owner process is gone" {
  cores 2
  machine_project "$PROJECT" A 1 0 "$(peek_check C2 "$CLAUDE_CONFIG_DIR/vbw/slots.json")"
  local dead
  sh -c 'exit 0' &
  dead=$!
  wait "$dead"
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw/slots.lock"
  printf '%s\n' "$dead" > "$CLAUDE_CONFIG_DIR/vbw/slots.lock/pid"
  run within 30 "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"C1 pass"* && "$output" != *"computer-wide limit"* ]] || { echo "$output"; false; }
  seen_store
  [ ! -e "$CLAUDE_CONFIG_DIR/vbw/slots.lock" ] || { echo "the lock was left behind"; false; }
}

# unforced KIND OUTPUT: OUTPUT holds exactly one computer-wide limit line, the
# one for KIND (unwritable or damaged), with check_jobs 2.
unforced() {
  local store="$CLAUDE_CONFIG_DIR/vbw/slots.json" want
  case "$1" in
    unwritable) want="vbw: the computer-wide limit was not in force: cannot write $store; this run was limited by check_jobs (2) alone" ;;
    damaged) want="vbw: the computer-wide limit was not in force: $store is damaged (delete it to restore the limit); this run was limited by check_jobs (2) alone" ;;
  esac
  [ "$(printf '%s\n' "$2" | grep -c 'computer-wide limit')" = 1 ] || { echo "not one limit line:"; echo "$2"; return 1; }
  printf '%s\n' "$2" | grep -qxF -- "$want" || { echo "want: $want"; echo "$2"; return 1; }
}

@test "R181: when the store cannot be written, prove, check and fix done run to the end under check_jobs and say so once" {
  [ "$(id -u)" != 0 ] || skip "root writes into a read-only folder"
  cores 4
  machine_project "$PROJECT" A 4 1
  "$VBW" config set check_jobs 2 > /dev/null
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw"
  chmod 555 "$CLAUDE_CONFIG_DIR/vbw"
  # fix done first: a passing proof closes F1, after which fix done has nothing to do.
  run within 120 "$VBW" fix "done" F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  unforced unwritable "$output"
  [[ "$output" == *"F1 fixed"* ]]
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  unforced unwritable "$output"
  [[ "$output" == *"proved"* ]]
  jq -e '.evidence.passed' .vbw/record.json > /dev/null
  [ "$(starts)" = 4 ] && [ "$(peak)" -le 2 ] || { echo "peak $(peak) with check_jobs 2"; show; false; }
  run within 120 "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  unforced unwritable "$output"
  [[ "$output" == *"C4 pass"* ]]
  [ ! -e "$CLAUDE_CONFIG_DIR/vbw/slots.json" ]
}

@test "R181: a damaged store never stops a run: it runs under check_jobs, says so once, and the store is left as it was" {
  cores 4
  machine_project "$PROJECT" A 4 1
  "$VBW" config set check_jobs 2 > /dev/null
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw"
  local store="$CLAUDE_CONFIG_DIR/vbw/slots.json" junk
  for junk in 'not json' '[1, 2]'; do
    printf '%s\n' "$junk" > "$store"
    : > "$LOG"
    run within 120 "$VBW" prove --full < /dev/null
    [ "$status" -eq 0 ] || { echo "$output"; show; false; }
    unforced damaged "$output"
    jq -e '.evidence.passed' .vbw/record.json > /dev/null
    [ "$(starts)" = 4 ] && [ "$(peak)" -le 2 ] || { echo "peak $(peak) with check_jobs 2"; show; false; }
    run within 120 "$VBW" check C1 < /dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    unforced damaged "$output"
    [ "$(cat "$store")" = "$junk" ] || { echo "the damaged store was changed: $(cat "$store")"; false; }
  done
}
