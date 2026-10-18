#!/usr/bin/env bats
# R192, phase P152 (L1): the file and Bash guards' "being written by run ... of
# another session" reason names the holder by its display name, from the
# glance's `holder` alone (the name vbw run start stored; no extra file read on
# the hot path): the stored name, else the first 8 characters of the id. A name
# with escape sequences is shown clean. When the glance is not current the guard
# reads the record, which never carries the name (D442), and falls back to the id.

load helper
load sessions-helper

GLANCE=.vbw/runtime/glance.json

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id: "C1", req: "R1", run: ["true"]}] | .phases = [{id: "P1", title: "A", reqs: ["R1"], milestone: "M1"}]
      | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["src/"], after: [], status: "planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  mkdir -p src
}

teardown() { vbw_teardown; }

file_write() {
  jq -nc --arg s "$1" --arg p "$PROJECT/src/a.txt" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' \
    | vbw_hook PreToolUse Write
}
bash_write() {
  jq -nc --arg s "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: $s, cwd: $d, tool_name: "Bash", tool_input: {command: "printf x > src/a.txt"}}' \
    | vbw_hook PreToolUse Bash
}
reason() { jq -r '.hookSpecificOutput | select(.permissionDecision == "deny") | .permissionDecisionReason' ; }

@test "R192: another session's file write is refused naming the holder by its stored name, from the glance" {
  registry_entry 101 "$SESSION_A" "Payments work"
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start build P1.1 > /dev/null
  jq -e '.holder.session_name == "Payments work"' "$GLANCE"
  local r
  r=$(file_write "$SESSION_B" | reason)
  [[ "$r" == *"of another session (Payments work)"* ]] || { echo "$r"; false; }
  [[ "$r" != *"$SESSION_A"* ]] || { echo "$r"; false; }
  # The guard reads only the glance: a later /rename in the list does not reach it.
  registry_entry 101 "$SESSION_A" "Checkout fix" 1792300090000
  r=$(file_write "$SESSION_B" | reason)
  [[ "$r" == *"(Payments work)"* ]] || { echo "$r"; false; }
}

@test "R192: the Bash guard names the holder the same way" {
  registry_entry 101 "$SESSION_A" "Payments work"
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start build P1.1 > /dev/null
  local r
  r=$(bash_write "$SESSION_B" | reason)
  [[ "$r" == *"of another session (Payments work)"* ]] || { echo "$r"; false; }
}

@test "R192: with no stored name the first 8 characters of the id name the holder; the holder's own session is not refused" {
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start build P1.1 > /dev/null
  local r
  r=$(file_write "$SESSION_B" | reason)
  [[ "$r" == *"of another session (01234567)"* ]] || { echo "$r"; false; }
  [[ "$r" != *"$SESSION_A"* ]] || { echo "$r"; false; }
  r=$(file_write "$SESSION_A" | reason)
  [ -z "$r" ] || { echo "$r"; false; }
}

@test "R192: a stored name with escape sequences is shown clean" {
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start build P1.1 > /dev/null
  # The stored copy is rewritten by hand with raw sequences; the glance is rebuilt from it.
  jq -c --arg n "$(printf 'Pay\033[31mments\007 work')" '.session_name = $n' .vbw/runtime/holder.json > "$TEST_ROOT/h.json"
  cp "$TEST_ROOT/h.json" .vbw/runtime/holder.json
  touch .vbw/record.json
  "$VBW" status > /dev/null
  jq -e '.holder.session_name | contains("\u001b")' "$GLANCE"
  local r
  r=$(file_write "$SESSION_B" | reason)
  [[ "$r" == *"(Payments work)"* ]] || { echo "$r"; false; }
  [[ "$r" != *$'\033'* && "$r" != *$'\007'* ]] || { echo "$r"; false; }
}

@test "R192: when the glance is not current the guard reads the record, which never carries the name, and names the id" {
  registry_entry 101 "$SESSION_A" "Payments work"
  VBW_SESSION_ID="$SESSION_A" "$VBW" run start build P1.1 > /dev/null
  sleep 1
  touch .vbw/record.json
  local r
  r=$(file_write "$SESSION_B" | reason)
  [[ "$r" == *"of another session (01234567)"* ]] || { echo "$r"; false; }
  [[ "$r" != *"Payments work"* ]] || { echo "$r"; false; }
}
