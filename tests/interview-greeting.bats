#!/usr/bin/env bats
# R59 (docs/interview.md): the interview opens with a fixed greeting that asks the
# level question, followed by the same four options in the same order as before.
# The procedure is the skill's text (L1: no model runs here); the level values and
# the resume point are the kernel's, and run for real.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
DOC="$BATS_TEST_DIRNAME/../docs/interview.md"
GREETING="Hello, Human! Welcome to VBW. Let me interview you real quick to better adapt to you. What is your level of proficiency?"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

@test "R59: the first question of the interview skill is exactly the new greeting" {
  grep -qF -- "1. \"$GREETING\"" "$SKILL"
  local first
  first=$(grep -nF -m1 -- "Hello, Human!" "$SKILL" | cut -d: -f1)
  [ "$first" = "$(grep -nE '^1\. ' "$SKILL" | head -1 | cut -d: -f1)" ]
}

@test "R59: the four level options are the kernel's values, and the skill names each" {
  [ "$(jq -r '.level | join("|")' "$PLUGIN_ROOT/lib/interview.json")" = "never|small scripts or no-code|professionally|senior engineer" ]
  local o
  for o in never "small scripts or no-code" professionally "senior engineer"; do
    grep -qF -- "$o" "$SKILL" || { echo "the skill does not name the option $o"; false; }
  done
}

@test "R59: choosing a level still records it and the interview continues at the next question" {
  grep -qF 'vbw interview set level "<option>"' "$SKILL"
  "$VBW" interview set level "senior engineer" > /dev/null
  run "$VBW" interview --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.level == "senior engineer" and .pending == "depth"'
}

@test "R59: the interview doc shows the greeting" {
  grep -qF -- "$GREETING" "$DOC"
}

@test "R59: the interview prompt holds the greeting" {
  grep -qF -- "$GREETING" "$SKILL"
}

@test "R59: a returning user whose level is recorded is not asked the level question again" {
  grep -i 'skip' "$SKILL" | grep -qF '`profile`' || { echo "the skill does not skip the answers profile holds"; false; }
  "$VBW" interview set level "never" > /dev/null
  run "$VBW" interview --json
  printf '%s' "$output" | jq -e '.pending != "level"'
}
