#!/usr/bin/env bats
# R166 (docs/proof.md): QA verdicts and shipping accept a current proof whose
# results ran or were reused; they refuse a stale proof (vbw prove) and a proof
# in which the quick command stood in for the test command or an approved full
# command was skipped (vbw prove --full). vbw next asks for vbw prove --full
# only in that incomplete case. A proof recorded before the fields of the
# reuse rule existed (no per-result "reused") is judged the same way. L1: the
# evidence is written into the record, not produced by vbw prove.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# proven FULL CHECKS COMMANDS: a built phase whose only requirement is proven
# by evidence with the given full flag, checks and commands.
proven() {
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .commands = {test: ["sh","t.sh"], quick: ["sh","q.sh"], lint: ["sh","l.sh"]}
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"done"}]' .vbw/record.json > "$TEST_ROOT/e.json"
  local hash tree
  cp "$TEST_ROOT/e.json" .vbw/record.json
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  jq --arg h "$hash" --arg t "$tree" --argjson f "$1" --argjson c "$2" --argjson m "$3" \
    '.evidence = {at: "2026-10-01T09:00:00Z", contract: $h, tree: $t, head: $t, passed: true, checks: $c, commands: $m, scope: []}
     | if $f == null then . else .evidence.full = $f end' .vbw/record.json > "$TEST_ROOT/n.json" && cp "$TEST_ROOT/n.json" .vbw/record.json
  vbw_consent_contract
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/cmd-approve.sh"; approve_commands "$(cat "$VBW_RECORD")" > /dev/null'
}

REUSED='{"C1": {"status":"pass","exit":0,"seconds":1,"tail":"","reused":true}}'
RAN='{"C1": {"status":"pass","exit":0,"seconds":1,"tail":""}}'
PASS='{"status":"pass","exit":0,"seconds":1,"tail":""}'
SKIP='{"status":"skipped","exit":null,"seconds":0,"tail":"not approved"}'

@test "R166: vbw qa record accepts a proof whose results were reused" {
  proven false "$REUSED" "{\"test\": $PASS, \"lint\": $PASS}"
  vbw_run qa record P1 pass quick "reused"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.phases[0].qa.result == "pass"' .vbw/record.json
}

@test "R166: vbw qa record refuses a stale proof and says vbw prove" {
  proven false "$REUSED" "{\"test\": $PASS}"
  printf 'x\n' > a.js && git add a.js && git commit -q -m "feat: a"
  vbw_run qa record P1 pass quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"the code changed since the last proof"* ]] || { echo "$output"; false; }
}

@test "R166: vbw qa record refuses a proof in which the quick command stood in for the test command, and says vbw prove --full" {
  proven false "$RAN" "{\"quick\": $PASS, \"lint\": $PASS}"
  vbw_run qa record P1 pass quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]]
}

@test "R166: vbw qa record refuses a proof in which an approved full command was skipped" {
  proven false "$RAN" "{\"test\": $PASS, \"lint\": $SKIP}"
  vbw_run qa record P1 pass quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw prove --full"* ]]
}

@test "R166: vbw next asks for vbw prove --full only for the quick stand-in or a skipped full command" {
  proven false "$RAN" "{\"quick\": $PASS}"
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "prove" and .detail.full == true' || { echo "$output"; false; }
  proven false "$RAN" "{\"test\": $PASS, \"lint\": $SKIP}"
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "prove" and .detail.full == true' || { echo "$output"; false; }
}

@test "R166: after a proof that reused results vbw next goes on to QA" {
  proven false "$REUSED" "{\"test\": $PASS, \"lint\": $PASS}"
  vbw_run next --json
  printf '%s' "$output" | jq -e '.action == "qa" and (.detail.full // false) == false' || { echo "$output"; false; }
}

@test "R166: vbw ship accepts a proof that reused results" {
  proven false "$REUSED" "{\"test\": $PASS, \"lint\": $PASS}"
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R166: vbw ship refuses a proof in which the quick command stood in" {
  proven true "$RAN" "{\"test\": $PASS}"
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq '.evidence.full = false | .evidence.commands = {quick: {status:"pass",exit:0,seconds:1,tail:""}}' .vbw/record.json > "$TEST_ROOT/n.json" && cp "$TEST_ROOT/n.json" .vbw/record.json
  vbw_run ship
  [ "$status" -ne 0 ]
  [[ "$output" == *"prove"* ]]
}

@test "R166: a proof recorded before the reuse fields existed (full true, or no full flag) is accepted" {
  proven true "$RAN" "{\"test\": $PASS}"
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  proven null "$RAN" "{\"test\": $PASS}"
  vbw_run qa record P1 pass quick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
