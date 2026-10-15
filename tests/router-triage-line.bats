#!/usr/bin/env bats
# R135 (L1): the router sends every new request, the user's words after
# /vbw:vibe ($ARGUMENTS), to vbw:triage.

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

@test "R135: the router takes the user's words as \$ARGUMENTS and names vbw:triage" {
  # shellcheck disable=SC2016 # the router's literal text
  grep -qF '$ARGUMENTS' "$ROUTER"
  grep -qF '`vbw:triage`' "$ROUTER"
}
