#!/usr/bin/env bats
# QA re-check rounds converge (docs/proof.md, "Which phases QA checks again").
# A phase that builds on another is checked again only when that phase's tests
# changed (its requirements' checks or the files they list), never because its
# code, documents, saved results or plan changed: those are its own phase's to
# check. A phase whose last verdict was fail, with its goal, criteria, plans and
# [auto] requirements unchanged since, gets a re-check round: vbw next names the
# fixes since that verdict and the commit it was taken at, and the verify
# workflow tells QA to check those fixes, what their changed files reach and
# the goal, not to sweep the whole phase again. (That a change to the tests of a
# phase another builds on lists the dependent too is pinned in
# qa-recheck-deps.bats.) L1.

load helper
load qa-recheck-helper
load fixture-helper

# The projects the tests start from, each built once per file.
setup_file() {
  fixture_build p1 qa_project 1
  fixture_build p2 qa_project 2
  fixture_build p2chain qa_project 2 chain
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# fail_round PHASE: QA fails PHASE with one finding; the fix touches its file
# and is marked fixed (as vbw fix done would); then prove.
fail_round() {
  local n="${1#P}"
  "$VBW" qa finding "$1" "R$n" "part $n misses an edge case" > /dev/null
  "$VBW" qa record "$1" fail standard "4/5 checks" > /dev/null
  edit_record '(.fixes[] | select(.source == "qa" and .status == "open")).status = "fixed"'
  git add .vbw/record.json && git commit -q -m "chore(vbw): fixed"
  qa_touch "$n"
}

cache_commit() { jq -r --arg p "$1" '.[$p].commit' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/qa.json"; }

@test "T118: a code change in a phase another builds on checks only that phase again" {
  fixture_copy p2chain
  qa_pass P1 P2
  qa_touch 1
  [ "$(listed)" = '["P1"]' ] || { next_json | jq -c .qa; false; }
  next_json | jq -e '.qa.standing == ["P2"]'
}

@test "T118: on a clone without the QA cache, a code change in a dependency still leaves the dependent standing" {
  fixture_copy p2chain
  qa_pass P1 P2
  rm -f "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/qa.json"
  qa_touch 1
  [ "$(listed)" = '["P1"]' ] || { next_json | jq -c .qa; false; }
}

@test "T45: a dependency's goal or plan change alone does not check the dependent again" {
  fixture_copy p2chain
  qa_pass P1 P2
  edit_record '(.phases[] | select(.id == "P1")).goal = "Part 1 works well"'
  [ "$(listed)" = '["P1"]' ] || { next_json | jq -c .qa; false; }
}

@test "T131: a failed phase whose goal and plans did not change gets a re-check round: the fixes since the verdict and its commit" {
  fixture_copy p1
  fail_round P1
  local since
  since=$(cache_commit P1)
  next_json | jq -e --arg c "$since" '.action == "qa" and .round.focus.P1.since == $c
    and .round.focus.P1.round == 2 and (.round.focus.P1.fixes | length == 1 and .[0].req == "R1" and (.[0].id | test("^F")))' \
    || { next_json | jq -c '{action, round, qa}'; false; }
}

@test "T131: the first round, a never-checked phase and a passed phase that changed get the whole-phase sweep" {
  fixture_copy p2
  qa_pass P2
  qa_touch 2
  next_json | jq -e '.action == "qa" and (.round.focus | has("P1") or has("P2") | not)' || { next_json | jq -c '.round'; false; }
}

@test "T131: a goal, criteria or plan change since the failed verdict brings back the whole-phase sweep" {
  fixture_copy p1
  fail_round P1
  edit_record '(.phases[] | select(.id == "P1")).criteria += ["src/p1.txt is not empty"]'
  next_json | jq -e '.action == "qa" and (.round.focus | has("P1") | not)' || { next_json | jq -c '.round'; false; }
}

@test "T131: without the QA cache a failed phase gets the whole-phase sweep" {
  fixture_copy p1
  fail_round P1
  rm -f "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/qa.json"
  next_json | jq -e '.action == "qa" and (.round.focus | has("P1") | not)' || { next_json | jq -c '.round'; false; }
}

@test "T131: the verify workflow tells a re-check round's QA the fixes, the commit to diff from and the goal, and the first round nothing of it" {
  command -v node > /dev/null || skip "node is not installed"
  local args out
  args='{"phases":["P1","P2"],"tier":"standard","round":{"focus":{"P1":{"since":"abc1234","round":2,"fixes":[{"id":"F7","req":"R1","note":"zero payment accepted"}]}}}}'
  out=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow.js" "$PLUGIN_ROOT/workflows/verifying.js" "$args" '{}') || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '([.calls[] | select(.opts.label == "qa P1")][0].prompt | contains("F7") and contains("abc1234") and contains("git diff") and contains("zero payment accepted") and contains("goal"))
    and ([.calls[] | select(.opts.label == "qa P2")][0].prompt | contains("abc1234") or contains("F7") | not)' || { echo "$out"; false; }
}

@test "T131: the QA agent's instructions carry the re-check round rule" {
  local qa="$PLUGIN_ROOT/agents/qa.md"
  grep -qi 're-check round' "$qa"
}
