#!/usr/bin/env bats
# R192, phase P153 (L1; D444): VBW suggests /rename once per project, when a
# second chat is open on it and this chat still has the name Claude Code gave it
# (nameSource auto or derived); it never renames a chat itself. The hint is
# `rename_hint` in vbw next --json: one sentence naming `/rename vbw · <project
# name>`, null otherwise. Once given, the mark in this clone's settings
# ($(git common dir)/vbw/settings.json, `rename_hint`) keeps it from coming
# again. /vbw:vibe says the sentence as given and runs no /rename.

load helper
load sessions-helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

hint() { VBW_SESSION_ID="${1:-$SESSION_A}" "$VBW" next --json < /dev/null | jq -r '.rename_hint // "null"'; }

@test "R192: a second chat on the project, this one still auto-named: vbw next carries the one-sentence hint, once per clone" {
  registry_entry 101 "$SESSION_A" "Visual candy color coding" 1792300000000 "$PROJECT" auto
  registry_entry 102 "$SESSION_B" "Market data recorder" 1792300050000 "$PROJECT/src" derived
  local h
  h=$(hint)
  [[ "$h" == *"/rename vbw · project with space"* ]] || { echo "$h"; false; }
  [[ "$h" == *"chat"* ]] || { echo "$h"; false; }
  [ "$(printf '%s' "$h" | tr -cd '.' | wc -c | tr -d ' ')" -le 1 ] || { echo "$h"; false; }
  jq -e '.rename_hint | type == "string"' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/settings.json"
  [ "$(hint)" = null ]
  [ "$(hint "$SESSION_B")" = null ]
}

@test "R192: no hint with one chat, with a chat of another project, with no list, or when this chat is unknown" {
  registry_entry 101 "$SESSION_A" "Visual candy color coding"
  [ "$(hint)" = null ]
  registry_entry 102 "$SESSION_B" "Elsewhere" 1792300050000 "$TEST_ROOT/other project"
  [ "$(hint)" = null ]
  registry_entry 103 "$SESSION_B" "Sibling folder" 1792300060000 "${PROJECT}2"
  [ "$(hint)" = null ]
  rm -r "$(registry_dir)"
  [ "$(hint)" = null ]
  registry_entry 101 "$SESSION_A" "Visual candy color coding"
  registry_entry 102 "$SESSION_B" "Market data recorder" 1792300050000
  [ "$("$VBW" next --json < /dev/null | jq -r '.rename_hint // "null"')" = null ]
  # A session id the list does not know gets no hint either, with two chats open.
  [ "$(hint unknown-session-0000)" = null ]
  [ ! -e "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/settings.json" ] \
    || jq -e 'has("rename_hint") | not' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/settings.json"
}

@test "R192: a chat the user already named gets no hint, and a malformed entry never fails vbw next" {
  registry_entry 101 "$SESSION_A" "vbw · payments" 1792300000000 "$PROJECT" user
  registry_entry 102 "$SESSION_B" "Market data recorder" 1792300050000
  printf 'not json\n' > "$(registry_dir)/99.json"
  VBW_SESSION_ID="$SESSION_A" run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rename_hint == null'
}

@test "R192: /vbw:vibe says rename_hint as given, once, and never runs /rename itself" {
  local s="$PLUGIN_ROOT/skills/vibe/SKILL.md"
  grep -q 'rename_hint' "$s"
  grep 'rename_hint' "$s" | grep -qiE 'never|not' || { echo "the skill does not say to leave /rename to the user"; false; }
  grep 'rename_hint' "$s" | grep -qiE 'once|as given' || { echo "the skill does not say to say it once, as given"; false; }
  # No shell block of the skill runs a rename: the user renames, never VBW.
  ! awk '/^```/ { on = !on; next } on' "$s" | grep -q 'rename'
}
