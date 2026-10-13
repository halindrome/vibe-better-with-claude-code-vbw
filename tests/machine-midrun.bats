#!/usr/bin/env bats
# R181 (docs/proof.md): the computer-wide limit lost in the middle of a run is
# never lost silently. A store that is damaged or unwritable after the run has
# started (a unit of the run, or another process, did it) lets the run go on
# under check_jobs alone and is told once, in one plain line, at the end of the
# command, also when a parallel runner (a subshell with hidden stderr) found it.
# A store lock held by a live process is waited for with no end: a live owner is
# not an error, and no unit runs without its slot meanwhile. L1: unit commands
# log their start and end to $LOG (tests/machine-helper.bash).

bats_require_minimum_version 1.5.0
load helper
load machine-helper

setup() { machine_setup; }

teardown() { machine_teardown; }

# damage_check ID MODE: a check of R1 that breaks the store it holds a slot in.
damage_check() {
  local store="$CLAUDE_CONFIG_DIR/vbw/slots.json" cmd
  case "$2" in
    junk) cmd="printf 'not json\\n' > '$store'" ;;
    readonly) cmd="chmod 555 '$CLAUDE_CONFIG_DIR/vbw'" ;;
  esac
  jq -nc --arg id "$1" --arg c "$cmd" '[{id: $id, req: "R1", run: ["sh", "-c", $c], files: []}]'
}

@test "R181: a store damaged after the run started is told once at the end, in check, prove and fix done" {
  [ "$(id -u)" != 0 ] || skip "root writes into a read-only folder"
  local mode kind
  for mode in junk readonly; do
    for kind in check prove fix; do
      cores 2
      machine_project "$PROJECT" A 3 0 "$(damage_check C0 "$mode")"
      "$VBW" config set check_jobs 2 > /dev/null
      case "$kind" in
        check) run within 60 "$VBW" check C0 C1 C2 C3 < /dev/null ;;
        prove) run within 60 "$VBW" prove --full < /dev/null ;;
        fix) run within 60 "$VBW" fix "done" F1 < /dev/null ;;
      esac
      [ "$status" -eq 0 ] || { echo "$mode $kind: $output"; show; false; }
      [ "$(printf '%s\n' "$output" | grep -c 'computer-wide limit was not in force')" = 1 ] || { echo "$mode $kind: not one limit line:"; echo "$output"; false; }
      chmod -R u+rwx "$CLAUDE_CONFIG_DIR" 2> /dev/null || true
      cd "$TEST_ROOT" && rm -rf "$PROJECT" "$CLAUDE_CONFIG_DIR/vbw" && mkdir -p "$PROJECT" && cd "$PROJECT"
      : > "$LOG"
    done
  done
}

@test "R181: the lost-limit line has its exact wording, on stderr, once, with the real check_jobs, in check, prove and fix done" {
  [ "$(id -u)" != 0 ] || skip "root writes into a read-only folder"
  local mode kind store="$CLAUDE_CONFIG_DIR/vbw/slots.json" why want
  for mode in junk readonly; do
    case "$mode" in
      junk) why="$store is damaged (delete it to restore the limit)" ;;
      readonly) why="cannot write $store" ;;
    esac
    want="vbw: the computer-wide limit was not in force: $why; this run was limited by check_jobs (2) alone from then on"
    for kind in check prove fix; do
      cores 2
      machine_project "$PROJECT" A 3 0 "$(damage_check C0 "$mode")"
      "$VBW" config set check_jobs 2 > /dev/null
      case "$kind" in
        check) run --separate-stderr within 60 "$VBW" check C0 C1 C2 C3 < /dev/null ;;
        prove) run --separate-stderr within 60 "$VBW" prove --full < /dev/null ;;
        fix) run --separate-stderr within 60 "$VBW" fix "done" F1 < /dev/null ;;
      esac
      [ "$status" -eq 0 ] || { echo "$mode $kind: $output $stderr"; show; false; }
      [ "$(printf '%s\n' "$stderr" | grep -cxF "$want")" = 1 ] || { echo "$mode $kind: wanted on stderr: $want"; echo "stderr: $stderr"; false; }
      ! printf '%s\n' "$output" | grep -q 'computer-wide limit was not in force' || { echo "$mode $kind: line on stdout"; false; }
      chmod -R u+rwx "$CLAUDE_CONFIG_DIR" 2> /dev/null || true
      cd "$TEST_ROOT" && rm -rf "$PROJECT" "$CLAUDE_CONFIG_DIR/vbw" && mkdir -p "$PROJECT" && cd "$PROJECT"
      : > "$LOG"
    done
  done
}

@test "R181: a store lock held by a live process for over 30 s is waited for, never skipped" {
  cores 2
  machine_project "$PROJECT" A 1 0
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw/slots.lock"
  sleep 120 &
  local holder=$! pb
  printf '%s\n' "$holder" > "$CLAUDE_CONFIG_DIR/vbw/slots.lock/pid"
  bg "$PROJECT" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  sleep 33
  kill -0 "$pb" 2> /dev/null || { echo "the run ended while the lock's owner lived:"; cat "$TEST_ROOT/b.out"; false; }
  [ "$(starts)" = 0 ] || { echo "a unit ran without a slot"; show; false; }
  kill "$holder"
  wait "$holder" 2> /dev/null || true
  wait "$pb" || { cat "$TEST_ROOT/b.out"; false; }
  [ "$(starts)" = 1 ]
  ! grep -q 'computer-wide limit was not in force' "$TEST_ROOT/b.out"
}
