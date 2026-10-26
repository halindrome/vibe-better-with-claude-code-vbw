#!/usr/bin/env bats
# Delivered files (docs/proof.md): the qafix finding of 2026-10-21. A quick QA
# passed a phase whose NOTES.md, delivered by its plan and named by no check,
# had been deleted by hand after the build. The kernel now checks it: each file
# a plan of the current milestone delivered (added or changed by its own
# VBW-Plan commits) must still be at HEAD as VBW's last commit of it left it. A
# later plan's or fix's commit moves the file on, and a plan that deletes a file
# delivers nothing for it. Any other difference is a deviation. vbw prove lists
# the deviations in its evidence. vbw next asks the user first (the deviations
# step): keep a change (a later decision naming the file covers it) or restore
# it (vbw fix restore FILE opens a fix that names it). A kept deviation goes to
# QA with its phase, even an express phase, in the round's list (round.deviations),
# and the QA brief names each file. vbw qa record PHASE pass refuses while one
# stands that no later decision of the user names. Only the record's own history counts (lib/history.sh):
# plan ids restart with a new record, so a commit older than the newest commit
# that added .vbw/record.json (a retired roadmap's VBW-Plan: P1.1) delivered
# nothing for today's P1.1. L1: kernel commands on a two-phase fixture and on a
# project with a retired roadmap; the QA brief under node with stubbed agents.

load helper
load fixture-helper

setup_file() {
  fixture_build built built_project
  fixture_build retired retired_project
}
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# built_project: P1.1 delivers greet.sh (checked by C1) and NOTES.md, HELP.md and
# TODO.md (no check names them), and deletes old.sh, which was there before.
# P2.1, after it, delivers farewell.sh (checked by C2), changes HELP.md and
# removes TODO.md. Both plans are built and proved; QA has recorded nothing.
built_project() {
  vbw_setup
  vbw_git_project
  printf 'echo old\n' > old.sh
  git add old.sh && git commit -q -m "chore(test): old.sh"
  "$VBW" init > /dev/null
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] greet.sh says hello\n- R2 [auto] farewell.sh says bye\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf '[ "$(sh greet.sh)" = hello ]\n' > tests/greet.sh
  printf '[ "$(sh farewell.sh)" = bye ]\n' > tests/farewell.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"], "tier": "standard"},
      {"id": "P2", "title": "Farewell", "reqs": ["R2"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Greet", "reqs": ["R1"], "files": ["greet.sh", "NOTES.md", "HELP.md", "TODO.md", "old.sh"],
        "tasks": ["greet.sh says hello", "NOTES.md says what greet.sh is for", "remove old.sh"]},
      {"id": "P2.1", "phase": "P2", "title": "Farewell", "reqs": ["R2"], "files": ["farewell.sh", "HELP.md", "TODO.md"], "after": ["P1.1"],
        "tasks": ["farewell.sh says bye", "HELP.md names it", "TODO.md is done"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/greet.sh"], "files": ["tests/greet.sh"]},
      {"id": "C2", "req": "R2", "run": ["sh", "tests/farewell.sh"], "files": ["tests/farewell.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'echo hello\n' > greet.sh
  printf 'greet.sh says hello.\n' > NOTES.md
  printf 'help\n' > HELP.md
  printf 'todo\n' > TODO.md
  rm old.sh
  "$VBW" commit P1.1 "feat(greet): hello" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  printf 'echo bye\n' > farewell.sh
  printf 'help\nfarewell.sh says bye\n' > HELP.md
  rm TODO.md
  "$VBW" commit P2.1 "feat(farewell): bye" > /dev/null
  "$VBW" plan done P2.1 > /dev/null
  "$VBW" prove --full > /dev/null
}

# retired_project: a retired roadmap's commits, older than the record, name
# VBW-Plan: P1.1: they add legacy.txt (changed by hand later, still before the
# record) and roadmap.md. Then a new record: its P1.1 delivers greet.sh
# (checked by C1) and NOTES.md, and is built.
retired_project() {
  vbw_setup
  vbw_git_project
  printf 'old\n' > legacy.txt
  printf '# Old roadmap\n' > roadmap.md
  git add legacy.txt roadmap.md && git commit -q -m "feat: old" -m "VBW-Plan: P1.1"
  printf 'old, by hand\n' > legacy.txt
  git commit -q -m "chore: legacy by hand" -- legacy.txt
  "$VBW" init > /dev/null
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] greet.sh says hello\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf '[ "$(sh greet.sh)" = hello ]\n' > tests/greet.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Greet", "reqs": ["R1"], "files": ["greet.sh", "NOTES.md"], "tasks": ["greet.sh says hello"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/greet.sh"], "files": ["tests/greet.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'echo hello\n' > greet.sh
  printf 'greet.sh says hello.\n' > NOTES.md
  "$VBW" commit P1.1 "feat(greet): hello" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
}

# plan_commit: the commit of P1.1 (the last one that touched greet.sh).
plan_commit() { git rev-list -1 HEAD -- greet.sh; }

# drop_notes: NOTES.md deleted by hand, committed, and proved.
drop_notes() {
  git rm -q NOTES.md && git commit -q -m "chore: drop NOTES.md" || return 1
  "$VBW" prove --full > /dev/null
}

deviations() { jq -c '.evidence.deviations' .vbw/record.json; }

@test "files still as their plans left them are no deviation: a later plan's change or removal, and a plan's own deletion, are delivered work, and QA passes as before" {
  jq -e '.evidence.passed and .evidence.deviations == []' .vbw/record.json || { deviations; false; }
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa" and .detail.phases == ["P1", "P2"] and .round.deviations == {}' || { echo "$output"; false; }
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run qa record P2 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"' || { echo "$output"; false; }
}

@test "the qafix shape: NOTES.md, delivered by P1.1 and named by no check, deleted by hand after the build: the proof lists it, QA is told, and no pass, quick or deep, is recorded until QA fails the phase" {
  local plan hand t
  plan=$(plan_commit)
  t=$(git log -1 --format=%ct "$plan")
  git rm -q NOTES.md && git commit -q -m "chore: drop NOTES.md"
  hand=$(git rev-parse HEAD)
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"delivered: NOTES.md (P1.1) deleted outside any plan, by ${hand:0:12}"* ]] || { echo "$output"; false; }
  jq -e --arg p "$plan" --arg h "$hand" --argjson t "$t" '.evidence.deviations
    == [{file: "NOTES.md", plan: "P1.1", commit: $p, at: ($t | todate), change: "deleted", by: [$h]}]' .vbw/record.json || { deviations; false; }
  vbw_run next --json
  echo "$output" | jq -e --arg p "$plan" --arg h "$hand" '.action == "deviations" and .gate
    and (.qa.recheck.P1 | any(.[]; . == "NOTES.md, delivered by P1.1, was deleted outside any plan"))
    and .detail.deviations == [{phase: "P1", file: "NOTES.md", plan: "P1.1", change: "deleted", commit: $p, by: [$h]}]' || { echo "$output"; false; }
  vbw_run show phase P1
  [[ "$output" == *"deviation: NOTES.md (P1.1) deleted outside any plan, by ${hand:0:12}"* ]] || { echo "$output"; false; }
  local tier
  for tier in quick deep; do
    vbw_run qa record P1 pass "$tier"
    [ "$status" -eq 1 ] || { echo "$output"; false; }
    [[ "$output" == *"NOTES.md (P1.1) deleted outside any plan, by ${hand:0:12}"* && "$output" == *"vbw qa finding P1 REQ TEXT, REQ one of R1"* && "$output" == *"vbw decide"* ]] || { echo "$output"; false; }
  done
  jq -e '.phases[0].qa == null' .vbw/record.json
  "$VBW" qa finding P1 R1 "NOTES.md, delivered by P1.1, was deleted" > /dev/null
  vbw_run qa record P1 fail quick "1/2 checks"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # P2 delivered nothing that changed: its pass is recorded as before.
  vbw_run qa record P2 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "what counts is HEAD: a hand commit back to the plan's content, or the file brought back through its plan, ends the deviation and QA may pass" {
  local plan
  plan=$(plan_commit)
  drop_notes
  git checkout -q "$plan" -- NOTES.md && git commit -q -m "chore: NOTES.md back" -- NOTES.md
  "$VBW" prove --full > /dev/null
  [ "$(deviations)" = '[]' ] || { deviations; false; }
  drop_notes
  [ "$(deviations | jq length)" -eq 1 ] || { deviations; false; }
  printf 'greet.sh says hello, again.\n' > NOTES.md
  "$VBW" commit P1.1 "fix(notes): bring NOTES.md back" NOTES.md > /dev/null
  "$VBW" prove --full > /dev/null
  [ "$(deviations)" = '[]' ] || { deviations; false; }
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a hand change after a later plan's change is that later plan's deviation, and lists its phase again though only a document changed and its pass stood" {
  "$VBW" qa record P1 pass standard > /dev/null
  "$VBW" qa record P2 pass standard > /dev/null
  printf 'help\nchanged by hand\n' > HELP.md
  git commit -q -m "docs: help by hand" -- HELP.md
  "$VBW" prove --full > /dev/null
  deviations | jq -e 'length == 1 and .[0].file == "HELP.md" and .[0].plan == "P2.1" and .[0].change == "changed"' || { deviations; false; }
  vbw_run next --json
  echo "$output" | jq -e '.action == "deviations" and ([.detail.deviations[] | [.phase, .file]] == [["P2", "HELP.md"]]) and .qa.standing == ["P1"]
    and .qa.recheck.P2 == ["HELP.md, delivered by P2.1, was changed outside any plan"]' || { echo "$output"; false; }
  vbw_run qa record P2 pass standard
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"HELP.md (P2.1) changed outside any plan, by"* ]] || { echo "$output"; false; }
}

@test "a commit whose VBW-Fix trailer names a fix of the record moves a delivered file on; one that names no fix of the record is a deviation" {
  local fixed hand
  "$VBW" qa finding P1 R1 "greet.sh should say why it greets" > /dev/null
  printf 'echo hello # says why\n' > greet.sh
  git commit -q -m "fix(greet): say why" -m "VBW-Fix: F1" -- greet.sh
  fixed=$(git rev-parse HEAD)
  "$VBW" prove --full > /dev/null
  [ "$(deviations)" = '[]' ] || { deviations; false; }
  printf 'echo hello # by hand\n' > greet.sh
  git commit -q -m "fix(greet): by hand" -m "VBW-Fix: F9" -- greet.sh
  hand=$(git rev-parse HEAD)
  "$VBW" prove --full > /dev/null
  deviations | jq -e --arg f "$fixed" --arg h "$hand" '. == [{file: "greet.sh", plan: "P1.1", commit: $f, at: .[0].at, change: "changed", by: [$h]}]' || { deviations; false; }
}

@test "the user's decision recorded after the delivery and naming the file covers the deviation and QA may pass; one naming other files, or recorded before the file was delivered, does not" {
  drop_notes
  "$VBW" decide "Keep NOTES.md.bak and docs/NOTES.md" > /dev/null
  vbw_run qa record P1 pass quick
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  "$VBW" decide "Drop NOTES.md: the README says enough" "the user's choice" > /dev/null
  local id
  id=$(jq -r '.decisions[-1].id' .vbw/record.json)
  vbw_run next --json
  echo "$output" | jq -e --arg d "$id" '.round.deviations.P1[0].decision == $d and .qa.recheck.P1 == ["not checked yet"]' || { echo "$output"; false; }
  edit_record '.decisions[-1].at = "2000-01-01T00:00:00Z"'
  vbw_run qa record P1 pass quick
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  "$VBW" decide "NOTES.md stays deleted" > /dev/null
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a file an express phase delivered changed outside any plan stops the ship until the user settles it; kept, nothing is left for QA" {
  edit_record '(.phases[] | select(.id == "P1")).tier = "express"'
  "$VBW" qa record P2 pass standard > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"' || { echo "$output"; false; }
  drop_notes
  vbw_run next --json
  echo "$output" | jq -e '.action == "deviations" and ([.detail.deviations[].file] == ["NOTES.md"])' || { echo "$output"; false; }
  "$VBW" decide "The user keeps NOTES.md deleted" > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"' || { echo "$output"; false; }
}

@test "the user chooses before QA: restoring opens one fix naming the file, which a fix brings back through its plan; QA follows the proof" {
  local plan
  plan=$(plan_commit)
  drop_notes
  vbw_run fix restore greet.sh
  [ "$status" -eq 1 ] && [[ "$output" == *"greet.sh is not a file its plan delivered that changed outside any plan"* ]] || { echo "$output"; false; }
  vbw_run fix restore NOTES.md
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "F1 opened for R1: restore NOTES.md" ] || { echo "$output"; false; }
  jq -e --arg p "$plan" '.fixes == [{id: "F1", req: "R1", restore: "NOTES.md", attempts: 0, status: "open",
    note: "Restore NOTES.md: P1.1 delivered it (commit \($p[0:12])) and it was deleted outside any plan; the user chose to bring it back to what P1.1 made"}]' .vbw/record.json || { jq .fixes .vbw/record.json; false; }
  vbw_run fix restore NOTES.md
  [ "$status" -eq 1 ] && [[ "$output" == *"NOTES.md is already being restored by F1"* ]] || { echo "$output"; false; }
  vbw_run next --json
  echo "$output" | jq -e '.action == "fix" and .detail.fixes == ["F1"]' || { echo "$output"; false; }
  git checkout -q "$plan" -- NOTES.md
  "$VBW" commit P1.1 "fix(notes): bring NOTES.md back" NOTES.md > /dev/null
  "$VBW" fix done F1 > /dev/null
  "$VBW" prove --full > /dev/null
  [ "$(deviations)" = '[]' ] || { deviations; false; }
  jq -e '.fixes[0].status == "closed"' .vbw/record.json || { jq .fixes .vbw/record.json; false; }
  vbw_run next --json
  echo "$output" | jq -e '.action == "qa" and (.detail.phases | index("P1"))' || { echo "$output"; false; }
}

@test "a restore whose file still deviates after its fix round opens again with one more attempt; passing checks do not close it" {
  drop_notes
  "$VBW" fix restore NOTES.md > /dev/null
  "$VBW" fix done F1 > /dev/null
  "$VBW" prove --full > /dev/null
  jq -e '.fixes[0].status == "open" and .fixes[0].attempts == 1 and .requirements[0].status == "proven"' .vbw/record.json || { jq '.fixes, .requirements' .vbw/record.json; false; }
  edit_record '.fixes[0].restore = ""'
  vbw_run status
  [ "$status" -ne 0 ] && [[ "$output" == *"F1 restore must be a file path"* ]] || { echo "$output"; false; }
}

@test "the check reads the history and HEAD once: the same shell commands for 3 deviating files as for 30, with every file named" {
  # many DIR N: a plan P1.2 of N files in DIR, delivered by one plan commit and deleted by one hand commit.
  many() {
    (
      cd "$1" || exit 1
      local i
      mkdir -p many
      for ((i = 1; i <= $2; i++)); do printf '%s\n' "$i" > "many/f$i.txt"; done
      jq --argjson n "$2" '.plans += [{id: "P1.2", phase: "P1", title: "Many", reqs: ["R1"], files: ["many/"], after: [], status: "done"}]' \
        .vbw/record.json > "$TEST_ROOT/many.json" && cp "$TEST_ROOT/many.json" .vbw/record.json
      git add many && git commit -q -m "feat(many): files" -m "VBW-Plan: P1.2"
      git rm -q -r many && git commit -q -m "chore: drop many"
    )
  }
  # trace DIR: delivered_deviations in DIR with bash's trace on; prints its result
  # and leaves the number of traced shell commands in $TEST_ROOT/count.
  trace() {
    # shellcheck disable=SC2016 # expanded by vbw_kernel
    (cd "$1" && vbw_kernel '. "$VBW_LIB/delivered.sh"; r=$(cat "$VBW_RECORD"); PS4="+TRACEMARK "; set -x
      delivered_deviations "$r" 2> "$TEST_ROOT/trace"; set +x') 2> /dev/null
    grep -o 'TRACEMARK' "$TEST_ROOT/trace" | wc -l | tr -d ' ' > "$TEST_ROOT/count"
  }
  cp -R "$PROJECT" "$TEST_ROOT/big"
  many "$PROJECT" 3
  many "$TEST_ROOT/big" 30
  local small big n3 n30
  small=$(trace "$PROJECT")
  n3=$(cat "$TEST_ROOT/count")
  big=$(trace "$TEST_ROOT/big")
  n30=$(cat "$TEST_ROOT/count")
  printf '%s' "$small" | jq -e 'length == 3 and all(.[]; .plan == "P1.2" and .change == "deleted")' || { echo "3: $small"; false; }
  printf '%s' "$big" | jq -e 'length == 30 and ([.[].file] | index("many/f30.txt")) != null' || { echo "30: $big"; false; }
  [ "$n3" -gt 0 ] || { echo "no traced command"; false; }
  [ "$n30" -eq "$n3" ] || { echo "shell commands: $n3 for 3 files, $n30 for 30"; false; }
}

@test "a plan's work reverted by hand is a deviation; a commit a park undid delivered nothing, even when a current plan has its plan id" {
  local r
  printf 'x\n' > stray.txt
  git add stray.txt && git commit -q -m "feat(farewell): stray" -m "VBW-Plan: P2.1"
  git revert --no-edit HEAD > /dev/null
  r=$(git rev-parse HEAD)
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/delivered.sh"; delivered_deviations "$(cat "$VBW_RECORD")"' > "$TEST_ROOT/hand.json"
  jq -e --arg r "$r" '. == [{file: "stray.txt", plan: "P2.1", commit: .[0].commit, at: .[0].at, change: "deleted", by: [$r]}]' "$TEST_ROOT/hand.json" \
    || { cat "$TEST_ROOT/hand.json"; false; }
  jq --arg r "$r" '.loop = {items: [{id: "T1", status: "parked", reverts: [$r]}]}' .vbw/record.json > "$TEST_ROOT/edit.json" \
    && cp "$TEST_ROOT/edit.json" .vbw/record.json
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/delivered.sh"; delivered_deviations "$(cat "$VBW_RECORD")"' > "$TEST_ROOT/park.json"
  [ "$(cat "$TEST_ROOT/park.json")" = '[]' ] || { cat "$TEST_ROOT/park.json"; false; }
}

@test "commits older than the record are not its plans' commits: a retired roadmap's P1.1 delivered nothing for today's P1.1, and a hand change to what today's P1.1 delivered is still a deviation" {
  fixture_copy retired
  printf '# Old roadmap, by hand\n' > roadmap.md
  git commit -q -m "docs: roadmap by hand" -- roadmap.md
  vbw_run prove --full
  # With the scope check on the record's own history too, the old roadmap fails nothing.
  [ "$status" -eq 0 ] && [[ "$output" == *"scope ok"* ]] || { echo "$output"; false; }
  [[ "$output" != *"delivered: legacy.txt"* && "$output" != *"delivered: roadmap.md"* ]] || { echo "$output"; false; }
  [ "$(deviations)" = '[]' ] || { deviations; false; }
  printf 'greet.sh says hello, by hand.\n' > NOTES.md
  git commit -q -m "docs: notes by hand" -- NOTES.md
  vbw_run prove --full
  [[ "$output" == *"delivered: NOTES.md (P1.1) changed outside any plan, by"* ]] || { echo "$output"; false; }
  deviations | jq -e '[.[].file] == ["NOTES.md"] and .[0].plan == "P1.1" and .[0].change == "changed"' || { deviations; false; }
}

@test "a malformed deviation in the evidence makes the record corrupt" {
  edit_record '.evidence.deviations = [{file: "NOTES.md", plan: "P1.1"}]'
  vbw_run status
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"evidence.deviations"* ]] || { echo "$output"; false; }
}

@test "the QA brief names each deviation of the round, its plan, how it changed and by which commit, and says a pass needs a finding or the user's decision; a decided one names the decision" {
  command -v node > /dev/null || skip "node is not installed"
  local args out p
  args=$(jq -nc --arg c "$(printf 'a%.0s' {1..40})" --arg h "$(printf 'b%.0s' {1..40})" '{phases: ["P1", "P2"], tier: "quick",
    round: {suite: null, deviations: {P1: [{file: "NOTES.md", plan: "P1.1", change: "deleted", commit: $c, by: [$h], decision: null},
      {file: "HELP.md", plan: "P1.1", change: "changed", commit: $c, by: [], decision: "D3"}]}}}')
  out=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow.js" "$PLUGIN_ROOT/workflows/verifying.js" "$args" '{}') || { echo "$out"; false; }
  p=$(printf '%s' "$out" | jq -r '[.calls[] | select(.opts.label == "qa P1")][0].prompt')
  [[ "$p" == *"NOTES.md (P1.1) deleted outside any plan, by bbbbbbbbbbbb"* ]] || { echo "$p"; false; }
  [[ "$p" == *"vbw qa finding P1"* && "$p" == *"vbw qa record P1 pass refuses"* ]] || { echo "$p"; false; }
  [[ "$p" == *"HELP.md (P1.1) changed outside any plan, since aaaaaaaaaaaa, covered by D3"* ]] || { echo "$p"; false; }
  p=$(printf '%s' "$out" | jq -r '[.calls[] | select(.opts.label == "qa P2")][0].prompt')
  [[ "$p" != *"outside any plan"* ]] || { echo "$p"; false; }
}

@test "the docs state the rule where they say what QA checks" {
  grep -q '^### Delivered files' "$REPO_ROOT/docs/proof.md"
  grep -q 'delivered by P1.1, was deleted outside any plan' "$REPO_ROOT/docs/proof.md"
  grep -q 'files its plans delivered' "$REPO_ROOT/docs/workflows.md"
  grep -q 'round.deviations' "$REPO_ROOT/docs/next.md"
  grep -q 'evidence.deviations\|`deviations`' "$REPO_ROOT/docs/record.md"
  grep -q 'outside any plan' "$REPO_ROOT/docs/rigor.md"
  grep -q 'vbw fix restore FILE' "$REPO_ROOT/docs/proof.md"
  grep -q '^| 10c | .*`deviations`' "$REPO_ROOT/docs/next.md"
  grep -q '`restore`' "$REPO_ROOT/docs/record.md"
  "$VBW" fix --help | grep -q 'vbw fix restore FILE'
  "$VBW" help | grep -q 'restore FILE'
  grep -q 'outside any plan' "$PLUGIN_ROOT/agents/qa.md"
}
