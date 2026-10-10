#!/usr/bin/env bats
# R150 (R46, R33; docs/record.md): a schema-4 record (more than 50 checks, the
# protected field) loads in this VBW; a VBW that reads up to schema 3 says the
# project needs a newer VBW and never calls it corrupt nor touches it; and the
# status line, the session-start hook and the panel show the same on a schema-4
# record as on the same project at schema 3, with no error. L1.

load helper
load protected-helper

FIXTURES="$BATS_TEST_DIRNAME/fixtures/records"

setup() {
  vbw_setup
}

teardown() { vbw_teardown; }

# older: a copy of this VBW that reads up to schema 3, as VBW 2.0.30 does.
older() {
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
  jq -e '.schema == 4 and (.checks | length) > 50 and .protected == ([.checks[].files // [] | .[]] | unique)
    and (keys_unsorted | .[:4]) == ["schema", "lease", "protected", "checks"]' .vbw/record.json
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
  jq -e '.schema == 4 and .decisions[-1].text == "still works"' .vbw/record.json
}

@test "R150: a VBW that reads up to schema 3 asks for a newer VBW on the schema-4 fixture, never calling it corrupt" {
  vbw_git_project
  mkdir -p .vbw
  cp "$FIXTURES/v4.json" .vbw/record.json
  older
  refused_by_older
  cmp .vbw/record.json "$FIXTURES/v4.json"
}

@test "R150: a VBW that reads up to schema 3 asks for a newer VBW on a record this VBW moved to schema 4" {
  protected_base
  protected_apply 51
  jq -e '.schema == 4' .vbw/record.json
  older
  refused_by_older
}

@test "R150: a VBW that reads up to schema 3 still reads a record of 50 checks this VBW wrote" {
  protected_base
  protected_apply 50
  jq -e '.schema == 1 and (has("protected") | not)' .vbw/record.json
  older
  run "$OLDER" status < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$OLDER" decide "older still writes"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# twins_at_schema_4_and_3: the same project twice, built with 51 checks: FOUR
# as this VBW wrote it (schema 4), THREE without the field at schema 3 (as the
# VBW before R150 wrote it), each in a folder named "project with space".
twins_at_schema_4_and_3() {
  FOUR="$TEST_ROOT/four/project with space"
  THREE="$TEST_ROOT/three/project with space"
  mkdir -p "$FOUR" "$TEST_ROOT/three"
  cd "$FOUR" || return 1
  protected_base
  protected_apply 51
  "$VBW" approve > /dev/null
  [ "${1:-}" != run ] || VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  jq -e '.schema == 4 and has("protected")' .vbw/record.json
  cp -R "$FOUR" "$THREE"
  as_schema3 "$THREE/.vbw/record.json"
  rm -f "$FOUR/.vbw/runtime/glance.json" "$THREE/.vbw/runtime/glance.json"
}

# same_shown OUT_FOUR OUT_THREE: equal once the twin folder names are made one
# and durations (a run's elapsed time) are removed.
same_shown() {
  local a b
  a=$(printf '%s\n' "$1" | sed -E "s#$TEST_ROOT/four#<twin>#g; s/[0-9]+(ms|s|m|h)([^a-z]|\$)/<t>\2/g")
  b=$(printf '%s\n' "$2" | sed -E "s#$TEST_ROOT/three#<twin>#g; s/[0-9]+(ms|s|m|h)([^a-z]|\$)/<t>\2/g")
  [ "$a" = "$b" ] || { printf 'schema 4:\n%s\nschema 3:\n%s\n' "$a" "$b" | cut -c 1-400; return 1; }
}

statusline_in() {
  jq -nc --arg d "$1" '{session_id: "s1", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"}}' \
    | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" 2> "$TEST_ROOT/err"
}

session_in() {
  jq -nc --arg d "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $d}' | HOOK_PROJECT_DIR="$1" vbw_hook SessionStart 2> "$TEST_ROOT/err"
}

@test "R150: the status line shows the same on a schema-4 record as on schema 3, idle and during a run" {
  local step a b
  for step in idle run; do
    rm -rf "$TEST_ROOT/four" "$TEST_ROOT/three"
    twins_at_schema_4_and_3 "$step"
    a=$(statusline_in "$FOUR")
    [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
    b=$(statusline_in "$THREE")
    [ -n "$a" ] && [[ "$a" != *unavailable* ]] || { echo "$a"; false; }
    same_shown "$a" "$b"
    # Once a command has rewritten the glance, the status line reads it: still the same.
    (cd "$FOUR" && "$VBW" status > /dev/null)
    a=$(statusline_in "$FOUR")
    [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
    same_shown "$a" "$b"
  done
}

@test "R150: the session-start hook says the same on a schema-4 record as on schema 3, with no error" {
  twins_at_schema_4_and_3
  local a b
  a=$(session_in "$FOUR")
  [ ! -s "$TEST_ROOT/err" ] || { cat "$TEST_ROOT/err"; false; }
  b=$(session_in "$THREE")
  [[ "$a" == *"VBW project"* ]] || { echo "$a"; false; }
  [[ "$a" != *"newer VBW"* && "$a" != *corrupt* ]] || { echo "$a"; false; }
  same_shown "$a" "$b"
}

@test "R150: the panel shows the same on a schema-4 record as on schema 3" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node --test "$REPO_ROOT/tests/panel/schema4.test.mjs"
  [ "$status" -eq 0 ] || { echo "$output" | tail -40; false; }
}
