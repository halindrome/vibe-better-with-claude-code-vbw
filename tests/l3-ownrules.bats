#!/usr/bin/env bats
# R202, phase P162: the ownrules scenario of tools/l3-suite.sh, run in the real
# Claude Code window (L3) on a project the scenario seeds: one requirement R1
# (greet.sh), two plans on the same file, P1.1 'the greeting with a name' and
# P1.2 'the default greeting' (after P1.1), one rule per plan with its own bats
# check (C1 -> P1.1, C2 -> P1.2). It shows that the early plan broke its task
# judged by its own rule while the later plan's check was still red (R193, the
# T159 case), and that a failing check's full output is kept and named with the
# failing test's name by vbw show fix (R195). As in tests/l3-qafix-autonomy.bats
# these tests do not run Claude Code (L1): they hold the scenario's structure and
# the result it wrote under tools/l3-results/. The result is written by the run,
# not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/ownrules.json"

body() { sed -n '/^scenario_ownrules()/,/^}/p;/^ownrules_seed()/,/^}/p' "$SUITE"; }

@test "R202: the suite has an ownrules scenario, in ALL and the header, seeding two plans on greet.sh with one bats-checked rule each and its plan named" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_ownrules"; false; }
  grep -E '^ALL=' "$SUITE" | grep -qw ownrules || { echo "ownrules is not in ALL"; false; }
  sed -n '1,24p' "$SUITE" | grep -qw ownrules || { echo "ownrules is not named in the header"; false; }
  body | grep -q 'result_write ownrules ' || { echo "scenario_ownrules does not write its result"; false; }
  body | grep -q 'config rigor standard' || { echo "rigor is not set to standard"; false; }
  body | grep -q 'greet.bats' || { echo "the checks are not bats tests (tests/greet.bats)"; false; }
  body | grep -q '"bats"' || { echo "the checks do not run bats"; false; }
  body | grep -q '"after": *\["P1.1"\]' || { echo "P1.2 does not come after P1.1"; false; }
  body | grep -q '"plan": *"P1.1"' || { echo "no rule names P1.1 as its plan"; false; }
  body | grep -q '"plan": *"P1.2"' || { echo "no rule names P1.2 as its plan"; false; }
  body | grep -qi 'fixture=' || { echo "no fixture text"; false; }
}

@test "R202: the scenario records the own-rule break from the record's mutation entries and the kept output from vbw show fix" {
  local fact
  for fact in own_rule_break proof_failed_fix_opened kept_output_named kept_exists failing_test_names; do
    body | grep -q "$fact" || { echo "scenario_ownrules does not record $fact"; false; }
  done
  body | grep -q 'mutations' || { echo "own_rule_break does not read the plan's mutation entries"; false; }
  body | grep -q 'record_history' || { echo "the record's history is not read (P1.2's status at the break's commit)"; false; }
  body | grep -q 'show fix' || { echo "vbw show fix is not run"; false; }
  body | grep -q 'full output: ' || { echo "the 'full output:' line is not read"; false; }
  body | grep -q 'failing tests:' || { echo "the 'failing tests:' line is not read"; false; }
  body | grep -q 'runtime/output/C2.log' || { echo "the kept file .vbw/runtime/output/C2.log is not looked for"; false; }
  body | grep -q 'not ok' || { echo "the kept file is not checked for 'not ok'"; false; }
  body | grep -q -- '--json' || { echo "vbw show fix --json (kept, failing_tests) is not read"; false; }
  body | grep -q 'common_checks' || { echo "the suite's common checks are not run"; false; }
}

@test "R202: a committed result of the ownrules scenario passed at L3: the early plan broke by its own rule, the kept output was named with the failing test" {
  [ -f "$RESULT" ] || { echo "the ownrules scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "ownrules" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-20")
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and .facts.own_rule_break == true
    and .facts.proof_failed_fix_opened == true
    and .facts.kept_output_named == true and .facts.kept_exists == true
    and (.facts.failing_test_names | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R202: the ownrules result names what it did not test: other name forms, a timed-out check, two vbw check at once, a survivor with a pending file, vbw check keeping output" {
  [ -f "$RESULT" ] || { echo "the ownrules scenario has not been run: no result is committed"; false; }
  local nt
  nt=$(jq -r '.not_tested | join(" | ")' "$RESULT")
  printf '%s' "$nt" | grep -q 'cargo' && printf '%s' "$nt" | grep -q 'pytest' || { echo "not_tested misses the other recognised name forms: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'timed.out\|timeout' || { echo "not_tested misses a timed-out check: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'at once\|same time\|concurrent' || { echo "not_tested misses two Devs running vbw check at once: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'survivor' || { echo "not_tested misses a survivor at the task break with a pending test file: $nt"; false; }
  printf '%s' "$nt" | grep -q 'vbw check' || { echo "not_tested misses vbw check keeping output: $nt"; false; }
}
