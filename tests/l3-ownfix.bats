#!/usr/bin/env bats
# R202, phase P162: the ownfix scenario of tools/l3-suite.sh, run in the real
# Claude Code window (L3) on a one-plan project the scenario seeds: R1 with three
# clauses (a name; no name; the greeting is the only output, nothing on stderr),
# rules and checks for the first two only, both in tests/greet.bats, and
# README.md naming the convention 'one bats file per requirement'. After the
# build the scenario commits greet.sh with one extra line on stderr and proves,
# so only QA can see it; the user then goes on with /vbw:vibe and the
# recommended answers. It shows that QA fails the phase naming the stderr
# output, that the fix commits its own requirement's protected check file with
# the VBW-Fix and VBW-Req trailers (R194), and that one user approval of the
# edited file came before the proof that closed the fix. As in
# tests/l3-qafix-autonomy.bats these tests do not run Claude Code (L1): they hold
# the scenario's structure and the result it wrote under tools/l3-results/. The
# result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/ownfix.json"

body() { sed -n '/^scenario_ownfix()/,/^}/p;/^ownfix_seed()/,/^}/p' "$SUITE"; }

@test "R202: the suite has an ownfix scenario, in ALL and the header, seeding one plan with two bats rules of a three-clause requirement and the project's test convention" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_ownfix"; false; }
  grep -E '^ALL=' "$SUITE" | grep -qw ownfix || { echo "ownfix is not in ALL"; false; }
  sed -n '1,24p' "$SUITE" | grep -qw ownfix || { echo "ownfix is not named in the header"; false; }
  body | grep -q 'result_write ownfix ' || { echo "scenario_ownfix does not write its result"; false; }
  body | grep -q 'config rigor standard' || { echo "rigor is not set to standard"; false; }
  body | grep -q 'tests/greet.bats' || { echo "the checks are not in tests/greet.bats"; false; }
  body | grep -q 'stderr' || { echo "the requirement's third clause (nothing on stderr) is missing"; false; }
  body | grep -q 'README.md' || { echo "README.md does not name the test convention"; false; }
  body | grep -q 'one bats file per requirement' || { echo "the convention 'one bats file per requirement' is not stated"; false; }
  body | grep -qi 'fixture=' || { echo "no fixture text"; false; }
}

@test "R202: the scenario seeds the stderr deviation after the build, proves it, and records the QA, commit and approval facts from the record and git" {
  local fact
  for fact in qa_found_deviation own_check_commit one_approval fix_closed final_qa_pass; do
    body | grep -q "$fact" || { echo "scenario_ownfix does not record $fact"; false; }
  done
  body | grep -q '>&2\|>& *2\|/dev/stderr' || { echo "the deviation does not write to stderr"; false; }
  body | grep -q '" prove' || { echo "the scenario does not prove the deviating build (vbw prove)"; false; }
  body | grep -q 'record_history' || { echo "the first QA verdict is not read from the record's history"; false; }
  body | grep -q 'VBW-Fix: ' || { echo "the VBW-Fix trailer is not read from git"; false; }
  body | grep -q 'VBW-Req: R1' || { echo "the VBW-Req: R1 trailer is not read from git"; false; }
  body | grep -q -- '--name-only' || { echo "the commit's changed files are not listed (git ... --name-only)"; false; }
  body | grep -q 'source == "qa"' || { echo "the fix's source (qa) is not checked"; false; }
  body | grep -q 'common_checks' || { echo "the suite's common checks are not run"; false; }
}

@test "R202: a committed result of the ownfix scenario passed at L3: QA found the stderr output, the fix committed its own check file with both trailers after one approval" {
  [ -f "$RESULT" ] || { echo "the ownfix scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "ownfix" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-20")
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and .facts.qa_found_deviation == true
    and .facts.own_check_commit == true
    and .facts.one_approval == true
    and .facts.fix_closed == true and .facts.final_qa_pass == true
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R202: the ownfix result names what it did not test: a wrong test file, another requirement's file, a [human] fix, a project-command fix, the loop" {
  [ -f "$RESULT" ] || { echo "the ownfix scenario has not been run: no result is committed"; false; }
  local nt
  nt=$(jq -r '.not_tested | join(" | ")' "$RESULT")
  printf '%s' "$nt" | grep -qi 'wrong' || { echo "not_tested misses a fix opened by a failing test whose test file is wrong: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'another requirement' || { echo "not_tested misses the refusal of another requirement's test file: $nt"; false; }
  printf '%s' "$nt" | grep -q 'human' || { echo "not_tested misses a [human] requirement's fix: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'project.command' || { echo "not_tested misses a project-command fix: $nt"; false; }
  printf '%s' "$nt" | grep -qi 'loop' || { echo "not_tested misses the loop: $nt"; false; }
}
