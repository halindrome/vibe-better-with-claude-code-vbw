#!/usr/bin/env bats
# R205 (docs/proof.md): the Clean copy list is part of the contract. Adding a
# path changes the fingerprint and the approval is asked again; vbw show
# contract prints one line naming the paths left out and no such line when
# nothing is listed; --changes names the new list and the old one; an edited,
# unsynced section cannot be approved, and vbw next says the contract is not
# ready instead of asking (R174, R171). The section's parsing and refusals are
# tests/clean-copy-spec.bats. L1: the kernel on a fixture project.

load helper
load fixture-helper

# shop: an initialized project with two ignored folders (data/, cache/), a
# tracked folder (src/) and an untracked, unignored folder (notes/).
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'data/\ncache/\n' > .gitignore
  mkdir -p data cache src notes tests
  printf 'big\n' > data/a.bin
  printf 'c\n' > cache/c.txt
  printf 'paid\n' > src/pay.txt
  printf 'todo\n' > notes/todo.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  git add .gitignore src tests && git commit -q -m "feat(shop): start"
}

setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# spec LINES: the spec with one requirement, a check-less plan is added by plan;
# LINES (when not empty) are the bullets of a Clean copy section. The section
# starts on line 7, so its first bullet is line 9.
spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  [ -z "$1" ] || printf '\n## Clean copy\n\n%s\n' "$1" >> .vbw/spec.md
}

# planned: one approved check on R1 and a plan, so the contract can be shown and approved.
planned() {
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying works", check: "C1"}]}' | "$VBW" apply > /dev/null
}

@test "R205: the list is part of the contract: adding a path changes the fingerprint and the approval is asked again" {
  spec '- data/'
  "$VBW" spec sync > /dev/null
  planned
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  local before
  before=$("$VBW" show contract | head -n 1)
  [[ "$before" == *"(approved)"* ]] || { echo "$before"; false; }
  spec '- data/
- cache/'
  "$VBW" spec sync > /dev/null
  run "$VBW" show contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | head -n 1 | cut -d' ' -f2)" != "$(printf '%s' "$before" | cut -d' ' -f2)" ] || { echo "$output"; false; }
  printf '%s\n' "$output" | head -n 1 | grep -q 'NOT APPROVED' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^approval question: Approve contract ' || { echo "$output"; false; }
}

@test "R205: vbw show contract prints one line naming the paths left out, and no such line when nothing is listed" {
  spec ''
  "$VBW" spec sync > /dev/null
  planned
  run "$VBW" show contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"clean copy leaves out"* ]] || { echo "$output"; false; }
  spec '- data/
- cache/'
  "$VBW" spec sync > /dev/null
  run "$VBW" show contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^clean copy leaves out: data/, cache/$')" -eq 1 ] || { echo "$output"; false; }
}

@test "R205: vbw show contract --changes names an added or removed path since the last approval" {
  spec '- data/'
  "$VBW" spec sync > /dev/null
  planned
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  spec '- data/
- cache/'
  "$VBW" spec sync > /dev/null
  run "$VBW" show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^  clean copy leaves out: data/, cache/ (was data/)$' || { echo "$output"; false; }
  spec ''
  "$VBW" spec sync > /dev/null
  run "$VBW" show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^  clean copy leaves out: none (was data/)$' || { echo "$output"; false; }
}

@test "R205: an edited, unsynced section cannot be approved, and vbw next says the contract is not ready instead of asking" {
  spec '- data/'
  "$VBW" spec sync > /dev/null
  planned
  git add -A && git commit -q -m "chore(vbw): plan"
  spec '- data/
- cache/'
  run "$VBW" approve
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"spec.md and the record differ (vbw spec sync)"* ]] || { echo "$output"; false; }
  run "$VBW" next --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | jq -e '.action == "contract" and .gate == false
    and (.detail.problems | any(.[]; contains("spec.md and the record differ")))' || { echo "$output"; false; }
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(vbw): sync"
  run "$VBW" next --json
  printf '%s\n' "$output" | jq -e '.action == "approve"' || { echo "$output"; false; }
}
