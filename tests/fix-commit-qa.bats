#!/usr/bin/env bats
# R160 (docs/proof.md): vbw commit --fix FIX, for a fix QA opened, commits the
# fix's new test files and the check files of the finding's requirement with a
# VBW-Fix trailer, and refuses a check file of another requirement or a code
# file (code goes through its plan). L1.

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
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1", "R2"], files: ["src/pay.txt", "src/refund.txt"], after: [], tasks: ["pay", "refund"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}, {req: "R2", text: "a refund is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt
  printf 'refund\n' > src/refund.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  "$VBW" qa finding R1 "a payment of zero is accepted" > /dev/null
  F_QA=$(jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json)
  export F_QA
  VBW_SESSION_ID=s1 "$VBW" run start fix "$F_QA" > /dev/null
  # The Dev's regression test, registered, and a stronger check file for R1.
  printf 'grep -qx paid src/pay.txt\n' > tests/r1-regression.sh
  printf '%s' '{"run": ["sh", "tests/r1-regression.sh"], "files": ["tests/r1-regression.sh"]}' | VBW_SESSION_ID=s1 "$VBW" fix check "$F_QA" > /dev/null
  printf 'grep -qx paid src/pay.txt\ntest -s src/pay.txt\n' > tests/c1.sh
}

teardown() { vbw_teardown; }

@test "R160: vbw commit --fix commits the fix's new test file and its requirement's check file, with a VBW-Fix trailer" {
  run "$VBW" commit --fix "$F_QA" "test(pay): regression for the zero payment" tests/r1-regression.sh tests/c1.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"committed"*"$F_QA"*"2 files"* ]] || { echo "$output"; false; }
  [ "$(git log -1 --format='%(trailers:key=VBW-Fix,valueonly)' | tr -d '\n')" = "$F_QA" ]
  [ "$(git show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' ')" = "tests/c1.sh tests/r1-regression.sh " ]
  [ -z "$(git status --porcelain -- tests/c1.sh tests/r1-regression.sh)" ]
}

@test "R160: vbw commit --fix refuses a check file of another requirement, and commits nothing" {
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  local before
  before=$(git rev-parse HEAD)
  run "$VBW" commit --fix "$F_QA" "test(refund): stricter" tests/c2.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"tests/c2.sh is a check file of R2, not of R1"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "R160: vbw commit --fix refuses a code file: code goes through its plan" {
  printf 'paid\nmore\n' > src/pay.txt
  local before
  before=$(git rev-parse HEAD)
  run "$VBW" commit --fix "$F_QA" "fix(pay): more" src/pay.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw commit PLAN MESSAGE"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "R160: a fix that is not open cannot commit check files this way" {
  local other before
  before=$(git rev-parse HEAD)
  jq '.fixes += [{id: "F77", req: "R2", attempts: 0, status: "closed", note: "proof"}]' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  run "$VBW" commit --fix F77 "test(refund): stricter" tests/c2.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"F77 is not open: only an open fix commits"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$before" ]
}
