#!/usr/bin/env bats
# R61 (L1, facts): the router asks for approval with AskUserQuestion, built from
# what vbw show contract prints, Approve before Not yet; /vbw:approve still
# works; the docs name the choice, its options, the Enter key and the command.

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

approve_step() { sed -n '/^\*\*approve\*\*/,/^\*\*build\*\*/p' "$ROUTER"; }

@test "R61: the router's approve step asks with AskUserQuestion, Approve first and Not yet second, from the question vbw show contract prints" {
  local s
  s=$(approve_step)
  [ -n "$s" ]
  [[ "$s" == *AskUserQuestion* ]]
  [[ "$s" == *"approval question"* ]]
  [[ "$s" == *Approve*"Not yet"* ]]
  [[ "$s" == *"/vbw:approve"* ]]
}

@test "R61: the help lists /vbw:approve" {
  grep -qF '/vbw:approve' "$PLUGIN_ROOT/skills/help/SKILL.md"
}

@test "R61: docs/proof.md names the options Approve and Not yet, the Enter key, /vbw:approve and the fingerprint" {
  local d="$REPO_ROOT/docs/proof.md"
  grep -q 'Approve' "$d"
  grep -q 'Not yet' "$d"
  grep -qi 'Enter' "$d"
  grep -q '/vbw:approve' "$d"
  grep -qi 'fingerprint' "$d"
}

@test "R61: docs/guards.md names the answer hook: AskUserQuestion and PostToolUse" {
  local d="$REPO_ROOT/docs/guards.md"
  grep -q 'AskUserQuestion' "$d"
  grep -qi 'PostToolUse' "$d"
}

@test "R61: the README says approval is a choice where Enter approves, and /vbw:approve still works" {
  grep -qi 'Enter' "$REPO_ROOT/README.md"
  grep -q '/vbw:approve' "$REPO_ROOT/README.md"
}
