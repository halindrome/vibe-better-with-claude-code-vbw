#!/usr/bin/env bats
# T178 (docs/next.md, docs/rigor.md): the round of a QA step (round.tiers, the
# depth chosen for the size and risk of the change; round.suite; round.focus)
# is handed to the QA workflow by the router, which starts the QA run first
# (vbw run start qa) and so can read vbw next --json on either side of it. A
# small change got a standard check instead of a quick one when the router
# read the answer after the run opened and found no round to hand over. While
# the caller's own QA run is open, vbw next --json answers run and carries the
# same round the qa answer did. A run of another session, and any run that is
# not QA, carries none. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

edit_record() { jq "$1" .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json; }

NONE='["requirements: 1","files: 1 (10 bytes)","risk: none","breaks: none","tests: project test command"]'

# qa_due: a built, proven, one-file phase of a standard tier whose QA verdict is on
# other code, so QA is next (the shape of a small change added to a milestone).
qa_due() {
  jq --argjson r "$NONE" '
      .requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .settings.profile = "balanced"
      | .commands = {test: ["sh", "t.sh"]}
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1", tier: "standard", reasons: $r, predicted: "standard"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"done"}]
      | .phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
  local hash tree
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  edit_record ".evidence = {at: \"2026-10-01T09:00:00Z\", contract: \"$hash\", tree: \"$tree\", full: true, passed: true, checks: {}, commands: {test: {command: \"test\", status: \"pass\", exit: 0, seconds: 7, tail: \"all 9 tests ok\"}}, scope: []}"
  vbw_consent_contract
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/cmd-approve.sh"; approve_commands "$(cat "$VBW_RECORD")" > /dev/null'
}

as() { local s="$1"; shift; VBW_SESSION_ID="$s" "$VBW" "$@" < /dev/null; }

@test "T178: the qa answer sizes a one-file standard phase quick and carries the proof's test run" {
  qa_due
  run as s1 next --json
  echo "$output" | jq -e '.action == "qa" and .round.tiers.P1 == "quick" and .rigor.P1.qa == "standard" and .round.suite.status == "pass"' || { echo "$output"; false; }
}

@test "T178: while the caller's QA run is open, vbw next answers run with the same round as the qa answer" {
  qa_due
  as s1 next --json > "$TEST_ROOT/before.json"
  jq -e '.action == "qa"' "$TEST_ROOT/before.json" > /dev/null
  as s1 run start qa > /dev/null
  run as s1 next --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.action == "run" and .detail.lease.kind == "qa"' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e --slurpfile b "$TEST_ROOT/before.json" '.round == $b[0].round and .round.tiers.P1 == "quick"' || { echo "$output"; false; }
}

@test "T178: a QA run opened without a session id (the caller unknown) carries the round too" {
  qa_due
  "$VBW" run start qa > /dev/null < /dev/null
  run "$VBW" next --json < /dev/null
  echo "$output" | jq -e '.action == "run" and .round.tiers.P1 == "quick"' || { echo "$output"; false; }
}

@test "T178: another session's QA run carries no round" {
  qa_due
  as s1 run start qa > /dev/null
  run as s2 next --json
  echo "$output" | jq -e '.action == "run" and (has("round") | not)' || { echo "$output"; false; }
}

@test "T178: an open run that is not QA carries no round" {
  qa_due
  as s1 run start plan > /dev/null
  run as s1 next --json
  echo "$output" | jq -e '.action == "run" and .detail.lease.kind == "plan" and (has("round") | not)' || { echo "$output"; false; }
}

# --- the QA workflow refuses a round that is not the object -------------------

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"

@test "T178: the QA workflow refuses a round that is not an object and starts no agent, instead of silently dropping the depth and the test run" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  local bad
  for bad in 0 '"0"' '[]' true; do
    run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" "{\"phases\":[\"P1\"],\"tier\":\"standard\",\"round\":$bad}" '{}'
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    printf '%s' "$output" | jq -e '(.calls | length) == 0 and (.result.error | test("round")) and .result.results == []' || { echo "round $bad: $output"; false; }
  done
}

@test "T178: the QA workflow still takes a missing, null or object round" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  local ok
  for ok in '' ',"round":null' ',"round":{}' ',"round":{"tiers":{"P1":"quick"},"suite":null}'; do
    run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" "{\"phases\":[\"P1\"],\"tier\":\"standard\"$ok}" '{}'
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label | test("^qa P"))] | length == 1' || { echo "round $ok: $output"; false; }
  done
}
