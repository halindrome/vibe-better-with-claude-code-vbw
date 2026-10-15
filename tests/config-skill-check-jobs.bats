#!/usr/bin/env bats
# R187 (T133, brainstorm B2): /vbw:config knows check_jobs, and says the computer-wide limit
# (R181, docs/proof.md "The computer-wide limit") caps it, so a user asking for more parallel
# checks is told where the ceiling is. L1.

load helper

@test "R187: the config skill names check_jobs, its range and its default" {
  local s="$PLUGIN_ROOT/skills/config/SKILL.md"
  grep -q '`check_jobs`' "$s"
  grep '`check_jobs`' "$s" | grep -q '1 to 64'
}

@test "R187: the config skill names the computer-wide limit on the check_jobs line" {
  local line
  line=$(grep '`check_jobs`' "$PLUGIN_ROOT/skills/config/SKILL.md")
  [[ "$line" == *"computer-wide limit"* ]] || { echo "$line"; false; }
}
