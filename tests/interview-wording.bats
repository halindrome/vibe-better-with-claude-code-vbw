#!/usr/bin/env bats
# R112 (L1): the interview skill runs before spec and convert work; the router
# hands both steps to vbw:interview. The facts: the skill exists and reads the
# kernel's answers, and the router names it at the spec and convert steps.

load helper

@test "R112: the interview skill exists and reads its answers with vbw interview" {
  grep -qx 'name: interview' "$PLUGIN_ROOT/skills/interview/SKILL.md"
  grep -qF 'vbw" interview' "$PLUGIN_ROOT/skills/interview/SKILL.md"
}

@test "R112: the router names vbw:interview on the profile.ask line and at the convert step" {
  grep -F '`profile.ask`' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -qF '`vbw:interview`'
  grep -E '^\*\*convert\*\*' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -qF '`vbw:interview`'
}
