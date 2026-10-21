#!/usr/bin/env bats
# R194 (T165; docs/guards.md): vbw run start fix F1 F2... opens as editable, for
# each requirement fix in the run whatever its source, the check files of that
# fix's requirement that no other requirement's check lists, and nothing more:
# the file guard denies any other check file during the run with its documented
# answer, which names the file and the files the fix may edit, and advises
# vbw fix check only for a fix QA opened (a proof's fix cannot register a test).
# A project-command fix opens no check file. New test files may be created when
# a fix of the run is QA's (R160), never for a proof's fix alone. L1: the kernel
# and the hooks on a fixture project.

load helper
load fix-helper
load fixture-helper

# R1 (C1: tests/c1.sh and tests/shared.sh) and R2 (C2: tests/c2.sh and
# tests/shared.sh); P1.1 writes src/pay.txt and src/refund.txt; built and proved.
# F1 as vbw prove opens a fix (no source), F2 for the test command (fix_project
# shared, built once per file).
setup_file() { fixture_build shared fix_project shared; }
setup() { fixture_copy shared; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
start() { VBW_SESSION_ID=s1 "$VBW" run start fix "$@" > /dev/null; }
qa_fix() {
  "$VBW" qa finding R2 "a refund of zero is written" > /dev/null
  jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json
}
# file_call TOOL PATH: a Dev's file tool call in session s1; prints the hook's answer.
file_call() {
  jq -nc --arg t "$1" --arg p "$2" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: $t,
    agent_id: "a1", agent_type: "vbw:dev", tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}}' | vbw_hook PreToolUse "$1"
}
bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash",
    agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}' | vbw_hook PreToolUse Bash
}
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1; }
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
lease() { jq -c "$1" .vbw/record.json; }

@test "R194: a proof's fix run opens its requirement's own check files, the shared one excluded, and allows no new test file" {
  start F1
  lease '.lease' | jq -e '.editable == ["tests/c1.sh"] and ((.new_tests // false) | not) and .files == ["src/pay.txt", "src/refund.txt"]' || { lease .lease; false; }
  local out
  out=$(file_call Edit tests/c1.sh)
  ! denied "$out" || { echo "$out"; false; }
  out=$(bash_call 'printf "x\n" >> tests/c1.sh')
  ! denied "$out" || { echo "$out"; false; }
  out=$(file_call Write tests/r1-regression.sh)
  denied "$out" || { echo "a new test file was allowed: $out"; false; }
}

@test "R194: during that run the guard denies any other check file, naming it and the files the fix may edit, without the vbw fix check advice" {
  start F1
  local out
  out=$(file_call Edit tests/c2.sh)
  denied "$out" || { echo "not denied: $out"; false; }
  reason "$out" | grep -q 'tests/c2.sh' || { reason "$out"; false; }
  reason "$out" | grep -q 'tests/c1.sh' || { echo "the editable files are not named:"; reason "$out"; false; }
  reason "$out" | grep -q '^Next: ' || { echo "no next step:"; reason "$out"; false; }
  ! reason "$out" | grep -q 'vbw fix check' || { echo "advises vbw fix check to a proof's fix:"; reason "$out"; false; }
  out=$(file_call Write tests/shared.sh)
  denied "$out" || { echo "the shared file was allowed: $out"; false; }
  out=$(bash_call 'printf x > tests/c2.sh')
  denied "$out" || { echo "not denied: $out"; false; }
}

@test "R194: a project-command fix opens no check file" {
  start F2
  lease '.lease' | jq -e '.files == null and ((.editable // []) == [])' || { lease .lease; false; }
  local out
  out=$(file_call Edit tests/c1.sh)
  denied "$out" || { echo "not denied: $out"; false; }
  reason "$out" | grep -q 'protected check file' || { reason "$out"; false; }
}

@test "R194: a QA fix's run keeps R160: its check files open, new test files allowed, and the refusal keeps the vbw fix check advice" {
  local qa out
  qa=$(qa_fix)
  start "$qa"
  lease '.lease' | jq -e '.editable == ["tests/c2.sh"] and .new_tests == true' || { lease .lease; false; }
  out=$(file_call Write tests/r2-regression.sh)
  ! denied "$out" || { echo "$out"; false; }
  out=$(file_call Edit tests/c1.sh)
  denied "$out" || { echo "not denied: $out"; false; }
  reason "$out" | grep -q 'vbw fix check' || { reason "$out"; false; }
}

@test "R194: a run of a proof's fix and a QA fix together opens both requirements' own check files and allows new test files" {
  local qa
  qa=$(qa_fix)
  start F1 "$qa"
  lease '.lease' | jq -e '(.editable | sort) == ["tests/c1.sh", "tests/c2.sh"] and .new_tests == true' || { lease .lease; false; }
}

@test "R194: a run of a proof's fix and a project-command fix together opens the requirement's own check files, the guard allows them and denies the others" {
  start F1 F2
  lease '.lease' | jq -e '.editable == ["tests/c1.sh"] and .files == null' || { lease .lease; false; }
  local out
  out=$(file_call Edit tests/c1.sh)
  ! denied "$out" || { echo "$out"; false; }
  out=$(file_call Edit tests/c2.sh)
  denied "$out" || { echo "not denied: $out"; false; }
}

@test "R194: a QA fix run whose requirement has no exclusive check file denies every protected check file with the vbw fix check advice, and allows a new test file" {
  edit_record '.checks |= map(if .req == "R2" then .files = ["tests/shared.sh"] else . end) | .protected = ([.checks[].files[]] | unique)'
  local qa out
  qa=$(qa_fix)
  start "$qa"
  lease '.lease' | jq -e '(.editable // []) == [] and .new_tests == true' || { lease .lease; false; }
  out=$(file_call Edit tests/c1.sh)
  denied "$out" || { echo "not denied: $out"; false; }
  reason "$out" | grep -q 'vbw fix check' || { reason "$out"; false; }
  out=$(file_call Write tests/r2-regression.sh)
  ! denied "$out" || { echo "$out"; false; }
}
