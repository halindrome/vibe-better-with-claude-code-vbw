#!/usr/bin/env bats
# R180 (P129): tools/l3-suite.sh gains a loop scenario (two backlog items, one
# that ships and one whose fix escalates twice and parks, a small ceiling) with
# its outcome checked in the record, the report file and git. The suite's
# structure is held here (L1); the scenario itself runs the real Claude Code
# app in the release run (L3), and its committed result, once there, must be
# labelled honestly. tests/l3-scenarios.bats is the frozen check file of R34,
# so the loop scenario is listed here instead. docs/loop.md, docs/guards.md and
# README describe the loop, its limits and the promise as it now stands.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

@test "R180: the loop scenario exists, is in the default list and the header, and writes its own result" {
  grep -q '^scenario_loop()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw loop
  sed -n '1,20p' "$SUITE" | grep -qw loop
  sed -n '/^scenario_loop()/,/^}/p' "$SUITE" | grep -q 'result_write loop '
}

@test "R180: the scenario arms two items with a small ceiling, one ships and one escalates twice and parks, checked in the record, the report and git" {
  local body
  body=$(sed -n '/^scenario_loop()/,/^}/p' "$SUITE")
  [ "$(printf '%s\n' "$body" | grep -c 'todo add')" -ge 2 ]
  printf '%s\n' "$body" | grep -q '/vbw:loop'
  printf '%s\n' "$body" | grep -q -- '--ceiling'
  printf '%s\n' "$body" | grep -q 'loop-report.md'
  printf '%s\n' "$body" | grep -qi 'parked'
  printf '%s\n' "$body" | grep -qi 'shipped'
  printf '%s\n' "$body" | grep -qi 'escalat'
  printf '%s\n' "$body" | grep -q 'git '
  printf '%s\n' "$body" | grep -qi 'revert'
}

@test "R180: a committed result of the loop scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/loop.json"
  [ -f "$f" ] || skip "no loop result committed yet: the release run writes it"
  jq -e '.scenario == "loop" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f"
}

@test "R180: docs/loop.md, docs/guards.md and README describe the loop, its limits and the promise" {
  grep -qF '/vbw:loop' "$REPO_ROOT/README.md"
  grep -qiE 'never leaves the project' "$REPO_ROOT/README.md"
  grep -qiE 'who approved' "$REPO_ROOT/README.md"
  grep -qF 'docs/loop.md' "$REPO_ROOT/README.md"
  grep -qF '/vbw:loop stop' "$REPO_ROOT/docs/guards.md"
  grep -qF 'never leaves the project' "$REPO_ROOT/docs/guards.md"
  grep -qF 'git push' "$REPO_ROOT/docs/guards.md"
  grep -qF 'vbw loop park' "$REPO_ROOT/docs/loop.md"
  grep -qF 'git revert' "$REPO_ROOT/docs/loop.md"
  grep -qiE 'never leaves the project' "$REPO_ROOT/docs/loop.md"
  grep -qiE 'who approved' "$REPO_ROOT/docs/loop.md"
  grep -qF 'parked' "$REPO_ROOT/docs/record.md"
}

@test "R180 (F183): the scenario judges reverts only when the parked item had commits, and names the gap in not_tested when it had none; a committed result keeps that promise" {
  local s="$REPO_ROOT/tools/l3-suite.sh" f="$RESULTS/loop.json"
  grep -q 'if \[ "\$n_rev" -gt 0 \]; then expect "the revert commits are in git' "$s"
  grep -q 'if \[ "\$n_rev" -eq 0 \]; then printf .%s. .\["a park that reverts commits' "$s"
  [ -f "$f" ] || skip "no loop result committed yet"
  jq -e '(.facts.revert_commits > 0) or any(.not_tested[]; test("revert"))' "$f"
}
