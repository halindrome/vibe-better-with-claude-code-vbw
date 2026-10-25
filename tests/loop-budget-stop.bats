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

# The item's time counts only while the loop works on it: from its last step before the loop stopped
# (ended, its session gone, a turn ended on an API error) to the step that resumes it is left out
# (away). The resumed session's hook leaves an empty mark, a failed turn's hook the time it failed
# (tests/loop-stop-hook.bats); the next step adds the time stopped to away and removes the mark.

# stepped_ago ITEM SECONDS: the loop last stepped the item that long ago.
stepped_ago() { edit_record "(.loop.items[] | select(.id == \"$1\")).stepped_at = \"$(ago "$2")\""; }
away() { jq -r --arg i "$1" '.loop.items[] | select(.id == $i) | .away // 0' .vbw/record.json; }

@test "T156: after the loop's session was gone, the time from the item's last step to the resumed step is left out" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  # Opened 5 hours ago, its last step 4 hours ago, then the session was gone until now.
  opened_ago T1 18000
  stepped_ago T1 14400
  : > .vbw/runtime/loop-away.s1
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  [ "$(away T1)" -ge 14400 ] && [ "$(away T1)" -lt 14520 ] || { away T1; false; }
  [ ! -e .vbw/runtime/loop-away.s1 ]
  run "$VBW" loop status --json
  echo "$output" | jq -e '.time.elapsed >= 3480 and .time.elapsed < 3720' || { echo "$output"; false; }
}

@test "T156: after a turn ended on an API error, the time from the failure to the resumed step is left out; time working still counts" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  # Opened 5 hours ago, its last step 4 hours ago, a turn failed 3 hours ago: 2 hours counted.
  opened_ago T1 18000
  stepped_ago T1 14400
  ago 10800 > .vbw/runtime/loop-away.s1
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  [ "$(away T1)" -ge 10800 ] && [ "$(away T1)" -lt 10920 ] || { away T1; false; }
  # With no mark the time between two steps is work: past the budget the loop stops.
  opened_ago T1 30000
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"time budget spent"* ]] || { reason; false; }
}

@test "T156: the budget set from the plan counts the time so far without the time away" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  road_known
  opened_ago T1 2400
  edit_record '.loop.items[0].away = 1200'
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  local road b
  road=$("$VBW" next --json | jq -r '.road.seconds')
  b=$(budget T1)
  [ "$b" -ge $(( 2 * (1200 + road) )) ] && [ "$b" -le $(( 2 * (1200 + road) + 60 )) ] || { echo "budget $b, road $road"; false; }
}

@test "T156: an item the last loop left in progress resumes when named again, keeping its work, time and budget, without the time stopped" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  "$VBW" loop stop > /dev/null
  [ "$(step)" = stopped ]
  local head
  head=$(jq -r '.loop.items[0].head' .vbw/record.json)
  # The next morning: opened 10 hours ago, its last step and the loop's end 9 hours ago.
  opened_ago T1 36000
  stepped_ago T1 32400
  edit_record ".loop.ended.at = \"$(ago 32400)\""
  run env VBW_SESSION_ID=s1 "$VBW" loop start T2 T1 --no-ceiling
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e --arg h "$head" '.loop.ended == null and (.loop.items | length) == 2
    and (.loop.items[0] | .id == "T1" and .status == "in_progress" and .head == $h and .budget.seconds == 14400 and .milestone == "M2")
    and (.loop.items[1] | .id == "T2" and .status == "waiting")' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  [ "$(away T1)" -ge 32400 ] && [ "$(away T1)" -lt 32520 ] || { away T1; false; }
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.loop.items[0].status == "in_progress" and .loop.items[1].status == "waiting"' .vbw/record.json
}

@test "T156: an item stopped after working past its budget is not resumed by a loop (finish it with /vbw:vibe); naming another item names it" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  opened_ago T1 18000
  [ "$(step)" = stopped ]
  local before
  before=$(project_sum)
  run env VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling
  [ "$status" -eq 1 ] && [[ "$output" == *"time budget"* ]] && [[ "$output" == *"Next: "*"/vbw:vibe"* ]] || { echo "$output"; false; }
  run env VBW_SESSION_ID=s1 "$VBW" loop start T2 --no-ceiling
  [ "$status" -eq 1 ] && [[ "$output" == *T1* ]] && [[ "$output" == *"Next: "* ]] || { echo "$output"; false; }
  [ "$(project_sum)" = "$before" ]
}

@test "T156: the validator takes stepped_at as a time and away as whole seconds, nothing else" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  edit_record '.loop.items[0].away = 60 | .loop.items[0].stepped_at = "2026-10-24T08:00:00Z"'
  run "$VBW" loop status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  edit_record '.loop.items[0].away = -1'
  run "$VBW" loop status
  [ "$status" -ne 0 ] && [[ "$output" == *"loop.items must be"* ]] || { echo "away -1 accepted: $output"; false; }
  edit_record '.loop.items[0].away = 60 | .loop.items[0].stepped_at = "yesterday"'
  run "$VBW" loop status
  [ "$status" -ne 0 ] && [[ "$output" == *"loop.items must be"* ]] || { echo "stepped_at accepted: $output"; false; }
}
