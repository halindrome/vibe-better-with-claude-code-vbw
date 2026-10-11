#!/usr/bin/env bats
# The store of recorded runs (vbw/runs.json in the git directory) is written
# only by vbw: a forged store would let a failing check be skipped. The file and
# Bash guards refuse an agent's write as they refuse the consent file, with a
# next step. L1.

load helper
load protected-helper
load glance-helper

setup() {
  vbw_setup
  glance_project
}

teardown() { vbw_teardown; }

@test "the file guard refuses Write and Edit of vbw/runs.json with a next step" {
  local tool
  for tool in Write Edit; do
    ANSWER=$(hook_answer "$PROJECT" "$(file_in "$tool" .git/vbw/runs.json workflow-subagent)")
    denied_with "the store of recorded runs (vbw/runs.json) only by vbw"
    denied_with "Next: "
  done
}

@test "the Bash guard refuses a redirect into vbw/runs.json with a next step" {
  ANSWER=$(hook_answer "$PROJECT" "$(bash_in 'echo {} > .git/vbw/runs.json' workflow-subagent)")
  denied_with "the store of recorded runs (vbw/runs.json) only by vbw"
  denied_with "Next: "
}

@test "the consent file keeps its answer and an ordinary file stays allowed" {
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write .git/vbw/consent.json workflow-subagent)")
  denied_with "the consent file is written only by /vbw:approve"
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write src/runs.json workflow-subagent)")
  allowed
}
