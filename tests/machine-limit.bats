#!/usr/bin/env bats
# R181 (docs/proof.md): the computer-wide limit on running checks. It is three
# quarters of the processor cores, rounded down, at least 1 and at most 64,
# from the core count check_jobs already reads (vbw_cores); 1 when the count
# cannot be read; and it is not a setting. Its slot store is slots.json in
# <claude-config-dir>/vbw/, the folder found in the same order as
# tools/resolve-claude-dir.sh by one kernel function (vbw_claude_dir) that the
# status line's settings lookup also uses. The store exists only while a run
# holds or waits for a slot; nothing else is written outside the project. The
# slot store code holds to the bash 3.2 floor. L1. The projects tests share
# are built once per file (setup_file) and copied for each test.

load helper
load machine-helper
load fixture-helper

STORE_REL=vbw/slots.json

# one_check: a project of one check. For fixture_build.
one_check() {
  machine_setup
  machine_project "$PROJECT" A 1 0
}

# peek_two: a project of two checks and a unit C3 that peeks at the store. For fixture_build.
peek_two() {
  machine_setup
  machine_project "$PROJECT" A 2 0 "$(peek_check C3 "$CLAUDE_CONFIG_DIR/$STORE_REL")"
}

setup_file() {
  fixture_build base machine_setup
  fixture_build one one_check
  fixture_build peek peek_two
}
setup() { fixture_copy base; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

@test "R181: the machine limit is three quarters of the cores, rounded down, at least 1 and at most 64; 1 when the count cannot be read" {
  fixture_copy one
  local pair got
  for pair in 4:3 8:6 10:7 3:2 2:1 1:1 85:63 86:64 128:64 none:1; do
    cores "${pair%%:*}"
    got=$(vbw_kernel 'vbw_machine_limit')
    [ "$got" = "${pair##*:}" ] || { echo "${pair%%:*} cores: limit '$got', want ${pair##*:}"; false; }
  done
}

@test "R181: the machine limit is not a setting: vbw config refuses one, and check_jobs does not change it" {
  fixture_copy one
  vbw_run config set machine_limit 8
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  "$VBW" config set check_jobs 64 > /dev/null
  [ "$(vbw_kernel 'vbw_machine_limit')" = 3 ]
}

@test "R181: one run whose check_jobs is above the limit runs exactly as many units at once as the limit" {
  machine_project "$PROJECT" A 6 2
  "$VBW" config set check_jobs 6 > /dev/null
  run within 120 "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [ "$(starts)" = 6 ] || { show; false; }
  [ "$(peak)" = 3 ] || { echo "peak $(peak) with 4 cores (limit 3)"; show; false; }
}

@test "R181: the slot store is <CLAUDE_CONFIG_DIR>/vbw/slots.json, inside this test's own folder, while a run uses it" {
  [[ "$CLAUDE_CONFIG_DIR" == "$TEST_ROOT"/* ]]
  machine_project "$PROJECT" A 1 0 "$(peek_check C2 "$CLAUDE_CONFIG_DIR/$STORE_REL")"
  vbw_run check
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  seen_store
  # No run holds or waits for a slot any more: nothing is left behind.
  [ ! -e "$CLAUDE_CONFIG_DIR/$STORE_REL" ] || { cat "$CLAUDE_CONFIG_DIR/$STORE_REL"; false; }
}

@test "R181: without CLAUDE_CONFIG_DIR the store is in ~/.config/claude-code/vbw when that folder exists" {
  machine_project "$PROJECT" A 1 0 "$(peek_check C2 "$HOME/.config/claude-code/$STORE_REL")"
  mkdir -p "$HOME/.config/claude-code"
  run env -u CLAUDE_CONFIG_DIR "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  seen_store
  [ ! -e "$HOME/.claude/vbw" ]
}

@test "R181: without CLAUDE_CONFIG_DIR or ~/.config/claude-code the store is in ~/.claude/vbw" {
  machine_project "$PROJECT" A 1 0 "$(peek_check C2 "$HOME/.claude/$STORE_REL")"
  run env -u CLAUDE_CONFIG_DIR "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  seen_store
}

@test "R181: one kernel function finds the Claude config folder, and the status line's settings lookup uses it" {
  fixture_copy one
  [ "$(vbw_kernel 'vbw_claude_dir')" = "$CLAUDE_CONFIG_DIR" ]
  [ "$(unset CLAUDE_CONFIG_DIR; vbw_kernel 'vbw_claude_dir')" = "$HOME/.claude" ]
  mkdir -p "$HOME/.config/claude-code"
  [ "$(unset CLAUDE_CONFIG_DIR; vbw_kernel 'vbw_claude_dir')" = "$HOME/.config/claude-code" ]
  # The status line asks the same function and repeats none of the lookup
  # (the settings command itself, which finds the plugin cache, aside).
  grep -q 'vbw_claude_dir' "$PLUGIN_ROOT/lib/cmd-statusline.sh"
  run grep -nE 'CLAUDE_CONFIG_DIR|\.config/claude-code' \
    <(sed -e '/^VBW_STATUSLINE_CMD=/d' -e '/^[[:space:]]*#/d' "$PLUGIN_ROOT/lib/cmd-statusline.sh")
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R181: a proof writes nothing outside the project but the slot store, and leaves nothing there when done" {
  fixture_copy peek
  local before after
  before=$(find "$TEST_ROOT" -path "$PROJECT" -prune -o -type f -print | sort)
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  seen_store
  # The test's own files (the log, the copy the peek unit made) aside.
  after=$(find "$TEST_ROOT" -path "$PROJECT" -prune -o -type f -print | grep -vxF "$TEST_ROOT/seen.json" | sort)
  [ -z "$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))" ] \
    || { echo "files left outside the project:"; comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"); false; }
}

@test "R181: the slot store code holds to the bash 3.2 floor: no wait -n, associative arrays, mapfile or case-changing expansions" {
  [ -f "$PLUGIN_ROOT/lib/slots.sh" ] || { echo "no plugin/lib/slots.sh"; false; }
  run grep -nE 'wait -n|(declare|local|typeset) -[a-zA-Z]*A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z_0-9]*(\^|,)' \
    "$PLUGIN_ROOT/lib/slots.sh" "$PLUGIN_ROOT/lib/checks.sh"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R181: under /bin/bash the kernel takes and gives back slots" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  fixture_copy peek
  run within 60 /bin/bash "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  seen_store
  [ ! -e "$CLAUDE_CONFIG_DIR/$STORE_REL" ]
  run within 60 /bin/bash "$VBW" check < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
