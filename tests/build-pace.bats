#!/usr/bin/env bats
# T174 (L1): a build wave's expected time counts the mutation step and waits for
# the wave's slowest plan. A plan's work is its tasks plus its breaks (the rules
# it owes the mutation check: those naming it and every rule of a requirement it
# completes, at standard and deep; none at express). Each plan is timed at the
# quantile 0.75^(1/n) of its tier's seconds per unit of work over the latest 10
# plans that recorded both (n: the wave's plans; 0.75 for a lone plan), times its
# own work; the wave takes its longest plan. History from before breaks were
# recorded times a plan per task at the same quantile. The note and the history
# carry each plan's breaks; the road's waves count them the same way. Seen in vbw
# next --json's step and road, and in the note vbw run start writes.

load helper
load step-helper
load road-helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

step_of() { "$VBW" next --json | jq -c '.step'; }

# rec_edit FILTER: change the record (rules kept), commit it and approve the contract again.
rec_edit() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "chore(vbw): edit"
  "$VBW" approve > /dev/null
}

# hist_unit TIER TASKS BREAKS SECONDS: one finished build of one plan at TIER with
# TASKS tasks and BREAKS breaks, done SECONDS after its run started.
hist_unit() {
  hist_add "$(jq -nc --arg t "$1" --argjson k "$2" --argjson b "$3" --argjson s "$4" '{kind: "build", seconds: $s, parts: 1,
    units: [{id: "P7.1", tier: $t, tasks: $k, breaks: $b, seconds: $s}]}')"
}

# alone: P1.2 and P1.3 wait for P1.1, so the next wave is P1.1 alone; two rules name P1.1.
alone() {
  rec_edit '(.plans[] | select(.id != "P1.1")).after = ["P1.1"]
    | .requirements[0].rules = [{text: "pays", check: "C1", plan: "P1.1"}, {text: "pays once", check: "C1", plan: "P1.1"},
                                {text: "logs the payment", check: "C1", plan: "P1.2"}]'
}

@test "T174: a lone plan takes the upper quartile of its tier's seconds per unit of work (tasks plus breaks), times its own" {
  tiered_project
  alone
  # 100, 200, 300 and 400 s per unit of work: the upper quartile is 325 (the median 250).
  hist_unit standard 1 1 200
  hist_unit standard 2 0 400
  hist_unit standard 1 2 900
  hist_unit standard 2 2 1600
  hist_unit deep 1 0 100000
  local s
  s=$(step_of)
  # P1.1: 2 tasks and 2 breaks (the rules naming it) = 4 units: 1300 s.
  printf '%s' "$s" | jq -e '.kind == "build" and .ids == ["P1.1"] and .seconds == 1300' || { echo "$s"; false; }
}

@test "T174: a wave waits for its slowest plan: n plans side by side take the quantile 0.75^(1/n)" {
  tiered_project
  hist_unit standard 1 0 100
  hist_unit standard 1 0 200
  hist_unit standard 1 0 300
  hist_unit standard 1 0 400
  hist_unit standard 1 0 500
  local s
  s=$(step_of)
  # Three plans: the quantile 0.909 of 100..500 is 463.4 s per unit; P1.2's five tasks take 2317 s.
  printf '%s' "$s" | jq -e '.ids == ["P1.1", "P1.2", "P1.3"] and .seconds == 2317' || { echo "$s"; false; }
  "$VBW" run start build P1.1 P1.2 P1.3 > /dev/null
  [ "$(step_secs first_end)" -eq 2317 ] || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  # The same history for P1.1 alone (no breaks here): the upper quartile, 400 s per unit, times 2.
  rec_edit '(.plans[] | select(.id != "P1.1")).after = ["P1.1"]'
  step_of | jq -e '.ids == ["P1.1"] and .seconds == 800' || { step_of; false; }
}

@test "T174: a plan's breaks are the rules it owes, carried in the note's units (the history keeps them); none at express" {
  tiered_project
  alone
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.units == [{id: "P1.1", tier: "standard", tasks: 2, breaks: 2, seconds: null}]' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  # A plan that completes the requirement owes every rule of it.
  rec_edit '(.plans[] | select(.id != "P1.1")).status = "done"'
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.units[0].breaks == 3' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  rec_edit '.phases[0].tier = "express"'
  "$VBW" run start build P1.1 > /dev/null
  jq -e '.units[0].breaks == 0' "$NOTE" || { cat "$NOTE"; false; }
}

@test "T174: history from before breaks were recorded times a plan per task, at the same quantile" {
  tiered_project
  alone
  hist_build standard 1 100 1
  hist_build standard 2 400 1
  hist_build standard 1 300 1
  hist_build standard 1 400 1
  # 100, 200, 300 and 400 s per task: the upper quartile 325, times P1.1's two tasks.
  step_of | jq -e '.ids == ["P1.1"] and .seconds == 650' || { step_of; false; }
}

@test "T174: the road's build waves count each plan's breaks the same way" {
  road_project
  road_hist
  hist_unit deep 1 0 100
  hist_unit deep 1 0 100
  hist_unit deep 1 0 100
  hist_unit standard 1 0 100
  hist_unit standard 1 0 100
  hist_unit standard 1 0 100
  local before after
  before=$("$VBW" next --json | jq '.road.seconds')
  [ "$before" != null ] || { "$VBW" next --json | jq '.road'; false; }
  # Two rules name P1.2 (five tasks): its wave grows from 500 s to 700 s.
  rec_edit '.requirements[0].rules = [{text: "pays", check: "C1", plan: "P1.2"}, {text: "pays once", check: "C1", plan: "P1.2"}]'
  after=$("$VBW" next --json | jq '.road.seconds')
  [ "$((after - before))" -eq 200 ] || { echo "before $before, after $after"; "$VBW" next --json | jq '.road'; false; }
}

@test "T174: docs/panel.md says a wave is timed for its slowest plan and that a plan's breaks count" {
  local s
  s=$(sed -n '/^## Time left/,/^## /p' "$REPO_ROOT/docs/panel.md" | sed '$d' | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]')
  printf '%s' "$s" | grep -q 'slowest plan' || { echo "no slowest plan"; false; }
  printf '%s' "$s" | grep -q 'upper quartile' || { echo "no upper quartile"; false; }
  printf '%s' "$s" | grep -q 'tasks plus its breaks' || { echo "no tasks plus its breaks"; false; }
  printf '%s' "$s" | grep -qF '0.75^(1/n)' || { echo "no 0.75^(1/n)"; false; }
}
