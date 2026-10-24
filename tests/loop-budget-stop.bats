#!/usr/bin/env bats
# T156 (docs/loop.md, The time budget): each loop item gets a time budget when it opens, from its size
# and the recorded times of shipped items of that size (twice their median, with three or more), else
# a fixed default per size. At a step boundary past the budget the loop ends with a reason naming the
# item, the step, its elapsed time, its budget and its spend; the item's work is kept, never parked.
# A ship is never stopped. vbw loop status and the report show the budget and the elapsed time.
# Once the item is planned and the step history times every piece of its road (build, proof,
# QA), the budget becomes twice the time so far plus that road, at least 30 minutes, set once;
# the label's budget stays where the history gives no road. The basis, in vbw loop status and
# the report, says which one was used. L1.

load helper
load step-helper
load road-helper
load loop-helper
load fixture-helper

setup_file() { fixture_build loop loop_project; }
setup() { fixture_copy loop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }
reason() { jq -r .reason "$TEST_ROOT/step.json"; }
budget() { jq -r --arg i "$1" '.loop.items[] | select(.id == $i) | .budget.seconds' .vbw/record.json; }

# ago SECONDS: the ISO time that many seconds ago.
ago() { jq -nr --argjson s "$1" 'now - $s | floor | todate'; }

# opened_ago ITEM SECONDS: the item was opened that long ago.
opened_ago() { edit_record "(.loop.items[] | select(.id == \"$1\")).opened_at = \"$(ago "$2")\""; }

# shipped_item ID SIZE MINUTES: a done backlog item of that size whose milestone (titled with its text)
# started MINUTES before it shipped, as the record keeps them: the start in its cost baseline.
shipped_item() {
  local t="Shipped item $1"
  "$VBW" todo add --sort next --size "$2" "$t" > /dev/null
  "$VBW" todo done "$(jq -r '.todos[-1].id' .vbw/record.json)" > /dev/null
  edit_record ".shipped += [{id: \"$1\", title: \"$t\", at: \"$(ago 600)\"}]
    | .costs.milestones[\"$1\"] = {baseline: {s1: {usd: 0, in: 0, out: 0, at: \"$(ago $(( $3 * 60 + 600 )))\"}}}"
}

@test "T156: with no history an item's budget is the default for its size (no size: medium)" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  [ "$(budget T1)" = 14400 ]
  jq -e '.loop.items[0].opened_at | fromdateiso8601 > now - 120' .vbw/record.json
}

@test "T156: a small item with no history gets the small default" {
  "$VBW" todo sort T1 next small > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  [ "$(budget T1)" = 7200 ]
}

@test "T156: with three or more shipped items of its size the budget is twice their median" {
  shipped_item M90 small 20
  shipped_item M91 small 40
  shipped_item M92 small 60
  shipped_item M93 large 600
  "$VBW" todo sort T1 next small > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  [ "$(budget T1)" = 4800 ]
  jq -e '.loop.items[0].budget.basis | test("median")' .vbw/record.json
}

@test "T156: with fewer than three shipped items of its size the default holds" {
  shipped_item M90 small 20
  shipped_item M91 small 40
  "$VBW" todo sort T1 next small > /dev/null
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  [ "$(budget T1)" = 7200 ]
}

@test "T156: past its budget the loop ends before the next step, names the item, step, time and budget, and keeps the work" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  opened_ago T1 18000
  head=$(git rev-parse HEAD)
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *T1* ]] && [[ "$(reason)" == *build* ]] && [[ "$(reason)" == *5h0* ]] && [[ "$(reason)" == *4h00m* ]] || { reason; false; }
  # The work stays: the item in progress in its milestone, its plan and requirement there, nothing reverted.
  jq -e '.loop.items[0].status == "in_progress" and .loop.items[1].status == "waiting" and .loop.ended != null' .vbw/record.json
  jq -e '.milestone.status == "active" and any(.plans[]; .id == "P2.1") and (.parked // [] | length) == 0' .vbw/record.json
  [ -z "$(git log --format=%s "$head..HEAD" | grep -i revert)" ]
  [ "$(step)" = stopped ]
}

@test "T156: under its budget the step runs" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  opened_ago T1 3600
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
}

@test "T156: a ship is never stopped by the budget; the next item gets its own" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  [ "$(step)" = prove ]
  loop_prove
  opened_ago T1 18000
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.loop.items[0].status == "shipped" and .loop.items[1].status == "in_progress" and .loop.ended == null' .vbw/record.json
}

@test "T156: vbw loop status and the report show the item's budget and elapsed time" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  opened_ago T1 5400
  run "$VBW" loop status
  [[ "$output" == *"1h30m"* ]] && [[ "$output" == *"4h00m"* ]] || { echo "$output"; false; }
  run "$VBW" loop status --json
  echo "$output" | jq -e '.time.item == "T1" and .time.budget == 14400 and (.time.elapsed >= 5400 and .time.elapsed < 5600)'
  "$VBW" loop stop > /dev/null
  [ "$(step)" = stopped ]
  grep -q "1h30m" .vbw/loop-report.md && grep -q "4h00m" .vbw/loop-report.md || { cat .vbw/loop-report.md; false; }
}

# road_known: the step history times a standard build, QA, fix round and proof, so the road of a planned item has a number.
road_known() {
  STEPS="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/steps.json"
  export STEPS
  hist_build standard 1 100 3
  hist_qa standard 100 3
  hist_fix standard 150 3
  hist_proof '[{"name": "check:X1", "seconds": 50}, {"name": "check:X2", "seconds": 50}]' 100 3
}

@test "T156: once the item is planned and the road is timed, the budget is twice the time so far plus the road, set once" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  road_known
  opened_ago T1 1200
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  local road b
  road=$("$VBW" next --json | jq -r '.road.seconds')
  [[ "$road" =~ ^[0-9]+$ ]] || { echo "no road in the fixture: $road"; false; }
  b=$(budget T1)
  [ "$b" -ge $(( 2 * (1200 + road) )) ] && [ "$b" -le $(( 2 * (1200 + road) + 60 )) ] || { echo "budget $b, road $road"; false; }
  jq -e '.loop.items[0].budget | .planned == true and (.basis | test("road"))' .vbw/record.json
  # Set once: another step leaves it alone.
  [ "$(step)" = build ]
  [ "$(budget T1)" = "$b" ]
}

@test "T156: a road shorter than a quarter of an hour still gets a budget of 30 minutes" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  road_known
  [ "$(step)" = build ]
  [ "$(budget T1)" = 1800 ] || { jq .loop.items[0].budget .vbw/record.json; false; }
}

@test "T156: with no timed road the label's budget stays, and its basis says so" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  [ "$(budget T1)" = 14400 ]
  jq -e '.loop.items[0].budget | .planned == null and (.basis | test("default"))' .vbw/record.json
}

@test "T156: the report names the basis of the budget it shows" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  road_known
  [ "$(step)" = build ]
  "$VBW" loop stop > /dev/null
  [ "$(step)" = stopped ]
  grep -q "twice the time so far" .vbw/loop-report.md || { cat .vbw/loop-report.md; false; }
}

@test "T156: the validator takes planned: true on a budget and refuses planned: false or any other key" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  edit_record '.loop.items[0].budget.planned = true'
  run "$VBW" loop status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  edit_record '.loop.items[0].budget.planned = false'
  run "$VBW" loop status
  [ "$status" -ne 0 ] && [[ "$output" == *"loop.items must be"* ]] || { echo "planned false accepted: $output"; false; }
  edit_record '.loop.items[0].budget = {seconds: 100, basis: "x", other: 1}'
  run "$VBW" loop status
  [ "$status" -ne 0 ] && [[ "$output" == *"loop.items must be"* ]] || { echo "another key accepted: $output"; false; }
}
