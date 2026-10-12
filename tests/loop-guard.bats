#!/usr/bin/env bats
# R178 (P127; docs/guards.md, docs/loop.md): the approval by delegation happens
# only inside the kernel's own loop step, never through a command Claude can
# run to approve. The Bash guard denies vbw loop start from any tool call in a
# VBW project (as it denies vbw approve: arming the loop is the user's own act),
# and the kernel's loop steps (vbw loop next, vbw loop park) the same way; each
# denial text is pinned here. The /vbw:loop skill is user-invoked only
# (disable-model-invocation) and runs vbw loop start in its preamble with the
# user's own arguments; no other skill runs it. L1.

load helper
load loop-helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
teardown() { vbw_teardown; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" --argjson x "${2:-null}" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", cwd: $d, tool_input: {command: $c}} + $x' \
    | vbw_hook PreToolUse Bash
}
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]; }

START_TEXT='VBW guard: only the user arms the loop: /vbw:loop ITEM... --ceiling USD is the user'"'"'s own command, like /vbw:approve
Next: ask the user to run /vbw:loop with the items and the ceiling they choose; never run vbw loop start yourself'
STEP_TEXT='VBW guard: vbw loop next and vbw loop park are the kernel'"'"'s own loop steps: the Stop hook of /vbw:loop runs them, never a tool call
Next: end your turn; the loop'"'"'s Stop hook gives the next step'

@test "R178: vbw loop start from any tool call is denied, however it is spelled, with the pinned text" {
  local c
  for c in 'vbw loop start T1 --no-ceiling' "\"$PLUGIN_ROOT/bin/vbw\" loop start T1 T2 --ceiling 5" 'bash plugin/bin/vbw loop start T1 --ceiling 5 --finish-item' \
           'sh -c "vbw loop start T1 --no-ceiling"' 'echo "$(vbw loop start T1 --no-ceiling)"' 'cd x && vbw loop start T1 --no-ceiling'; do
    run bash_call "$c"
    denied || { echo "not denied: $c -> $output"; false; }
    [ "$(reason)" = "$START_TEXT" ] || { echo "$c -> $(reason)"; false; }
  done
  run bash_call 'vbw loop start T1 --no-ceiling' '{"agent_type": "dev"}'
  denied
}

@test "R178: the kernel's loop steps, vbw loop next and vbw loop park, are denied from any tool call with the pinned text" {
  local c
  for c in 'vbw loop next --json' 'VBW_SESSION_ID=s1 vbw loop next --json' 'vbw loop park' "\"$PLUGIN_ROOT/bin/vbw\" loop park"; do
    run bash_call "$c"
    denied || { echo "not denied: $c -> $output"; false; }
    [ "$(reason)" = "$STEP_TEXT" ] || { echo "$c -> $(reason)"; false; }
  done
}

@test "R178: vbw loop stop, status and help, and the words in text, stay allowed" {
  local c
  for c in 'vbw loop stop' 'vbw loop status' 'vbw loop status --json' 'vbw loop --help' 'vbw loop start --help' \
           'echo "vbw loop start T1 --no-ceiling"' 'git commit -m "docs: vbw loop start is the user'"'"'s"' 'grep -rn "vbw loop next" docs'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "denied: $c -> $output"; false; }
  done
}

@test "R178: the /vbw:loop skill is user-invoked only and arms the loop in its preamble with the user's own arguments" {
  local f="$PLUGIN_ROOT/skills/loop/SKILL.md" front
  [ -f "$f" ]
  front=$(awk 'NR == 1 && /^---$/ { on = 1; next } on && /^---$/ { exit } on' "$f")
  printf '%s\n' "$front" | grep -qx 'disable-model-invocation: true'
  printf '%s\n' "$front" | grep -qx 'name: loop'
  # The preamble runs the kernel by its plugin path with $ARGUMENTS, as the approve skill runs vbw approve.
  awk '/^```!$/ { on = 1; next } on && /^```$/ { on = 0 } on' "$f" | grep -qE '^"\$\{CLAUDE_PLUGIN_ROOT\}/bin/vbw" loop start .*\$ARGUMENTS.* \|\| true$'
  # The Stop hook is the kernel's gate, the one the router registers.
  printf '%s\n' "$front" | grep -qF '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" auto gate 2>/dev/null || true'
}

@test "R178: no other skill arms the loop, and the guards doc names the denial" {
  local f
  while IFS= read -r f; do
    [ "$f" = "$PLUGIN_ROOT/skills/loop/SKILL.md" ] && continue
    ! grep -q 'bin/vbw" loop start' "$f" || { echo "arms the loop outside /vbw:loop: $f"; false; }
  done < <(find "$PLUGIN_ROOT/skills" -name SKILL.md | LC_ALL=C sort)
  grep -qF 'vbw loop start' "$REPO_ROOT/docs/guards.md"
}

@test "R178 (F167): --help as a value arms nothing: only a bare help form passes the guard" {
  run bash_call 'vbw loop start --session --help T1 --no-ceiling'
  denied || { echo "not denied: $output"; false; }
  [ "$(reason)" = "$START_TEXT" ] || { reason; false; }
  run bash_call 'vbw loop start T1 --no-ceiling -h'
  denied || { echo "not denied: $output"; false; }
  local c
  for c in 'vbw loop --help' 'vbw loop -h' 'vbw loop start --help' 'vbw loop start -h'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "refused: $c -> $output"; false; }
  done
}
