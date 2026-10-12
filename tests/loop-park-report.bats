#!/usr/bin/env bats
# R179 (P129; docs/loop.md, The report): the report's parked section names each
# parked item, its reason, its revert commits and how to bring the work back;
# the loop's total cost includes parked items' cost, and the record stores the
# same facts. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }

@test "R179: the parked section names the item, the reason, the revert commits and the way back; the total includes the parked item's cost" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 50 > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  loop_break P2
  [ "$(step)" = prove ]
  loop_prove
  [ "$(step)" = fix ]
  edit_record '(.fixes[] | select(.id == "F1")).status = "escalated"'
  [ "$(step)" = fix ]
  edit_record '(.fixes[] | select(.id == "F1")).status = "escalated"'
  figures s1 4 2000 200
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  [ -f .vbw/loop-report.md ]
  local parked
  parked=$(awk '/^## /{on = tolower($0) ~ /parked/} on' .vbw/loop-report.md)
  [ -n "$parked" ] || { cat .vbw/loop-report.md; false; }
  printf '%s\n' "$parked" | grep -q 'T1'
  printf '%s\n' "$parked" | grep -q 'Visitors can read a greeting'
  printf '%s\n' "$parked" | grep -qi 'escalat'
  printf '%s\n' "$parked" | grep -qE '[0-9a-f]{7}'
  printf '%s\n' "$parked" | grep -qi 'revert'
  printf '%s\n' "$parked" | grep -qi 'again'
  local cost
  cost=$(awk '/^## /{on = tolower($0) ~ /cost/} on' .vbw/loop-report.md)
  printf '%s\n' "$cost" | grep -q '\$2\.00'
  printf '%s\n' "$cost" | grep -q 'T1'
  jq -e '.loop.items[0] | .status == "parked" and .cost.usd == 2 and (.reason | test("escalat")) and (.reverts | type == "array" and length == 2)' .vbw/record.json \
    || { jq .loop .vbw/record.json; false; }
  [ -z "$(git status --porcelain -- .vbw/loop-report.md)" ]
}
