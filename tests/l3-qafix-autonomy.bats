#!/usr/bin/env bats
# R201, phase P160: the qafix scenario of tools/l3-suite.sh, run in the real
# Claude Code app (L3), opens with 'Use guided autonomy for this project.' in the
# user's own words. The 2.0.40 run (2026-10-19) asked for guided and ran
# balanced. The scenario reads the setting back ('vbw config autonomy', expecting
# guided) and records that it was written before the first run: in the session
# transcript the settings write comes before the record's first 'Contract
# approved' decision and before the first run lease. As in tests/l3-results.bats
# these tests do not run Claude Code (L1): they hold the scenario's structure and
# the result it wrote under tools/l3-results/. The result is written by the run,
# not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/qafix.json"

body() { sed -n '/^scenario_qafix()/,/^}/p;/^autonomy_written_before_run()/,/^}/p' "$SUITE"; }

@test "R201: the qafix scenario states guided autonomy in the user's words, reads the setting back with vbw config autonomy and expects guided" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_qafix"; false; }
  body | grep -E '^[[:space:]]*start=' | grep -qi 'guided autonomy' || { echo "the user's first words do not ask for guided autonomy"; false; }
  body | grep -E '^[[:space:]]*fixture=' | grep -qi 'guided' || { echo "the fixture does not name the guided autonomy stated in words"; false; }
  body | grep -q 'config autonomy' || { echo "scenario_qafix does not read the setting back (vbw config autonomy)"; false; }
  body | grep -qE 'autonomy: \$[a-z_]+' || { echo "scenario_qafix does not record the fact autonomy"; false; }
  body | grep -E 'expect ' | grep -q 'guided' || { echo "scenario_qafix does not expect guided"; false; }
}

@test "R201: the scenario records that the setting was written before the first run: the settings write in the transcript comes before the first 'Contract approved' decision and the first run lease" {
  body | grep -q 'autonomy_set_before_first_run' || { echo "scenario_qafix does not record autonomy_set_before_first_run"; false; }
  body | grep -q 'config set autonomy' || { echo "scenario_qafix does not look for the settings write (config set autonomy) in the transcript"; false; }
  body | grep -q 'transcripts' || { echo "scenario_qafix does not read the session transcript"; false; }
  body | grep -q 'Contract approved' || { echo "scenario_qafix does not read the first 'Contract approved' decision"; false; }
  body | grep -qE 'run start|Workflow' || { echo "scenario_qafix does not read the first run lease"; false; }
  body | grep -E 'expect ' | grep -qE 'before the first run|autonomy_set_before_first_run' || { echo "the fact is not expect()ed"; false; }
  body | grep -E 'passed=false' | grep -q 'guided' || { echo "the autonomy facts are not in the passed chain"; false; }
}

@test "R201: a committed result of the qafix scenario passed with autonomy guided, set before the first run, and the deviation restored, at L3" {
  [ -f "$RESULT" ] || { echo "the qafix scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "qafix" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-19")
    and (.fixture | type == "string" and length > 0)
    and .facts.autonomy == "guided" and .facts.autonomy_set_before_first_run == true
    and .facts.asked_before_qa == true and .facts.restore_fix == true and .facts.restored_at_head == true
    and (.facts.deviation | type == "string" and length > 0)
    and .facts.fix_rounds >= 1 and .facts.final_qa_verdict == "pass" and .facts.phase_proved == true
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

# The comparison itself, run on a fixture record and fixture transcripts.
fixture() { # fixture WRITE_AT [APPROVAL_AT|none]  -> writes $BATS_TEST_TMPDIR/record.json and transcript.jsonl
  local approval='[{"text":"Contract approved by the user","at":"'"${2:-2026-10-19T10:00:05Z}"'"}]'
  [ "${2:-}" = none ] && approval='[{"text":"Something else","at":"2026-10-19T10:00:05Z"}]'
  printf '{"decisions":%s}\n' "$approval" > "$BATS_TEST_TMPDIR/record.json"
  jq -nc --arg t "$1" '{type:"assistant",timestamp:$t,message:{content:[{type:"tool_use",name:"Bash",input:{command:"vbw config set autonomy guided"}}]}}' > "$BATS_TEST_TMPDIR/transcript.jsonl"
}
before() {
  sed -n '/^autonomy_written_before_run()/,/^}/p' "$SUITE" > "$BATS_TEST_TMPDIR/fn.sh"
  [ -s "$BATS_TEST_TMPDIR/fn.sh" ] || { echo "tools/l3-suite.sh has no autonomy_written_before_run"; return 2; }
  . "$BATS_TEST_TMPDIR/fn.sh"
  autonomy_written_before_run "$BATS_TEST_TMPDIR/record.json" < "$BATS_TEST_TMPDIR/transcript.jsonl"
}

@test "R201: the comparison passes when the settings write is earlier than the first Contract approved decision" {
  fixture 2026-10-19T10:00:01Z
  before
}

@test "R201: the comparison fails when the settings write is later than the first Contract approved decision" {
  fixture 2026-10-19T10:00:09Z
  run before
  [ "$status" -eq 1 ]
}

@test "R201: a record with no Contract approved decision is not treated as before" {
  fixture 2026-10-19T10:00:01Z none
  run before
  [ "$status" -eq 1 ]
}

@test "R201: a record that cannot be read is not treated as before" {
  fixture 2026-10-19T10:00:01Z
  printf 'not json' > "$BATS_TEST_TMPDIR/record.json"
  run before
  [ "$status" -eq 1 ]
}
