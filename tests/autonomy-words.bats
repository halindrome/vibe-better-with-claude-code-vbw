#!/usr/bin/env bats
# R201, phase P160 (L1): when the user states an autonomy setting in their own
# words to /vbw:vibe ('use guided autonomy', 'ask me before each step', 'do not
# ask, just go'), the router records it with vbw config set autonomy before any
# step, so the session runs under that setting. The 2.0.40 qafix L3 run
# (2026-10-19) asked for guided and ran balanced: the router had no rule for
# words. These tests hold the words of the router (plugin/skills/vibe/SKILL.md),
# the triage skill and the user docs, as tests/triage-skill.bats does; the
# real-session proof is tests/l3-qafix-autonomy.bats.

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
TRIAGE="$PLUGIN_ROOT/skills/triage/SKILL.md"
README="$REPO_ROOT/README.md"
INTERVIEW="$REPO_ROOT/docs/interview.md"

# flat FILE: the file on one line, lower case, so a sentence wrapped over lines still matches.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
# section FILE HEADING: one '## ' section of a markdown file, flat.
section() { sed -n "/^## $2\$/,/^## /p" "$1" | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
# The router's rule for a setting stated in words: between the user's words and the Autonomy section.
words_raw() { sed -n '/^User said:/,/^## Autonomy$/p' "$ROUTER"; }
words() { words_raw | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
says() { words | grep -qE -- "$1" || { echo "the router's rule for a setting stated in words lacks: $1"; return 1; }; }
# line_of FILE TEXT: the line number of the first line holding TEXT ('' when none).
line_of() { grep -n -m1 -F -- "$2" "$1" | cut -d: -f1; }

@test "R201: before any step, words naming guided, balanced or hands-off, or a plain phrase clearly meaning one, run vbw config set autonomy first" {
  says 'vbw config set autonomy'
  says 'guided'
  says 'balanced'
  says 'hands-off'
  says 'ask me before each step'
  says 'do not ask, just go'
  says 'first|before any step'
  local rule
  rule=$(line_of "$ROUTER" 'vbw config set autonomy')
  [ -n "$rule" ] || { echo "the router never runs vbw config set autonomy"; false; }
  [ "$rule" -lt "$(line_of "$ROUTER" '## Autonomy')" ] || { echo "the rule comes after the Autonomy section"; false; }
  [ "$rule" -lt "$(line_of "$ROUTER" '## Loop')" ] || { echo "the rule comes after the loop"; false; }
  [ "$rule" -lt "$(line_of "$ROUTER" '## Steps')" ] || { echo "the rule comes after the steps"; false; }
}

@test "R201: after the write the router says in one line what was set and follows the Autonomy section with that value, not the line loaded before" {
  says 'one line'
  says 'that value|just set'
  section "$ROUTER" Autonomy | grep -q 'just set' || { echo "the Autonomy section still reads only the line loaded at the start"; false; }
}

@test "R201: a stated setting equal to the current one writes nothing and says nothing about it" {
  says 'writes nothing'
  says 'says nothing'
}

@test "R201: words that do not clearly name one setting change nothing: no guessing" {
  says 'guess'
  says 'change(s)? nothing'
}

@test "R201: a setting stated later in the session is recorded at once and applies from the next step" {
  says 'later'
  says 'at once'
  says 'next step'
}

@test "R201: a switch to guided while the autonomous run is armed runs vbw auto off for this session" {
  words_raw | grep -qF 'vbw auto off ${CLAUDE_SESSION_ID}' || { echo "the rule does not run vbw auto off with the session id"; false; }
  says 'armed|arm'
}

@test "R201: a switch to balanced or hands-off arms vbw auto on once" {
  words_raw | grep -qF 'vbw auto on ${CLAUDE_SESSION_ID}' || { echo "the rule does not run vbw auto on with the session id"; false; }
  says 'once'
}

@test "R201: --auto runs alone this time only and never changes the setting" {
  says -- '--auto'
  says 'never change'
}

@test "R201: the triage skill lists a setting stated in words among what is not a new idea, and the rest of the same message still goes to triage" {
  local s
  s=$(section "$TRIAGE" "When it applies")
  [ -n "$s" ] || { echo "triage/SKILL.md has no 'When it applies' section"; false; }
  printf '%s' "$s" | grep -q 'not a new idea' || { echo "the section no longer lists what is not a new idea"; false; }
  printf '%s' "$s" | grep -q 'autonomy' || { echo "the section does not list an autonomy setting stated in words"; false; }
  printf '%s' "$s" | grep -q 'guided' || { echo "the section does not name guided"; false; }
  printf '%s' "$s" | grep -q 'hands-off' || { echo "the section does not name hands-off"; false; }
  printf '%s' "$s" | grep -qE 'rest of (the|that|the same) message' || { echo "the section does not say the rest of the message still goes to triage"; false; }
}

@test "R201: README.md's autonomy row and docs/interview.md say the setting can be stated to /vbw:vibe in words" {
  local row s
  row=$(grep -E '^\| `autonomy` \|' "$README")
  [ -n "$row" ] || { echo "README.md has no autonomy row"; false; }
  printf '%s' "$row" | grep -q 'in words' || { echo "the README's autonomy row does not say the setting can be stated in words"; false; }
  printf '%s' "$row" | grep -qF '/vbw:vibe' || { echo "the README's autonomy row does not name /vbw:vibe"; false; }
  s=$(section "$INTERVIEW" "What never changes")
  [ -n "$s" ] || { echo "docs/interview.md has no 'What never changes' section"; false; }
  printf '%s' "$s" | grep -qE 'autonomy[^|]*in words' || { echo "docs/interview.md's autonomy bullet does not say the setting can be stated in words"; false; }
  printf '%s' "$s" | grep -qF '/vbw:vibe' || { echo "docs/interview.md's autonomy bullet does not name /vbw:vibe"; false; }
}
