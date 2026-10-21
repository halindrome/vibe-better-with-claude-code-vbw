#!/usr/bin/env bats
# R31: the Lead and the express router write rules with the "rules" key of vbw apply.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "the Lead writes rules through the \"rules\" key of vbw apply" {
  grep -q '"rules"' "$PLUGIN_ROOT/agents/lead.md"
}

@test "the router's express apply example carries rules" {
  grep -q '"rules":\[{"req"' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}
