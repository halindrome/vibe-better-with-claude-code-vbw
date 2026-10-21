#!/usr/bin/env bats
# R181 (docs/proof.md): the computer-wide limit lost in the middle of a run is
# never lost silently. A store that is damaged or unwritable after the run has
# started (a unit of the run, or another process, did it) lets the run go on
# under check_jobs alone and is told once, in one plain line, at the end of the
# command, also when a parallel runner (a subshell with hidden stderr) found it.
# A store lock held by a live process is waited for with no end: a live owner is
# not an error, and no unit runs without its slot meanwhile. L1: unit commands
# log their start and end to $LOG (tests/machine-helper.bash). The projects are
# built once per file (setup_file) and copied for each test, and for each
# round of the damage tests.

bats_require_minimum_version 1.5.0
load helper
load machine-helper
load fixture-helper

teardown() { machine_teardown; }

# damage_check ID MODE: a check of R1 that breaks the store it holds a slot in.
# The check's shell reads CLAUDE_CONFIG_DIR when it runs (a check's command
# inherits the environment), so the record names no folder of the test and a
# copy of the project damages its own test's store.
damage_check() {
  local cmd
  # shellcheck disable=SC2016 # expanded by the check's shell
  case "$2" in
    junk) cmd='printf '\''not json\n'\'' > "$CLAUDE_CONFIG_DIR/vbw/slots.json"' ;;
    readonly) cmd='chmod 555 "$CLAUDE_CONFIG_DIR/vbw"' ;;
  esac
  jq -nc --arg id "$1" --arg c "$cmd" '[{id: $id, req: "R1", run: ["sh", "-c", $c], files: []}]'
}

# damaged MODE: the project of the damage tests, on 2 cores, whose check C0
# breaks the store (damage_check), with check_jobs 2. For fixture_build.
damaged() {
  machine_setup
  cores 2
  machine_project "$PROJECT" A 3 0 "$(damage_check C0 "$1")"
  "$VBW" config set check_jobs 2 > /dev/null
}

# one_check: a project of one check, on 2 cores. For fixture_build.
one_check() {
  machine_setup
  cores 2
  machine_project "$PROJECT" A 1 0
}

setup_file() {
  fixture_build junk damaged junk
  fixture_build readonly damaged readonly
  fixture_build one one_check
}
setup() { fixture_copy one; }
teardown_file() { fixture_teardown; }

@test "R181: a store damaged after the run started is told once at the end, in check, prove and fix done" {
  [ "$(id -u)" != 0 ] || skip "root writes into a read-only folder"
  local mode kind
  for mode in junk readonly; do
    for kind in check prove fix; do
      fixture_copy "$mode"
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
  local mode kind store why want
  for mode in junk readonly; do
    for kind in check prove fix; do
      # Each copy is a test folder of its own: the store's path is taken from it.
      fixture_copy "$mode"
      store="$CLAUDE_CONFIG_DIR/vbw/slots.json"
      case "$mode" in
        junk) why="$store is damaged (delete it to restore the limit)" ;;
        readonly) why="cannot write $store" ;;
      esac
      want="vbw: the computer-wide limit was not in force: $why; this run was limited by check_jobs (2) alone from then on"
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
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw/slots.lock"
  sleep 120 &
  local holder=$! pb
  printf '%s\n' "$holder" > "$CLAUDE_CONFIG_DIR/vbw/slots.lock/pid"
  bg "$PROJECT" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  # Over 30 s on the kernel's own clock: each try of slots_lock sleeps 0.05 s,
  # and a lock with no live owner is given up after 600 tries (30 s). Here
  # slots_lock runs with sleep counted instead of slept, on a lock of its own
  # held by the same live process: it is still waiting after 700 tries (35 s),
  # never takes the lock from its owner, and takes it once the lock is free.
  # Meanwhile the run above waits on the real store's lock.
  mkdir -p "$TEST_ROOT/store/slots.lock"
  printf '%s\n' "$holder" > "$TEST_ROOT/store/slots.lock/pid"
  # shellcheck disable=SC2016 # expanded by the inner bash
  run bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"; . "$VBW_LIB/slots.sh"
    SLOTS_DIR=$2 live=$3 tries=0
    sleep() {
      local p=
      tries=$((tries + 1))
      IFS= read -r p < "$SLOTS_DIR/slots.lock/pid" || true
      [ "$p" = "$live" ] || { echo "the lock was taken from its live owner at try $tries"; exit 1; }
      [ "$tries" -lt 700 ] || rm -rf "$SLOTS_DIR/slots.lock"
    }
    slots_lock && rc=0 || rc=$?
    [ "$rc" -eq 0 ] || { echo "slots_lock gave up after $tries tries (exit $rc)"; exit 1; }
    echo "locked after $tries tries"' _ "$PLUGIN_ROOT" "$TEST_ROOT/store" "$holder"
  [ "$status" -eq 0 ] && [ "$output" = "locked after 700 tries" ] || { echo "$output"; false; }
  kill -0 "$pb" 2> /dev/null || { echo "the run ended while the lock's owner lived:"; cat "$TEST_ROOT/b.out"; false; }
  [ "$(starts)" = 0 ] || { echo "a unit ran without a slot"; show; false; }
  kill "$holder"
  wait "$holder" 2> /dev/null || true
  wait "$pb" || { cat "$TEST_ROOT/b.out"; false; }
  [ "$(starts)" = 1 ]
  ! grep -q 'computer-wide limit was not in force' "$TEST_ROOT/b.out"
}
