#!/usr/bin/env bats
# R179 (F204; D332; docs/proof.md, QA): a QA finding belongs to the phase whose QA
# found it. vbw qa finding PHASE REQ TEXT records the phase; a finding given as
# REQ TEXT is adopted by that phase's fail verdict. A verdict changes only its own
# phase's findings: the pass of another phase that shares the requirement leaves
# them open, so phases verified in parallel never close each other's findings.
# The record refuses a finding whose phase is unknown. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  # Two phases share R1: the payment and its receipt.
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "tier": "standard"}, {"id": "P2", "title": "Receipt", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
              {"id": "P2.1", "phase": "P2", "title": "Receipt", "reqs": ["R1"], "files": ["src/receipt.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  printf 'receipt\n' > src/receipt.txt && "$VBW" commit P2.1 "feat(pay): receipt" > /dev/null
  "$VBW" plan done P2.1 > /dev/null
  "$VBW" prove --full > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "R179 (F204): a finding names its phase; the pass of another phase sharing the requirement leaves it open; its own phase's pass closes it" {
  "$VBW" qa finding P1 R1 "the plan said a receipt is printed; none is" > /dev/null
  jq -e '.fixes[0] | .source == "qa" and .status == "open" and .req == "R1" and .phase == "P1"' .vbw/record.json
  vbw_run qa record P1 fail standard "1 deviation"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run qa record P2 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.fixes[0].status == "open" and .phases[1].qa.result == "pass" and .phases[0].qa.result == "fail"' .vbw/record.json || { jq '{fixes, qa: [.phases[].qa]}' .vbw/record.json; false; }
  vbw_run next --json
  echo "$output" | jq -e '.action == "fix" and .detail.fixes == ["F1"]' > /dev/null || { echo "$output"; false; }
  "$VBW" fix done F1 > /dev/null
  "$VBW" prove --full > /dev/null
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
  # Another phase's pass does not close a fixed finding either.
  vbw_run qa record P2 pass standard
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.fixes[0].status == "closed" and .phases[0].qa.result == "pass"' .vbw/record.json
}

@test "R179 (F204): a finding given without its phase is adopted by the phase's fail verdict; a fail needs a finding of its own phase" {
  "$VBW" qa finding R1 "untagged deviation" > /dev/null
  jq -e '.fixes[0] | has("phase") | not' .vbw/record.json
  vbw_run qa record P1 fail standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.fixes[0].phase == "P1"' .vbw/record.json
  # P2 has no finding of its own: its fail verdict is refused, naming the form with the phase.
  vbw_run qa record P2 fail standard
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs its findings first"* && "$output" == *"vbw qa finding P2 REQ TEXT"* ]] || { echo "$output"; false; }
}

@test "R179 (F204): a finding for a phase that does not have the requirement, or does not exist, is refused; the record refuses a fix whose phase is unknown" {
  vbw_run qa finding P9 R1 "nowhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P9 is not a phase with requirement R1"* ]] || { echo "$output"; false; }
  jq -e '.fixes | length == 0' .vbw/record.json
  "$VBW" qa finding P1 R1 "a finding" > /dev/null
  jq '.fixes[0].phase = "P9"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"unknown phase P9"* ]] || { echo "$output"; false; }
}

@test "R179 (F204): docs/proof.md and the QA agent name the finding's phase and the one-phase rule" {
  grep -q 'vbw qa finding PHASE REQ TEXT' "$REPO_ROOT/docs/proof.md"
  grep -q 'never another phase' "$REPO_ROOT/docs/proof.md"
  grep -q 'vbw qa finding <phase> <requirement>' "$REPO_ROOT/plugin/agents/qa.md"
  grep -q 'D332' "$REPO_ROOT/docs/record.md"
}
