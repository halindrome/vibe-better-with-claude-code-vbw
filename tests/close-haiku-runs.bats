#!/usr/bin/env bats
# R186: scripted runs (L2) of the closing step on Haiku. tools/close-haiku-run.sh
# builds a practice project in .vbw/runtime/scratch/, opens a run, starts the
# real workflow in a headless Claude Code session with this tree's plugin and a
# Lead model that is not Haiku, and writes what happened to
# tools/baseline/results/close-haiku/<scenario>.json: the closing agent's model,
# the effort the workflow sent it, its answer, the commands it ran in order,
# whether a run was still open afterwards and, in a fix round, each fix's state
# in the record. Scenarios: building, fixing, and long-fix (a vbw fix done
# longer than one shell command's 10-minute limit). These tests do not run
# Claude Code (L1): they hold the tool's shape and the committed results,
# written by the runs, not by a person.

load helper

TOOL="$REPO_ROOT/tools/close-haiku-run.sh"
RESULTS="$REPO_ROOT/tools/baseline/results/close-haiku"
EFFORTS="$PLUGIN_ROOT/lib/efforts.json"

# The checks every committed result passes, whatever its scenario.
COMMON='def at($p): (.commands | map(test($p)) | index(true));
  .evidence_level == "L2" and (.fixture | type == "string" and length > 0) and (.at | type == "string" and length > 0)
  and (.claude_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+")) and (.cost_usd | type == "number" and . > 0)
  and (.profile | IN("quality", "balanced", "budget"))
  and (.lead_model | type == "string" and length > 0 and (ascii_downcase | contains("haiku") | not))
  and .close.label == "close run" and (.close.model | type == "string" and (ascii_downcase | contains("haiku")))
  and .close.effort_sent == $e[0][.profile].lead.close and .close.answer.ended == true
  and .run_open_after == false
  and (.commands | type == "array" and all(.[]; type == "string"))
  and at("vbw run confirm") != null and at("vbw run end") != null and at("vbw run confirm") < at("vbw run end")
  and (.not_tested | type == "array" and length > 0)'

# The fix round's own checks: fix done first, and the fixes it reports closed and open are the record's.
FIXES='def at($p): (.commands | map(test($p)) | index(true));
  at("vbw fix done") != null and at("vbw fix done") < at("vbw run confirm")
  and .close.answer.fixdone == "ran"
  and (.fixes | type == "array" and length > 0 and all(.[]; (.id | type == "string") and (.status | type == "string")))
  and ((.fixes | map({(.id): .status}) | add) as $s
    | all(.close.answer.closed[]; $s[.] == "fixed") and all(.close.answer.open[]; $s[.fix] == "open"))
  and ((.close.answer.closed + [.close.answer.open[].fix]) | sort) == ([.fixes[].id] | sort)'

# result SCENARIO: the committed result file, or a failure naming the run to do.
result() {
  [ -f "$RESULTS/$1.json" ] || {
    echo "the $1 run has not been done: no tools/baseline/results/close-haiku/$1.json is committed (run: bash tools/close-haiku-run.sh $1)"
    return 1
  }
}

@test "R186: the tool names its three scenarios, builds its project in .vbw/runtime/scratch and never in /tmp" {
  [ -f "$TOOL" ]
  sed -n '1,30p' "$TOOL" | grep -qw building
  sed -n '1,30p' "$TOOL" | grep -qw fixing
  sed -n '1,30p' "$TOOL" | grep -qw long-fix
  grep -q '\.vbw/runtime/scratch' "$TOOL"
  grep -q 'tools/baseline/results/close-haiku' "$TOOL"
  ! grep -qE '(^|[^A-Za-z_])/tmp' "$TOOL"
}

@test "R186: the tool refuses a missing or unknown scenario with its usage, before anything runs" {
  vbw_setup
  run bash "$TOOL" < /dev/null
  [ "$status" -eq 2 ] && [[ "$output" == *usage* ]] || { echo "$output"; vbw_teardown; false; }
  run bash "$TOOL" sideways < /dev/null
  [ "$status" -eq 2 ] && [[ "$output" == *usage* ]] || { echo "$output"; vbw_teardown; false; }
  vbw_teardown
}

@test "R186: a scripted building run: the closing step ran on Haiku with the profile's effort, confirmed, ended the run" {
  result building
  jq -e --slurpfile e "$EFFORTS" "$COMMON"' and .scenario == "building"
    and (.commands | any(test("vbw fix done")) | not)' "$RESULTS/building.json" || { cat "$RESULTS/building.json"; false; }
}

@test "R186: a scripted fixing run: on Haiku, fix done, then confirm, then run end; the fixes it reports match the record" {
  result fixing
  jq -e --slurpfile e "$EFFORTS" "$COMMON"' and .scenario == "fixing"' "$RESULTS/fixing.json" || { cat "$RESULTS/fixing.json"; false; }
  jq -e "$FIXES" "$RESULTS/fixing.json" || { cat "$RESULTS/fixing.json"; false; }
}

@test "R186: a long fix round on Haiku: a vbw fix done past 10 minutes moved to the background is waited for, read whole, then confirm and run end" {
  result long-fix
  jq -e --slurpfile e "$EFFORTS" "$COMMON"' and .scenario == "long-fix"
    and (.fixdone.seconds | type == "number" and . > 600) and .fixdone.backgrounded == true' "$RESULTS/long-fix.json" \
    || { cat "$RESULTS/long-fix.json"; false; }
  jq -e "$FIXES" "$RESULTS/long-fix.json" || { cat "$RESULTS/long-fix.json"; false; }
}
