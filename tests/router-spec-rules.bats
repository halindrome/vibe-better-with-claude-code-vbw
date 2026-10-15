#!/usr/bin/env bats
# R60 (P45.2 regression): shortening the router for the stop line must not drop
# the spec step's rules: recommend instead of interrogating, and check that the
# project commands fit the right sub-project and interpreter (L1: the rules'
# key words, not their sentences).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

spec_step() { sed -n '/^\*\*spec\*\*/,/^\*\*plan\*\*/p' "$ROUTER"; }

@test "R60: the spec step keeps its rules: recommend, and the commands' sub-project and interpreter" {
  spec_step | grep -qi 'recommend'
  spec_step | grep -qi 'sub-project'
  spec_step | grep -qi 'interpreter'
}
