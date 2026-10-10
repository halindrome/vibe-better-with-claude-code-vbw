#!/usr/bin/env bats
# R150 (R46, R33; docs/record.md): a format-4 record (schema 4, the protected
# list) loads in this VBW; a VBW that reads up to schema 3 says the project
# needs a newer VBW on every record this VBW writes, whatever its number of
# checks, and never calls it corrupt nor touches it; and the status line, the
# session-start hook and the panel show the same on a format-4 record with 0
# checks and with 60 as on the same project as an older VBW wrote it
# (schema 3), with no error. L1.

load helper
load protected-helper

FIXTURES="$BATS_TEST_DIRNAME/fixtures/records"

setup() {
  vbw_setup
}

teardown() { vbw_teardown; }

# older: a copy of this VBW that reads up to schema 3, as VBW 2.0.30 does.
older() {
  rm -rf "$TEST_ROOT/older"
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/older"
  sed 's/^VBW_SCHEMA_MAX=.*/VBW_SCHEMA_MAX=3/' "$PLUGIN_ROOT/lib/record.sh" > "$TEST_ROOT/older/lib/record.sh"
  grep -qx 'VBW_SCHEMA_MAX=3' "$TEST_ROOT/older/lib/record.sh"
  OLDER="$TEST_ROOT/older/bin/vbw"
}

# refused_by_older: every command of the older VBW exits non-zero, says the
# project needs a newer VBW and how to update, never "corrupt", and leaves the
# record as it was.
refused_by_older() {
  local before cmd
  before=$(cksum < .vbw/record.json)
  for cmd in "status" "next" "show roadmap" "show requirements" "decide a-decision" "todo add x" "prove" "doctor"; do
    # shellcheck disable=SC2086 # the command words split on purpose
    run "$OLDER" $cmd < /dev/null
    [ "$status" -ne 0 ] || { echo "older vbw $cmd succeeded: $output"; return 1; }
    [[ "$output" == *"needs a newer VBW"* && "$output" == *"update"* ]] || { echo "older vbw $cmd: $output"; return 1; }
    ! printf '%s' "$output" | grep -qi corrupt || { echo "older vbw $cmd called it corrupt: $output"; return 1; }
  done
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R150: the schema-4 fixture loads and shows correctly in this VBW" {
  vbw_git_project
  mkdir -p .vbw
  cp "$FIXTURES/v4.json" .vbw/record.json
  format4
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run show roadmap
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"M2 Refunds [active]"* ]]
  [[ "$output" == *"P2 Refunds [planned]"* ]]
  vbw_run doctor
  [[ "$output" != *"needs a newer VBW"* ]] || { echo "$output"; false; }
  vbw_run decide "still works"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  format4
  jq -e '.decisions[-1].text == "still works"' .vbw/record.json
}

@test "R150: a VBW that reads up to schema 3 asks for a newer VBW on the schema-4 fixture, never calling it corrupt" {
  vbw_git_project
  mkdir -p .vbw
  cp "$FIXTURES/v4.json" .vbw/record.json
  older
  refused_by_older
  cmp .vbw/record.json "$FIXTURES/v4.json"
}

@test "R150: a VBW that reads up to schema 3 asks for a newer VBW on every record this VBW writes: 0, 1, 3 and 51 checks" {
  protected_base
  "$VBW" decide "first" > /dev/null
  format4
  older
  refused_by_older || { echo "with 0 checks"; false; }
  local n
  for n in 1 3 51; do
    protected_apply "$n"
    format4
    refused_by_older || { echo "with $n checks"; false; }
  done
}

# twins N [run]: the same project twice with N checks (0: none applied): FOUR
# as this VBW wrote it (format 4), OLD as an older VBW wrote it (schema 3, a
# sorted todo, no list), each in a folder named "project with space"; with
# "run" a build run is open.
twins() {
  FOUR="$TEST_ROOT/four/project with space"
  OLD="$TEST_ROOT/old/project with space"
  rm -rf "$TEST_ROOT/four" "$TEST_ROOT/old"
  mkdir -p "$FOUR" "$TEST_ROOT/old"
  cd "$FOUR" || return 1
  protected_base
  "$VBW" todo add --sort later --size small "Gift cards" > /dev/null
  if [ "$1" -gt 0 ]; then
    protected_apply "$1"
    "$VBW" approve > /dev/null
    [ "${2:-}" != run ] || VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  fi
  format4
  cp -R "$FOUR" "$OLD"
  as_older "$OLD/.vbw/record.json"
  jq -e '.schema == 3 and (has("protected") | not)' "$OLD/.vbw/record.json"
  rm -f "$FOUR/.vbw/runtime/glance.json" "$OLD/.vbw/runtime/glance.json"
}

# same_shown OUT_FOUR OUT_OLD: equal once the twin folder names are made one
# and durations (a run's elapsed time) are removed.
same_shown() {
  local a b
  a=$(printf '%s\n' "$1" | sed -E "s#$TEST_ROOT/four#<twin>#g; s/[0-9]+(ms|s|m|h)([^a-z]|\$)/<t>\2/g")
  b=$(printf '%s\n' "$2" | sed -E "s#$TEST_ROOT/old#<twin>#g; s/[0-9]+(ms|s|m|h)([^a-z]|\$)/<t>\2/g")
  [ "$a" = "$b" ] || { printf 'schema 4:\n%s\nolder:\n%s\n' "$a" "$b" | cut -c 1-400; return 1; }
}

statusline_in() {
  jq -nc --arg d "$1" '{session_id: "s1", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"}}' \
    | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" 2> "$TEST_ROOT/err"
}

session_in() {
  jq -nc --arg d "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $d}' | HOOK_PROJECT_DIR="$1" vbw_hook SessionStart 2> "$TEST_ROOT/err"
}

@test "R150: the status line shows the same on a format-4 record with 0 and 60 checks as on an older one, idle and during a run, with no error" {
  local n step a b
  for n in 0 60; do
    for step in idle run; do
      [ "$n" -gt 0 ] || [ "$step" = idle ] || continue
      twins "$n" "$step"
      a=$(statusline_in "$FOUR")
      [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
      b=$(statusline_in "$OLD")
      [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
      [ -n "$a" ] && [[ "$a" != *unavailable* ]] || { echo "$a"; false; }
      same_shown "$a" "$b" || { echo "$n checks, $step"; false; }
      # Once a command has rewritten the glance, the status line reads it: still the same.
      (cd "$FOUR" && "$VBW" status > /dev/null)
      a=$(statusline_in "$FOUR")
      [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
      same_shown "$a" "$b" || { echo "$n checks, $step, glance"; false; }
    done
  done
}

@test "R150: the session-start hook says the same on a format-4 record as on an older one, with no error" {
  local n a b
  for n in 0 60; do
    twins "$n"
    a=$(session_in "$FOUR")
    [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
    b=$(session_in "$OLD")
    [[ "$a" == *"VBW project"* ]] || { echo "$a"; false; }
    [[ "$a" != *"newer VBW"* && "$a" != *corrupt* ]] || { echo "$a"; false; }
    same_shown "$a" "$b" || { echo "$n checks"; false; }
  done
}

@test "R150: the panel shows the same on a format-4 record with 0 and 60 checks as on an older one" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node --test "$REPO_ROOT/tests/panel/schema4.test.mjs"
  [ "$status" -eq 0 ] || { echo "$output" | tail -40; false; }
}
