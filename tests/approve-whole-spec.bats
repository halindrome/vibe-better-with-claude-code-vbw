#!/usr/bin/env bats
# R174 (docs/proof.md): vbw approve, and vbw next's contract-readiness check,
# compare every section of .vbw/spec.md with the record (Requirements, Commands,
# Test files, Test results) and refuse while any differs, so an edited list that
# was not synced can never be approved as the record's list. No "## Test
# results" section and no folders recorded compare equal; the same folders in
# the same order compare equal; any other difference does not. After vbw spec
# sync the same vbw approve proceeds. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  printf 'x\n' > tests/t_a.sh
  spec '- results/a/
- results/b/'
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "Customers pay", criteria: ["paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

# spec RESULTS [REQ] [TEST_CMD] [FORM_RUN]: write .vbw/spec.md with every section; RESULTS is the
# Test results list (lines) or "none" for no such section.
spec() {
  {
    printf '# Shop\n\n## Requirements\n\n- R1 [auto] %s\n\n## Commands\n\n- test: %s\n\n## Test files\n\n- run: %s\n- files: tests/t_*.sh\n' \
      "${2:-A customer can pay}" "${3:-sh tests/all.sh}" "${4:-sh {file}}"
    [ "$1" = none ] || printf '\n## Test results\n\n%s\n' "$1"
  } > .vbw/spec.md
}

decisions() { jq '.decisions | length' .vbw/record.json; }
commits() { git rev-list --count HEAD; }
approved() { "$VBW" show contract | sed -n '1p' | grep -q '(approved)'; }

# refused: vbw approve refuses the unsynced spec: exit 1, both lines, nothing written.
refused() {
  local d c
  d=$(decisions) c=$(commits)
  vbw_run approve
  [ "$status" -eq 1 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"the contract is not ready for approval:"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"spec.md and the record differ (vbw spec sync)"* ]] || { echo "$output"; return 1; }
  [ "$(decisions)" = "$d" ] || { echo "a decision was written"; return 1; }
  [ "$(commits)" = "$c" ] || { echo "a commit was made"; return 1; }
  ! approved || { echo "consent was written"; return 1; }
}

@test "R174: a Test results folder added to the spec and not synced is refused: exit 1, both lines, no decision, no commit, no consent" {
  spec '- results/a/
- results/b/
- results/c/'
  refused
}

@test "R174: a folder removed or renamed, or the whole section removed, is refused" {
  spec '- results/a/'
  refused
  spec '- results/a/
- results/x/'
  refused
  spec none
  refused
}

@test "R174: the same unsynced edit makes vbw next say the contract is not ready and name vbw spec sync, never the approval question" {
  spec '- results/a/
- results/b/
- results/c/'
  run "$VBW" next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "contract" and .gate == false' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.detail.problems | any(.[]; . == "spec.md and the record differ (vbw spec sync)")' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.instruction | test("vbw spec sync")' || { echo "$output"; false; }
}

@test "R174: the same folders in the same order compare equal; another order does not; after vbw spec sync the same vbw approve proceeds" {
  spec '- results/a/
- results/b/'
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"approved contract"* ]] || { echo "$output"; false; }
  spec '- results/b/
- results/a/'
  refused
  "$VBW" spec sync > /dev/null
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"approved contract"* ]] || { echo "$output"; false; }
  jq -e '.project.results == ["results/b/", "results/a/"]' .vbw/record.json
}

@test "R174: no Test results section and no folders recorded compare equal; a section added and not synced does not" {
  spec none
  "$VBW" spec sync > /dev/null
  jq -e '.project | has("results") | not' .vbw/record.json
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"approved contract"* ]] || { echo "$output"; false; }
  spec '- results/a/'
  refused
  "$VBW" spec sync > /dev/null
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R174: an unsynced Requirements edit is refused" {
  spec '- results/a/
- results/b/' 'A customer can pay by card'
  refused
}

@test "R174: an unsynced Commands edit is refused" {
  spec '- results/a/
- results/b/' 'A customer can pay' 'sh tests/all.sh -v'
  refused
}

@test "R174: an unsynced Test files edit is refused" {
  spec '- results/a/
- results/b/' 'A customer can pay' 'sh tests/all.sh' 'sh -e {file}'
  refused
}
