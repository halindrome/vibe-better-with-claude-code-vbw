#!/usr/bin/env bats
# R60: at every stop VBW ends with one plain line, "What I need from you". The
# router holds the rule (L1: the line's label in the router and its budget; the
# real-user scenarios show it in a session).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

@test "R60: the router names the stop line What I need from you" {
  grep -qF 'What I need from you' "$ROUTER"
}

@test "R60: the router stays within its 1,400-word budget" {
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
}
