#!/usr/bin/env bats
# R181 (docs/proof.md): every unit of vbw prove, vbw fix done and vbw check (a
# check, a project command, a test file) takes one slot of the computer-wide
# store for as long as its command runs, and gives it back when the command
# ends, passes, fails or times out (D340: one slot per unit). Across projects
# and commands, never more unit commands run at once than the machine limit;
# check_jobs stays a per-run cap below it and never lifts a run above it. L1:
# unit commands log their start and end to $LOG (tests/machine-helper.bash).
# The project two tests share is built once per file (setup_file) and copied;
# the core count is read when a run starts, so each test sets it after the copy.
# The store's own steps (R181, T141) are driven in bash processes of their own
# (in_store): the lock's takeover, a lock that cannot be made, and a store lost
# or a wait met after the run's folder has ended.

load helper
load machine-helper
load fixture-helper

# six_checks: a project of six checks of 1 s. For fixture_build.
six_checks() {
  machine_setup
  machine_project "$PROJECT" A 6 1
}

setup_file() {
  fixture_build base machine_setup
  fixture_build six six_checks
}
setup() { fixture_copy base; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

@test "R181: two projects each proving 6 units, plus a vbw fix done in one of them, never run more than 3 at once with 4 cores" {
  fixture_copy six
  cores 4
  machine_project "$OTHER" B 6 1
  local p1 p2 p3
  bg "$PROJECT" "$TEST_ROOT/a.out" prove
  p1=$BG_PID
  bg "$OTHER" "$TEST_ROOT/b.out" prove
  p2=$BG_PID
  bg "$PROJECT" "$TEST_ROOT/f.out" fix "done" F1
  p3=$BG_PID
  wait_ok "$p1" "$p2" "$p3" || { show; false; }
  [ "$(starts)" = 18 ] || { echo "$(starts) units started, want 18"; show; false; }
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with 4 cores (limit 3)"; show; false; }
}

@test "R181: a run with check_jobs 2 never runs more than 2 units at once, even with free slots" {
  fixture_copy six
  cores 8
  "$VBW" config set check_jobs 2 > /dev/null
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [ "$(starts)" = 6 ]
  [ "$(peak)" -le 2 ] || { echo "peak $(peak) with check_jobs 2"; show; false; }
}

@test "R181: a check_jobs above the machine limit never lifts a proof above it" {
  cores 4
  machine_project "$PROJECT" A 8 1
  "$VBW" config set check_jobs 8 > /dev/null
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [ "$(starts)" = 8 ]
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with check_jobs 8 and 4 cores (limit 3)"; show; false; }
}

@test "R181: project commands and test files take a slot like checks: at limit 1, nothing of another project runs beside them" {
  cores 2
  mkdir -p "$PROJECT/tests"
  printf 'exec sh tests/unit.sh A-t_1 1 0\n' > "$PROJECT/tests/t_1.sh"
  printf 'exec sh tests/unit.sh A-t_2 1 0\n' > "$PROJECT/tests/t_2.sh"
  SPEC_MORE=$'\n## Commands\n\n- test: sh tests/unit.sh A-test 1 0\n- lint: sh tests/unit.sh A-lint 1 0\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' \
    machine_project "$PROJECT" A 1 1
  machine_project "$OTHER" B 3 1
  local pa pb
  bg "$PROJECT" "$TEST_ROOT/a.out" prove
  pa=$BG_PID
  bg "$OTHER" "$TEST_ROOT/b.out" check
  pb=$BG_PID
  wait_ok "$pa" "$pb" || { show; false; }
  [ -n "$(start_line A-lint)" ] && [ -n "$(start_line A-t_1)" ] && [ -n "$(start_line A-t_2)" ] || { echo "a command or test file did not run"; show; false; }
  [ "$(starts B-)" = 3 ] || { show; false; }
  [ "$(peak)" = 1 ] || { echo "peak $(peak) with 2 cores (limit 1)"; show; false; }
}

@test "R181: a unit gives its slot back when it fails or times out, so later units and runs are not held up" {
  cores 2
  machine_project "$PROJECT" A 0 0 "$(jq -c --argjson p "$(peek_check C4 "$CLAUDE_CONFIG_DIR/vbw/slots.json")" '. + $p' << 'JSON'
[{"id": "C1", "req": "R1", "run": ["sh", "tests/unit.sh", "A-fail", "0", "1"], "files": ["tests/unit.sh"]},
 {"id": "C2", "req": "R1", "run": ["sh", "tests/unit.sh", "A-slow", "30", "0"], "files": ["tests/unit.sh"], "timeout": 1},
 {"id": "C3", "req": "R1", "run": ["sh", "tests/unit.sh", "A-ok", "0", "0"], "files": ["tests/unit.sh"]}]
JSON
)"
  run within 60 "$VBW" check C1 C2 C3 < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; show; false; }
  [[ "$output" == *"C1 fail"* && "$output" == *"C2 timeout"* && "$output" == *"C3 pass"* ]] || { echo "$output"; false; }
  # The next run finds the only slot free, though the timed-out command may still be ending.
  run within 20 "$VBW" check C3 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  run within 20 "$VBW" check C1 < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  run within 20 "$VBW" check C3 C4 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  seen_store
  # Every slot came back: no run holds or waits for one, so no store is left.
  [ ! -e "$CLAUDE_CONFIG_DIR/vbw/slots.json" ] || { cat "$CLAUDE_CONFIG_DIR/vbw/slots.json"; false; }
}

# in_store BODY [ARG...]: BODY run (stopped after 60 s) by a bash process of its
# own, so a run of its own ($$), with the slot store in $TEST_ROOT/store (limit 1,
# state on) and a run folder CHECK_OUT in $TEST_ROOT/run (made, unless a test removes it).
in_store() {
  local body="$1"
  shift
  mkdir -p "$TEST_ROOT/store" "$TEST_ROOT/run"
  # shellcheck disable=SC2016 # expanded by the inner bash
  run within 60 bash -c 'VBW_LIB="$PLUGIN_ROOT/lib"; . "$VBW_LIB/core.sh"; . "$VBW_LIB/record.sh"; . "$VBW_LIB/slots.sh"
    SLOTS_DIR="$TEST_ROOT/store" SLOTS_FILE="$TEST_ROOT/store/slots.json" SLOTS_LIMIT=1 SLOTS_STATE=on CHECK_OUT="$TEST_ROOT/run"
    body=$1; shift; eval "$body"' _ "$body" "$@"
}

# gone_pid: GONE is the id of a process that has ended.
gone_pid() {
  sh -c 'exit 0' &
  GONE=$!
  wait "$GONE"
}

@test "T141: a lock whose dead owner two runs find is never taken from the run that took it over first" {
  gone_pid
  sleep 120 &
  local live=$!
  mkdir -p "$TEST_ROOT/store/slots.lock"
  printf '%s\n' "$GONE" > "$TEST_ROOT/store/slots.lock/pid"
  # The other run takes the lock over while this one is still judging its owner gone,
  # and holds it. This run must wait for it, and never hold the lock beside it.
  # shellcheck disable=SC2016 # expanded by in_store
  in_store 'dead=$1 live=$2 tries=0 fired=
    slots_live() {
      if [ "$1" = "$dead" ] && [ -z "$fired" ]; then
        fired=1
        rm -rf "$SLOTS_DIR/slots.lock"; mkdir "$SLOTS_DIR/slots.lock"; printf "%s\n" "$live" > "$SLOTS_DIR/slots.lock/pid"
      fi
      [ "$1" != "$dead" ] && kill -0 "$1" 2> /dev/null
    }
    sleep() {
      local p=
      tries=$((tries + 1))
      { IFS= read -r p < "$SLOTS_DIR/slots.lock/pid"; } 2> /dev/null || true
      [ "$p" = "$live" ] || { echo "the run that held the lock lost it at try $tries"; exit 1; }
      [ "$tries" -lt 3 ] || rm -rf "$SLOTS_DIR/slots.lock"
    }
    slots_lock || { echo "slots_lock failed ($?)"; exit 1; }
    [ "$tries" -gt 0 ] || { echo "the lock was taken beside the run that held it"; exit 1; }
    echo "locked after $tries tries"' "$GONE" "$live"
  kill "$live"
  wait "$live" 2> /dev/null || true
  [ "$status" -eq 0 ] && [ "$output" = "locked after 3 tries" ] || { echo "$output"; false; }
}

@test "T141: a lock left by a dead owner, as a file or as the folder an older VBW made, is taken over" {
  gone_pid
  local form
  for form in file folder; do
    rm -rf "$TEST_ROOT/store"
    mkdir -p "$TEST_ROOT/store"
    if [ "$form" = file ]; then
      printf '%s\n' "$GONE" > "$TEST_ROOT/store/slots.lock"
    else
      mkdir "$TEST_ROOT/store/slots.lock"
      printf '%s\n' "$GONE" > "$TEST_ROOT/store/slots.lock/pid"
    fi
    # shellcheck disable=SC2016 # expanded by in_store
    in_store 'slots_lock || { echo "slots_lock failed ($?)"; exit 1; }
      slots_unlock
      [ ! -e "$SLOTS_DIR/slots.lock" ] || { echo "the lock was left behind"; exit 1; }
      echo taken'
    [ "$status" -eq 0 ] && [ "$output" = taken ] || { echo "$form: $output"; false; }
  done
}

@test "T141: a lock that cannot be made while the folder reports writable is told at once" {
  # A full disk or a sandbox: the folder answers "writable", every new file fails.
  # shellcheck disable=SC2016 # expanded by in_store
  in_store 'tries=0
    sleep() { tries=$((tries + 1)); [ "$tries" -lt 700 ] || { echo "still trying after $tries tries"; exit 1; }; }
    vbw_lock_create() { return 1; }
    [ -w "$SLOTS_DIR" ] || { echo "the folder does not report writable"; exit 1; }
    slots_lock && rc=0 || rc=$?
    echo "exit $rc after $tries tries"'
  [ "$status" -eq 0 ] && [ "$output" = "exit 2 after 0 tries" ] || { echo "$output"; false; }
}

@test "T141: a store lost after the run's folder has ended is told once, by the command's own shell" {
  [ "$(id -u)" != 0 ] || skip "root writes into a read-only folder"
  # The save at the end of a proof comes after the run's folder is removed: the
  # lost-limit marker has no folder to be written in.
  # shellcheck disable=SC2016 # expanded by in_store
  in_store 'rm -rf "$CHECK_OUT"
    chmod 555 "$SLOTS_DIR"
    slots_hold vbw:save && echo held || echo "no slot"
    slots_total
    slots_say 2>&1
    slots_say 2>&1'
  chmod -R u+rwx "$TEST_ROOT/store"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'computer-wide limit was not in force: cannot write')" = 1 ] || { echo "$output"; false; }
  [[ "$output" == "no slot"* ]] || { echo "$output"; false; }
}

@test "T141: waits in the run's folder and after it ended are added up and told once" {
  # shellcheck disable=SC2016 # expanded by in_store
  in_store 'slots_waited $(($(date +%s) - 30))
    slots_total
    rm -rf "$CHECK_OUT"
    slots_waited $(($(date +%s) - 40))
    slots_say 2>&1
    slots_say 2>&1'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "waited 1 min for other VBW runs on this computer ("* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'waited')" = 1 ] || { echo "$output"; false; }
}
