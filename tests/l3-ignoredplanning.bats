#!/usr/bin/env bats
# #695: a real-user scenario in tools/l3-suite.sh (L3, the real Claude Code TUI).
# ignoredplanning: a project whose .gitignore ignores .vbw-planning, with one file
# there tracked and one untracked, ships its milestone; the proof recorded a tree,
# the kernel's fingerprints equal the evidence after the session, and a proof after
# an unrelated commit reuses results. Judged in the record and git, never on screen
# text. As in tests/l3-hiddenrecord.bats these tests do not run Claude Code (L1):
# they hold the scenario's structure and its committed result to its facts.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }
facts() { jq -e "$2" "$RESULTS/$1.json" > /dev/null; }

@test "#695: the ignoredplanning scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_ignoredplanning()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw ignoredplanning
  sed -n '1,20p' "$SUITE" | grep -qw ignoredplanning
}

@test "#695: it seeds an ignored .vbw-planning, tracked and untracked, and reads the record and git, never the screen" {
  [ -n "$(body ignoredplanning)" ]
  body ignoredplanning | grep -q 'result_write ignoredplanning '
  body ignoredplanning | grep -qF "printf '.vbw-planning/\\n' > \"\$dir/.gitignore\""
  body ignoredplanning | grep -qF 'git -C "$dir" add .vbw-planning/STATE.md'
  body ignoredplanning | grep -qF 'kernel_trees'
  if body ignoredplanning | grep -qE 'screen \|'; then false; fi
  local k
  for k in planning_ignored_tracked_and_untracked proof_passed evidence_tree fingerprints_match_evidence second_proof_passed reused_units; do
    body ignoredplanning | grep -qF "$k"
  done
}

@test "#695: the committed ignoredplanning result shows a recorded tree, no change seen and results reused" {
  local f="$RESULTS/ignoredplanning.json"
  [ -f "$f" ] || { echo "the ignoredplanning scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "ignoredplanning" and .passed == true and .evidence_level == "L3"
    and (.at | type == "string" and . >= "2026-10-28")
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.not_tested | type == "array" and length > 0)' "$f" > /dev/null || { cat "$f"; false; }
  facts ignoredplanning '.facts.planning_ignored_tracked_and_untracked == true'
  facts ignoredplanning '.facts.proof_passed == true and (.facts.evidence_tree | test("^[0-9a-f]{40,64}$"))'
  facts ignoredplanning '.facts.fingerprints_match_evidence == true'
  facts ignoredplanning '.facts.second_proof_passed == true and .facts.second_tree != .facts.evidence_tree'
  facts ignoredplanning '.facts.reused_units >= 1'
}
