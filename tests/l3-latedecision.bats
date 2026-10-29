#!/usr/bin/env bats
# #705: the real-user scenario `latedecision` in tools/l3-suite.sh (L3, the real
# Claude Code TUI): a decision recorded after the contract was approved changes
# what an unbuilt plan delivers and itself needs the contract approved again; the
# user approves by the choice VBW asks, and the plan's Dev still applies the
# decision. Judged in the project's files, git, the record and the Dev's tool
# results in the subagent transcripts, never on screen. As in
# tests/l3-fixchecks.bats these tests do not run Claude Code (L1): they hold the
# scenario's structure, and its committed result once a run wrote one.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "#705: the latedecision scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_latedecision()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw latedecision
  sed -n '1,20p' "$SUITE" | grep -qw latedecision
}

@test "#705: the seed records the decision after the approval and leaves the plan as approved, so only a re-approval waits" {
  local seed
  seed=$(sed -n '/^latedecision_seed()/,/^}/p' "$SUITE")
  printf '%s\n' "$seed" | grep -qF '"$VBW" approve'
  printf '%s\n' "$seed" | grep -qF '"$VBW" decide "$LATE_DECISION"'
  printf '%s\n' "$seed" | grep -qF 'plans: [.plans[] | del(.status)]'
  printf '%s\n' "$seed" | grep -qF '= approve ]'
  # The judged detail is in the decision only: no plan, requirement or check names it.
  grep -E '^LATE_DECISION=' "$SUITE" | grep -qF -- '--quiet'
  if sed -n '/^plan_seed()/,/^}/p' "$SUITE" | grep -qF -- 'quiet'; then false; fi
}

@test "#705: it approves by the choice and reads the Dev's call, the files and the record, never the screen" {
  [ -n "$(body latedecision)" ]
  body latedecision | grep -q 'result_write latedecision '
  body latedecision | grep -qi 'fixture='
  body latedecision | grep -qF 'Approve contract'
  body latedecision | grep -qF 'show decisions --since-approval'
  body latedecision | grep -qF 'VBW-Plan: P2.1'
  if body latedecision | grep -qE 'screen \|.*grep.*(quiet|decision|See you)'; then false; fi
}

@test "#705: the result states each fact the scenario judged" {
  local k
  for k in reapproval_plans approval_questions dev_asked_with_plan_id dev_saw_decision dev_since_approval_output quiet_flag_in_code quiet_prints_nothing built_through_plan decisions_added; do
    body latedecision | grep -qF "$k"
  done
}

@test "#705: a committed result of the latedecision scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/latedecision.json"
  [ -f "$f" ] || skip "no latedecision result committed yet: a run writes it"
  jq -e '.scenario == "latedecision" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)
    and .facts.reapproval_plans == [[]] and .facts.dev_saw_decision == true and .facts.quiet_prints_nothing == true' "$f"
}
