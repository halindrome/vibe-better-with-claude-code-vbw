#!/usr/bin/env bats
# R122 (decision D207; L1): when the user picks a sort other than VBW's, VBW
# asks exactly one follow-up question that says plainly what the choice
# displaces and its risk, with ready reasons, the user's own words, or keeping
# VBW's sorting. An overrule with a reason is followed and recorded with vbw
# decide (the idea, VBW's sort, the user's sort, the reason); keeping VBW's
# sorting records nothing; the warning is said once per idea. The tests check
# the facts the skill (plugin/skills/triage/SKILL.md) names: the menu tool and
# vbw decide (L1); the decision itself is written by the kernel, run for real
# below.

load helper

SKILL="$PLUGIN_ROOT/skills/triage/SKILL.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "the triage skill lacks: $2"; return 1; }; }

@test "R122: the overrule question is asked with AskUserQuestion and recorded with vbw decide" {
  [ -f "$SKILL" ]
  has "$SKILL" 'askuserquestion'
  grep -qF 'vbw decide' "$SKILL"
}

@test "R122: the decision the skill records is kept by the kernel with the reason as its why" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  run "$VBW" decide "Triage overrule: Dark mode: VBW sorted later, the user chose now" "a customer asked for it this week" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; vbw_teardown; false; }
  jq -e '.decisions[-1] | (.text | test("VBW sorted later")) and (.text | test("chose now")) and .why == "a customer asked for it this week"' .vbw/record.json
  vbw_teardown
}
