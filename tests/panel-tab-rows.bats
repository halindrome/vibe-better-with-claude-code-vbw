#!/usr/bin/env bats
# R199, phase P159: Mission Control's whole-row tab layout is held in the places
# beyond the stand-in test (tests/panel/r199/tab-rows.test.mjs, L1).
# tests/panel/wiring.test.mjs and tests/panel/r189/containment.test.mjs assert
# whole tab rows in place of their one-line assertions; the panel scenario of
# tools/l3-suite.sh records, in the real Claude Code window (L3), that each of
# the six tab names appears whole as '[ Name ]' at the short and the narrow
# size; docs/panel.md states the whole-row rule. As in tests/l3-panel-comms.bats
# these tests do not run Claude Code (L1): they hold the files' text and the
# result the scenario wrote under tools/l3-results/. The result is written by
# the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/panel.json"
WIRING="$REPO_ROOT/tests/panel/wiring.test.mjs"
CONTAINMENT="$REPO_ROOT/tests/panel/r189/containment.test.mjs"
DOC="$REPO_ROOT/docs/panel.md"

body() { sed -n '/^scenario_panel()/,/^}/p' "$SUITE"; }
# flat FILE: the file on one line, lower case, so a sentence wrapped over lines still matches.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
# section FILE HEADING: one '## ' section of a markdown file, flat.
section() { sed -n "/^## $2\$/,/^## /p" "$1" | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
# names FILE N...: FILE names each number N as a whole number.
names() {
  local f="$1" n
  shift
  for n in "$@"; do
    grep -qE "(^|[^0-9])$n([^0-9]|\$)" "$f" || { echo "$(basename "$f") does not name $n columns"; return 1; }
  done
}

@test "R199: tests/panel/wiring.test.mjs asserts whole tab rows at 40, 50 and 60 columns in place of 'the tab row is one line at 40 columns'" {
  ! grep -q 'the tab row is one line' "$WIRING" || { echo "wiring.test.mjs still asserts a one-line tab row"; false; }
  flat "$WIRING" | grep -q 'whole' || { echo "wiring.test.mjs does not assert whole tab rows"; false; }
  grep -q 'screen' "$WIRING" || { echo "wiring.test.mjs does not read the drawn lines (screen.mjs)"; false; }
  names "$WIRING" 40 50 60
}

@test "R199: tests/panel/r189/containment.test.mjs asserts whole tab rows at 100, 64, 60, 50 and 40 body columns on every tab in place of 'never wraps onto a second line at 40 columns'" {
  ! grep -q 'never wraps onto a second line' "$CONTAINMENT" || { echo "containment.test.mjs still asserts a one-line tab row"; false; }
  flat "$CONTAINMENT" | grep -q 'whole' || { echo "containment.test.mjs does not assert whole tab rows"; false; }
  grep -qF "'sessions'" "$CONTAINMENT" || { echo "containment.test.mjs does not visit the Sessions tab: not every tab"; false; }
  names "$CONTAINMENT" 100 64 60 50 40
}

@test "R199: the panel scenario records that each of the six tab names appears whole as '[ Name ]' at the short and the narrow size, in its pass set" {
  local fact name
  for fact in tabs_whole_short tabs_whole_narrow; do
    body | grep -q "$fact" || { echo "scenario_panel does not record $fact"; false; }
    body | grep -E '^[[:space:]]*for k in ' | grep -q "$fact" || { echo "$fact is not in the pass set (the 'for k in' list)"; false; }
    body | grep -E 'passed=\$\(jq' | grep -q "$fact" || { echo "$fact is not in the passed expression"; false; }
  done
  for name in Now Plan Proof Timeline Sessions Settings Time Sess Set; do
    body | grep -qF "[ $name ]" || { echo "scenario_panel does not read the tab '[ $name ]'"; false; }
  done
}

@test "R199: a committed result of the panel scenario passed with both tab facts true, at L3" {
  [ -f "$RESULT" ] || { echo "the panel scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "panel" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-19")
    and .facts.tabs_whole_short == true and .facts.tabs_whole_narrow == true
    and .facts.no_spill_short == true and .facts.no_spill_narrow == true
    and (.facts.short_rows | type == "number" and . > 0 and . <= 30)
    and (.facts.narrow_columns | type == "number" and . > 0 and . <= 100)
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R199: docs/panel.md no longer says the tab row is always one line and states the whole-row rule with the widths 71, 65, 52, 44 and 38" {
  ! flat "$DOC" | grep -q 'the tab row is always one line' || { echo "docs/panel.md still says the tab row is always one line"; false; }
  local s
  s=$(section "$DOC" "Mission Control")
  [ -n "$s" ] || { echo "docs/panel.md has no Mission Control section"; false; }
  printf '%s' "$s" | grep -qE 'never split|whole' || { echo "the Mission Control section does not say a tab name is never split"; false; }
  printf '%s' "$s" | grep -q 'fewest rows' || { echo "the Mission Control section does not say the fewest rows win"; false; }
  printf '%s' "$s" | grep -q 'full names' || { echo "the Mission Control section does not say the full names win a tie"; false; }
  printf '%s' "$s" | grep -q 'short names' || { echo "the Mission Control section does not name the short names"; false; }
  printf '%s' "$s" | grep -q 'portrait' || { echo "the Mission Control section does not say when the portrait is left out"; false; }
  local n
  for n in 71 65 52 44 38; do
    printf '%s' "$s" | grep -qE "(^|[^0-9])$n([^0-9]|\$)" || { echo "the Mission Control section does not name $n columns"; false; }
  done
}
