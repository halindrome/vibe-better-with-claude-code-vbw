#!/usr/bin/env bats
# R178 (P127; docs/loop.md): vbw loop start ITEM... with a ceiling choice records
# the loop in the record and commits it: the items in the order given with a
# snapshot of each one's backlog text, the ceiling and its mode, the session,
# the start time and every known session's figures as the baseline. The ceiling
# is the user's choice (D317): --ceiling USD (stop at the next step), --ceiling
# USD --finish-item, or --no-ceiling; none of them, --finish-item alone or a
# USD that is not a positive number is a usage error (exit 2). Every refusal
# names what to do instead and changes nothing. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

loop_json() { "$VBW" loop status --json < /dev/null; }

@test "R178: loop start records the items in order, the ceiling, the session, the start time and the baseline, and commits the record" {
  local before
  before=$(git rev-parse HEAD)
  run env VBW_SESSION_ID=s1 "$VBW" loop start T2 T1 --ceiling 5
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.items | length == 2 and .[0].id == "T2" and .[1].id == "T1"
    and .[0].text == "Visitors can read a farewell" and .[1].text == "Visitors can read a greeting"
    and all(.[]; .status == "waiting" and .proof == "auto")' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  jq -e '.loop.ceiling == {usd: 5, finish_item: false} and .loop.session == "s1"
    and (.loop.started_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and .loop.baseline.s1.usd == 2 and .loop.baseline.s1.in == 1000 and .loop.baseline.s1.out == 100
    and (.loop.baseline.s1.at | type == "string")' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  jq -e '.todos[] | select(.id == "T1") | .status == "open"' .vbw/record.json
  [ "$(git rev-parse HEAD)" != "$before" ]
  [ -z "$(git status --porcelain -- .vbw/record.json)" ]
}

@test "R178: the items are a snapshot: a later edit of the backlog changes nothing in the loop" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  edit_record '(.todos[] | select(.id == "T1")).text = "Something else entirely"'
  loop_json | jq -e '.items[0].text == "Visitors can read a greeting"'
  run "$VBW" loop status
  [[ "$output" == *"Visitors can read a greeting"* ]] && [[ "$output" != *"Something else"* ]] || { echo "$output"; false; }
}

@test "R178: vbw loop status prints all of it from any session of the project" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 --finish-item > /dev/null
  local started
  started=$(jq -r .loop.started_at .vbw/record.json)
  run env VBW_SESSION_ID=s9 "$VBW" loop status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"T1"*"Visitors can read a greeting"*"T2"*"Visitors can read a farewell"* ]] || { echo "$output"; false; }
  [[ "$output" == *'$5'* ]] && [[ "$output" == *"finish"* ]] && [[ "$output" == *"s1"* ]] && [[ "$output" == *"$started"* ]] || { echo "$output"; false; }
  [[ "$output" == *'$2.00'* ]] || { echo "$output"; false; }
  run env VBW_SESSION_ID=s9 "$VBW" loop status --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.on == true and (.items | length) == 2 and .ceiling == {usd: 5, finish_item: true}
    and .session == "s1" and .baseline.s1.usd == 2 and (.started_at | type == "string")'
}

@test "R178: the three ceiling forms are recorded as the user chose them (D317)" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 12.5 > /dev/null
  jq -e '.loop.ceiling == {usd: 12.5, finish_item: false}' .vbw/record.json
  run "$VBW" loop status
  [[ "$output" == *"next step"* ]] || { echo "$output"; false; }
  edit_record 'del(.loop)'
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 3 --finish-item > /dev/null
  jq -e '.loop.ceiling == {usd: 3, finish_item: true}' .vbw/record.json
  run "$VBW" loop status
  [[ "$output" == *"finish"* ]] || { echo "$output"; false; }
  edit_record 'del(.loop)'
  no_figures
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  jq -e '.loop.ceiling == null' .vbw/record.json
  run "$VBW" loop status
  [[ "$output" == *"no ceiling"* ]] || [[ "$output" == *"ceiling: none"* ]] || { echo "$output"; false; }
}

@test "R178: no ceiling choice, --finish-item alone, or a USD that is not a positive number is a usage error (exit 2) and nothing changes" {
  local before args
  before=$(project_sum)
  for args in "T1" "T1 --finish-item" "T1 --ceiling 0" "T1 --ceiling -3" "T1 --ceiling abc" "T1 --ceiling" "T1 --ceiling 5 --no-ceiling"; do
    # shellcheck disable=SC2086 # the arguments split on purpose
    run env VBW_SESSION_ID=s1 "$VBW" loop start $args
    [ "$status" -eq 2 ] || { echo "loop start $args: exit $status: $output"; false; }
    [[ "$output" == *"--ceiling USD"* ]] && [[ "$output" == *"--no-ceiling"* ]] || { echo "loop start $args: $output"; false; }
    [ "$(project_sum)" = "$before" ] || { echo "loop start $args changed the project"; false; }
    jq -e 'has("loop") | not' .vbw/record.json
  done
}

# refused ARGS...: loop start refuses with exit 1, names what to do instead, and changes nothing.
refused() {
  local before
  before=$(project_sum)
  run env VBW_SESSION_ID=s1 "$VBW" loop start "$@"
  [ "$status" -eq 1 ] || { echo "loop start $*: exit $status: $output"; return 1; }
  [[ "$output" == *"Next: "* ]] || { echo "loop start $*: no next step: $output"; return 1; }
  [ "$(project_sum)" = "$before" ] || { echo "loop start $* changed the project"; return 1; }
}

@test "R178: no item, an unknown item, a closed item or the same item twice is refused with what to do instead" {
  refused --no-ceiling
  [[ "$output" == *"no item"* ]] || { echo "$output"; false; }
  refused T99 --no-ceiling
  [[ "$output" == *"T99"* ]] && [[ "$output" == *"vbw todo list"* ]] || { echo "$output"; false; }
  "$VBW" todo done T2 > /dev/null
  refused T2 --no-ceiling
  [[ "$output" == *"T2"* ]] && [[ "$output" == *"done"* ]] || { echo "$output"; false; }
  "$VBW" todo add "Dropped idea" > /dev/null
  "$VBW" todo drop T3 > /dev/null
  refused T3 --no-ceiling
  [[ "$output" == *"T3"* ]] && [[ "$output" == *"dropped"* ]] || { echo "$output"; false; }
  refused T1 T1 --no-ceiling
  [[ "$output" == *"T1"* ]] && [[ "$output" == *"twice"* ]] || { echo "$output"; false; }
}

@test "R178: a loop already on is refused and names vbw loop stop" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  refused T2 --no-ceiling
  [[ "$output" == *"vbw loop stop"* ]] || { echo "$output"; false; }
  jq -e '.loop.items | length == 1 and .[0].id == "T1"' .vbw/record.json
}

@test "R178: a current milestone with requirements that is not shipped is refused: finish or ship it first" {
  "$VBW" spec add auto "Visitors can search the notes" > /dev/null
  refused T1 --no-ceiling
  [[ "$output" == *"M2"* ]] && { [[ "$output" == *"ship"* ]] || [[ "$output" == *"finish"* ]]; } || { echo "$output"; false; }
}

@test "R178: --ceiling when no session has a cost figure is refused: vbw statusline on, or --no-ceiling" {
  no_figures
  refused T1 --ceiling 5
  [[ "$output" == *"vbw statusline on"* ]] && [[ "$output" == *"--no-ceiling"* ]] || { echo "$output"; false; }
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  jq -e '.loop.baseline == {}' .vbw/record.json
}

@test "R178: a loop started outside any session records no session, and --help changes nothing" {
  local before
  before=$(project_sum)
  run "$VBW" loop start --help
  [ "$status" -eq 0 ]
  [[ "$output" == "usage: vbw loop"* ]]
  [ "$(project_sum)" = "$before" ]
  run "$VBW" loop start T1 --no-ceiling
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.session == null' .vbw/record.json
}

@test "R178 (F169): a [human] requirement an earlier ship carried over does not make the current milestone unfinished: the loop starts" {
  vbw_teardown
  loop_project human
  jq -e '.requirements[] | select(.id == "R2") | .proof == "human" and .milestone == .milestone' .vbw/record.json > /dev/null
  run env VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.items | length == 1' .vbw/record.json
}
