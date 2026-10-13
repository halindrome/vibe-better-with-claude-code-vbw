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

# corrupt FILTER: the record edited by FILTER is refused by the kernel, with the rule's words on stdout.
corrupt() {
  edit_record "$1"
  run "$VBW" status
  [ "$status" -ne 0 ] || { echo "accepted: $1"; echo "$output"; return 1; }
  [[ "$output" == *"$2"* ]] || { echo "$1 -> $output"; return 1; }
}

@test "R179 (F182): the record's rules for parked milestones: fields, parked twice, shipped and parked, a parked milestone that keeps work, the current milestone parked exactly when listed" {
  corrupt '.parked = [{id: "M9", title: "Old", at: "2026-10-12T00:00:00Z", reason: ""}]' "need an id, a title, an ISO-8601 UTC time and a reason"
  git checkout -q -- .vbw/record.json
  corrupt '.parked = [{id: "M9", title: "Old", at: "2026-10-12T00:00:00Z", reason: "x", extra: 1}]' "unknown field"
  git checkout -q -- .vbw/record.json
  corrupt '.parked = [{id: "M9", title: "Old", at: "2026-10-12T00:00:00Z", reason: "x"}, {id: "M9", title: "Old", at: "2026-10-12T00:00:00Z", reason: "x"}]' "parked twice"
  git checkout -q -- .vbw/record.json
  corrupt '.parked = [{id: (.shipped[0].id), title: "Old", at: "2026-10-12T00:00:00Z", reason: "x"}]' "cannot be both shipped and parked"
  git checkout -q -- .vbw/record.json
  corrupt '.parked = [{id: (.milestone.id), title: "Old", at: "2026-10-12T00:00:00Z", reason: "x"}]' "parked exactly when it is in parked"
  git checkout -q -- .vbw/record.json
  corrupt '.parked = [{id: "M9", title: "Old", at: "2026-10-12T00:00:00Z", reason: "x"}] | .requirements[0].milestone = "M9"' "belongs to parked milestone"
  git checkout -q -- .vbw/record.json
}

@test "R179 (F182): a parked milestone keeps its name, and vbw status --json lists the parked ids" {
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
  step > /dev/null
  jq -e '.parked | length == 1' .vbw/record.json || { jq '{parked, milestone}' .vbw/record.json; false; }
  local p
  p=$(jq -r '.parked[0].id' .vbw/record.json)
  "$VBW" status --json < /dev/null | jq -e --arg p "$p" '.parked | index($p) != null' || { "$VBW" status --json < /dev/null; false; }
  "$VBW" show roadmap | grep -q "parked"
}

@test "R179 (F186): a parked milestone keeps its name: vbw milestone rename refuses and says to start the next one" {
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
  step > /dev/null
  jq -e '.milestone.status == "parked"' .vbw/record.json || { jq .milestone .vbw/record.json; false; }
  run "$VBW" milestone rename "Another name"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"has been parked"* ]] || { echo "$output"; false; }
  jq -e '.milestone.title != "Another name"' .vbw/record.json
}

# parked_with_figures: T1 parked after the figures reach $4 (its milestone froze at $2 over its $2 baseline), T2 open.
parked_with_figures() {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 "$@" > /dev/null
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
}

@test "R179 (F195): vbw show costs prices a parked milestone by its frozen total, which later spend does not change" {
  parked_with_figures --ceiling 50
  figures s1 4 2000 200
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  local m frozen
  m=$(jq -r '.parked[0].id' .vbw/record.json)
  frozen=$(jq -c --arg m "$m" '.costs.milestones[$m].total' .vbw/record.json)
  [ "$(printf '%s' "$frozen" | jq -r .usd)" = 2 ] || { jq .costs .vbw/record.json; false; }
  "$VBW" show costs --json | jq -e --arg m "$m" --argjson f "$frozen" '.milestones[] | select(.id == $m) | .status == "parked" and .usd == $f.usd and .in == $f.in and .out == $f.out' \
    || { "$VBW" show costs --json; false; }
  "$VBW" show costs | grep -q "$m"
  figures s1 9 5000 500
  "$VBW" show costs --json | jq -e --arg m "$m" '.milestones[] | select(.id == $m) | .usd == 2' || { "$VBW" show costs --json; false; }
  # The live milestone counts the new spend; the parked one does not.
  "$VBW" show costs --json | jq -e '.milestones[] | select(.status == "active") | .usd == 5' || { "$VBW" show costs --json; false; }
}

@test "R179 (F195): a milestone parked with no figure seen is unknown in vbw show costs, and stays unknown after spend" {
  no_figures
  parked_with_figures --no-ceiling
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  local m
  m=$(jq -r '.parked[0].id' .vbw/record.json)
  "$VBW" show costs --json | jq -e --arg m "$m" '(.milestones[] | select(.id == $m) | .status == "parked" and .usd == null) and (.unknown.milestones | index($m) != null)' \
    || { "$VBW" show costs --json; false; }
  figures s1 9 5000 500
  "$VBW" show costs --json | jq -e --arg m "$m" '.milestones[] | select(.id == $m) | .usd == null' || { "$VBW" show costs --json; false; }
}
