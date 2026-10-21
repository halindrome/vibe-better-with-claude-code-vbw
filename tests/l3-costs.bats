#!/usr/bin/env bats
# R173: the real-session proof of the cost data. The costs scenario in
# tools/l3-suite.sh drives a VBW run through the real Claude Code TUI with the
# VBW status line on and ends with vbw show costs --json reporting a known,
# non-zero cost for that run and for the milestone, of the same order as the
# /cost figure the suite captures. This test does not run Claude Code (L1); it
# holds the committed result to those facts. L1.

load helper

RESULTS="$REPO_ROOT/tools/l3-results"

@test "R173: the costs scenario exists, is in the suite's list and its saved result passed at L3" {
  grep -q '^scenario_costs()' "$REPO_ROOT/tools/l3-suite.sh"
  grep -E '^ALL=' "$REPO_ROOT/tools/l3-suite.sh" | grep -qw costs
  [ -f "$RESULTS/costs.json" ]
  jq -e '.scenario == "costs" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string") and (.facts | type == "object")
    and (.not_tested | type == "array")' "$RESULTS/costs.json" > /dev/null
}

@test "R173: the result shows a known, non-zero cost for the run and the milestone, of the same order as /cost" {
  jq -e '.facts.statusline_on == true
    and (.facts.run_id | type == "string" and length > 0)
    and (.facts.run_cost_usd | type == "number" and . > 0)
    and (.facts.milestone_cost_usd | type == "number" and . > 0)
    and (.facts.session_cost_usd | type == "number" and . > 0)
    and (.facts.milestone_cost_usd / .facts.session_cost_usd | . >= 0.2 and . <= 5)
    and (.facts.run_cost_usd <= .facts.milestone_cost_usd)
    and .facts.unknown_runs == 0' "$RESULTS/costs.json" > /dev/null
}
