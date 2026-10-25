#!/usr/bin/env bats
# R195: the real-user scenario `failoutput` in tools/l3-suite.sh (L3, the real
# Claude Code TUI): a later commit breaks a proven requirement, the proof keeps
# the failing check's whole output in .vbw/runtime/output/ and opens a fix, and
# the agents read the file and the failing test's name through `vbw show fix`.
# Judged in the kept file, the transcripts' tool results and the record (the fix
# closed, the file removed once the check passes), never on screen. As in
# tests/l3-smallchange.bats these tests do not run Claude Code (L1): they hold
# the scenario's structure, and its committed result once the release run wrote
# one, to facts from files and the record.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R195: the failoutput scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_failoutput()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw failoutput
  sed -n '1,20p' "$SUITE" | grep -qw failoutput
}

@test "R195: it breaks a proven requirement, reads the kept output file and the agents' show fix results in the transcripts" {
  [ -n "$(body failoutput)" ]
  body failoutput | grep -q 'result_write failoutput '
  body failoutput | grep -qi 'fixture='
  body failoutput | grep -qF '.vbw/runtime/output/'
  body failoutput | grep -qF 'show fix'
  body failoutput | grep -qF 'transcript_tool_output'
  body failoutput | grep -qF 'failing tests:'
  body failoutput | grep -qE 'fixes'
  if body failoutput | grep -qE 'screen \|.*grep.*(failing|output)'; then false; fi
}

@test "R195: the result states each fact the scenario judged" {
  local k
  for k in kept_file kept_names_failing_test show_fix_named_file show_fix_named_test file_removed_after_pass; do
    body failoutput | grep -qF "$k"
  done
}

@test "R195: a committed result of the failoutput scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/failoutput.json"
  [ -f "$f" ] || skip "no failoutput result committed yet: the release run writes it"
  jq -e '.scenario == "failoutput" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f"
}
