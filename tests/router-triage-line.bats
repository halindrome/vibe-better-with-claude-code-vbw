#!/usr/bin/env bats
# R135 (L1): the router sends every new request, the user's words after
# /vbw:vibe ($ARGUMENTS), to vbw:triage, and stays within its 1,400-word budget
# (about 2k tokens; decision D161).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

@test "R135: the router's paragraph with \$ARGUMENTS names vbw:triage" {
  # shellcheck disable=SC2016 # the router's literal text
  awk 'BEGIN { RS = "" } index($0, "$ARGUMENTS") && index($0, "`vbw:triage`") { found = 1 } END { exit !found }' "$ROUTER"
}

@test "R135: the router stays within its 1,400-word budget" {
  [ "$(wc -w < "$ROUTER" | tr -d ' ')" -le 1400 ]
}
