#!/usr/bin/env bats
# R202 (docs/proof.md, L1): vbw fix done opens its run and the computer-wide
# slot store before its planning, which holds vbw:plan, but asks for the
# approved contract only when a check or test file will run. A fix with nothing
# to run closes on an unapproved contract, as before the slot store; one with a
# check to run is refused with the approval message and stays open.

load helper

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

# shop: R1 (pay) with its check C1, applied and never approved; F1 (R1) is open.
shop() {
  vbw_git_project
  mkdir -p tests src
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -n '{phases: [{id: "P1", title: "Checkout", reqs: ["R1"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}]}' | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt
  git add -A && git commit -q -m "feat: built"
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
}

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R202: with nothing to run, fix done closes the fix on an unapproved contract" {
  shop
  run "$VBW" fix done F1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"F1 fixed"* ]] || { echo "$output"; false; }
  [[ "$output" != *"not approved"* ]] || { echo "$output"; false; }
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
}

@test "R202: with a check to run, fix done on an unapproved contract is refused and the fix stays open" {
  shop
  edit_record '.plans[].status = "done"'
  run "$VBW" fix done F1 < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"the contract is not approved"* ]] || { echo "$output"; false; }
  jq -e '.fixes[0].status == "open"' .vbw/record.json
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'run.*')" ] || { ls .vbw/runtime; false; }
}
