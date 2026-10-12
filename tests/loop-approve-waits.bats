#!/usr/bin/env bats
# R178 (P127; docs/loop.md): any other contract waits for the user exactly as
# today: a requirement whose text differs from its item's recorded text by one
# character, an extra requirement in the milestone, a requirement matching an
# item not on this loop's list, no loop on, a loop that is stopping, a contract
# that is not ready (a missing check file; spec and record differing). In each
# case vbw next answers approve (gate true) or contract as it does now, nothing
# is approved, no consent is granted and no decision is recorded. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

contract_state() { "$VBW" show contract < /dev/null | sed -n '1s/^contract [0-9a-f]* (\(.*\))$/\1/p'; }
consent_count() { jq '.granted | length' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/consent.json"; }

# planned TEXT...: the milestone holds a requirement per TEXT, planned with a check.
planned() {
  local t q
  for t in "$@"; do "$VBW" spec add auto "$t" > /dev/null; done
  q=$(item_req "$1")
  loop_plan "$q" P2
  [ $# -eq 1 ] || jq -c --arg q "$(item_req "$2")" '{phases: [{id: "P3", title: "More", reqs: [$q], goal: "more", criteria: ["more"]}],
    plans: [{id: "P3.1", phase: "P3", title: "More", reqs: [$q], files: ["src/more.txt"], after: [], tasks: ["more"]}],
    checks: [{id: "C3", req: $q, run: ["sh", "tests/greet.sh"], files: ["tests/greet.sh"]}],
    rules: [{req: $q, text: "more", check: "C3"}]}' | "$VBW" apply --add > /dev/null
  git add -A && git commit -q -m "chore(test): planned"
}

# waits ACTION: the loop step approves nothing; vbw next answers ACTION as today.
waits() {
  local decisions consents
  decisions=$(jq '.decisions | length' .vbw/record.json)
  consents=$(consent_count)
  run loop_next s1
  [ "$status" -eq 0 ] || { echo "loop next: $output"; return 1; }
  [ "$(contract_state)" = "NOT APPROVED" ] || { echo "approved: $output"; return 1; }
  [ "$(consent_count)" -eq "$consents" ] || { echo "consent granted"; return 1; }
  [ "$(jq '.decisions | length' .vbw/record.json)" -eq "$decisions" ] || { echo "a decision was recorded"; return 1; }
  [ "$(next_action)" = "$1" ] || { echo "vbw next says $(next_action), not $1"; return 1; }
  if [ "$1" = approve ]; then VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null | jq -e '.gate == true' > /dev/null; fi
}

@test "R178: a requirement whose text differs from its item's by one character waits for the user" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  planned "Visitors can read a greeting!"
  waits approve
}

@test "R178: an extra requirement in the milestone waits for the user" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  planned "Visitors can read a greeting" "Visitors can search the notes"
  waits approve
}

@test "R178: a requirement that matches an item not on this loop's list waits for the user" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  planned "Visitors can read a farewell"
  waits approve
}

@test "R178: with no loop on, nothing is approved and the loop step says the loop is off" {
  planned "Visitors can read a greeting"
  run loop_next s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "off"' || { echo "$output"; false; }
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(next_action)" = approve ]
}

@test "R178: a loop that is stopping approves nothing" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  planned "Visitors can read a greeting"
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  local consents
  consents=$(consent_count)
  run loop_next s1
  printf '%s' "$output" | jq -e '.action == "stopped"' || { echo "$output"; false; }
  [ "$(contract_state)" = "NOT APPROVED" ]
  [ "$(consent_count)" -eq "$consents" ]
  [ "$(next_action)" = approve ]
}

@test "R178: a contract that is not ready (a missing check file) is not approved: vbw next answers contract as today" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  planned "Visitors can read a greeting"
  git rm -q tests/greet.sh && git commit -q -m "chore(test): check file gone"
  waits contract
}

@test "R178: a contract whose spec and record differ is not approved: vbw next answers contract as today" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  planned "Visitors can read a greeting"
  sed -i.bak 's/Visitors can read a greeting/Visitors can read a greeting now/' .vbw/spec.md && rm -f .vbw/spec.md.bak
  waits contract
}
