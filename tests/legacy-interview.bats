#!/usr/bin/env bats
# R65 (docs/convert.md): the interview's old-folder step. Right after the level
# answer, when a project has a VBW 1 folder and no recorded choice, VBW shows the
# kernel's review, recommends converting or starting fresh, and asks. These tests
# check the facts the skills name: the commands, the menu tool and the budgets
# (L1); the real-app run is its own check.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
CONVERT="$PLUGIN_ROOT/skills/convert/SKILL.md"

# section: the old-folder section: from its "## ...VBW 1..." heading to the next "## " heading.
section() { awk '/^## .*VBW 1/ { f = 1; print; next } f && /^## / { exit } f' "$SKILL"; }

@test "R65: the interview skill has an old-folder section, and reads the review with its other facts" {
  [ -n "$(section)" ]
  grep -qF 'vbw" legacy review' "$SKILL"
}

@test "R65: the choice is asked with AskUserQuestion, the recommended option marked (Recommended)" {
  section | grep -qF 'AskUserQuestion'
  section | grep -qF '(Recommended)'
}

@test "R65: each choice is recorded with its command: vbw legacy choose convert runs /vbw:convert, vbw legacy choose fresh" {
  section | grep -qF 'vbw legacy choose convert'
  section | grep -qE 'vbw:convert|/vbw:convert'
  section | grep -qF 'vbw legacy choose fresh'
}

@test "R65: the review can still be run on demand from the convert skill" {
  grep -qF 'vbw legacy review' "$CONVERT"
}

@test "R65: the router's convert step defers to this step instead of a fixed recommendation" {
  local step
  step=$(awk '/^\*\*convert\*\*/ { f = 1; print; next } f && /^\*\*[a-z]/ { exit } f' "$ROUTER")
  [ -n "$step" ]
  [[ "$step" == *"vbw:interview"* || "$step" == *"legacy review"* ]]
  [[ "$step" != *'"Convert it (Recommended)"'* ]]
}

@test "R65: the prompts stay within their budgets: the step 190 words, the interview 900, the router 1,400, every skill 2,000, all prompts 22,800" {
  [ "$(section | wc -w)" -le 190 ]
  [ -n "$(section)" ]
  [ "$(wc -w < "$SKILL")" -le 900 ]
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
  local f total=0 w
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md; do
    w=$(wc -w < "$f"); total=$((total + w))
    [ "$w" -le 2000 ] || [ "$f" = "$ROUTER" ] || { echo "$f has $w words"; false; }
  done
  [ "$total" -le 22800 ]
}
