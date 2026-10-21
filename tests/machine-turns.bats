#!/usr/bin/env bats
# R181 (docs/proof.md, D339): runs take equal turns at the computer-wide limit.
# A freed slot goes to the waiting run that holds the fewest slots; between
# runs holding the same number, to the one that has waited longest. A check
# marked alone keeps its per-project meaning (R45) and takes one machine slot;
# a unit passes its project's gate before it asks for a machine slot, so two
# projects never block each other. A vbw run started inside a unit's command,
# on the same store, takes no slot of its own (the unit's slot covers it, D340)
# and never waits for its parent. Waiting changes no result: a unit's timeout
# counts from its command's start. L1: unit commands log their start and end
# to $LOG (tests/machine-helper.bash). Project B of one quick check, which
# three tests share, is built once per file (setup_file) and copied; the core
# count is read when a run starts, so each test sets it after the copy.

load helper
load machine-helper
load fixture-helper

# other_one: project B of one quick check. For fixture_build.
other_one() {
  machine_setup
  machine_project "$OTHER" B 1 0
}

setup_file() {
  fixture_build base machine_setup
  fixture_build b other_one
}
setup() { fixture_copy base; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

@test "R181: a freed slot goes to the waiting run holding the fewest: B's one unit starts before A's fourth" {
  fixture_copy b
  cores 4
  machine_project "$PROJECT" A 6 6
  (cd "$PROJECT" && "$VBW" config set check_jobs 6 > /dev/null)
  local pa pb
  bg "$PROJECT" "$TEST_ROOT/a.out" check
  pa=$BG_PID
  wait_starts 3 A-
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_in_store "$pb" || { show; false; }
  [ -z "$(end_line A-C1)$(end_line A-C2)$(end_line A-C3)" ] || { echo "A's units ended before B was waiting: the machine is too slow for this test"; show; false; }
  wait_ok "$pa" "$pb" || { show; false; }
  [ "$(starts A-)" = 6 ] && [ "$(starts B-)" = 1 ] || { show; false; }
  [ "$(start_line B-C1)" -lt "$(nth_start 4 A-)" ] || { echo "A's fourth unit started before B's only unit"; show; false; }
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with 4 cores (limit 3)"; show; false; }
}

@test "R181: between waiting runs holding the same number of slots, the one that waited longest goes first" {
  fixture_copy b
  cores 2
  machine_project "$PROJECT" A 1 8
  machine_project "$THIRD" T 1 0
  local pa pb pt
  bg "$PROJECT" "$TEST_ROOT/a.out" check C1
  pa=$BG_PID
  wait_starts 1 A-
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_in_store "$pb" || { show; false; }
  bg "$THIRD" "$TEST_ROOT/t.out" check C1
  pt=$BG_PID
  wait_ok "$pa" "$pb" "$pt" || { show; false; }
  [ "$(end_line A-C1)" -lt "$(start_line B-C1)" ] || { echo "B did not wait for the only slot"; show; false; }
  [ "$(start_line B-C1)" -lt "$(start_line T-C1)" ] || { echo "T, which waited less, went first"; show; false; }
  [ "$(peak)" = 1 ] || { echo "peak $(peak) with 2 cores (limit 1)"; show; false; }
}

@test "R181: an alone check in one project and shared checks in another both finish at limit 1, the alone one still by itself in its project" {
  cores 2
  machine_project "$PROJECT" A 2 1 '[{"id": "C3", "req": "R1", "run": ["sh", "tests/unit.sh", "A-alone", "1", "0"], "files": ["tests/unit.sh"], "alone": true}]'
  machine_project "$OTHER" B 3 1
  local pa pb pc
  bg "$PROJECT" "$TEST_ROOT/a.out" check
  pa=$BG_PID
  bg "$OTHER" "$TEST_ROOT/b.out" check
  pb=$BG_PID
  bg "$PROJECT" "$TEST_ROOT/c.out" check C3
  pc=$BG_PID
  wait_ok "$pa" "$pb" "$pc" || { show; false; }
  [ "$(starts A-)" = 4 ] && [ "$(starts B-)" = 3 ] || { show; false; }
  [ "$(peak)" = 1 ] || { echo "peak $(peak) with 2 cores (limit 1)"; show; false; }
}

@test "R181: a vbw run inside a unit's command, on the same store, takes no slot of its own and never waits for its parent" {
  fixture_copy b
  cores 2
  mkdir -p "$PROJECT/tests"
  printf 'cd "$OTHER" && "$VBW" check C1\n' > "$PROJECT/tests/nested.sh"
  machine_project "$PROJECT" A 0 0 "$(jq -c --argjson p "$(peek_check C2 "$CLAUDE_CONFIG_DIR/vbw/slots.json")" '. + $p' << 'JSON'
[{"id": "C1", "req": "R1", "run": ["sh", "tests/nested.sh"], "files": ["tests/nested.sh"]}]
JSON
)"
  run within 60 "$VBW" check C2 C1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [[ "$output" == *"C1 pass"* ]]
  [ "$(starts B-)" = 1 ]
  seen_store
}

@test "R181: a unit that waited reports what it would alone, and its timeout counts from its command's start" {
  cores 2
  machine_project "$OTHER" B 1 6
  machine_project "$PROJECT" A 0 0 '[{"id": "C1", "req": "R1", "run": ["sh", "tests/unit.sh", "A-ok", "1", "0"], "files": ["tests/unit.sh"], "timeout": 3},
    {"id": "C2", "req": "R1", "run": ["sh", "tests/unit.sh", "A-bad", "0", "3"], "files": ["tests/unit.sh"]}]'
  local alone shared pb
  run within 60 "$VBW" prove --full < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  alone=$(jq -c '.evidence.checks | map_values({status, exit, tail})' .vbw/record.json)
  [ "$alone" = '{"C1":{"status":"pass","exit":0,"tail":"unit A-ok done"},"C2":{"status":"fail","exit":3,"tail":"unit A-bad done"}}' ] || { echo "$alone"; false; }
  : > "$LOG"
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  pb=$BG_PID
  wait_starts 1 B-
  run within 60 "$VBW" prove --full < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; show; false; }
  shared=$(jq -c '.evidence.checks | map_values({status, exit, tail})' .vbw/record.json)
  [ "$shared" = "$alone" ] || { echo "alone: $alone"; echo "after waiting: $shared"; show; false; }
  # It did wait (longer than C1's timeout) for B's unit to end.
  [ "$(end_line B-C1)" -lt "$(start_line A-ok)" ] || { echo "A's units did not wait for the only slot"; show; false; }
  wait_ok "$pb" || { show; false; }
}
