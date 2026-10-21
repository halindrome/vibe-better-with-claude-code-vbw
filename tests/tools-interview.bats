#!/usr/bin/env bats
# R62 (docs/tools.md): once the interview knows what is being built, VBW asks
# one plain yes/no question for permission to look for tools, once per project.
# The question explains each term in a few words; on no nothing is searched or
# installed and the flow goes on; on yes the same research as /vbw:skills runs.
# The interview skill is a specification, so these tests hold its text to those
# rules (L1), and `vbw interview` still comes first.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"

# section: the tools section, from its heading to the next "## " heading or the end.
section() { awk '/^## .*[Tt]ools/ { f = 1; print; next } f && /^## / { exit } f' "$SKILL"; }

@test "R62: the interview skill has a tools section, after what and for whom, the follow-ups and the keep question" {
  [ -n "$(section)" ]
  local tools keep what follow
  tools=$(grep -nE '^## .*[Tt]ools' "$SKILL" | head -1 | cut -d: -f1)
  keep=$(grep -nE '^## Keep' "$SKILL" | head -1 | cut -d: -f1)
  what=$(grep -nE '^## What and for whom' "$SKILL" | head -1 | cut -d: -f1)
  follow=$(grep -nE '^## Follow-ups' "$SKILL" | head -1 | cut -d: -f1)
  [ "$tools" -gt "$what" ] && [ "$tools" -gt "$follow" ] && [ "$tools" -gt "$keep" ]
}

@test "R62: it asks with AskUserQuestion" {
  section | grep -qF 'AskUserQuestion'
}

@test "R62: it reads the remembered state with vbw tools" {
  section | grep -qF 'vbw tools'
}

@test "R62: the answer is recorded as soon as it is given, yes or no" {
  section | grep -qF 'vbw tools answer yes'
  section | grep -qF 'vbw tools answer no'
}

@test "R62: on yes it hands over to the same research and proposal as /vbw:skills" {
  section | grep -qE '/vbw:skills|vbw:skills|vbw:tooling'
}

@test "R62: the interview still reads its answers first and keeps 'keep' as the last of the interview's own questions" {
  grep -qF 'vbw" interview' "$SKILL"
  grep -qE '^## Keep' "$SKILL"
}

@test "the tools offer is always asked: it is the user's consent, never answered for them, whatever their involvement" {
  local s
  s=$(awk '/^## Tools/ { on = 1; next } /^## / { on = 0 } on' "$REPO_ROOT/plugin/skills/interview/SKILL.md" | tr '\n' ' ')
  [[ "$s" == *"even under \"decide and tell me\""* ]] || { echo "$s"; false; }
  [[ "$s" == *"never answer it for them"* ]] || { echo "$s"; false; }
}
