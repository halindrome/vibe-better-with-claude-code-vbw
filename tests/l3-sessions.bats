#!/usr/bin/env bats
# R202, phase P161: the sessions scenario of tools/l3-suite.sh, run in the real
# Claude Code window (L3) with two chats open on one project, shows that VBW
# names the chat holding the run (chat A, renamed vbw-l3-holder by the user) in
# the status line, Comms and vbw next; that the Sessions tab lists both chats
# with the holder marked and its resume line; and that the /rename hint is said
# once to chat B and never applied. tools/l3.sh drives two chats on one folder,
# each with its own debug log. As in tests/l3-qafix-autonomy.bats these tests do
# not run Claude Code (L1): they hold the driver, the scenario's structure and the
# result it wrote under tools/l3-results/. The result is written by the run,
# not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
L3="$REPO_ROOT/tools/l3.sh"
RESULT="$REPO_ROOT/tools/l3-results/sessions.json"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

body() { sed -n '/^scenario_sessions()/,/^}/p' "$SUITE"; }

# A tmux stand-in that logs every call; start never reaches claude (it runs inside
# the tmux command string), capture-pane prints an empty screen.
stub_tmux() {
  STUBS="$TEST_ROOT/stubs"
  mkdir -p "$STUBS"
  cat > "$STUBS/tmux" << 'SH'
#!/usr/bin/env bash
{ printf %s tmux; printf " %s" "$@"; echo; } >> "$LOG"
exit 0
SH
  chmod +x "$STUBS/tmux"
  LOG="$TEST_ROOT/tmux.log"
  : > "$LOG"
  export LOG STUBS
}

# debug_file_of NAME: the --debug-file path the logged new-session for chat NAME carries.
debug_file_of() {
  grep "new-session" "$LOG" | grep -- "-s vbw-l3-$1 " | sed -n "s/.*--debug-file '\([^']*\)'.*/\1/p" | head -1
}

@test "R202: tools/l3.sh debuglog DIR NAME names one debug log per chat, so two chats on one folder never share a log" {
  local a b
  a=$(bash "$L3" debuglog "$TEST_ROOT/proj" a)
  b=$(bash "$L3" debuglog "$TEST_ROOT/proj" b)
  [ -n "$a" ] && [ -n "$b" ] || { echo "debuglog printed nothing: '$a' '$b'"; false; }
  [ "$a" != "$b" ] || { echo "both chats would write $a"; false; }
  case "$a" in "$TEST_ROOT/proj"*.debug.log) ;; *) echo "not a debug log beside the folder: $a"; false ;; esac
  case "$b" in "$TEST_ROOT/proj"*.debug.log) ;; *) echo "not a debug log beside the folder: $b"; false ;; esac
}

@test "R202: tools/l3.sh debuglog DIR alone lists the logs the chats of that folder wrote, one per line" {
  local a b out
  a=$(bash "$L3" debuglog "$TEST_ROOT/proj" a)
  b=$(bash "$L3" debuglog "$TEST_ROOT/proj" b)
  : > "$a"
  : > "$b"
  out=$(bash "$L3" debuglog "$TEST_ROOT/proj")
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq 2 ] || { echo "expected two logs, got: $out"; false; }
  printf '%s\n' "$out" | grep -qxF "$a" || { echo "$a not listed: $out"; false; }
  printf '%s\n' "$out" | grep -qxF "$b" || { echo "$b not listed: $out"; false; }
}

@test "R202: tools/l3.sh start gives each chat on one folder its own tmux session and the debug log debuglog names" {
  stub_tmux
  mkdir -p "$TEST_ROOT/proj"
  PATH="$STUBS:$PATH" bash "$L3" start a "$TEST_ROOT/proj" > /dev/null
  PATH="$STUBS:$PATH" bash "$L3" start b "$TEST_ROOT/proj" > /dev/null
  grep -q -- "new-session.* -s vbw-l3-a " "$LOG" || { echo "no tmux session for chat a:"; cat "$LOG"; false; }
  grep -q -- "new-session.* -s vbw-l3-b " "$LOG" || { echo "no tmux session for chat b:"; cat "$LOG"; false; }
  local fa fb
  fa=$(debug_file_of a)
  fb=$(debug_file_of b)
  [ -n "$fa" ] && [ -n "$fb" ] || { echo "no --debug-file in the start commands:"; cat "$LOG"; false; }
  [ "$fa" != "$fb" ] || { echo "both chats write the same debug log $fa"; false; }
  [ "$fa" = "$(bash "$L3" debuglog "$TEST_ROOT/proj" a)" ] || { echo "start writes $fa, debuglog finds $(bash "$L3" debuglog "$TEST_ROOT/proj" a)"; false; }
  [ "$fb" = "$(bash "$L3" debuglog "$TEST_ROOT/proj" b)" ] || { echo "start writes $fb, debuglog finds $(bash "$L3" debuglog "$TEST_ROOT/proj" b)"; false; }
}

@test "R202: the suite has a sessions scenario, in ALL and the header, that seeds a long enough build, renames chat A and opens chat B once a run is open" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_sessions"; false; }
  grep -E '^ALL=' "$SUITE" | grep -qw sessions || { echo "sessions is not in ALL"; false; }
  sed -n '1,24p' "$SUITE" | grep -qw sessions || { echo "sessions is not named in the header"; false; }
  body | grep -q 'result_write sessions ' || { echo "scenario_sessions does not write its result"; false; }
  body | grep -q 'L3_STATUSLINE=1' || { echo "the working tree's status line is not turned on"; false; }
  body | grep -q 'config rigor standard' || { echo "rigor is not set to standard"; false; }
  body | grep -q '/rename vbw-l3-holder' || { echo "chat A is not renamed vbw-l3-holder as a user would"; false; }
  body | grep -q 'l3 start' || { echo "scenario_sessions does not open a second chat"; false; }
  body | grep -qi 'fixture=' || { echo "no fixture text"; false; }
}

@test "R202: the scenario records every fact from the window, the record, git and Claude Code's list of chats" {
  local fact
  for fact in next_names_holder statusline_leading statusline_holder comms_holder \
    sessions_two_rows holder_marked this_chat_marked resume_line_matches_lease \
    rename_hint_shown_once hint_marked_once no_rename_applied lease_never_taken; do
    body | grep -q "$fact" || { echo "scenario_sessions does not record $fact"; false; }
  done
  body | grep -q 'belongs to another session' || { echo "next_names_holder does not read vbw next's words"; false; }
  body | grep -q 'held by' || { echo "the held-by words are not read"; false; }
  body | grep -q 'leading' || { echo "the leading word is not read"; false; }
  body | grep -q 'holds the run' || { echo "the Sessions tab's holder mark is not read"; false; }
  body | grep -q 'this chat' || { echo "the Sessions tab's own-chat mark is not read"; false; }
  body | grep -q -- '--resume' || { echo "the resume line is not read"; false; }
  body | grep -q 'lease.session' || { echo "the lease's session is not compared"; false; }
  body | grep -q 'nameSource' || { echo "chat B's nameSource is not read from Claude Code's list"; false; }
  body | grep -q 'rename_hint' || { echo "the clone's rename_hint mark is not read"; false; }
  body | grep -q '/rename vbw · ' || { echo "the hint sentence is not looked for"; false; }
  body | grep -q 'Still running' || { echo "chat B does not answer with Still running: wait"; false; }
  body | grep -q 'run end' || { echo "lease_never_taken does not look at who ran vbw run end"; false; }
  body | grep -q 'common_checks' || { echo "the suite's common checks are not run"; false; }
}

@test "R202: a committed result of the sessions scenario passed at L3 with every fact true and its gaps named" {
  [ -f "$RESULT" ] || { echo "the sessions scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "sessions" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-20")
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and .facts.next_names_holder == true
    and .facts.statusline_leading == true and .facts.statusline_holder == true and .facts.comms_holder == true
    and .facts.sessions_two_rows == true and .facts.holder_marked == true and .facts.this_chat_marked == true
    and .facts.resume_line_matches_lease == true
    and .facts.rename_hint_shown_once == true and .facts.hint_marked_once == true and .facts.no_rename_applied == true
    and .facts.lease_never_taken == true
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R202: the sessions result names what it did not test: the closed holder's row, a long name, a rename mid-run, the guards' reason, one window" {
  [ -f "$RESULT" ] || { echo "the sessions scenario has not been run: no result is committed"; false; }
  local nt
  nt=$(jq -r '.not_tested | join(" | ")' "$RESULT")
  printf '%s' "$nt" | grep -q 'closed or not seen' || { echo "not_tested misses the holder's row after chat A is closed: $nt"; false; }
  printf '%s' "$nt" | grep -q '20 characters' || { echo "not_tested misses a name longer than 20 characters: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'renamed' || { echo "not_tested misses a holder renamed while the run is open: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'guard' || { echo "not_tested misses the file guards' reason: $nt"; false; }
  printf '%s' "$nt" | grep -q '200' || { echo "not_tested misses the one 200-column window: $nt"; false; }
}
