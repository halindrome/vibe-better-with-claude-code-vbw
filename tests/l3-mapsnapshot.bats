#!/usr/bin/env bats
# #707: the real-user scenario `mapsnapshot` in tools/l3-suite.sh (L3, the real
# Claude Code TUI): the user maps a codebase whose tests have a failing case, and
# .vbw/map.md writes the result "as of <short commit>, <date>", never as current,
# with no advice resting on it. Judged in the map, git and the transcripts' tool
# calls, never on screen. As in tests/l3-leaveout.bats these tests do not run
# Claude Code (L1): they hold the scenario's structure, and its committed result
# once a run wrote one, to facts from files.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "#707: the mapsnapshot scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_mapsnapshot()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw mapsnapshot
  sed -n '1,20p' "$SUITE" | grep -qw mapsnapshot
}

@test "#707: it seeds a failing test, runs /vbw:map and judges .vbw/map.md, git and the transcripts" {
  [ -n "$(body mapsnapshot)" ]
  body mapsnapshot | grep -q 'result_write mapsnapshot '
  body mapsnapshot | grep -qi 'fixture='
  sed -n '/^mapsnapshot_seed()/,/^}/p' "$SUITE" | grep -qF 'not ok 2 no name greets the world'
  body mapsnapshot | grep -qF 'start="/vbw:map"'
  body mapsnapshot | grep -qF '.vbw/map.md'
  body mapsnapshot | grep -qF 'rev-parse --short HEAD'
  body mapsnapshot | grep -qF 'as of'
  body mapsnapshot | grep -qF 'transcript_tool_called'
  if body mapsnapshot | grep -qE 'screen \|.*grep'; then false; fi
}

@test "#707: the result states each fact the scenario judged" {
  local k
  for k in map_written scout_ran_tests seed_commit head_at_end tag_line result_lines untagged_result_lines advice_lines; do
    body mapsnapshot | grep -qF "$k"
  done
}

@test "#707: a committed result of the mapsnapshot scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/mapsnapshot.json"
  [ -f "$f" ] || skip "no mapsnapshot result committed yet: a run writes it"
  jq -e '.scenario == "mapsnapshot" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)
    and .facts.scout_ran_tests == true and .facts.result_lines >= 1 and (.facts.tag_line | length > 0)
    and .facts.untagged_result_lines == "" and .facts.advice_lines == ""' "$f"
}
