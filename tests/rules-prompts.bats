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

# R211 and R212 (T187, T191): the Lead's brief states the two rules vbw apply enforces.

@test "R211: the Lead's brief says a check's rules belong to one plan: plans of a requirement that build one after the other give each plan's rules a check of their own" {
  grep -q 'one after the other' "$PLUGIN_ROOT/agents/lead.md" || { echo "no sentence about plans that build one after the other"; false; }
  grep 'one after the other' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'check of their own' || { echo "the sentence does not give each plan's rules a check of their own"; false; }
  grep 'check of their own' "$PLUGIN_ROOT/agents/lead.md" | grep -qi 'case filter' || { echo "the sentence does not offer the same file with a case filter as a distinct check"; false; }
}

@test "R212: the Lead's brief rule 7 (Rules) says the plan is named on every rule of the requirement or on none" {
  grep -E '^7\. \*\*Rules' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'every rule' || { echo "rule 7 does not say every rule"; false; }
  grep -E '^7\. \*\*Rules' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'or on none' || { echo "rule 7 does not say or on none"; false; }
}
