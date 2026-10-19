#!/usr/bin/env bats
# R194 (T124, T165; docs/proof.md, docs/workflows.md): vbw commit --fix FIX
# MESSAGE FILE... for an open requirement fix of any source (QA-opened, or
# opened by vbw prove for a failing check) commits the named changed check files
# of the fix's requirement with both trailers, VBW-Fix and VBW-Req. The message
# is validated as today; the commit touches only the named changed files and
# leaves the user's staged work staged. Refused, committing nothing: a check file
# of another requirement (named), a code file (commit it through its plan), a
# path under .vbw/ or outside the project, an unknown or non-open fix, a file
# that did not change, and a fix of a [human] requirement, which has no check
# files. A project-command fix keeps today's behaviour. After such a commit the
# file waits for one approval: vbw fix done names it, vbw next asks once naming
# it, vbw prove refuses until then and runs it after; the commit shows under its
# requirement and the proof's scope check blames no plan. The Dev's instructions
# say so. L1: the kernel on a fixture project.

load helper

# R1 (pay) and R2 (refund) [auto], R3 [human]; P1.1 writes src/pay.txt and
# src/refund.txt, P1.2 src/ui.txt; C1 (R1) runs tests/c1.sh, C2 (R2) tests/c2.sh.
# Built and proved, then the user breaks the payment: the proof opens F_PROVE for R1.
setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a refund\n- R3 [human] Paying feels safe\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf 'test -f src/refund.txt\n' > tests/c2.sh
  printf 'three\n' > src/staged.txt
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1", "R2", "R3"], goal: "Customers pay and get refunds", criteria: ["paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt", "src/refund.txt"], after: [], tasks: ["pay", "refund"]},
            {id: "P1.2", phase: "P1", title: "Feel", reqs: ["R3"], files: ["src/ui.txt"], after: [], tasks: ["calm words"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}, {req: "R2", text: "a refund is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt
  printf 'refund\n' > src/refund.txt
  printf 'calm\n' > src/ui.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" commit P1.2 "feat(ui): calm" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" plan done P1.2 > /dev/null
  "$VBW" prove > /dev/null 2>&1 || { echo "the first proof failed"; return 1; }
  printf 'unpaid\n' > src/pay.txt
  git commit -q -am "feat(pay): a bug"
  "$VBW" prove > /dev/null 2>&1 || true
  F_PROVE=$(jq -r '[.fixes[] | select(.req == "R1" and .status == "open")][0].id // empty' .vbw/record.json)
  [ -n "$F_PROVE" ] || { echo "the proof opened no fix for R1"; jq .fixes .vbw/record.json; return 1; }
  export F_PROVE
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
stricter_c1() { printf 'grep -qx paid src/pay.txt\ntest -s src/pay.txt\n' > tests/c1.sh; }
trailer() { git log -1 --format="%(trailers:key=$1,valueonly)" | tr -d '\n'; }
# refused ARGS...: vbw commit --fix ARGS fails and HEAD does not move.
refused() {
  local before
  before=$(git rev-parse HEAD)
  run "$VBW" commit --fix "$@" < /dev/null
  [ "$status" -ne 0 ] || { echo "committed: $output"; return 1; }
  [ "$(git rev-parse HEAD)" = "$before" ] || { echo "HEAD moved: $output"; return 1; }
}

@test "R194: a proof-opened requirement fix commits its requirement's changed check file with VBW-Fix and VBW-Req, touching only it; staged work stays staged" {
  stricter_c1
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  printf 'mine\n' >> src/staged.txt
  git add src/staged.txt
  run "$VBW" commit --fix "$F_PROVE" "test(pay): stricter" tests/c1.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *committed*"$F_PROVE"* ]] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = tests/c1.sh ]
  [ "$(trailer VBW-Fix)" = "$F_PROVE" ]
  [ "$(trailer VBW-Req)" = R1 ]
  git log -1 --format=%s | grep -q '^test(pay): stricter$'
  [ "$(git diff --cached --name-only)" = src/staged.txt ]
  [ -n "$(git status --porcelain -- tests/c2.sh)" ]
}

@test "R194: the message is validated as today" {
  stricter_c1
  refused "$F_PROVE" "stricter" tests/c1.sh
}

@test "R194: a check file of another requirement is refused, naming that requirement; a code file is refused, pointing to the plan" {
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  refused "$F_PROVE" "test(refund): stricter" tests/c2.sh
  [[ "$output" == *R2* ]] || { echo "$output"; false; }
  printf 'paid\n' > src/pay.txt
  refused "$F_PROVE" "fix(pay): pay" src/pay.txt
  [[ "$output" == *"vbw commit PLAN"* ]] || { echo "$output"; false; }
}

@test "R194: a path under .vbw/ or outside the project, an unknown fix, a non-open fix and an unchanged file are refused" {
  stricter_c1
  refused "$F_PROVE" "test(pay): record" .vbw/record.json
  printf 'x\n' > "$TEST_ROOT/outside.txt"
  refused "$F_PROVE" "test(pay): outside" "../outside.txt"
  refused F99 "test(pay): unknown" tests/c1.sh
  [[ "$output" == *F99* ]] || { echo "$output"; false; }
  edit_record '.fixes += [{id: "F90", req: "R1", attempts: 0, status: "fixed", note: "x"}]'
  refused F90 "test(pay): closed" tests/c1.sh
  [[ "$output" == *F90* ]] || { echo "$output"; false; }
  git checkout -q -- tests/c1.sh
  refused "$F_PROVE" "test(pay): unchanged" tests/c1.sh
  [[ "$output" == *"nothing to commit"* ]] || { echo "$output"; false; }
}

@test "R194: a fix of a [human] requirement has no check files to commit and is refused the same way" {
  edit_record '.fixes += [{id: "F91", req: "R3", attempts: 0, status: "open", note: "feels unsafe"}]'
  stricter_c1
  refused F91 "test(pay): stricter" tests/c1.sh
  [[ "$output" == *"check file"* ]] || { echo "$output"; false; }
}

@test "R194: a project-command fix keeps today's behaviour, and a QA fix's check file commits as today, with both trailers" {
  edit_record '.commands = {test: ["true"]} | .fixes += [{id: "F92", command: "test", attempts: 0, status: "open", note: "t"}]'
  printf 'tool\n' > src/tool.txt
  run "$VBW" commit --fix F92 "fix(test): tool" src/tool.txt < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = src/tool.txt ]
  [ "$(trailer VBW-Fix)" = F92 ]
  "$VBW" qa finding R2 "a refund of zero is written" > /dev/null
  local qa
  qa=$(jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json)
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  run "$VBW" commit --fix "$qa" "test(refund): stricter" tests/c2.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = tests/c2.sh ]
  [ "$(trailer VBW-Fix)" = "$qa" ]
  [ "$(trailer VBW-Req)" = R2 ]
}

@test "R194: after the commit, fix done names the file as waiting, next asks the approval naming it, prove refuses until then and runs it after; the commit shows under its requirement, scope ok" {
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "fix(pay): pay again" > /dev/null
  stricter_c1
  "$VBW" commit --fix "$F_PROVE" "test(pay): stricter" tests/c1.sh > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  run "$VBW" fix done "$F_PROVE" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"waiting for approval"*"tests/c1.sh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$F_PROVE fixed"* ]] || { echo "$output"; false; }
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "approve" and .gate == true and .detail.files == ["tests/c1.sh"]' || { echo "$output"; false; }
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"tests/c1.sh"* ]] || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass" and (.evidence.checks.C1.reused | not) and .evidence.scope == []' .vbw/record.json
  run "$VBW" show req R1 < /dev/null
  [[ "$output" == *"test(pay): stricter"* ]] || { echo "$output"; false; }
}

@test "R194: the Dev's instructions and the fixing workflow say a requirement fix commits its own requirement's check files with vbw commit --fix, code through the plan, waiting for one approval" {
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/agents/dev.md" | grep -qi 'check file' || { echo "dev.md: no line with vbw commit --fix and check file"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/agents/dev.md" | grep -qi 'approval' || { echo "dev.md: no line with vbw commit --fix and approval"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/workflows/fixing.js" | grep -qi 'check file' || { echo "fixing.js: no line with vbw commit --fix and check file"; false; }
}
