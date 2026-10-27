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

@test "R211 R215: the Lead's brief says a check's rules belong to one plan: several open plans of a requirement, whatever their order and the same wave included, each get a check of their own" {
  grep -q "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" || { echo "no sentence saying a check's rules belong to one plan"; false; }
  grep "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" | grep -q 'whatever their order' || { echo "the sentence does not cover plans whatever their order"; false; }
  grep "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" | grep -q 'same wave included' || { echo "the sentence does not name the same wave"; false; }
  grep 'check of their own' "$PLUGIN_ROOT/agents/lead.md" | grep -qi 'case filter' || { echo "the sentence does not offer the same file with a case filter as a distinct check"; false; }
  grep "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" | grep -q 'vbw apply. refuses' || { echo "the sentence does not say vbw apply refuses it"; false; }
}

@test "R212: the Lead's brief rule 7 (Rules) says the plan is named on every rule of the requirement or on none" {
  grep -E '^7\. \*\*Rules' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'every rule' || { echo "rule 7 does not say every rule"; false; }
  grep -E '^7\. \*\*Rules' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'or on none' || { echo "rule 7 does not say or on none"; false; }
}
