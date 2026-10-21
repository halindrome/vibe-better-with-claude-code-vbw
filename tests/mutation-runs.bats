#!/usr/bin/env bats
# R188 (P141): scripted runs (L2) of the mutation check on a real build.
# tools/mutation-run.sh standard|express builds a practice project in
# .vbw/runtime/scratch/ whose approved test for one rule cannot fail, starts the
# real building workflow in a headless Claude Code session with this tree's
# plugin, and writes what happened to tools/baseline/results/mutation/<scenario>.json,
# read from the record, vbw next and the session's transcripts, never typed by
# hand:
#   scenario, tier            standard or express
#   evidence_level            "L2"
#   fixture, at               the practice project, when the run ended
#   claude_version, cost_usd  the Claude Code version, the session's cost
#   minutes, minutes_added    the whole run, and the part the mutation step took
#   decision                  the vbw decide id that records the result (D...)
#   weak_rule                 {req, text}: the rule whose approved test cannot fail
#   mutations                 the plan's recorded breaks after the build
#   next_after_build          {action, files}: what vbw next asked before the proof
#   plan_status               the plan's status after the build
#   commands                  the Bash commands the session's agents ran, in order
# These tests do not run Claude Code (L1): they hold the tool's shape and the
# committed results.

load helper

TOOL="$REPO_ROOT/tools/mutation-run.sh"
RESULTS="$REPO_ROOT/tools/baseline/results/mutation"

COMMON='.evidence_level == "L2" and (.fixture | type == "string" and length > 0) and (.at | type == "string" and length > 0)
  and (.claude_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+")) and (.cost_usd | type == "number" and . > 0)
  and (.minutes | type == "number" and . > 0) and (.minutes_added | type == "number" and . >= 0)
  and (.decision | type == "string" and test("^D[0-9]+$"))
  and (.weak_rule | type == "object" and (.req | test("^R[0-9]+$")) and (.text | length > 0))
  and (.mutations | type == "array") and (.commands | type == "array" and all(.[]; type == "string"))
  and .plan_status == "done"'

@test "R188: the tool exists, parses, and takes standard or express only" {
  [ -x "$TOOL" ] || { echo "missing or not executable: $TOOL"; false; }
  bash -n "$TOOL"
  run "$TOOL" < /dev/null
  [ "$status" -eq 2 ] && [[ "$output" == *usage* ]] || { echo "$output"; false; }
  run "$TOOL" deep < /dev/null
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  head -n 30 "$TOOL" | grep -q 'L2'
  grep -q '.vbw/runtime/scratch' "$TOOL"
  grep -q 'tools/baseline/results/mutation' "$TOOL"
}

@test "R188: the standard run shows the weak test caught before QA: survivor, strengthened check file, approval before the proof, then red" {
  local r="$RESULTS/standard.json"
  [ -f "$r" ] || { echo "missing $r"; false; }
  jq -e "$COMMON"' and .scenario == "standard" and .tier == "standard" and .minutes_added > 0
    and (.weak_rule as $w | any(.mutations[]; .rule == $w and .result == "survivor")
      and any(.mutations[]; .rule == $w and .result == "red" and ((.strengthened // []) | length) > 0))
    and .next_after_build.action == "approve"
    and ([.mutations[] | (.strengthened // [])[]] - .next_after_build.files | length == 0)
    and any(.commands[]; test("vbw mutate"))' "$r" || { jq . "$r"; false; }
}

@test "R188: the express run of the same project has no mutation step and an unchanged plan done" {
  local r="$RESULTS/express.json"
  [ -f "$r" ] || { echo "missing $r"; false; }
  jq -e "$COMMON"' and .scenario == "express" and .tier == "express" and .minutes_added == 0
    and .mutations == [] and (any(.commands[]; test("vbw mutate")) | not)' "$r" || { jq . "$r"; false; }
}

@test "R188: both runs are of the same practice project" {
  [ -f "$RESULTS/standard.json" ] && [ -f "$RESULTS/express.json" ] || { echo "a result is missing"; false; }
  [ "$(jq -r .fixture "$RESULTS/standard.json")" = "$(jq -r .fixture "$RESULTS/express.json")" ]
}
