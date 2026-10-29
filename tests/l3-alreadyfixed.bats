#!/usr/bin/env bats
# R121 (#717): the real-user scenario `alreadyfixed` in tools/l3-suite.sh (L3,
# the real Claude Code TUI). The user asks VBW to fix a bug whose fix is already
# committed. Triage checks the code first, says it is already
# fixed with the evidence, records that with vbw decide, and adds no
# requirement, no backlog item and no planning. As in tests/l3-smallchange.bats
# these tests do not run Claude Code (L1): they hold the scenario's structure
# and its committed result to facts from the record, git and the session
# transcript, never screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/alreadyfixed.json"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "#717: the alreadyfixed scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_alreadyfixed()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw alreadyfixed
  sed -n '1,24p' "$SUITE" | grep -qw alreadyfixed
}

@test "#717: it seeds a committed fix and reads the record, git and the transcript" {
  [ -n "$(body alreadyfixed)" ]
  body alreadyfixed | grep -q 'result_write alreadyfixed '
  body alreadyfixed | grep -qi 'fixture='
  body alreadyfixed | grep -q 'workflow_started'
  body alreadyfixed | grep -qE 'git (-C "\$dir" )?(log|status|diff|show|rev-parse)'
  body alreadyfixed | grep -q 'decisions'
  if body alreadyfixed | grep -q 'screen |.*grep.*fixed'; then false; fi
}

@test "#717: the committed result: L3, passed, recorded as already fixed with evidence, nothing added, no planning, the code untouched" {
  jq -e '.scenario == "alreadyfixed" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.not_tested | type == "array" and length > 0)
    and .facts.already_fixed_decided == true
    and .facts.evidence_named == true
    and .facts.new_requirements == 0
    and .facts.new_todos == 0
    and .facts.planning_workflow == false
    and .facts.code_unchanged == true' "$RESULT"
}
