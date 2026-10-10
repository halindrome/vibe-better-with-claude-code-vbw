#!/usr/bin/env bats
# R160 (docs/proof.md, docs/guards.md): a fix that follows a QA finding can add
# its regression test. During a fix run for a fix QA opened, the Dev may create
# a new test file and edit the approved check files of the finding's
# requirement; a check file of any other requirement stays blocked, with a
# message that says what to do instead. The new test is registered with
# vbw fix check FIX (a check document on stdin: run, files and the optional
# fields vbw apply takes) as a check of the finding's requirement, and vbw show
# lists it under that requirement, naming the fix. Before vbw prove runs any
# new or changed check file of the fix, vbw next asks once for the user's
# approval, naming every such file; nothing runs them before the approval, and
# without it vbw prove names the waiting files and the next step while the fix
# stays open. The approval is by content: a later change needs a new one.
# Outside fix runs for QA findings, check files stay protected as before. L1.

load helper

# R1 (pay) and R2 (refund) [auto]; plan P1.1 writes src/pay.txt and
# src/refund.txt; C1 (R1) runs tests/c1.sh, C2 (R2) runs tests/c2.sh.
setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf 'test -f src/refund.txt\n' > tests/c2.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1", "R2"], goal: "Customers pay and get refunds", criteria: ["paid", "refunded"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt", "src/refund.txt"], after: [], tasks: ["pay", "refund", "note"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}, {req: "R2", text: "a refund is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

# built [refund]: P1.1 built and proved (with the refund only when asked).
built() {
  printf 'paid\n' > src/pay.txt
  [ "${1:-}" != refund ] || printf 'refund\n' > src/refund.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
}

# qa_fix_run: QA found a problem with R1 (fix F_QA) and its fix run is open (session s1).
qa_fix_run() {
  "$VBW" qa finding R1 "a payment of zero is accepted" > /dev/null
  F_QA=$(jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json)
  export F_QA
  VBW_SESSION_ID=s1 "$VBW" run start fix "$F_QA" > /dev/null
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

# regression: the Dev's new test, which leaves a mark whenever it runs. The mark
# is an absolute path outside the project: vbw prove runs checks in a copy of
# the committed project, so a mark inside the project would never be seen.
regression() {
  printf ': > "%s"\ngrep -qx paid src/pay.txt\n' "$TEST_ROOT/ran-regression" > tests/r1-regression.sh
}
register() {
  printf '%s' '{"run": ["sh", "tests/r1-regression.sh"], "files": ["tests/r1-regression.sh"]}' | VBW_SESSION_ID=s1 "$VBW" fix check "$F_QA"
}
new_check() { jq -r --arg f "$F_QA" '[.checks[] | select(.fix == $f)][0].id // empty' .vbw/record.json; }

# fixed_and_ended: the Dev edits C1's file, adds and registers the regression
# test, commits, reports the fix done and the run ends.
fixed_and_ended() {
  regression
  register > /dev/null
  printf 'grep -qx paid src/pay.txt\ntest -s src/pay.txt\n' > tests/c1.sh
  git add tests/c1.sh tests/r1-regression.sh
  git commit -q -m "test(pay): regression for the zero payment"
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  VBW_SESSION_ID=s1 "$VBW" fix done "$F_QA" > /dev/null 2>&1 || true
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
}

@test "R160: during a fix run for a QA finding the Dev may create a new test file" {
  built refund
  qa_fix_run
  local out
  out=$(file_call Write tests/r1-regression.sh)
  ! denied "$out" || { echo "$out"; false; }
  out=$(bash_call 'printf "true\n" > tests/r1-regression.sh')
  ! denied "$out" || { echo "$out"; false; }
}

@test "R160: during that run the Dev may edit an approved check file of the finding's requirement" {
  built refund
  qa_fix_run
  local out
  out=$(file_call Edit tests/c1.sh)
  ! denied "$out" || { echo "$out"; false; }
}

@test "R160: a check file of another requirement stays blocked, and the message names it and says what to do instead" {
  built refund
  qa_fix_run
  local out
  out=$(file_call Edit tests/c2.sh)
  denied "$out" || { echo "not blocked: $out"; false; }
  printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason | grep -q 'tests/c2.sh' || { echo "$out"; false; }
  printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason | grep -q 'Next: ' || { echo "no next step: $out"; false; }
  out=$(bash_call 'printf x > tests/c2.sh')
  denied "$out" || { echo "not blocked: $out"; false; }
}

@test "R160: the new test is registered as a check of the finding's requirement, and vbw show names the fix it came from" {
  built refund
  qa_fix_run
  regression
  run register
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local id
  id=$(new_check)
  [ -n "$id" ] || { jq -c .checks .vbw/record.json; false; }
  jq -e --arg id "$id" '.checks[] | select(.id == $id) | .req == "R1" and .run == ["sh", "tests/r1-regression.sh"] and .files == ["tests/r1-regression.sh"]' .vbw/record.json
  run "$VBW" show req R1
  printf '%s\n' "$output" | grep "$id" | grep -q "$F_QA" || { echo "$output"; false; }
}

@test "R160: one approval question names every new or changed check file of the fix, and nothing runs them before it" {
  built refund
  qa_fix_run
  fixed_and_ended
  [ ! -e "$TEST_ROOT/ran-regression" ] || { echo "the new test ran before the approval"; false; }
  local next
  next=$("$VBW" next --json < /dev/null)
  printf '%s' "$next" | jq -e '.action == "approve" and .gate == true and .detail.files == ["tests/c1.sh", "tests/r1-regression.sh"]' || { echo "$next"; false; }
  printf '%s' "$next" | jq -r .instruction | grep -q 'tests/r1-regression.sh' || { echo "$next"; false; }
  printf '%s' "$next" | jq -r .instruction | grep -q 'tests/c1.sh' || { echo "$next"; false; }
}

@test "R160: without the approval vbw prove runs none of them, names the waiting files and the next step, and the fix stays open" {
  built refund
  qa_fix_run
  fixed_and_ended
  run "$VBW" prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [ ! -e "$TEST_ROOT/ran-regression" ] || { echo "the new test ran before the approval"; false; }
  [[ "$output" == *"tests/r1-regression.sh"* && "$output" == *"tests/c1.sh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"approv"* ]] || { echo "$output"; false; }
  jq -e --arg f "$F_QA" '.fixes[] | select(.id == $f) | .status != "closed"' .vbw/record.json
}

@test "R160: once approved, vbw prove runs the new test" {
  built refund
  qa_fix_run
  fixed_and_ended
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  [ -e "$TEST_ROOT/ran-regression" ] || { echo "the new test did not run after the approval"; false; }
  jq -e --arg id "$(new_check)" '.evidence.checks[$id].status == "pass"' .vbw/record.json
}

@test "R160: the approval is by content: a later change to the new test waits for a new approval" {
  built refund
  qa_fix_run
  fixed_and_ended
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  rm -f "$TEST_ROOT/ran-regression"
  printf 'test -s src/pay.txt\n' >> tests/r1-regression.sh
  git add tests/r1-regression.sh
  git commit -q -m "test(pay): stricter"
  run "$VBW" prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [ ! -e "$TEST_ROOT/ran-regression" ] || { echo "the changed test ran without a new approval"; false; }
  [[ "$output" == *"tests/r1-regression.sh"* ]] || { echo "$output"; false; }
}

@test "R160: outside fix runs for QA findings check files stay protected as before" {
  local out
  # A build run: neither a check file nor a new test file outside the plan.
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  out=$(file_call Edit tests/c1.sh)
  denied "$out" || { echo "build run, check file: $out"; false; }
  out=$(file_call Write tests/new-test.sh)
  denied "$out" || { echo "build run, new test file: $out"; false; }
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  # A fix run for a fix the proof opened (R2's refund went missing), not QA.
  built refund
  rm src/refund.txt
  "$VBW" commit P1.1 "fix(pay): drop the refund" > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  local f
  f=$(jq -r '[.fixes[] | select(.req == "R2" and (.source // "") != "qa")][0].id' .vbw/record.json)
  VBW_SESSION_ID=s1 "$VBW" run start fix "$f" > /dev/null
  out=$(file_call Edit tests/c2.sh)
  denied "$out" || { echo "proof fix run, its check file: $out"; false; }
  out=$(file_call Write tests/r2-new.sh)
  denied "$out" || { echo "proof fix run, new test file: $out"; false; }
  # Another session's main conversation, outside the run: the same answer as before (none).
  out=$(jq -nc --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s2", cwd: $d, tool_name: "Edit", tool_input: {file_path: "tests/c1.sh"}}' | vbw_hook PreToolUse Edit)
  [ -z "$out" ] || { echo "another session: $out"; false; }
}
