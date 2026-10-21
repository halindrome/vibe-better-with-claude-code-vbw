#!/usr/bin/env bats
# R171 (docs/next.md, row 3a): while the contract cannot be approved yet (a
# check file is missing, the spec and the record differ), vbw next does not
# offer the approval question. Its answer is action "contract", not gated: the
# instruction says the contract is not ready, names each problem and the step
# that fixes it, and detail.problems lists them. Once every problem is fixed
# the answer is the approval question as before, and vbw approve still refuses
# an unready contract. Found in the M7 senior run (T16): the approval question
# was shown for a contract whose check file did not exist yet. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "Customers pay", criteria: ["paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}]}' | "$VBW" apply > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

next() { "$VBW" next --json 2> /dev/null; }

@test "R171: a check file that does not exist yet: no approval question, the problem and its step are named" {
  run next
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "contract" and .gate == false' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.detail.problems == ["check file missing: tests/c1.sh"]' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.instruction | test("not ready") and test("tests/c1.sh") and test("vbw next")' || { echo "$output"; false; }
}

@test "R171: once the check file is written the approval question comes, as before" {
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  run next
  printf '%s' "$output" | jq -e '.action == "approve" and .gate == true' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.detail | has("problems") | not' || { echo "$output"; false; }
}

@test "R171: a spec edited and not synced: no approval question, the sync step is named" {
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay by card\n' > .vbw/spec.md
  run next
  printf '%s' "$output" | jq -e '.action == "contract" and .gate == false' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.detail.problems | any(.[]; test("spec.md and the record differ")) ' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.instruction | test("vbw spec sync")' || { echo "$output"; false; }
}

@test "R171: several problems are all listed, one per entry" {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay by card\n' > .vbw/spec.md
  run next
  printf '%s' "$output" | jq -e '.detail.problems | length == 2' || { echo "$output"; false; }
}

@test "R171: an approved contract is not examined again: the answer is the next step, with no problems field" {
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  git add -A && git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
  run next
  printf '%s' "$output" | jq -e '.action == "build"' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.detail | has("problems") | not' || { echo "$output"; false; }
}

@test "R171: vbw approve still refuses an unready contract, naming the missing check file" {
  run "$VBW" approve
  [ "$status" -ne 0 ]
  [[ "$output" == *"check file missing: tests/c1.sh"* ]] || { echo "$output"; false; }
}
