#!/usr/bin/env bats
# R149: on a record larger than 2 MB the session-start hook, the Bash and file
# guards, the approve hooks, the status line and the panel give the same
# answers as on the small twin (big-record-helper.bash) and print no error,
# and tools/bench-hooks.sh measures the guards and the status line on a record
# larger than 2 MB within their limits (hook CPU per call within its budget,
# status line at most 30 ms). L1.

load helper
load big-record-helper

setup() {
  vbw_setup
  twins
}

teardown() { vbw_teardown; }

# hook_in TWIN_DIR EVENT TOOL INPUT_JSON: the hook's answer for INPUT_JSON
# (its cwd set to the twin) in that twin; stderr is kept in $TEST_ROOT/err.
hook_in() {
  printf '%s' "$4" | jq -c --arg d "$1" '.cwd = $d' \
    | HOOK_PROJECT_DIR="$1" vbw_hook "$2" "$3" 2> "$TEST_ROOT/err"
}

# same_answer EVENT TOOL INPUT_JSON: the hook answers the same in both twins,
# and the large twin's run prints nothing on stderr.
same_answer() {
  local s b
  s=$(hook_in "$SMALL" "$@" | twin_norm)
  b=$(hook_in "$BIG" "$@")
  [ ! -s "$TEST_ROOT/err" ] || { echo "$1 $2 printed an error on the large record:"; cut -c 1-400 "$TEST_ROOT/err"; return 1; }
  b=$(printf '%s\n' "$b" | twin_norm)
  [ "$s" = "$b" ] || { printf '%s %s answers differ on %s\nsmall: %s\nlarge: %s\n' "$1" "$2" "$3" "$s" "$b" | cut -c 1-600; return 1; }
  ANSWER=$b
}

bash_input() { jq -nc --arg c "$1" --arg a "${2:-}" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", tool_input: {command: $c}}
  + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'; }
file_input() { jq -nc --arg t "$1" --arg p "$2" --arg a "${3:-}" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, tool_input: {file_path: $p, content: "x"}}
  + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'; }

# planned: the active milestone applied in both twins, its contract waiting for approval.
planned() {
  twin_doc > "$TEST_ROOT/doc.json"
  TWIN_IN="$TEST_ROOT/doc.json" twin_step apply
}

@test "R149: the session-start hook says the same on a record over 2 MB, with no error" {
  same_answer SessionStart "" '{"hook_event_name": "SessionStart", "source": "startup"}'
  [[ "$ANSWER" == *"VBW project"* ]] || { echo "$ANSWER"; false; }
  planned
  same_answer SessionStart "" '{"hook_event_name": "SessionStart", "source": "startup"}'
}

@test "R149: the Bash and file guards answer the same on a record over 2 MB, with and without a run" {
  same_answer PreToolUse Bash "$(bash_input 'git status && ls src')"
  same_answer PreToolUse Bash "$(bash_input 'printf x > .vbw/record.json')"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same_answer PreToolUse Write "$(file_input Write .vbw/record.json)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same_answer PreToolUse Read "$(file_input Read src/app.js)"
  planned
  twin_step approve
  VBW_SESSION_ID=s1 twin_step run start build P51.1 P52.1
  # A build agent may write its plan's files, never a check file or a file outside the run.
  same_answer PreToolUse Write "$(file_input Write src/a.txt workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
  same_answer PreToolUse Write "$(file_input Write tests/a.sh workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same_answer PreToolUse Edit "$(file_input Edit README.md workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same_answer PreToolUse Bash "$(bash_input 'printf x > tests/b.sh' workflow-subagent)"
  [[ "$ANSWER" == *deny* ]] || { echo "$ANSWER"; false; }
  same_answer PreToolUse Bash "$(bash_input 'printf "a\n" > src/a.txt' workflow-subagent)"
  [ -z "$ANSWER" ] || { echo "$ANSWER"; false; }
  # Another session writing the run's files is told to wait.
  same_answer PreToolUse Write "$(file_input Write src/b.txt | jq -c '.session_id = "s2"')"
  [[ "$ANSWER" == *"another session"* ]] || { echo "$ANSWER"; false; }
}

@test "R149: the approve hooks answer the same on a record over 2 MB" {
  planned
  local q fp_s fp_b
  q=$(jq -nc '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "AskUserQuestion",
    tool_input: {questions: [{question: "Approve the plan for parts a and b?", header: "Approval", multiSelect: false,
      options: [{label: "Approve", description: "x"}, {label: "Not yet", description: "x"}]}]}}')
  same_answer PreToolUse AskUserQuestion "$q"
  [[ "$ANSWER" == *"Approve contract <hex>?"* ]] || { echo "$ANSWER"; false; }
  fp_s=$(hook_in "$SMALL" PreToolUse AskUserQuestion "$q" | jq -r '.hookSpecificOutput.updatedInput.questions[0].question' | sed -n 's/^Approve contract \([0-9a-f]*\)?.*/\1/p')
  fp_b=$(hook_in "$BIG" PreToolUse AskUserQuestion "$q" | jq -r '.hookSpecificOutput.updatedInput.questions[0].question' | sed -n 's/^Approve contract \([0-9a-f]*\)?.*/\1/p')
  [ -n "$fp_s" ] && [ -n "$fp_b" ]
  local s b
  s=$(hook_in "$SMALL" PostToolUse AskUserQuestion "$(jq -nc --arg q "Approve contract $fp_s? Approve the plan?" \
    '{hook_event_name: "PostToolUse", session_id: "s1", tool_name: "AskUserQuestion", tool_input: {questions: [{question: $q, options: [{label: "Approve"}, {label: "Not yet"}]}]},
      tool_response: {answers: {($q): "Approve"}}}')" | twin_norm)
  b=$(hook_in "$BIG" PostToolUse AskUserQuestion "$(jq -nc --arg q "Approve contract $fp_b? Approve the plan?" \
    '{hook_event_name: "PostToolUse", session_id: "s1", tool_name: "AskUserQuestion", tool_input: {questions: [{question: $q, options: [{label: "Approve"}, {label: "Not yet"}]}]},
      tool_response: {answers: {($q): "Approve"}}}')")
  [ ! -s "$TEST_ROOT/err" ] || { cut -c 1-400 "$TEST_ROOT/err"; false; }
  b=$(printf '%s\n' "$b" | twin_norm)
  [ "$s" = "$b" ] || { printf 'small: %s\nlarge: %s\n' "$s" "$b" | cut -c 1-600; false; }
  [[ "$b" == *"Approved contract"* ]] || { echo "$b"; false; }
}

# statusline TWIN_DIR: the status line for a session in that twin.
statusline() {
  jq -nc --arg d "$1" '{session_id: "s1", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"}}' \
    | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" 2> "$TEST_ROOT/err"
}

@test "R149: the status line shows the same on a record over 2 MB, before and during a run" {
  local s b
  for step in idle run; do
    if [ "$step" = run ]; then
      planned
      twin_step approve
      VBW_SESSION_ID=s1 twin_step run start build P51.1 P52.1
    fi
    s=$(statusline "$SMALL" | twin_norm)
    b=$(statusline "$BIG")
    [ ! -s "$TEST_ROOT/err" ] || { cut -c 1-400 "$TEST_ROOT/err"; false; }
    b=$(printf '%s\n' "$b" | twin_norm)
    [[ "$b" != *"unavailable"* ]] || { echo "$b"; false; }
    [ "$s" = "$b" ] || { printf 'small:\n%s\nlarge:\n%s\n' "$s" "$b" | cut -c 1-600; false; }
  done
}

@test "R149: the panel shows the same on a record over 2 MB" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node --test "$REPO_ROOT/tests/panel/big-record.test.mjs"
  [ "$status" -eq 0 ] || { echo "$output" | tail -40; false; }
}

@test "R149: tools/bench-hooks.sh measures the guards and the status line on a record over 2 MB, within their limits" {
  run env VBW_BENCH_RUNS=20 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local size input
  size=$(printf '%s\n' "$output" | sed -n 's/^large record: \([0-9]*\) bytes$/\1/p')
  [ -n "$size" ] && [ "$size" -gt 2097152 ] || { echo "no 'large record: N bytes' line over 2 MB"; echo "$output"; false; }
  for input in git npm big interp read answer; do
    printf '%s\n' "$output" | grep -qE "^guard \($input\): [0-9.]+ ms own CPU per call" || { echo "no small-record line for $input"; echo "$output"; false; }
    printf '%s\n' "$output" | grep -qE "^guard \($input, large record\): [0-9.]+ ms own CPU per call" || { echo "no large-record line for $input"; echo "$output"; false; }
  done
  printf '%s\n' "$output" | grep -qE '^status line: [0-9.]+ ms CPU per call; budget 30 ms$' || { echo "no status line measurement"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^status line \(large record\): [0-9.]+ ms CPU per call; budget 30 ms$' || { echo "no large-record status line measurement"; echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q OVER
}
