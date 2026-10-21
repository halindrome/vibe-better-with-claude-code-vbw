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
