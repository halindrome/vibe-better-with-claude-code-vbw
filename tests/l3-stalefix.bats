#!/usr/bin/env bats
# #706: the real-user scenario `stalefix` in tools/l3-suite.sh (L3, the real Claude
# Code TUI): a fix round's repair breaks another finished requirement, its vbw fix
# done is refused and the fix stays open on code changed since the proof; VBW proves
# again before the next fix round. Judged in the transcripts' tool calls and results,
# git and the committed record's history, never on screen. As in
# tests/l3-failoutput.bats these tests do not run Claude Code (L1): they hold the
# scenario's structure, and its committed result once the release run wrote one, to
# facts from files and the record.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "#706: the stalefix scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_stalefix()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw stalefix
  sed -n '1,20p' "$SUITE" | grep -qw stalefix
}

@test "#706: it reads the refused fix done, the rounds and proofs in the transcripts and the record's history" {
  [ -n "$(body stalefix)" ]
  body stalefix | grep -q 'result_write stalefix '
  body stalefix | grep -qi 'fixture='
  body stalefix | grep -qF 'transcript_tool_output'
  body stalefix | grep -qF 'broke finished work'
  body stalefix | grep -qF 'stalefix_steps'
  body stalefix | grep -qF 'record_history'
  if body stalefix | grep -qE 'screen \|'; then false; fi
}

@test "#706: the result states each fact the scenario judged" {
  local k
  for k in fixes_before round_committed_repair fix_done_refused f1_fix_rounds proof_between_rounds evidence_advanced f2 steps; do
    body stalefix | grep -qF "$k"
  done
}

@test "#706: a committed result of the stalefix scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/stalefix.json"
  [ -f "$f" ] || skip "no stalefix result committed yet: the release run writes it"
  jq -e '.scenario == "stalefix" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)
    and .facts.fix_done_refused == true and .facts.f1_fix_rounds == 1 and .facts.proof_between_rounds == true' "$f"
}
