#!/usr/bin/env bats
# R205: the real-user scenario `leaveout` in tools/l3-suite.sh (L3, the real
# Claude Code TUI): a project ignoring a data folder, listed under `## Clean
# copy` in the spec, reaches an approved contract whose `vbw show contract` names
# the path, and a passed proof whose clean copy held nothing of the folder. Judged
# in the record, in the kernel's own output and in a probe the seeded check
# writes from inside the copy, never on screen text. As in tests/l3-taskbreak.bats
# these tests do not run Claude Code (L1): they hold the scenario's structure and
# its committed result to facts from the record and the project.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }
facts() { jq -e "$2" "$RESULTS/$1.json" > /dev/null; }

@test "R205: the leaveout scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_leaveout()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw leaveout
  sed -n '1,20p' "$SUITE" | grep -qw leaveout
}

@test "R205: it seeds an ignored data folder listed under Clean copy, a check that probes the copy, and reads the record and vbw show contract" {
  [ -n "$(body leaveout)" ]
  body leaveout | grep -q 'result_write leaveout '
  body leaveout | grep -qi 'fixture='
  sed -n '/^leaveout_seed()/,/^}/p' "$SUITE" | grep -qF '## Clean copy'
  sed -n '/^leaveout_seed()/,/^}/p' "$SUITE" | grep -qF -- '- data/'
  sed -n '/^leaveout_seed()/,/^}/p' "$SUITE" | grep -qF '.gitignore'
  body leaveout | grep -qF 'show contract'
  body leaveout | grep -qF 'leave_out'
  if body leaveout | grep -qE 'screen \|.*grep.*(leave|copy)'; then false; fi
}

@test "R205: the result states each fact the scenario judged" {
  local k
  for k in contract_names_path leave_out proof_passed copy_without_data; do
    body leaveout | grep -qF "$k"
  done
}

@test "R205: the committed result of the leaveout scenario shows the path in the contract, a passed proof and a copy without the data" {
  local f="$RESULTS/leaveout.json"
  [ -f "$f" ] || { echo "the leaveout scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "leaveout" and .passed == true and .evidence_level == "L3"
    and (.at | type == "string" and . >= "2026-10-26")
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f" || { cat "$f"; false; }
  facts leaveout '.facts.contract_names_path == true'
  facts leaveout '.facts.leave_out == ["data/"]'
  facts leaveout '.facts.proof_passed == true'
  facts leaveout '.facts.copy_without_data == true'
}
