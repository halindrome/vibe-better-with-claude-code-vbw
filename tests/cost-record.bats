#!/usr/bin/env bats
# R173 (docs/record.md): the record validator accepts the cost data strictly
# (known shapes, dollars non-negative numbers or null, ISO-8601 UTC times,
# milestone ids that exist, no unknown keys) and refuses malformed data as
# corrupt (exit 3). A record written before the token figures were dropped
# (Claude Code gives the status line no running token total) also carries "in"
# and "out" beside the dollars, both or neither: it stays valid. A record
# without any cost data stays valid too. Only kernel
# commands write it: the status line script never names the record as a write
# target. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# with FILTER: a hand edit of the record; the glance goes with it (R155).
with() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

VALID='.costs = {
  runs: [{id: "build-20261011T215215Z", kind: "build", session: "s1", milestone: "M1",
          started: "2026-10-11T21:52:15Z", ended: "2026-10-11T22:02:15Z", cost: {usd: 0.5}},
         {id: "qa-20261011T220500Z", kind: "qa", session: null, milestone: "M1",
          started: "2026-10-11T22:05:00Z", ended: "2026-10-11T22:06:00Z", cost: null}],
  milestones: {M1: {baseline: {s1: {usd: 1.25, at: "2026-10-11T21:00:00Z"}}}}}'

# refused FILTER: the record with FILTER applied over the valid cost data is corrupt (exit 3) and the message names costs.
refused() {
  with "$VALID | $1"
  vbw_run status
  [ "$status" -eq 3 ] || { echo "accepted: $1 (exit $status)"; echo "$output"; return 1; }
  [[ "$output" == *costs* ]] || { echo "the refusal does not name costs: $output"; return 1; }
}

@test "R173: a record without cost data stays valid" {
  jq -e 'has("costs") | not' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "R173: well-formed cost data is accepted, a frozen total and an unknown cost included" {
  with "$VALID"
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  with "$VALID | .costs.milestones.M1.total = {usd: 3, sessions: 2}"
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  with "$VALID | .lease = {run: \"plan-20261011T230000Z\", kind: \"plan\", started_at: \"2026-10-11T23:00:00Z\", files: [\".vbw/\"], session: \"s1\", cost: {usd: 1.25}}"
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  with "$VALID | .lease = {run: \"plan-20261011T230000Z\", kind: \"plan\", started_at: \"2026-10-11T23:00:00Z\", files: [\".vbw/\"], cost: null}"
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R173: cost data written before the token figures were dropped (usd, in and out together) stays valid" {
  with "$VALID | .costs.runs[0].cost = {usd: 0.5, in: 200, out: 30}
    | .costs.milestones.M1.baseline.s1 = {usd: 1.25, in: 100, out: 10, at: \"2026-10-11T21:00:00Z\"}
    | .costs.milestones.M1.total = {usd: 3, in: 1500, out: 150, sessions: 2}
    | .lease = {run: \"plan-20261011T230000Z\", kind: \"plan\", started_at: \"2026-10-11T23:00:00Z\", files: [\".vbw/\"], session: \"s1\", cost: {usd: 1.25, in: 100, out: 10}}"
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R173: a run with an unknown key, a bad kind, a missing field or a bad time is refused" {
  refused '.costs.runs[0].extra = 1'
  refused '.costs.runs[0].kind = "bogus"'
  refused 'del(.costs.runs[0].ended)'
  refused '.costs.runs[0].started = "yesterday"'
  refused '.costs.runs[0].session = 7'
}

@test "R173: dollars must be a non-negative number (or the whole cost null); tokens only both together, beside the dollars, non-negative" {
  refused '.costs.runs[0].cost.usd = -0.5'
  refused '.costs.runs[0].cost.usd = "0.5"'
  refused 'del(.costs.runs[0].cost.usd)'
  refused '.costs.runs[0].cost.in = 1'
  refused '.costs.runs[0].cost += {in: -1, out: 0}'
  refused '.costs.runs[0].cost += {in: 1, out: null}'
  refused '.costs.runs[0].cost = 0'
  refused '.costs.runs[0].cost.extra = 1'
}

@test "R173: milestone ids must exist, in runs and in the milestones map; unknown keys are refused everywhere" {
  refused '.costs.runs[0].milestone = "M9"'
  refused '.costs.milestones.M9 = {baseline: {}}'
  refused '.costs.milestones.M1.extra = 1'
  refused '.costs.milestones.M1.baseline.s1.extra = 1'
  refused '.costs.milestones.M1.baseline.s1.at = "noon"'
  refused '.costs.milestones.M1.baseline.s1.usd = -1'
  refused '.costs.milestones.M1.total = {usd: 3}'
  refused '.costs.milestones.M1.total = {usd: 3, sessions: -1}'
  refused '.costs.milestones.M1.total = {usd: 3, in: 1, out: 1, sessions: -1}'
  refused '.costs.milestones.M1.total = {usd: 3, in: 1, sessions: 1}'
  refused '.costs.extra = []'
  refused '.costs = []'
}

@test "R173: the lease's opening figures follow the same rules" {
  refused '.lease = {run: "plan-20261011T230000Z", kind: "plan", started_at: "2026-10-11T23:00:00Z", files: [".vbw/"], cost: {usd: "x"}}'
  refused '.lease = {run: "plan-20261011T230000Z", kind: "plan", started_at: "2026-10-11T23:00:00Z", files: [".vbw/"], cost: {in: 1, out: 1}}'
  refused '.lease = {run: "plan-20261011T230000Z", kind: "plan", started_at: "2026-10-11T23:00:00Z", files: [".vbw/"], cost: {usd: 1, in: 1}}'
}

@test "R173: the status line never writes the record" {
  ! grep -nE '>[[:space:]]*"?\$?[A-Za-z_/$.{}]*record\.json' "$PLUGIN_ROOT/scripts/vbw-statusline.sh" || false
  ! grep -qF 'record_update' "$PLUGIN_ROOT/scripts/vbw-statusline.sh"
}
