#!/usr/bin/env bats
# R190, phase P146 (L1): when a run ends, VBW adds it to the step history,
# steps.json in the clone's git folder: its kind (plan, build, fix, qa or map),
# start, end, seconds and, where it has countable parts, how many (plans for a
# build, fixes for a fix). Proofs are tests/step-proof-history.bats's. The history
# keeps the latest 50 steps of each kind; a missing, damaged or unwritable
# history never fails a step and means 'no end time yet'. Nothing is written
# outside the project but the clone's git folder.

load helper
load step-helper
load fixture-helper

built_project() {
  vbw_setup
  step_project
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# last KIND: the newest step of KIND in the history.
last() { jq -c --arg k "$1" '[.steps[] | select(.kind == $k)] | last' "$STEPS"; }

@test "R190: a finished build adds one step with its kind, start, end, seconds and its plans as parts" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  "$VBW" run end > /dev/null
  last build | jq -e '.kind == "build" and (.run | startswith("build-")) and .parts == 2
    and (.started_at | test("^[0-9-]+T[0-9:]+Z$")) and (.ended_at | test("^[0-9-]+T[0-9:]+Z$"))
    and (.seconds | type == "number" and . >= 0)' || { cat "$STEPS"; false; }
}

@test "R190: a fix step counts its fixes as parts" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"},
    {id: "F2", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fixes"
  "$VBW" run start fix F1 F2 > /dev/null
  "$VBW" run end > /dev/null
  last fix | jq -e '.kind == "fix" and .parts == 2' || { cat "$STEPS"; false; }
}

@test "R190: planning, QA and mapping steps have no parts to count" {
  local k
  for k in plan qa map; do
    "$VBW" run start "$k" > /dev/null
    jq -e --arg k "$k" '.kind == $k and .parts == null' "$NOTE" || { cat "$NOTE"; false; }
    "$VBW" run end > /dev/null
    last "$k" | jq -e --arg k "$k" '.kind == $k and (.parts // null) == null and (.seconds | type == "number")' || { cat "$STEPS"; false; }
  done
}

@test "R190: the history keeps the latest 50 steps of each kind, so many builds never push out planning" {
  step_seed build 60 1 60
  step_seed plan 30 - 3
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  jq -e '([.steps[] | select(.kind == "build")] | length) == 50 and ([.steps[] | select(.kind == "plan")] | length) == 4' "$STEPS" || { cat "$STEPS"; false; }
  # The oldest ten builds went; the newest fifty stayed, in order.
  jq -e '[.steps[] | select(.kind == "build") | .run] | .[0] == "build-seed-0-10" and .[-1] == "build-seed-0-59"' "$STEPS" || { cat "$STEPS"; false; }
  step_seed plan 30 - 60
  "$VBW" run start qa > /dev/null
  "$VBW" run end > /dev/null
  jq -e '([.steps[] | select(.kind == "plan")] | length) == 50 and ([.steps[] | select(.kind == "build")] | length) == 50
    and ([.steps[] | select(.kind == "qa")] | length) == 1' "$STEPS" || { cat "$STEPS"; false; }
}

@test "R190: a damaged history never fails a step and means no end time yet" {
  mkdir -p "$(dirname "$STEPS")"
  printf 'not json' > "$STEPS"
  vbw_run run start build P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.kind == "build" and .first_end == null and .end == null' "$NOTE" || { cat "$NOTE"; false; }
  vbw_run run end
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"run ended"* ]]
  jq -e '.steps | length == 1' "$STEPS"
}

@test "R190: a missing or unwritable history never fails a step and means no end time yet" {
  rm -f "$STEPS"
  vbw_run run start build P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.first_end == null' "$NOTE" || { cat "$NOTE"; false; }
  "$VBW" run end > /dev/null
  rm -f "$STEPS"
  mkdir -p "$STEPS"
  vbw_run run start build P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.first_end == null' "$NOTE" || { cat "$NOTE"; false; }
  vbw_run run end
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(jq -r '.lease // empty' .vbw/record.json)" ]
}

@test "R190: under bash 3.2's rules, the history and the note stay inside the project and its git folder" {
  local before after
  [ -x /bin/bash ] || skip "no /bin/bash"
  step_seed build 600 2 3
  before=$(cd "$TEST_ROOT" && find . -path './project with space' -prune -o -type f -print | grep -v '/vbw/slots' | sort)
  VBW_SESSION_ID=s1 /bin/bash "$VBW" run start build P1.1 P1.2 > /dev/null
  [ -f "$NOTE" ]
  step_finish P1.1 src/a.txt
  VBW_SESSION_ID=s1 /bin/bash "$VBW" run end > /dev/null
  after=$(cd "$TEST_ROOT" && find . -path './project with space' -prune -o -type f -print | grep -v '/vbw/slots' | sort)
  [ "$before" = "$after" ] || { diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"); false; }
  case "$STEPS" in "$(cd "$PROJECT" && pwd -P)/.git/"*) ;; *) echo "the history is not in the clone's git folder: $STEPS"; false ;; esac
  jq -e '([.steps[] | select(.kind == "build")] | length) == 4 and ([.steps[] | select(.kind == "build")] | last | .parts) == 2' "$STEPS" || { cat "$STEPS"; false; }
}

@test "R190: the step code reads and writes JSON only through jq" {
  local f="$PLUGIN_ROOT/lib/steps.sh"
  [ -f "$f" ] || { echo "no plugin/lib/steps.sh"; false; }
  ! grep -nE '(^|[^[:alnum:]_-])(sed|awk|grep|cut)[[:space:]]' "$f" || { echo "steps.sh parses text with sed, awk, grep or cut"; false; }
}
