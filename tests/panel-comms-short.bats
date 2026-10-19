#!/usr/bin/env bats
# R200, phase P159: Comms keeps its helper line in little room, held in the
# places beyond the stand-in test (tests/panel/r200/comms-short.test.mjs, L1).
# tests/panel/r189/containment.test.mjs draws Comms with a live step note at 1,
# 2, 3, 4 and 8 rows at 80 and 40 columns; the panel scenario of tools/l3-suite.sh
# records, in the real Claude Code window (L3), the 'VBW ▸' helper line drawn
# once at 200x24 while helpers work, with the prompt box whole; docs/panel.md's
# Comms section states the order of lines in little room and the one-row form.
# As in tests/l3-panel-comms.bats these tests do not run Claude Code (L1): they
# hold the files' text and the result the scenario wrote under tools/l3-results/.
# The result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/panel.json"
CONTAINMENT="$REPO_ROOT/tests/panel/r189/containment.test.mjs"
DOC="$REPO_ROOT/docs/panel.md"

body() { sed -n '/^scenario_panel()/,/^}/p' "$SUITE"; }
# flat FILE: the file on one line, lower case, so a sentence wrapped over lines still matches.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
# section FILE HEADING: one '## ' section of a markdown file, flat.
section() { sed -n "/^## $2\$/,/^## /p" "$1" | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

@test "R200: tests/panel/r189/containment.test.mjs draws Comms with a live step note at 1, 2, 3, 4 and 8 rows at 80 and 40 columns" {
  grep -q 'step\.json' "$CONTAINMENT" || { echo "containment.test.mjs writes no step note"; false; }
  grep -qF "'build-1'" "$CONTAINMENT" || { echo "containment.test.mjs's step note is not the lease's run (build-1), so the panel would not show it"; false; }
  flat "$CONTAINMENT" | grep -qE '1, 2, 3, 4,? (and )?8' || { echo "containment.test.mjs does not draw Comms at 1, 2, 3, 4 and 8 rows"; false; }
  grep -qE '(^|[^0-9])80([^0-9]|$)' "$CONTAINMENT"
  grep -qE '(^|[^0-9])40([^0-9]|$)' "$CONTAINMENT"
}

@test "R200: the panel scenario records the short-window helper line ('VBW ▸' once at 200x24 while helpers work, the prompt box whole) as its own fact, in its pass set" {
  body | grep -q 'helper_line_short' || { echo "scenario_panel does not record helper_line_short"; false; }
  body | grep -E '^[[:space:]]*for k in ' | grep -q 'helper_line_short' || { echo "helper_line_short is not in the pass set (the 'for k in' list)"; false; }
  body | grep -E 'passed=\$\(jq' | grep -q 'helper_line_short' || { echo "helper_line_short is not in the passed expression"; false; }
  # The fact is read while helpers work: the crew-time short window ('VBW ▸' exactly once).
  body | grep -q 'crew_sh' || { echo "scenario_panel has no crew-time short-window result"; false; }
  body | grep -qF 'spill_checks "VBW ▸"' || { echo "scenario_panel does not look for 'VBW ▸' exactly once in the short window while helpers work"; false; }
  body | grep -qE 'SHORT_ROWS=24' || { echo "the short window is not 24 rows"; false; }
}

@test "R200: a committed result of the panel scenario passed with helper_line_short and no_spill_short true, at L3" {
  [ -f "$RESULT" ] || { echo "the panel scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "panel" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-19")
    and .facts.helper_line_short == true and .facts.no_spill_short == true
    and .facts.helper_seen_working == true
    and (.facts.short_rows | type == "number" and . > 0 and . <= 24)
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R200: docs/panel.md's Comms section states the order of lines in little room and the one-row form" {
  local s
  s=$(section "$DOC" "Comms")
  [ -n "$s" ] || { echo "docs/panel.md has no Comms section"; false; }
  printf '%s' "$s" | grep -qE 'needs-you line.*helper line.*step line' || { echo "the Comms section does not give the order: the needs-you line, the helper line, the step line"; false; }
  printf '%s' "$s" | grep -q 'one row' || { echo "the Comms section does not describe the one-row form"; false; }
  printf '%s' "$s" | grep -qE 'vbw ▸ [a-z]+ · 1 working · [0-9]+m[0-9]+s · .*until around' || { echo "the Comms section gives no one-row example with the step's time after the helper line's own parts"; false; }
  printf '%s' "$s" | grep -q 'two rows' || { echo "the Comms section does not describe the two-row form"; false; }
  printf '%s' "$s" | grep -qE 'no helper works|proof' || { echo "the Comms section does not say when the step line shows alone"; false; }
}
