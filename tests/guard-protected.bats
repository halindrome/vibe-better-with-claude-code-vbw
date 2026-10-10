#!/usr/bin/env bats
# R150 (decision D226; docs/guards.md): on a schema-4 record the Bash and file
# guards read only schema, lease and the protected field, and stop before the
# checks begin; their answers are exactly those they give on the same project
# at schema 3 (no field, read as before), for a build or fix agent, the main
# conversation, another session and calls outside a run. Records of 50 checks
# or fewer keep today's answers. L1.

load helper
load protected-helper

setup() {
  vbw_setup
  FOUR="$TEST_ROOT/four/project with space"
  THREE="$TEST_ROOT/three/project with space"
  mkdir -p "$FOUR" "$TEST_ROOT/three"
  cd "$FOUR" || return 1
  protected_base
  # The plan may write src/ and tests/, so a check file is inside the run's
  # files and only its protection stops a write.
  protected_apply 51 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  cp -R "$FOUR" "$THREE"
  as_schema3 "$THREE/.vbw/record.json"
  export FOUR THREE
}

teardown() { vbw_teardown; }

# answer DIR INPUT_JSON: the hook's answer in the project at DIR (its cwd set to
# DIR); stderr goes to $TEST_ROOT/err.
answer() {
  local tool
  tool=$(printf '%s' "$2" | jq -r .tool_name)
  printf '%s' "$2" | jq -c --arg d "$1" '.cwd = $d' \
    | HOOK_PROJECT_DIR="$1" vbw_hook PreToolUse "$tool" 2> "$TEST_ROOT/err"
}

# same INPUT_JSON: both formats give the same answer, with no error; the
# answer is left in ANSWER.
same() {
  local four three
  four=$(answer "$FOUR" "$1")
  [ ! -s "$TEST_ROOT/err" ] || { echo "error on schema 4:"; cat "$TEST_ROOT/err"; return 1; }
  three=$(answer "$THREE" "$1")
  [ "$four" = "$three" ] || { printf 'answers differ for %s\nschema 4: %s\nschema 3: %s\n' "$1" "$four" "$three"; return 1; }
  ANSWER=$four
}

bash_in() { jq -nc --arg c "$1" --arg a "${2:-}" --arg s "${3:-s1}" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: "Bash", tool_input: {command: $c}}
  + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'; }
file_in() { jq -nc --arg t "$1" --arg p "$2" --arg a "${3:-}" --arg s "${4:-s1}" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: $t,
  tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}} + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'; }

protected_denied() { [[ "$ANSWER" == *deny* && "$ANSWER" == *"protected check file"* ]] || { echo "not denied as protected: $ANSWER"; return 1; }; }

@test "R150: the fixture is a schema-4 record beside the same project at schema 3" {
  jq -e '.schema == 4 and has("protected") and (.lease.kind == "build")' "$FOUR/.vbw/record.json"
  jq -e '.schema != 4 and (has("protected") | not) and (.checks | length) == 51' "$THREE/.vbw/record.json"
}

@test "R150: under a build run, an agent's Edit, Write or Bash change of a check file is stopped the same way on schema 4 and 3" {
  same "$(file_in Write tests/c50.sh workflow-subagent)"
  protected_denied
  same "$(file_in Edit tests/shared.sh workflow-subagent)"
  protected_denied
  same "$(file_in MultiEdit tests/c7.sh workflow-subagent)"
  protected_denied
  same "$(bash_in 'printf x > tests/c9.sh' workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same "$(bash_in 'printf x >> tests/c10.sh' workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same "$(bash_in "$(printf 'python3 - <<%s\nopen("tests/c11.sh", "w").write("x")\nEOF' "'EOF'")" workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
}

@test "R150: under a build run, an unprotected file the run may write is not stopped, on schema 4 and 3" {
  same "$(file_in Write src/pay.txt workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
  same "$(file_in Write tests/new_test.sh workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
  same "$(bash_in 'printf "paid\n" > src/pay.txt' workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
  same "$(file_in Read tests/c50.sh workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
}

@test "R150: the main conversation, another session and calls outside a run are answered as before, on schema 4 and 3" {
  same "$(file_in Write tests/c50.sh)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
  same "$(file_in Write src/pay.txt "" s2)"
  [[ "$ANSWER" == *"another session"* ]] || { echo "$ANSWER"; false; }
  same "$(file_in Write .vbw/record.json workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  record_edit '.lease = null' "$FOUR/.vbw/record.json"
  record_edit '.lease = null' "$THREE/.vbw/record.json"
  same "$(file_in Write tests/c50.sh workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
}

@test "R150: under a fix run, an agent's change of a check file is stopped the same way on schema 4 and 3" {
  record_edit '.lease.kind = "fix" | .lease.files = null' "$FOUR/.vbw/record.json"
  record_edit '.lease.kind = "fix" | .lease.files = null' "$THREE/.vbw/record.json"
  jq -e '(keys_unsorted | .[:4]) == ["schema", "lease", "protected", "checks"]' "$FOUR/.vbw/record.json"
  same "$(file_in Write tests/c50.sh workflow-subagent)"
  protected_denied
  same "$(bash_in 'printf x > tests/shared.sh' workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same "$(file_in Write src/pay.txt workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
}

@test "R150: on schema 4 the guards stop reading before the checks begin" {
  # Cut the record where the checks begin: a guard that reads into them meets
  # broken JSON and loses the lease; one that stops after protected answers in full.
  local rec
  rec=$(jq -c . "$FOUR/.vbw/record.json")
  [[ "$rec" == *',"protected":['*',"checks":['* ]]
  printf '%s,"checks":[{"i' "${rec%%,\"checks\":*}" > "$FOUR/.vbw/record.json"
  ANSWER=$(answer "$FOUR" "$(file_in Write tests/c50.sh workflow-subagent)")
  protected_denied
  ANSWER=$(answer "$FOUR" "$(bash_in 'printf x > tests/c9.sh' workflow-subagent)")
  [[ "$ANSWER" == *deny* && "$ANSWER" == *"protected check file"* ]] || { echo "$ANSWER"; false; }
  ANSWER=$(answer "$FOUR" "$(file_in Write src/pay.txt workflow-subagent)")
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
}

@test "R150: a record of 50 checks keeps its format and today's answers" {
  local fifty="$TEST_ROOT/fifty/project with space"
  mkdir -p "$fifty"
  cd "$fifty" || return 1
  protected_base
  protected_apply 50 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  jq -e '(has("protected") | not) and .schema == 1' .vbw/record.json
  ANSWER=$(answer "$fifty" "$(file_in Write tests/c49.sh workflow-subagent)")
  protected_denied
  ANSWER=$(answer "$fifty" "$(file_in Write src/pay.txt workflow-subagent)")
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
}
