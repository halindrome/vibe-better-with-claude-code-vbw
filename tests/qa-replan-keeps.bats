#!/usr/bin/env bats
# R66 (docs/proof.md): re-planning mid-milestone (vbw apply with a phase added)
# keeps each existing phase's QA verdict; QA then checks again only the new
# phase and the phases whose own inputs changed, by the R47 re-check rule. (A
# checked phase has started, so a re-plan can no longer change its goal: R158.)

load helper
load qa-recheck-helper

teardown() { vbw_teardown; }

# replan_add: R3 joins the spec and the milestone is re-applied with P3 added.
replan_add() {
  printf -- '- R3 [auto] Part 3 works\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'grep -qx part3 src/p3.txt\n' > tests/p3.sh
  qa_doc 3 | "$VBW" apply > /dev/null
}

@test "R66: adding a phase mid-milestone keeps the QA verdicts of the phases already checked" {
  qa_project 2
  qa_pass P1 P2
  replan_add
  jq -e '[.phases[] | select(.id == "P1" or .id == "P2") | .qa.result] == ["pass", "pass"]' .vbw/record.json
}

@test "R66: after the new phase is built, QA checks only the new phase" {
  qa_project 2
  qa_pass P1 P2
  replan_add
  "$VBW" approve > /dev/null
  printf 'part3\n' > src/p3.txt
  "$VBW" commit P3.1 "feat(p3): part 3" > /dev/null
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P3.1 > /dev/null
  "$VBW" prove --full > /dev/null
  [ "$(listed)" = '["P3"]' ]
  next_json | jq -e '.qa.standing == ["P1","P2"]'
}
