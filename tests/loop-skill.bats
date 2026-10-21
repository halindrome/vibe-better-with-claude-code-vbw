#!/usr/bin/env bats
# R179 (P128; docs/loop.md): the /vbw:loop skill arms the loop with the user's
# own arguments, then shows in one message what changed (the items in order,
# the ceiling and its mode, that approval is delegated for these items only,
# what never happens: no push, release or publish, no work beyond the items, a
# [human] requirement waits for the user; and how to stop, /vbw:loop stop from
# any session); then the cycle begins through the Stop hook. /vbw:loop stop
# runs vbw loop stop and says what the loop was doing. The loop's steps are the
# ones the /vbw:vibe router describes, run the same way; the guided autonomy
# setting never makes the loop ask; a decision planning asks for is taken with
# the recommended option and recorded as chosen by the loop; the loop accepts
# no suggestion on the user's behalf; it never calls vbw approve and never asks
# the approval menu. L1.

load helper

SKILL="$REPO_ROOT/plugin/skills/loop/SKILL.md"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

has() { grep -qiE -- "$1" "$SKILL" || { echo "the loop skill lacks: $1"; return 1; }; }
lacks() { ! grep -qE -- "$1" "$SKILL" || { echo "the loop skill must not say: $1"; return 1; }; }

@test "R179: the skill exists, is user-invoked only, names its arguments, and runs vbw loop start with them" {
  [ -f "$SKILL" ]
  grep -qx 'disable-model-invocation: true' "$SKILL"
  grep -qE '^argument-hint: .*ITEM.*--ceiling USD.*--finish-item.*--no-ceiling.*stop' "$SKILL"
  grep -qE '^"\$\{CLAUDE_PLUGIN_ROOT\}/bin/vbw" loop start .*\$ARGUMENTS' "$SKILL"
  grep -qE '^"\$\{CLAUDE_PLUGIN_ROOT\}/bin/vbw" loop status' "$SKILL"
  ! grep -q '^hooks:' "$SKILL" || false
  grep -qE '^allowed-tools: .*Workflow\(vbw:planning\).*Workflow\(vbw:building\).*Workflow\(vbw:fixing\).*Workflow\(vbw:verifying\)' "$SKILL"
}

@test "R179: the one message says what changed and what never happens, and how to stop" {
  has 'items? in (the )?order'
  has 'ceiling'
  has 'delegated'
  has 'these items only|only (for )?these items'
  has 'no push'
  has 'release'
  has 'publish'
  has 'beyond the items|only the items|nothing (else|more) than'
  has '\[human\]'
  has '/vbw:loop stop'
  has 'any session'
}

@test "R179: /vbw:loop stop runs vbw loop stop and says what the loop was doing" {
  has 'vbw loop stop'
  has 'what (the loop|it) was doing'
}

@test "R179: the steps are the router's, run the same way, and the loop never asks" {
  has 'vbw:vibe|skills/vibe/SKILL.md'
  has 'same (workflows|arguments)|as (/vbw:vibe|the router) describes'
  has 'guided'
  has 'never ask'
  has 'needs_decisions'
  has 'recommended'
  has 'chosen by the loop'
  has 'vbw decide'
  has 'suggest'
  has 'Stop hook'
}

@test "R179: the skill never arms autonomy steps, never approves and never asks the approval menu" {
  lacks 'vbw auto on'
  lacks 'bin/vbw" approve'
  lacks 'vbw approve --hash'
  lacks 'Approve contract'
  ! grep -qE 'AskUserQuestion' "$SKILL" || grep -qiE 'never.*AskUserQuestion|AskUserQuestion.*never' "$SKILL"
}

@test "R179: the skill follows the shell-block rules of tests/skills.bats" {
  run bats --filter 'shell block|allowed-tools|named after its directory|only the user can approve' "$REPO_ROOT/tests/skills.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
