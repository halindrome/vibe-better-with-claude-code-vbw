#!/usr/bin/env bats
# R173 (docs/record.md, docs/costs.md): vbw run start stores the opening
# session's figures with the run (lease.cost, from that session's side file,
# matched by the lease's session id); vbw run end computes the run's cost as the
# end figures minus the start figures and appends the finished run to
# costs.runs in the record, committed by the run's record commit. A run whose
# session had no figures at start or at end, or no session id, is recorded with
# cost null: never 0, never an estimate. Only the dollars count: Claude Code
# gives the status line no running token total (its token fields describe the
# last request), so a token figure never makes a run unknown. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore(vbw): init"
}

teardown() { vbw_teardown; }

# figures SID USD: the session's side file, as the status line writes it.
figures() {
  mkdir -p .vbw/runtime
  jq -nc --arg s "$1" --argjson u "$2" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{session: $s, usd: $u, at: $at}' > ".vbw/runtime/cost.$1.json"
}

# cc_render SID USD IN OUT: one render of the status line from the JSON Claude Code 2.1.305 sends:
# total_input_tokens is the size of the context now and total_output_tokens the last response's
# output, both per request, not running totals; total_cost_usd is the session's running total.
cc_render() {
  jq -nc --arg d "$PROJECT" --arg sid "$1" --argjson u "$2" --argjson i "$3" --argjson o "$4" \
    '{session_id: $sid, workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"}, version: "2.1.305",
      cost: {total_cost_usd: $u}, context_window: {total_input_tokens: $i, total_output_tokens: $o, context_window_size: 200000, used_percentage: 33}}' \
    | NO_COLOR=1 bash "$PLUGIN_ROOT/scripts/vbw-statusline.sh" > /dev/null
}

last_run() { jq -c '.costs.runs[-1]' .vbw/record.json; }

# seed_run ID: the record already holds a finished run with this id.
seed_run() {
  jq --arg id "$1" '.costs = {runs: ((.costs.runs // []) + [{id: $id, kind: "qa", milestone: "M1", session: null, started: "2026-10-12T03:06:50Z", ended: "2026-10-12T03:06:50Z", cost: null}]), milestones: (.costs.milestones // {})}' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
}

@test "R173 (F140): a run id is the kind and its start second, and a second run in that second gets -2, a third -3: no two runs share an id" {
  run vbw_kernel '. "$VBW_LIB/cmd-run.sh"; run_id qa 2026-10-12T03:06:50Z'
  [ "$output" = qa-20261012T030650Z ] || { echo "$output"; false; }
  seed_run qa-20261012T030650Z
  run vbw_kernel '. "$VBW_LIB/cmd-run.sh"; run_id qa 2026-10-12T03:06:50Z'
  [ "$output" = qa-20261012T030650Z-2 ] || { echo "$output"; false; }
  seed_run qa-20261012T030650Z-2
  run vbw_kernel '. "$VBW_LIB/cmd-run.sh"; run_id qa 2026-10-12T03:06:50Z'
  [ "$output" = qa-20261012T030650Z-3 ] || { echo "$output"; false; }
  run vbw_kernel '. "$VBW_LIB/cmd-run.sh"; run_id build 2026-10-12T03:06:50Z'
  [ "$output" = build-20261012T030650Z ] || { echo "$output"; false; }
  # Runs started back to back, within one second or not, never share an id, and the lease carries the id the run was recorded under.
  git add -A && git commit -q -m "chore(test): seeded runs"
  local i lease
  for i in 1 2 3; do
    VBW_SESSION_ID=s1 "$VBW" run start qa > /dev/null
    lease=$(jq -r '.lease.run' .vbw/record.json)
    VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
    [ "$(last_run | jq -r .id)" = "$lease" ] || { last_run; false; }
  done
  [ "$(jq '[.costs.runs[].id] | unique | length' .vbw/record.json)" -eq 5 ] || { jq '[.costs.runs[].id]' .vbw/record.json; false; }
}

@test "R173: the run keeps the opening figures; its cost is end minus start, appended and committed" {
  figures s1 1.25
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  jq -e '.lease.cost == {usd: 1.25}' .vbw/record.json || { jq .lease .vbw/record.json; false; }
  local id
  id=$(jq -r '.lease.run' .vbw/record.json)
  figures s1 1.75
  VBW_SESSION_ID=s1 vbw_run run end
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  last_run | jq -e --arg id "$id" '.id == $id and .kind == "plan" and .session == "s1" and .milestone == "M1"
    and .cost == {usd: 0.5}
    and (.started | test("^[0-9]{4}-")) and (.ended | test("^[0-9]{4}-"))
    and (keys == ["cost", "ended", "id", "kind", "milestone", "session", "started"])' || { last_run; false; }
  [ -z "$(git status --porcelain -- .vbw/record.json)" ] || { git status --porcelain; false; }
  [ "$(git log -1 --format=%s)" = "chore(vbw): record after $id" ]
  jq -e '.lease == null' .vbw/record.json
}

@test "R173: every finished run is appended in order, each with its own cost" {
  figures s1 1
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  figures s1 2
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start qa > /dev/null
  figures s1 2.5
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  jq -e '.costs.runs | length == 2 and .[0].kind == "plan" and .[0].cost.usd == 1 and .[1].kind == "qa" and .[1].cost == {usd: 0.5}' .vbw/record.json || { jq .costs .vbw/record.json; false; }
}

@test "R173: no figures at the start: the run's cost is unknown (null), never 0" {
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  jq -e '.lease.cost == null' .vbw/record.json
  figures s1 1.75
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  last_run | jq -e '.session == "s1" and .cost == null' || { last_run; false; }
}

@test "R173: no figures at the end: the run's cost is unknown (null)" {
  figures s1 1.25
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  rm .vbw/runtime/cost.s1.json
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  last_run | jq -e '.session == "s1" and .cost == null' || { last_run; false; }
}

@test "R173: no session id: the run is recorded with session null and cost unknown" {
  figures s1 1.25
  "$VBW" run start plan > /dev/null
  "$VBW" run end > /dev/null
  last_run | jq -e '.session == null and .cost == null and .kind == "plan"' || { last_run; false; }
}

@test "R173: another session's figures never count for this run" {
  figures s2 9
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  jq -e '.lease.cost == null' .vbw/record.json
  figures s2 9.5
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  last_run | jq -e '.cost == null' || { last_run; false; }
}

@test "R173 (F143): a figure that fell during the run makes its cost unknown (null), and the run still ends" {
  figures s1 2
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  figures s1 1
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  jq -e '.lease == null' .vbw/record.json
  last_run | jq -e '.cost == null and .session == "s1"' || { last_run; false; }
}

@test "R173: Claude Code's token figures are per request, so a falling one never makes a run unknown (through the status line's own side file)" {
  # The sequence of a build run in a session of Claude Code 2.1.305 (seen in a real-user scenario): the response
  # that started the run had 524 output tokens, a later one 237 and the context grew. Dollars rose; the token
  # fields are the last request's, not running totals.
  cc_render s1 0.32 66352 524
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  jq -e '.lease.cost == {usd: 0.32}' .vbw/record.json || { jq .lease .vbw/record.json; false; }
  cc_render s1 0.3396 67819 237
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  last_run | jq -e '.session == "s1" and .cost == {usd: 0.0196}' || { last_run; false; }
}

@test "R173: a side file written by an earlier status line (with token fields) counts by its dollars alone" {
  mkdir -p .vbw/runtime
  jq -nc '{session: "s1", usd: 1.25, in: 66352, out: 524, at: "2026-10-12T03:00:00Z"}' > .vbw/runtime/cost.s1.json
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  jq -e '.lease.cost == {usd: 1.25}' .vbw/record.json || { jq .lease .vbw/record.json; false; }
  jq -nc '{session: "s1", usd: 1.5, in: 900, out: 12, at: "2026-10-12T03:01:00Z"}' > .vbw/runtime/cost.s1.json
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  last_run | jq -e '.cost == {usd: 0.25}' || { last_run; false; }
}
