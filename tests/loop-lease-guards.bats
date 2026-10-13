#!/usr/bin/env bats
# R180 (P129; docs/guards.md): the guards that hold for any run hold for the
# loop's runs. Under a loop, a run the loop opened denies the same writes as
# any run: the record, a path outside the project, a protected check file, a
# vbw approve call, a git push by a builder. The plan's own file stays
# writable. Driven with a loop on and a lease open. L1.

load helper
load loop-helper

setup() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  loop_next s1 > /dev/null
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(loop_next s1 | jq -r .action)" = build ]
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  jq -e '.lease.kind == "build" and .loop != null' .vbw/record.json
}
teardown() { vbw_teardown; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", agent_type: "dev", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}
file_call() {
  jq -nc --arg t "$1" --arg p "$2" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", agent_type: "dev", tool_name: $t, cwd: $d, tool_input: {file_path: $p}}' \
    | vbw_hook PreToolUse "$1"
}
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]; }

@test "R180: under a loop a builder may not write the record, a path outside the project or a protected check file" {
  run file_call Write "$PROJECT/.vbw/record.json"
  denied && [[ "$(reason)" == *"written only by vbw"* ]] || { echo "$output"; false; }
  run file_call Write /tmp/notes.txt
  denied && [[ "$(reason)" == *"outside the project"* ]] || { echo "$output"; false; }
  # A protected check file inside the lease's own files: only the protected rule can answer (F189).
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  edit_record '(.plans[] | select(.id == "P2.1")).files += ["tests/greet.sh"]'
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  jq -e '.lease.files | index("tests/greet.sh") != null' .vbw/record.json
  jq -e '.protected | index("tests/greet.sh") != null' .vbw/record.json
  run file_call Edit "$PROJECT/tests/greet.sh"
  denied && [[ "$(reason)" == *"protected check file"* ]] || { echo "$output"; false; }
  run bash_call 'echo x > .vbw/record.json'
  denied || { echo "$output"; false; }
  run bash_call 'echo x > /tmp/notes.txt'
  denied || { echo "$output"; false; }
  run file_call Write "$PROJECT/src/greet.txt"
  [ -z "$output" ] || { echo "the plan's own file was denied: $output"; false; }
}

@test "R180: under a loop a builder may not approve and may not push" {
  run bash_call 'vbw approve'
  denied && [[ "$(reason)" == *"only the user approves"* ]] || { echo "$output"; false; }
  run bash_call 'git push origin main'
  denied && [[ "$(reason)" == *"push"* ]] || { echo "$output"; false; }
  run bash_call 'git commit -m "feat: x"'
  denied && [[ "$(reason)" == *"vbw commit"* ]] || { echo "$output"; false; }
}
