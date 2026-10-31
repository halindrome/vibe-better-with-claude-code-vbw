#!/usr/bin/env bats
# R121 (decisions D206, D161; L1): every new idea brought to /vbw:vibe is sorted
# as now, next or later with a size, in an AskUserQuestion menu. The
# instructions live in the triage skill (plugin/skills/triage/SKILL.md),
# outside the router, which only points to it. These tests check the facts the
# skill names (sorts, sizes, commands, the menu tool, the limit of four); the
# kernel's part is tests/triage-kernel.bats.

load helper

SKILL="$PLUGIN_ROOT/skills/triage/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
DOC="$REPO_ROOT/docs/triage.md"
README="$REPO_ROOT/README.md"

# flat FILE: the file on one line, lower case, so a sentence wrapped over lines still matches.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$(basename "$(dirname "$1")")/$(basename "$1") lacks: $2"; return 1; }; }

@test "R121: the triage skill exists, loads the kernel's summary in one call and starts no agent or workflow" {
  [ -f "$SKILL" ]
  grep -qx 'name: triage' "$SKILL"
  grep -qE '^description: .{20,}$' "$SKILL"
  grep -qF '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" triage' "$SKILL"
  ! grep -qE '^allowed-tools:.*(Workflow|Agent|Task)' "$SKILL" || { echo "the triage may not start an agent or a workflow"; false; }
}

@test "R121: the router points to the triage skill" {
  grep -qF 'vbw:triage' "$ROUTER"
}

@test "R121: the skill names the three sorts and the three sizes" {
  local w
  for w in now next later small medium large; do
    grep -qw "$w" "$SKILL" || { echo "triage/SKILL.md does not name $w"; false; }
  done
}

@test "R121: the line is asked in an AskUserQuestion menu, VBW's sort marked (Recommended), at most four ideas at a time" {
  grep -qF 'AskUserQuestion' "$SKILL"
  grep -qF '(Recommended)' "$SKILL"
  has "$SKILL" 'four'
}

@test "R121: 'now' uses vbw spec add and vbw milestone start; 'next' and 'later' use vbw todo add with its sort and size" {
  grep -qF 'vbw spec add' "$SKILL"
  grep -qF 'vbw milestone start' "$SKILL"
  grep -qE 'vbw todo add --sort (next|later|<|\$|\{)' "$SKILL"
  grep -qF -- '--size' "$SKILL"
}

@test "R121: the skill names the three autonomy settings: guided, balanced and hands-off" {
  has "$SKILL" 'guided'
  has "$SKILL" 'balanced'
  has "$SKILL" 'hands-off'
}

@test "R121 (#717): a fix idea is checked against the code first; already fixed is said with its evidence and adds nothing" {
  has "$SKILL" 'still happens'
  has "$SKILL" 'git log --grep'
  has "$SKILL" 'already fixed.{0,40}\(recommended\)'
  grep -qF 'vbw decide "<idea>: already fixed by <evidence>"' "$SKILL"
  has "$SKILL" 'separate idea'
  grep -qE '^allowed-tools:.*Read' "$SKILL"
  # No git command is pre-approved: git grep -O runs a program, git log --output writes a file.
  if grep -E '^allowed-tools:' "$SKILL" | grep -q 'git'; then echo "triage pre-approves a git command"; false; fi
  has "$DOC" 'already fixed'
  # The router sends a fix that looks fixed to triage too, instead of answering it itself (seen in L3).
  has "$ROUTER" 'vbw:triage. first, before you read code.{0,80}already fixed'
}

@test "R121: the user documentation names the three sorts, the sizes and vbw todo list, and the README links it" {
  [ -f "$DOC" ]
  local w
  for w in now next later small medium large; do
    grep -qw "$w" "$DOC" || { echo "docs/triage.md does not name $w"; false; }
  done
  has "$DOC" 'vbw todo list'
  grep -qF 'docs/triage.md' "$README"
}

@test "F90: docs/triage.md shows the real vbw todo list format" {
  grep -qF 'T3 [next, small] Refunds' "$DOC"
  grep -qF 'T2 [later, large] Gift cards' "$DOC"
}

# R229 (#734): after every now idea of one menu is added with vbw spec add, the router
# follows vbw:suggest once, before the first planning run (the normal flow comes after
# it); a now sorted during a run waits for the run to end and the suggestions come
# then, still before planning.
@test "R229: the now outcome follows vbw:suggest once after the ideas are added, before the first planning run" {
  local out
  out=$(sed -n '/^## Outcomes/,/^## /p' "$SKILL" | tr '\n' ' ' | tr -s ' ')
  printf '%s' "$out" | grep -qF 'vbw:suggest' || { echo "the Outcomes section does not follow vbw:suggest"; false; }
  printf '%s' "$out" | grep -qiE 'vbw spec add[^.]*vbw:suggest[^.]*(planning|normal flow)' || { echo "vbw:suggest does not come between vbw spec add and the planning"; false; }
  printf '%s' "$out" | grep -qi 'before the first planning run' || { echo "the Outcomes section does not place the suggestions before the first planning run"; false; }
  printf '%s' "$out" | grep -qiE 'during a run[^.]*(waits|wait)' || { echo "the Outcomes section does not say a now idea during a run waits"; false; }
}
