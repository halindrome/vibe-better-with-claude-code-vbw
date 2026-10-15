#!/usr/bin/env bats
# R62 (docs/tools.md): /vbw:skills researches and proposes tools at any time,
# whatever the first answer was and from any state of a VBW project: it starts
# the tooling workflow with the project's stack, shows a short explained list,
# installs nothing until the user approves it, asks per approved tool whether it
# goes into this project or all the user's projects, and says plainly when
# nothing was found. These tests check the facts the skill names (its workflow,
# tools, commands and files) (L1); the behavior itself is run in
# tests/l3-tools.bats's scenario.

load helper

SKILL="$PLUGIN_ROOT/skills/skills/SKILL.md"

front() { awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { exit } f' "$SKILL"; }
text() { cat "$SKILL"; }

@test "R62: the skill starts the tooling workflow and may use it" {
  front | grep -E '^allowed-tools:' | grep -qF 'Workflow(vbw:tooling)'
  text | grep -qF 'vbw:tooling'
}

@test "R62: it works out the stack first (the map, else the manifest files) and passes it to the workflow" {
  text | grep -qF '.vbw/map.md'
  text | grep -qE 'package\.json|pyproject|Cargo\.toml'
  text | grep -qE '"stack"|stack:'
}

@test "R62: it records that the user wants tools: vbw tools answer yes" {
  text | grep -qF 'vbw tools'
  text | grep -qE 'vbw tools answer yes'
}

@test "R62: it names the angles: safety, quality and tests" {
  text | grep -qiE 'safety'
  text | grep -qiE 'quality|lint'
  text | grep -qiE 'test'
}

@test "R62: the user approves with AskUserQuestion, and an approved tool installs with npx skills add, -g for all projects" {
  text | grep -qF 'AskUserQuestion'
  text | grep -qE 'npx skills add'
  text | grep -qE '(^|[^a-z])-g([^a-z]|$)'
}

@test "R62: it keeps the user's words and no longer needs Node.js to search a registry by hand" {
  text | grep -qF 'vbw" interview'
  ! text | grep -qiE 'the skills CLI needs Node\.js and stop'
}
