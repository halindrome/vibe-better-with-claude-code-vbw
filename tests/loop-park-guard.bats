#!/usr/bin/env bats
# R179 (P129; docs/guards.md): vbw loop park is callable only by the kernel's
# loop step: the Bash guard denies it from any tool call (an agent's or the
# main session's) with the pinned text, inside sh -c and $(...) too. L1.

load helper
load loop-helper
load fixture-helper

setup_file() { fixture_build started loop_started T1 --no-ceiling; }
setup() { fixture_copy started; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" --argjson x "${2:-null}" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", cwd: $d, tool_input: {command: $c}} + $x' \
    | vbw_hook PreToolUse Bash
}
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

STEP_TEXT='VBW guard: vbw loop next and vbw loop park are the kernel'"'"'s own loop steps: the Stop hook of /vbw:loop runs them, never a tool call
Next: end your turn; the loop'"'"'s Stop hook gives the next step'

@test "R179: vbw loop park is denied from any tool call with the pinned text" {
  local c
  for c in 'vbw loop park' "\"$PLUGIN_ROOT/bin/vbw\" loop park" 'sh -c "vbw loop park"' 'echo "$(vbw loop park)"' 'cd sub && vbw loop park'; do
    run bash_call "$c"
    [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ] || { echo "not denied: $c -> $output"; false; }
    [ "$(reason)" = "$STEP_TEXT" ] || { echo "$c -> $(reason)"; false; }
  done
  run bash_call 'vbw loop park' '{"agent_type": "dev"}'
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
  run bash_call 'vbw loop park' '{"agent_type": "lead"}'
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
}

@test "R179: the denial holds with no loop on and in a project with a stale glance" {
  edit_record 'del(.loop)'
  run bash_call 'vbw loop park'
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
  rm -f .vbw/runtime/glance.json
  run bash_call 'vbw loop park'
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
}
