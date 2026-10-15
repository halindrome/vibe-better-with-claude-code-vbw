#!/usr/bin/env bats
# R188 (P140; docs/proof.md, docs/guards.md): a test that cannot fail is
# strengthened in place during the build, and waits for one approval. Once
# vbw mutate records a survivor in a build run, the check files of that rule's
# check that no other requirement uses become writable for the run's agents;
# every other check file stays protected. vbw commit PLAN commits such a file
# with the plan's trailers (a check file with no survivor in that plan is
# refused), and the proof's scope check does not count that commit as outside
# the plan. The changed check file lets the build finish, then vbw next asks
# for one approval naming it before the proof, and vbw prove refuses until it is
# given. L1: the kernel and the hooks on a fixture project.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  printf 'true\n' > tests/shared.sh
  # C1 cannot fail on what is printed; tests/shared.sh serves C1 and C2.
  printf 'sh src/pay.sh > /dev/null && sh tests/shared.sh\n' > tests/pay.sh
  printf '[ "$(sh src/receipt.sh)" = receipt ] && sh tests/shared.sh\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "g", criteria: ["c"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh", "tests/shared.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh", "tests/shared.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  # P2 asks for no mutation check (express), so only P1's break is in play.
  jq '(.phases[] | select(.id == "P2")).tier = "express"' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P2.1 > /dev/null
}

teardown() { vbw_teardown; }

# file_in TOOL PATH: a build agent's file tool call in session s1.
file_in() {
  jq -nc --arg t "$1" --arg p "$2" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: env.PROJECT,
    tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}, agent_id: "x1", agent_type: "workflow-subagent"}'
}
# answer TOOL PATH: the file guard's answer to that call, in ANSWER.
answer() { ANSWER=$(file_in "$1" "$2" | vbw_hook PreToolUse "$1"); }
denied() { [[ "$ANSWER" == *'"deny"'* ]] || { echo "not denied: $ANSWER"; return 1; }; }
allowed() { [ -z "$ANSWER" ] || { echo "not allowed: $ANSWER"; return 1; }; }

# survivor: a break of src/pay.sh C1 cannot notice, recorded as a survivor of R1.1.
survivor() {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "no survivor: $output"; return 1; }
}
strengthen() { printf '[ "$(sh src/pay.sh)" = paid ] && sh tests/shared.sh\n' > tests/pay.sh; }

@test "R188: before a survivor a build agent cannot write a check file; after it, only the survivor's own check files open" {
  answer Write tests/pay.sh
  denied
  survivor
  answer Write tests/pay.sh
  allowed
  answer Edit tests/pay.sh
  allowed
  # Shared with R2, and R2's own: still protected.
  answer Write tests/shared.sh
  denied
  answer Edit tests/receipt.sh
  denied
}

@test "R188: vbw commit PLAN commits a survivor's check file with the plan's trailers; any other check file is refused" {
  strengthen
  run "$VBW" commit P1.1 "test(pay): check what is printed" tests/pay.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "committed with no survivor: $output"; false; }
  git checkout -q -- tests/pay.sh
  survivor
  strengthen
  run "$VBW" commit P1.1 "test(pay): check what is printed" tests/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = tests/pay.sh ]
  git log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | grep -qx P1.1
  printf '[ "$(sh src/receipt.sh)" = receipt ]\n' > tests/receipt.sh
  run "$VBW" commit P1.1 "test(pay): not mine" tests/receipt.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R188: a strengthened check file lets the build finish, then one approval is asked before the proof, which refuses until then; the scope check counts the commit as the plan's" {
  survivor
  strengthen
  "$VBW" commit P1.1 "test(pay): check what is printed" tests/pay.sh > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  printf 'echo receipt\n# thanks\n' > src/receipt.sh
  "$VBW" commit P2.1 "feat(receipt): thanks" > /dev/null
  "$VBW" plan done P2.1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "approve" and .gate == true and .detail.files == ["tests/pay.sh"]' || { echo "$output"; false; }
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *tests/pay.sh* ]] || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  run "$VBW" prove < /dev/null
  jq -e '.evidence.scope == []' .vbw/record.json || { echo "$output"; jq '.evidence.scope' .vbw/record.json; false; }
}

@test "R188: in a build run a check file changed and not committed refuses the break, naming it, nothing written (commit it first)" {
  survivor
  strengthen
  local sum
  sum=$(cksum < .vbw/record.json)
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *tests/pay.sh* && "$output" == *"commit them first"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$sum" ]
}
