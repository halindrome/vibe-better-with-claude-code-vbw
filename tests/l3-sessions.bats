#!/usr/bin/env bats
# R192: the real-user scenario `sessions` in tools/l3-suite.sh (L3, the real
# Claude Code TUI, two chats on one project): the user names the chat with
# /rename and starts a build; while the run is open a second chat on the same
# project asks VBW. The holder's name is judged where VBW keeps it: Claude
# Code's list of chats, .vbw/runtime/holder.json, the second chat's transcript,
# the status line script run for the second chat, and the record and git, which
# never carry it. Like tests/l3-smallchange.bats, these tests do not run Claude
# Code (L1): they hold the scenario's structure, and its committed result once
# the release run wrote one, to facts from files, never screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R192: the sessions scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_sessions()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw sessions
  sed -n '1,20p' "$SUITE" | grep -qw sessions
}

@test "R192: it names the chat with /rename, asks from a second chat during the run, and reads files, never the screen" {
  [ -n "$(body sessions)" ]
  body sessions | grep -q 'result_write sessions '
  body sessions | grep -qi 'fixture='
  body sessions | grep -qF '/rename'
  body sessions | grep -qF 'holder.json'
  body sessions | grep -qE 'transcripts|transcript_tool_output'
  body sessions | grep -qF 'vbw-statusline.sh'
  body sessions | grep -qF 'sessions_panel_rows'
  sed -n '/^sessions_panel_rows()/,/^}/p' "$SUITE" | grep -qF 'sessionsModel'
  body sessions | grep -qE 'git .*(log|grep)'
  if body sessions | grep -qE 'screen \|.*grep.*(holder|held)'; then false; fi
}

@test "R192: the result states each fact the scenario judged" {
  local k
  for k in chat_name registry_name_matches holder_file_names_chat other_chat_told_name statusline_held_by panel_resume_line name_not_in_record_or_git holder_cleared_at_end; do
    body sessions | grep -qF "$k"
  done
}

@test "R192: a committed result of the sessions scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/sessions.json"
  [ -f "$f" ] || skip "no sessions result committed yet: the release run writes it"
  jq -e '.scenario == "sessions" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f"
}
