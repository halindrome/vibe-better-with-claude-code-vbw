#!/usr/bin/env bats
# R179 (P128; docs/loop.md, The report): .vbw/loop-report.md is written when
# the loop ends and refreshed each time an item ends, so a machine that died
# overnight still leaves one. It says what shipped (item, milestone,
# requirement, the commits), what was parked and why, what waits for the user
# (skipped [human] requirements, the stop reason), and what it cost: the loop's
# total and each item's cost in dollars and tokens, unknown where VBW saw no
# figure, never 0 or an estimate. The record stores the same facts; vbw loop
# status after the end says the loop ended, why, and names the report. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }

# one_item: the loop runs T1 through to its ship, spending $1.50 in session s1.
one_item() {
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  figures s1 3.5 2500 250
  [ "$(step)" = prove ]
  loop_prove
}

@test "R179: at the loop's end the report names what shipped, with its commits, and what it cost in dollars" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 20 > /dev/null
  one_item
  [ "$(step)" = done ]
  [ -f .vbw/loop-report.md ]
  [ -z "$(git status --porcelain -- .vbw/loop-report.md)" ]
  grep -qi '^## .*shipped' .vbw/loop-report.md
  grep -qi '^## .*parked' .vbw/loop-report.md
  grep -qi '^## .*wait' .vbw/loop-report.md
  grep -qi '^## .*cost' .vbw/loop-report.md
  grep -E 'T1' .vbw/loop-report.md | grep -q 'Visitors can read a greeting'
  grep -q 'M2' .vbw/loop-report.md
  grep -q 'R2' .vbw/loop-report.md
  grep -q 'feat(greet): hello' .vbw/loop-report.md
  grep -q '\$1\.50' .vbw/loop-report.md
  ! grep -qE 'tokens|[0-9] in,' .vbw/loop-report.md || false
  grep -qi 'end of' .vbw/loop-report.md
  jq -e '.loop.items[0] | .status == "shipped" and .milestone == "M2" and .cost == {usd: 1.5}' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  jq -e '.loop.report == ".vbw/loop-report.md" and (.loop.ended.reason | test("end of"))' .vbw/record.json
  run "$VBW" loop status
  [[ "$output" == *"ended"* ]] && [[ "$output" == *"end of"* ]] && [[ "$output" == *".vbw/loop-report.md"* ]] || { echo "$output"; false; }
}

@test "R179: a cost VBW did not see is unknown, never 0 or an estimate" {
  no_figures
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  [ "$(step)" = prove ]
  loop_prove
  [ "$(step)" = done ]
  grep -qi 'unknown' .vbw/loop-report.md
  ! grep -q '\$0\.00' .vbw/loop-report.md || false
  ! grep -qiE 'estimat|approx' .vbw/loop-report.md || false
  jq -e '.loop.items[0].cost == null' .vbw/record.json
}

@test "R179: the report is refreshed each time an item ends, before the loop is over" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 20 > /dev/null
  one_item
  [ "$(step)" = plan ]
  jq -e '.loop.ended == null and .loop.items[1].status == "in_progress"' .vbw/record.json
  [ -f .vbw/loop-report.md ]
  grep -q 'T1' .vbw/loop-report.md
  grep -q 'feat(greet): hello' .vbw/loop-report.md
  grep -qiE 'running|in progress' .vbw/loop-report.md
  [ -z "$(git status --porcelain -- .vbw/loop-report.md)" ]
}

@test "R179: a stop reason is in the report and in the record" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  [ "$(step)" = stopped ]
  grep -q 'stopped by the user' .vbw/loop-report.md
  grep -q 's9' .vbw/loop-report.md
  jq -e '.loop.ended.reason | test("stopped by the user")' .vbw/record.json
}
