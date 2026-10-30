#!/usr/bin/env bats
# R177 (docs/guards.md): during a run, VBW's guards deny any write by an agent
# to a path outside the project folder, a file write or a shell redirect, /tmp
# included, and say where the run may write instead. Inside the project the
# lease rules decide as before. Outside runs and outside VBW projects nothing
# changes. Found 2026-10-11: the Lead wrote /tmp/dbg.bats during a plan run and
# the file guard let it through (a path outside the project resolved to null,
# which the lease rule took as nothing to deny). L1: the hooks run through
# hooks.json the way Claude Code runs them (vbw_hook).

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "Customers pay", criteria: ["paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

open_run() { VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null; }

# write_in PATH: a Write by a Dev agent to PATH, as Claude Code hands it to the hook.
write_in() { jq -nc --arg d "${HOOK_DIR:-$PROJECT}" --arg p "$1" --arg a "${2:-vbw:dev}" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Write", agent_id: "a1", agent_type: $a, tool_input: {file_path: $p, content: "x"}}'; }
# bash_in COMMAND: a Bash call by a Dev agent.
bash_in() { jq -nc --arg d "${HOOK_DIR:-$PROJECT}" --arg c "$1" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash", agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}'; }

# denied_outside OUTPUT PATH: a deny whose reason names PATH, says it is outside the project and where to write.
denied_outside() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null || { echo "not denied: $1"; return 1; }
  local why
  why=$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  [ -n "${2:-}" ] || { echo "denied_outside needs the path the refusal must name"; return 1; }
  [[ "$why" == *"$2"* ]] || { echo "the refusal does not name $2: $why"; return 1; }
  [[ "$why" == *"outside the project"* ]] || { echo "the reason does not say outside the project: $why"; return 1; }
  [[ "$why" == *"Next: "* ]] || { echo "no next step: $why"; return 1; }
  # The place the advice names must be one the lease really allows (F135).
  [[ "$why" == *"or put scratch work in .vbw/runtime/scratch/" ]] || { echo "the advice does not name the scratch folder: $why"; return 1; }
}

# allowed OUTPUT: the hook let the call through (no answer).
allowed() { [ -z "$1" ] || { echo "not allowed: $1"; return 1; }; }

@test "R177: during a run a file write to /tmp is denied, naming the path and where the run may write" {
  open_run
  out=$(printf '%s' "$(write_in /tmp/scratch.txt)" | vbw_hook PreToolUse Write)
  denied_outside "$out" /tmp/scratch.txt
  [[ "$out" == *"there only its plan files (src/pay.txt)"* ]] || { echo "$out"; false; }
}

# where OUTPUT TEXT: the refusal says the run writes only inside the project, and there only TEXT.
where() { [[ "$1" == *"agents write only inside the project, and there only $2"* ]] || { echo "the refusal does not say where ($2): $1"; return 1; }; }

@test "R177 (F157): the refusal says where each kind of run may write: a plan run its test files and .vbw/, a fix of a failed project command any project file, a build its plan files" {
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  out=$(printf '%s' "$(write_in /tmp/dbg.bats vbw:lead)" | vbw_hook PreToolUse Write)
  denied_outside "$out" /tmp/dbg.bats
  where "$out" "the project's test files and .vbw/"
  out=$(printf '%s' "$(bash_in 'echo x > /tmp/dbg.log')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/dbg.log
  where "$out" "the project's test files and .vbw/"
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  jq '.commands = {test: ["sh", "tests/c1.sh"]} | .fixes = [{id: "F1", command: "test", attempts: 0, status: "open", note: "test fail"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  VBW_SESSION_ID=s1 "$VBW" run start fix F1 > /dev/null
  jq -e '.lease.files == null' .vbw/record.json > /dev/null
  out=$(printf '%s' "$(write_in /tmp/scratch.txt)" | vbw_hook PreToolUse Write)
  denied_outside "$out" /tmp/scratch.txt
  where "$out" "project files"
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  open_run
  out=$(printf '%s' "$(bash_in 'echo x > /tmp/scratch.txt')" | vbw_hook PreToolUse Bash)
  where "$out" "its plan files (src/pay.txt)"
}

@test "R177: during a run a shell redirect to /tmp is denied the same way" {
  open_run
  out=$(printf '%s' "$(bash_in 'echo hi > /tmp/scratch.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/scratch.txt
}

@test "R177 (F156): the clobber redirect >| is a redirect like any other: outside the project it is denied naming the path, and the plan's own file stays allowed" {
  open_run
  out=$(printf '%s' "$(bash_in 'echo a >| /tmp/x.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/x.txt
  out=$(printf '%s' "$(bash_in 'echo a >|/tmp/y.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/y.txt
  allowed "$(printf '%s' "$(bash_in 'echo a >| src/pay.txt')" | vbw_hook PreToolUse Bash)"
  allowed "$(printf '%s' "$(bash_in 'cat src/pay.txt | wc -l')" | vbw_hook PreToolUse Bash)"
}

@test "R177 (F149): bash's >&FILE and >& FILE forms write a file and are denied outside the project; >&1, 2>&1 and >&- are descriptors and pass" {
  open_run
  out=$(printf '%s' "$(bash_in 'echo a >&/tmp/a.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/a.txt
  out=$(printf '%s' "$(bash_in 'echo a >& /tmp/b.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/b.txt
  out=$(printf '%s' "$(bash_in 'echo a &> /tmp/c.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/c.txt
  local c
  for c in 'echo a >&1' 'echo a 2>&1' 'echo a >&-' 'cat <&0' 'npm test 2>&1 | tail -1'; do
    allowed "$(printf '%s' "$(bash_in "$c")" | vbw_hook PreToolUse Bash)" || { echo "refused: $c"; false; }
  done
}

@test "R177: a path outside the project that is not /tmp, and a relative path that climbs out, are denied too" {
  open_run
  out=$(printf '%s' "$(write_in "$TEST_ROOT/elsewhere.txt")" | vbw_hook PreToolUse Write)
  denied_outside "$out" "$TEST_ROOT/elsewhere.txt"
  out=$(printf '%s' "$(write_in ../outside.txt)" | vbw_hook PreToolUse Write)
  denied_outside "$out" ../outside.txt
}

@test "R177: an inline interpreter program that writes outside the project is denied, by absolute path and by a relative climb; the scratch folder stays allowed" {
  open_run
  out=$(printf '%s' "$(bash_in "python3 -c \"open('/tmp/q', 'w').write('x')\"")" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/q
  out=$(printf '%s' "$(bash_in "node -e \"require('fs').writeFileSync('/tmp/q.js', 'x')\"")" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/q.js
  out=$(printf '%s' "$(bash_in "python3 -c \"open('../outside.txt', 'w').write('x')\"")" | vbw_hook PreToolUse Bash)
  denied_outside "$out" ../outside.txt
  allowed "$(printf '%s' "$(bash_in "python3 -c \"open('.vbw/runtime/scratch/x', 'w').write('x')\"")" | vbw_hook PreToolUse Bash)"
}

@test "R177: the place the refusal names is writable: under a build lease a Dev writes under .vbw/runtime/scratch/, by file tool and by shell redirect, the folder itself included" {
  open_run
  allowed "$(printf '%s' "$(write_in .vbw/runtime/scratch/debug.log)" | vbw_hook PreToolUse Write)"
  allowed "$(printf '%s' "$(write_in "$PROJECT/.vbw/runtime/scratch/probe.sh")" | vbw_hook PreToolUse Write)"
  allowed "$(printf '%s' "$(bash_in 'mkdir -p .vbw/runtime/scratch && echo hi > .vbw/runtime/scratch/out.txt')" | vbw_hook PreToolUse Bash)"
}

@test "R177: the rest of .vbw/runtime/ is vbw's own: under a build lease the run marker and the glance stay refused" {
  open_run
  out=$(printf '%s' "$(write_in .vbw/runtime/run-open)" | vbw_hook PreToolUse Write)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null || { echo "run-open was allowed: $out"; false; }
  out=$(printf '%s' "$(write_in .vbw/runtime/glance.json)" | vbw_hook PreToolUse Write)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null || { echo "the glance was allowed: $out"; false; }
}

@test "R177: a read-only run promises no scratch folder: its refusal says the run writes nothing, and the scratch write is refused too" {
  VBW_SESSION_ID=s1 "$VBW" run start map > /dev/null
  out=$(printf '%s' "$(write_in /tmp/scratch.txt vbw:scout)" | vbw_hook PreToolUse Write)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null || { echo "not denied: $out"; false; }
  why=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  [[ "$why" == *"is outside the project: during a map run agents write nothing"* && "$why" == *"Next: leave it; report what you needed in your result, this run's agents write nothing" ]] || { echo "$why"; false; }
  out=$(printf '%s' "$(write_in .vbw/runtime/scratch/x.txt vbw:scout)" | vbw_hook PreToolUse Write)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null || { echo "a read-only run wrote scratch: $out"; false; }
}

@test "R177 (F147): a path the guard cannot resolve counts as outside: ~ and \$HOME redirects during a plan run, and a ~ file write, are refused" {
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  local c
  local p
  for c in 'echo a > ~/tests/a.test.js' 'echo a > $HOME/tests/a.test.js' 'echo a > "$HOME/tests/a.test.js"' 'echo a > `pwd`/../x.test.js' 'echo a > $(pwd)/tests/x.test.js'; do
    out=$(printf '%s' "$(bash_in "$c")" | vbw_hook PreToolUse Bash)
    # The refusal names the target as the guard read it: the text after >, unquoted; a cut-off backtick target as `...`.
    case "$c" in *'`'*) p='`...`' ;; *'$('*) p='$(...)' ;; *'"'*) p='$HOME/tests/a.test.js' ;; *) p=${c#*> } ;; esac
    denied_outside "$out" "$p" || { echo "let through or unnamed: $c"; false; }
    [[ "$out" == *"cannot be resolved by the guard"* ]] || { echo "$out"; false; }
  done
  # A file tool never expands ~: that is a folder named ~ inside the project, judged by the lease like any file.
  out=$(printf '%s' "$(write_in '~/notes.md')" | vbw_hook PreToolUse Write)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null || { echo "allowed: $out"; false; }
  [[ "$(printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason)" == *"~/notes.md cannot be written while planning"* ]] || { echo "$out"; false; }
}

@test "R177 (F159): a plan file with a \$ in its name is written through the file tool; a shell redirect to it is refused as unresolved, naming the file" {
  jq '.plans[0].files += ["src/$id.txt"]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(test): a plan file named with a dollar sign"
  "$VBW" approve > /dev/null
  open_run
  jq -e '.lease.files | index("src/$id.txt") != null' .vbw/record.json > /dev/null
  allowed "$(printf '%s' "$(write_in 'src/$id.txt')" | vbw_hook PreToolUse Write)"
  allowed "$(printf '%s' "$(write_in "$PROJECT/src/\$id.txt")" | vbw_hook PreToolUse Write)"
  out=$(printf '%s' "$(bash_in 'echo x > src/$id.txt')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" 'src/$id.txt'
  [[ "$out" == *"cannot be resolved by the guard"* ]] || { echo "$out"; false; }
}

@test "R177 (F148): the device files stay writable under a run, and nothing else under /dev is" {
  open_run
  local c
  for c in 'ls 2>/dev/null' 'echo x > /dev/stderr' 'echo x > /dev/stdout' 'echo x > /dev/tty' 'npm test > /dev/null 2>&1'; do
    allowed "$(printf '%s' "$(bash_in "$c")" | vbw_hook PreToolUse Bash)" || { echo "refused: $c"; false; }
  done
  out=$(printf '%s' "$(bash_in 'echo x > /dev/sda')" | vbw_hook PreToolUse Bash)
  denied_outside "$out" /dev/sda
  out=$(printf '%s' "$(write_in /dev/shm/x)" | vbw_hook PreToolUse Write)
  denied_outside "$out" /dev/shm/x
}

@test "R177: inside the project the lease rules decide as before: the plan's file is allowed, another file is refused as outside the run's files" {
  open_run
  out=$(printf '%s' "$(write_in src/pay.txt)" | vbw_hook PreToolUse Write)
  [ -z "$out" ] || { echo "the plan's file was not allowed: $out"; false; }
  out=$(printf '%s' "$(write_in src/other.txt)" | vbw_hook PreToolUse Write)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null
  [[ "$(printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason)" == *"outside this run's files"* ]] || { echo "$out"; false; }
}

@test "R177: from a subfolder of the project the project is still the git top, and a relative path is read from the session's folder" {
  open_run
  local sub="$PROJECT/Sub Folder With Spaces" out why
  mkdir -p "$sub"
  out=$(printf '%s' "$(HOOK_DIR="$sub" write_in ../src/pay.txt)" | HOOK_PROJECT_DIR="$sub" vbw_hook PreToolUse Write)
  allowed "$out"
  out=$(printf '%s' "$(HOOK_DIR="$sub" write_in src/pay.txt)" | HOOK_PROJECT_DIR="$sub" vbw_hook PreToolUse Write)
  why=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  [[ "$why" == "VBW guard: Sub Folder With Spaces/src/pay.txt is outside this run's files"* ]] || { echo "$out"; false; }
  out=$(printf '%s' "$(HOOK_DIR="$sub" write_in ../../elsewhere.txt)" | HOOK_PROJECT_DIR="$sub" vbw_hook PreToolUse Write)
  denied_outside "$out" ../../elsewhere.txt
  out=$(printf '%s' "$(HOOK_DIR="$sub" bash_in 'echo x > /tmp/dbg.log')" | HOOK_PROJECT_DIR="$sub" vbw_hook PreToolUse Bash)
  denied_outside "$out" /tmp/dbg.log
  # An agent told the project folder (args.root) writes scratch work under it by absolute path.
  out=$(printf '%s' "$(HOOK_DIR="$sub" write_in "$PROJECT/.vbw/runtime/scratch/x")" | HOOK_PROJECT_DIR="$sub" vbw_hook PreToolUse Write)
  allowed "$out"
  out=$(printf '%s' "$(HOOK_DIR="$sub" bash_in "mkdir -p '$PROJECT/.vbw/runtime/scratch' && echo x > '$PROJECT/.vbw/runtime/scratch/x.log'")" | HOOK_PROJECT_DIR="$sub" vbw_hook PreToolUse Bash)
  allowed "$out"
}

@test "R177: with no run open a write outside the project gets no answer from VBW" {
  out=$(printf '%s' "$(write_in /tmp/scratch.txt)" | vbw_hook PreToolUse Write)
  [ -z "$out" ] || { echo "$out"; false; }
}

@test "R177: outside a VBW project the guards say nothing" {
  mkdir -p "$TEST_ROOT/plain"
  out=$(cd "$TEST_ROOT/plain" && printf '%s' "$(HOOK_DIR="$TEST_ROOT/plain" write_in /tmp/scratch.txt)" | HOOK_PROJECT_DIR="$TEST_ROOT/plain" vbw_hook PreToolUse Write)
  [ -z "$out" ] || { echo "$out"; false; }
}

@test "R177 (F158): no test of this file runs a helper function inside bash -c, where it would not exist and its error would be swallowed" {
  ! grep -nE "bash -c '[^']*(vbw_hook|write_in|bash_in|denied_outside|allowed)" "$BATS_TEST_FILENAME"
}
