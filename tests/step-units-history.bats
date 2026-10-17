#!/usr/bin/env bats
# R191, phase P149 (L1): the step history (steps.json in the clone's git folder)
# records every finished step's units. A build: each plan done in it with its id,
# its rigor tier (its phase's at that moment; standard when the phase has none),
# its number of tasks and its own seconds, from the run's start to its vbw plan
# done; a plan the run left unfinished is no unit. A fix round: its fixes and the
# highest tier of their phases. Planning: how many open requirements of the
# milestone it planned. QA: the phases it checked, each with its tier. Entries from
# before (kind, seconds, parts) stay as they are, readable beside the new ones; the
# latest 50 of each kind are kept; a damaged or unwritable history never fails a
# step. The parts shown while a step runs are unchanged ('1 of 2').

load helper
load step-helper
load road-helper

setup() {
  vbw_setup
  tiered_project
}
teardown() { vbw_teardown; }

# last KIND: the newest step of KIND in the history.
last() { jq -c --arg k "$1" '[.steps[] | select(.kind == $k)] | last' "$STEPS"; }

@test "R191: a finished build records each plan done with its id, tier, tasks and own seconds; the note counts them as they finish" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  sleep 2
  step_finish P1.1 src/a.txt
  jq -e '.parts == {done: 1, total: 2}' "$NOTE" || { cat "$NOTE"; false; }
  jq -e '[.units[] | select(.id == "P1.1")][0] | .tier == "standard" and .tasks == 2 and (.seconds | type == "number" and . >= 2)' "$NOTE" || { cat "$NOTE"; false; }
  jq -e '[.units[] | select(.id == "P1.2")][0] | .tier == "standard" and .tasks == 5 and .seconds == null' "$NOTE" || { cat "$NOTE"; false; }
  step_finish P1.2 src/b.txt
  "$VBW" run end > /dev/null
  last build | jq -e '.kind == "build" and .parts == 2 and (.units | length == 2)
    and (.units[0] | .id == "P1.1" and .tier == "standard" and .tasks == 2 and (.seconds | type == "number" and . >= 2))
    and (.units[1] | .id == "P1.2" and .tier == "standard" and .tasks == 5 and (.seconds | type == "number" and . >= 0))' || { cat "$STEPS"; false; }
}

@test "R191: a plan's tier is its phase's at that moment, standard when the phase has none; a plan left unfinished is no unit" {
  step_edit '.phases[0].tier = "express"'
  "$VBW" run start build P1.1 P1.3 > /dev/null
  step_finish P1.1 src/a.txt
  "$VBW" run end > /dev/null
  last build | jq -e '.parts == 2 and (.units | length == 1) and .units[0].id == "P1.1" and .units[0].tier == "express" and .units[0].tasks == 2' || { cat "$STEPS"; false; }
  step_edit 'del(.phases[0].tier) | .plans[].status = "planned"'
  "$VBW" run start build P1.2 > /dev/null
  step_finish P1.2 src/b.txt
  "$VBW" run end > /dev/null
  last build | jq -e '(.units | length == 1) and .units[0].id == "P1.2" and .units[0].tier == "standard" and .units[0].tasks == 5' || { cat "$STEPS"; false; }
}

@test "R191: a fix round records its fixes and the highest tier of their phases" {
  printf -- '- R2 [auto] A customer gets a receipt\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  step_edit '.plans[].status = "done"
    | .phases += [{id: "P2", title: "Receipt", reqs: ["R2"], milestone: "M1", tier: "deep"}]
    | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"},
                {id: "F2", req: "R2", attempts: 0, status: "open", note: "C1 fail"}]'
  "$VBW" run start fix F1 F2 > /dev/null
  "$VBW" run end > /dev/null
  last fix | jq -e '.kind == "fix" and .parts == 2 and .fixes == ["F1", "F2"] and .tier == "deep"' || { cat "$STEPS"; false; }
  step_edit '.fixes[].status = "open"'
  "$VBW" run start fix F1 > /dev/null
  "$VBW" run end > /dev/null
  last fix | jq -e '.fixes == ["F1"] and .tier == "standard"' || { cat "$STEPS"; false; }
}

@test "R191: planning records how many open requirements of the milestone it planned" {
  printf -- '- R2 [auto] A customer gets a receipt\n- R3 [human] The page feels trustworthy\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  last plan | jq -e '.kind == "plan" and .reqs == 3 and (has("parts") | not)' || { cat "$STEPS"; false; }
  step_edit '(.requirements[] | select(.id == "R2")).status = "proven"'
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  last plan | jq -e '.reqs == 2' || { cat "$STEPS"; false; }
  step_edit '(.requirements[] | select(.id == "R3")).status = "accepted"'
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  last plan | jq -e '.reqs == 1' || { cat "$STEPS"; false; }
  step_edit '(.requirements[] | select(.id == "R2")).status = "open" | (.requirements[] | select(.id == "R3")).status = "open"'
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  last plan | jq -e '.reqs == 3' || { cat "$STEPS"; false; }
}

@test "R191: QA records the phases it checked, each with its tier" {
  step_edit '.plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" prove --full > /dev/null
  "$VBW" next --json | jq -e '.action == "qa" and .detail.phases == ["P1"]' > /dev/null || { "$VBW" next --json; false; }
  "$VBW" run start qa > /dev/null
  "$VBW" run end > /dev/null
  last qa | jq -e '.kind == "qa" and .phases == [{id: "P1", tier: "standard"}]' || { cat "$STEPS"; false; }
  step_edit '.phases[0].tier = "deep"'
  "$VBW" run start qa > /dev/null
  "$VBW" run end > /dev/null
  last qa | jq -e '.phases == [{id: "P1", tier: "deep"}]' || { cat "$STEPS"; false; }
}

@test "R191: entries from before stay as they are beside the new ones, and the latest 50 of each kind are kept" {
  step_seed build 300 1 2
  step_seed build 5000 - 47
  "$VBW" run start build P1.1 > /dev/null
  step_finish P1.1 src/a.txt
  "$VBW" run end > /dev/null
  [ "$(jq '[.steps[] | select(.kind == "build")] | length' "$STEPS")" -eq 50 ] || { jq '.steps | length' "$STEPS"; false; }
  jq -e '([.steps[] | select(.kind == "build" and (has("units") | not))] | length == 49)
    and ([.steps[] | select(.kind == "build" and .seconds == 300 and .parts == 1 and (has("units") | not))] | length == 2)
    and ([.steps[] | select(.kind == "build" and has("units"))] | length == 1)' "$STEPS" || { cat "$STEPS"; false; }
  step_seed build 1 1 3
  "$VBW" run start build P1.2 > /dev/null
  step_finish P1.2 src/b.txt
  "$VBW" run end > /dev/null
  [ "$(jq '[.steps[] | select(.kind == "build")] | length' "$STEPS")" -eq 50 ]
  jq -e '[.steps[] | select(.kind == "build")] | last | has("units")' "$STEPS" || { cat "$STEPS"; false; }
}

@test "R191: a damaged or unwritable history never fails a step and only means no end time yet" {
  mkdir -p "$(dirname "$STEPS")"
  printf 'garbage\n' > "$STEPS"
  vbw_run run start build P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"no end time yet"* ]] || { echo "$output"; false; }
  jq -e '.end == null and .first_end == null and (.units | length == 1)' "$NOTE" || { cat "$NOTE"; false; }
  step_finish P1.1 src/a.txt
  vbw_run run end
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -f "$STEPS"
  mkdir -p "$STEPS"
  vbw_run run start build P1.2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  step_finish P1.2 src/b.txt
  vbw_run run end
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -rf "$STEPS"
  mkdir -p "$(dirname "$STEPS")/runs.json"
  vbw_run run start build P1.3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" run end > /dev/null
}
