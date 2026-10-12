#!/usr/bin/env bats
# R173 (docs/costs.md, D288): a milestone's cost is everything spent in this
# project's sessions while it was open. vbw milestone start records each known
# session's current figures as the milestone's baseline; a session first seen
# later counts from its first figure; vbw ship freezes the total on the shipped
# milestone; the active milestone's total is computed on demand. vbw show costs
# prints the totals and each run's share in plain words, --json returns one
# object, and --ceiling USD judges the active milestone's known spend: exit 0
# "under", exit 1 "reached", exit 1 "cannot tell" when no figure was seen (fail
# closed), exit 2 for a USD that is not a positive number. What VBW did not see
# is unknown, with the remedy, never a guess. L1.

load helper
load rigor-helper

setup() {
  rigor_flow_setup
  rigor_flow_build
  "$VBW" qa record P1 pass quick > /dev/null
}

teardown() { vbw_teardown; }

# figures SID USD IN OUT: the session's side file, as the status line writes it.
figures() {
  mkdir -p .vbw/runtime
  jq -nc --arg s "$1" --argjson u "$2" --argjson i "$3" --argjson o "$4" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{session: $s, usd: $u, in: $i, out: $o, at: $at}' > ".vbw/runtime/cost.$1.json"
}

costs_json() { "$VBW" show costs --json < /dev/null; }
milestone() { costs_json | jq -c --arg m "$1" '.milestones[] | select(.id == $m)'; }

@test "R173: the active milestone's total is the sum over the sessions seen, each from its first figure when no baseline was recorded" {
  figures s1 2 1000 100
  figures s2 1 500 50
  milestone M1 | jq -e '.status == "active" and .usd == 3 and .in == 1500 and .out == 150 and .sessions == 2' || { costs_json; false; }
  run "$VBW" show costs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"M1"* ]] && [[ "$output" == *'$3.00'* ]] && [[ "$output" == *"2 sessions"* ]] || { echo "$output"; false; }
}

@test "R173: vbw ship freezes the total; vbw milestone start records baselines; later spend counts in the new milestone only, a new session from its first figure" {
  figures s1 2 1000 100
  figures s2 1 500 50
  "$VBW" ship > /dev/null
  jq -e '.costs.milestones.M1.total == {usd: 3, in: 1500, out: 150, sessions: 2}' .vbw/record.json || { jq .costs .vbw/record.json; false; }
  "$VBW" milestone start "Second" > /dev/null
  jq -e '.costs.milestones.M2.baseline.s1 | .usd == 2 and .in == 1000 and .out == 100 and (.at | type == "string")' .vbw/record.json || { jq .costs .vbw/record.json; false; }
  jq -e '.costs.milestones.M2.baseline.s2.usd == 1' .vbw/record.json
  figures s1 2.5 1200 130
  figures s3 0.4 200 20
  milestone M1 | jq -e '.status == "shipped" and .usd == 3 and .in == 1500 and .out == 150' || { costs_json; false; }
  milestone M2 | jq -e '.status == "active" and .usd == 0.9 and .in == 400 and .out == 50' || { costs_json; false; }
  # Spend before the ship stays in M1 and is counted once: both totals add up to what the sessions report.
  costs_json | jq -e '[.milestones[].usd] | add == 3.9' || { costs_json; false; }
  run "$VBW" show costs
  [[ "$output" == *"M1"*'$3.00'* ]] && [[ "$output" == *"M2"*'$0.90'* ]] || { echo "$output"; false; }
}

@test "R173: each run's cost is shown as its share; a run whose session had no figures is unknown with the remedy" {
  figures s1 2 1000 100
  VBW_SESSION_ID=s1 "$VBW" run start qa > /dev/null
  figures s1 2.25 1100 110
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  VBW_SESSION_ID=s9 "$VBW" run start qa > /dev/null
  VBW_SESSION_ID=s9 "$VBW" run end > /dev/null
  local known unknown
  known=$(jq -r '.costs.runs[0].id' .vbw/record.json)
  unknown=$(jq -r '.costs.runs[1].id' .vbw/record.json)
  costs_json | jq -e --arg k "$known" --arg u "$unknown" '
    (.runs[] | select(.id == $k) | .cost == {usd: 0.25, in: 100, out: 10} and .milestone == "M1" and .kind == "qa")
    and (.runs[] | select(.id == $u) | .cost == null)
    and (.unknown.runs == [$u]) and (.remedy | test("vbw statusline on"))' || { costs_json; false; }
  run "$VBW" show costs
  [[ "$output" == *"$known"*'$0.25'* ]] || { echo "$output"; false; }
  [[ "$output" == *"$unknown"*"unknown"* ]] && [[ "$output" == *"vbw statusline on"* ]] || { echo "$output"; false; }
}

@test "R173: a milestone with no figure seen is unknown, not 0" {
  costs_json | jq -e '(.milestones[] | select(.id == "M1") | .usd == null and .sessions == 0) and .unknown.milestones == ["M1"] and (.remedy | test("vbw statusline on"))' || { costs_json; false; }
  run "$VBW" show costs
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]] && [[ "$output" == *"vbw statusline on"* ]] || { echo "$output"; false; }
  [[ "$output" != *'$0.00'* ]] || { echo "$output"; false; }
}

@test "R173: a milestone shipped without figures stays unknown when figures arrive later; no dollar counts twice" {
  "$VBW" ship > /dev/null
  figures s1 2 1000 100
  costs_json | jq -e '(.milestones[] | select(.id == "M1") | .status == "shipped" and .usd == null and .sessions == 0)
    and (.unknown.milestones | index("M1") != null)
    and ([.milestones[].usd // 0] | add) <= 2' || { costs_json; false; }
}

@test "R173: --ceiling: under (exit 0, both figures), reached at or above (exit 1), cannot tell with no figure (exit 1)" {
  run "$VBW" show costs --ceiling 5
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "cannot tell"* ]] && [[ "$output" == *"vbw statusline on"* ]] || { echo "$output"; false; }
  figures s1 2 1000 100
  run "$VBW" show costs --ceiling 5
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "${lines[0]}" == "under"* ]] && [[ "${lines[0]}" == *'$2.00'* ]] && [[ "${lines[0]}" == *'$5'* ]] || { echo "$output"; false; }
  run "$VBW" show costs --ceiling 2
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "reached"* ]] && [[ "${lines[0]}" == *'$2.00'* ]] || { echo "$output"; false; }
  run "$VBW" show costs --ceiling 1.5
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "reached"* ]] || { echo "$output"; false; }
}

@test "R173: --ceiling with anything but a positive number is a usage error (exit 2) that changes nothing" {
  local before
  before=$(cat .vbw/record.json)
  local bad
  for bad in 0 -1 abc 5usd ""; do
    run "$VBW" show costs --ceiling "$bad"
    [ "$status" -eq 2 ] || { echo "ceiling '$bad': exit $status: $output"; false; }
  done
  run "$VBW" show costs --ceiling
  [ "$status" -eq 2 ]
  [ "$(cat .vbw/record.json)" = "$before" ]
}

@test "R173: vbw show lists costs in its usage" {
  run "$VBW" show --help
  [[ "$output" == *"costs"* ]] || { echo "$output"; false; }
}
