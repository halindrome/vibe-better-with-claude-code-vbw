#!/usr/bin/env bats
# R173 (docs/statusline.md): while the VBW status line is on, each render in a
# VBW project writes the session's latest figures Claude Code sent it (session
# id, total cost in dollars, the time) to .vbw/runtime/cost.SESSION.json,
# written to a temporary name and renamed, and never to .vbw/record.json. The
# token fields of the status line's JSON are the last request's, not running
# totals, so they are not stored. A render with no cost field leaves the file as
# it was; a folder that cannot be written still renders. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
}

teardown() {
  chmod -R u+w "$PROJECT/.vbw" 2> /dev/null || true
  vbw_teardown
}

# cc_json [COST]: Claude Code's status line JSON; COST "none" leaves the cost fields out.
cc_json() {
  jq -nc --arg d "$PROJECT" --arg sid "${SID:-s1}" --arg cost "${1:-yes}" '{session_id: $sid, workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"},
    version: "2.1.286", context_window: {used_percentage: 31, context_window_size: 200000}}
    + (if $cost == "none" then {} else {cost: {total_cost_usd: 1.4234, total_duration_ms: 622000, total_api_duration_ms: 355000,
        total_lines_added: 303, total_lines_removed: 12},
      context_window: {used_percentage: 31, total_input_tokens: 62000, total_output_tokens: 1200, context_window_size: 200000}} end)'
}

render() { cc_json "${1:-}" | NO_COLOR=1 bash "$SL"; }
side() { printf '%s/.vbw/runtime/cost.%s.json' "$PROJECT" "${1:-s1}"; }

@test "R173: a render in a VBW project writes the session's figures to its own side file" {
  "$VBW" init > /dev/null
  run render
  [ "$status" -eq 0 ]
  [ -f "$(side)" ] || { ls -la .vbw/runtime; false; }
  jq -e '.session == "s1" and .usd == 1.4234
    and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and (keys == ["at", "session", "usd"])' "$(side)" || { cat "$(side)"; false; }
}

@test "R173: a render with no cost field leaves the side file unchanged" {
  "$VBW" init > /dev/null
  render > /dev/null
  cp "$(side)" "$TEST_ROOT/before.json"
  sleep 1
  run render none
  [ "$status" -eq 0 ]
  cmp -s "$TEST_ROOT/before.json" "$(side)" || { diff "$TEST_ROOT/before.json" "$(side)"; false; }
}

@test "R173: the record is never written by a render, and no temporary file is left behind" {
  "$VBW" init > /dev/null
  cp .vbw/record.json "$TEST_ROOT/record.before"
  render > /dev/null
  cmp -s "$TEST_ROOT/record.before" .vbw/record.json
  run bash -c 'ls "$1"/.vbw/runtime | grep "^cost\." | grep -v "^cost\.s1\.json$"' _ "$PROJECT"
  [ -z "$output" ] || { echo "left behind: $output"; false; }
}

@test "R173: outside a VBW project nothing is written" {
  # The script hands back there (R224): exit 3, nothing printed, nothing written.
  run render
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [ ! -e "$PROJECT/.vbw" ]
}

@test "R173: a session id that is not a safe token writes no file" {
  "$VBW" init > /dev/null
  SID='../escape' run render
  [ "$status" -eq 0 ]
  run bash -c 'ls "$1"/.vbw/runtime | grep -c "^cost\."' _ "$PROJECT"
  [ "$output" = 0 ]
  [ ! -e "$PROJECT/.vbw/cost.json" ] && [ ! -e "$PROJECT/.vbw/runtime/cost.json" ]
}

@test "R173: when the runtime folder cannot be written the status line still renders" {
  "$VBW" init > /dev/null
  chmod a-w .vbw/runtime
  run render
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 4 ] || { echo "$output"; false; }
  [ "$output" != "[VBW] status line unavailable" ]
  [[ "${lines[0]}" == "[VBW] project with space"* ]] || { echo "$output"; false; }
}
