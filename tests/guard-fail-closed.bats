#!/usr/bin/env bats
# R165 (docs/guards.md): during a VBW run (the record shows a run lease), a
# guard that crashes, cannot start or runs past its time limit blocks the file
# write or Bash command it guards instead of letting it through, with a message
# that says the guard failed and what to do (vbw doctor). The same holds when
# the guard must read the record (its small side file, the glance, is not
# current) and the record cannot be parsed. In a VBW project with no open run a
# failing guard lets the action through as before; outside VBW projects a
# failing or missing guard changes nothing and prints nothing. The time limit is
# written in docs/guards.md. The doctor's guard self-test still passes. L1: the
# hooks.json commands run as Claude Code runs them (sh -c, hook input on stdin)
# from a copy of the plugin whose guard is broken on purpose.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: []}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  COPY="$TEST_ROOT/plugin copy"
  cp -R "$PLUGIN_ROOT" "$COPY"
  export COPY
}

teardown() {
  [ -z "${COPY:-}" ] || chmod -R u+rw "$COPY" 2> /dev/null || true
  vbw_teardown
}

# open_run: a build run of session s1, opened by the kernel.
open_run() { VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null; }

# break_guard HOW: break both guards of the copy. crash: the guard stops with
# a jq error; hang: it never ends; missing: the guard file is gone;
# unreadable: it cannot be read.
break_guard() {
  local g
  for g in guard-file.jq guard-bash.jq; do
    case "$1" in
      crash) printf 'error("broken on purpose")\n' > "$COPY/hooks/$g" ;;
      hang) printf 'reduce range(1e15) as $i (0; . + 1)\n' > "$COPY/hooks/$g" ;;
      missing) rm -f "$COPY/hooks/$g" ;;
      unreadable) chmod 000 "$COPY/hooks/$g" ;;
    esac
  done
}

# hook TOOL INPUT_JSON [PATH]: the copy's hooks.json command for TOOL, run as
# Claude Code runs it, with PATH as given (default: this PATH). Sets CODE, OUT,
# ERR and SECS (wall-clock seconds).
hook() {
  local cmd start
  cmd=$(jq -r --arg t "$1" '[.hooks.PreToolUse[] | select((.matcher // "") as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$COPY/hooks/hooks.json")
  CODE=0
  start=$(date +%s)
  OUT=$(printf '%s' "$2" | env PATH="${3:-$PATH}" CLAUDE_PLUGIN_ROOT="$COPY" CLAUDE_PROJECT_DIR="${HOOK_DIR:-$PROJECT}" sh -c "$cmd" 2> "$TEST_ROOT/err") || CODE=$?
  SECS=$(($(date +%s) - start))
  ERR=$(cat "$TEST_ROOT/err")
}

write_in() { jq -nc --arg d "${HOOK_DIR:-$PROJECT}" --arg a "${1:-}" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Write",
  tool_input: {file_path: "src/pay.txt", content: "paid"}} + (if $a == "" then {} else {agent_id: "a1", agent_type: $a} end)'; }
bash_in() { jq -nc --arg d "${HOOK_DIR:-$PROJECT}" --arg a "${1:-}" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash",
  tool_input: {command: "ls"}} + (if $a == "" then {} else {agent_id: "a1", agent_type: $a} end)'; }

# blocked: the last hook call blocked the action (a deny answer, or exit 2 with
# a message), saying the guard failed and naming vbw doctor.
blocked() {
  local why
  if [ "$CODE" -eq 2 ] && [ -n "$ERR" ]; then
    why=$ERR
  elif printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1; then
    why=$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.permissionDecisionReason)
  else
    echo "not blocked: exit $CODE, stdout '$OUT', stderr '$ERR'"
    return 1
  fi
  printf '%s' "$why" | grep -qi 'guard' && printf '%s' "$why" | grep -q 'vbw doctor' \
    || { echo "the message does not say the guard failed and name vbw doctor: $why"; return 1; }
  printf '%s' "$OUT" | grep -q '"allow"' && { echo "an allow answer: $OUT"; return 1; }
  return 0
}

# through: the last hook call let the action through with no answer and no message.
through() {
  [ "$CODE" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] || { echo "not let through quietly: exit $CODE, stdout '$OUT', stderr '$ERR'"; return 1; }
}

# each_blocked WHAT: a Write and a Bash call, from the main conversation and from an agent, all blocked.
each_blocked() {
  local who
  for who in "" vbw:dev; do
    hook Write "$(write_in "$who")"
    blocked || { echo "Write (${who:-main}): $1"; return 1; }
    hook Bash "$(bash_in "$who")"
    blocked || { echo "Bash (${who:-main}): $1"; return 1; }
  done
}

# nojq: a PATH with every program of /bin and /usr/bin except jq.
nojq() {
  local d="$TEST_ROOT/nojq" f
  mkdir -p "$d"
  for f in /bin/* /usr/bin/*; do
    case "${f##*/}" in jq) continue ;; esac
    [ -x "$f" ] && [ ! -e "$d/${f##*/}" ] && ln -s "$f" "$d/${f##*/}"
  done
  printf '%s' "$d"
}

@test "R165: during a run a guard that crashes blocks the write or command, saying the guard failed and to run vbw doctor" {
  open_run
  break_guard crash
  each_blocked crash
}

@test "R165: during a run a guard that cannot start blocks: the guard file missing or unreadable" {
  open_run
  break_guard missing
  each_blocked missing
  cp "$PLUGIN_ROOT/hooks/guard-file.jq" "$PLUGIN_ROOT/hooks/guard-bash.jq" "$COPY/hooks/"
  [ "$(id -u)" -ne 0 ] || skip "root reads any file"
  break_guard unreadable
  each_blocked unreadable
}

@test "R165: during a run a guard that cannot start because jq is missing blocks" {
  open_run
  local p
  p=$(nojq)
  hook Write "$(write_in vbw:dev)" "$p"
  blocked
  hook Bash "$(bash_in)" "$p"
  blocked
}

@test "R165: during a run a guard that runs past its time limit is stopped and the action blocked; docs/guards.md states the limit" {
  grep -qi 'time limit' "$REPO_ROOT/docs/guards.md" || { echo "docs/guards.md states no time limit"; false; }
  open_run
  break_guard hang
  hook Bash "$(bash_in vbw:dev)"
  blocked
  [ "$SECS" -le 30 ] || { echo "the hang lasted $SECS s"; false; }
  hook Write "$(write_in)"
  blocked
  [ "$SECS" -le 30 ] || { echo "the hang lasted $SECS s"; false; }
}

@test "R165: during a run a record that cannot be parsed blocks the action when the guard must read it" {
  open_run
  printf '{"schema": 4, "lease": ' > .vbw/record.json
  each_blocked "corrupt record"
}

@test "R165: in a VBW project with no open run a failing guard lets the action through as before" {
  local how
  for how in crash missing; do
    cp "$PLUGIN_ROOT/hooks/guard-file.jq" "$PLUGIN_ROOT/hooks/guard-bash.jq" "$COPY/hooks/"
    break_guard "$how"
    hook Write "$(write_in vbw:dev)"
    through || { echo "$how"; false; }
    hook Bash "$(bash_in)"
    through || { echo "$how"; false; }
  done
  hook Bash "$(bash_in)" "$(nojq)"
  through
}

@test "R165: outside VBW projects a failing or missing guard changes nothing and prints nothing" {
  HOOK_DIR="$TEST_ROOT/plain"
  export HOOK_DIR
  mkdir -p "$HOOK_DIR"
  local how
  for how in crash missing; do
    cp "$PLUGIN_ROOT/hooks/guard-file.jq" "$PLUGIN_ROOT/hooks/guard-bash.jq" "$COPY/hooks/"
    break_guard "$how"
    hook Write "$(write_in vbw:dev)"
    through || { echo "$how"; false; }
    hook Bash "$(bash_in)"
    through || { echo "$how"; false; }
  done
  hook Write "$(write_in)" "$(nojq)"
  through
}

@test "R165: with the guards intact a run still gets their ordinary answers, and the doctor's guard self-test passes" {
  open_run
  hook Write "$(write_in vbw:dev)"
  through
  hook Bash "$(bash_in vbw:dev)"
  through
  run "$VBW" doctor
  [[ "$output" == *"the guards work"* ]] || { echo "$output"; false; }
}
