#!/usr/bin/env bats
# R208: two real-user scenarios in tools/l3-suite.sh (L3, the real Claude Code
# TUI). hiddenrecord: a project whose .gitignore holds *.json reaches an approved
# contract with .vbw/record.json committed, the un-hide lines in .vbw/.gitignore.
# greenfield, run again on this code, records that the project's .vbw/.gitignore
# holds the un-hide lines and that the record is tracked. Judged in git and the
# project's files, never on screen text. As in tests/l3-taskbreak.bats these
# tests do not run Claude Code (L1): they hold the scenarios' structure and their
# committed results to facts from git and the project.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }
facts() { jq -e "$2" "$RESULTS/$1.json" > /dev/null; }

# committed NAME: the committed result of NAME is from this code (dated 2026-10-26 or later) and labelled honestly.
committed() {
  local f="$RESULTS/$1.json"
  [ -f "$f" ] || { echo "the $1 scenario has not been run: no result is committed"; return 1; }
  jq -e --arg n "$1" '.scenario == $n and .passed == true and .evidence_level == "L3"
    and (.at | type == "string" and . >= "2026-10-26")
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f" > /dev/null || { cat "$f"; return 1; }
}

@test "R208: the hiddenrecord scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_hiddenrecord()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw hiddenrecord
  sed -n '1,20p' "$SUITE" | grep -qw hiddenrecord
}

@test "R208: it seeds a project whose .gitignore holds *.json and reads git and .vbw/.gitignore, never the screen" {
  [ -n "$(body hiddenrecord)" ]
  body hiddenrecord | grep -q 'result_write hiddenrecord '
  body hiddenrecord | grep -qi 'fixture='
  body hiddenrecord | grep -qF '*.json'
  body hiddenrecord | grep -qF '.gitignore'
  body hiddenrecord | grep -qE 'git .*(ls-files|log|show)'
  if body hiddenrecord | grep -qE 'screen \|.*grep.*(record|ignore)'; then false; fi
  local k
  for k in gitignore_rule record_committed unhide_lines record_commits; do
    body hiddenrecord | grep -qF "$k"
  done
}

@test "R208: the committed hiddenrecord result shows the record committed under a *.json rule, with the un-hide lines" {
  committed hiddenrecord
  facts hiddenrecord '.facts.gitignore_rule == "*.json"'
  facts hiddenrecord '.facts.record_committed == true'
  facts hiddenrecord '.facts.unhide_lines == true'
  facts hiddenrecord '.facts.record_commits | type == "number" and . >= 1'
}

@test "R208: the greenfield scenario records the un-hide lines and the tracked record, and its committed result from this code shows them" {
  body greenfield | grep -qF 'plan_files_unhidden'
  committed greenfield
  facts greenfield '.facts.plan_files_unhidden == true'
}
