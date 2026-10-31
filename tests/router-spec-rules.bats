#!/usr/bin/env bats
# R60 (P45.2 regression): shortening the router for the stop line must not drop
# the spec step's rules: recommend instead of interrogating, and check that the
# project commands fit the right sub-project and interpreter (L1: the rules'
# key words, not their sentences).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

spec_step() { sed -n '/^\*\*spec\*\*/,/^\*\*plan\*\*/p' "$ROUTER"; }

@test "R60: the spec step keeps its rules: recommend, and the commands' sub-project and interpreter" {
  spec_step | grep -qi 'recommend'
  spec_step | grep -qi 'sub-project'
  spec_step | grep -qi 'interpreter'
}

qa_step() { sed -n '/^\*\*qa\*\*/,/^\*\*run\*\*/p' "$ROUTER"; }

deviations_step() { sed -n '/^\*\*deviations\*\*/,/^\*\*accept\*\*/p' "$ROUTER"; }

@test "deviations: the router never repairs a deviating delivered file: the deviations step asks the user to keep it (a decision naming it) or restore it (a fix round)" {
  qa_step | grep -qi 'never repaired by you'
  qa_step | grep -q '\*\*deviations\*\* step'
  deviations_step | grep -q '(needs user)'
  deviations_step | grep -q 'AskUserQuestion'
  deviations_step | grep -q 'vbw decide'
  deviations_step | grep -q 'vbw fix restore'
  deviations_step | grep -qi 'never repair a file yourself'
}

# R228 (#733, D534): the spec step chooses ## Commands from the map's Tests section. A
# command the map ran and dated is preferred; a whole suite marked Not run is never
# written silently: one AskUserQuestion per such suite names it unverified with its
# expected time (or says the time is unknown) and offers run it now (Recommended),
# leave it out, add it unverified; hands-off takes run it now. Run it now is its own
# step before planning: the suite runs once (a long one in the background, its whole
# result read), the user hears green or red with the failing tests' names, and the dated
# outcome is recorded with vbw decide, never by editing .vbw/map.md. A suite red today is
# named before planning with the narrower command recommended; a red suite goes in only
# on the user's choice, and the first proof is then said to be red. L1: the step's words.

# spec_flat: the spec step on one line, so a rule wrapped over lines still matches.
spec_flat() { spec_step | tr '\n' ' ' | tr -s ' '; }

@test "R228: the spec step chooses ## Commands from the map's Tests section and prefers a command the map ran and dated" {
  spec_flat | grep -qi 'tests section'
  spec_flat | grep -qi 'dated'
  spec_step | grep -qF '`vbw spec sync`'
}

@test "R228: a suite marked Not run is put to the user before planning: unverified, with its expected time or that the time is unknown, and the three D534 options with run it now recommended" {
  spec_step | grep -qF 'Not run'
  spec_flat | grep -qi 'unverified'
  spec_flat | grep -qi 'expected time'
  spec_flat | grep -qi 'unknown'
  spec_flat | grep -qi 'run it now'
  spec_flat | grep -qi 'leave it out'
  spec_flat | grep -qi 'add it unverified'
  spec_flat | grep -qiE 'run it now[^.]{0,40}\(Recommended\)|\(Recommended\)[^.]{0,40}run it now'
  spec_flat | grep -qi 'hands-off'
  spec_flat | grep -qi 'before planning'
}

@test "R228: run it now is its own step: the suite runs once (a long one in the background, its whole result read), green or red with the failing tests named, recorded with vbw decide and never by editing the map" {
  spec_flat | grep -qi 'background'
  spec_flat | grep -qiE 'whole (result|output)'
  spec_flat | grep -qi 'failing tests'
  spec_flat | grep -qF 'vbw decide'
  spec_flat | grep -qiE 'never [^.]{0,40}\.vbw/map\.md|\.vbw/map\.md[^.]{0,40}never'
  spec_flat | grep -qF 'Commands: <command> ran <date> at <short commit>: green|red (<n> failing)'
}

@test "R228: a suite that fails today is named before planning with the narrower command recommended; a red suite enters ## Commands only on the user's choice, and the first proof is then said to be red" {
  spec_flat | grep -qiE 'narrower|one test file'
  spec_flat | grep -qiE 'first proof[^.]{0,30}red'
  spec_flat | grep -qF '## Commands'
}
