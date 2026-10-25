#!/usr/bin/env bats
# T162 (docs/proof.md): the proof's scope check judges the plans of the
# current milestone only. A shipped milestone's commits were judged by the
# proofs before its ship; judged again by today's record they can fail for
# reasons that did not exist then (a later check reading a test file that a
# shipped plan strengthened), and the loop parked T94 on such a false alarm.
# It judges only the record's own history ("Whose commits VBW judges", lib/
# history.sh): plan ids restart with a new record, so a commit older than the
# record's first commit is never taken for today's plan of the same id.
# L1: the kernel on a fixture project.

load helper

KEEP_PROTECTED='if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .shipped = [{id:"M0", title:"Old", at:"2026-01-01T00:00:00Z"}]
    | .phases = [{id:"P0", title:"Old", reqs:["R1"], milestone:"M0"},
                 {id:"P1", title:"Pay", reqs:["R1"], milestone:.milestone.id}]
    | .plans = [{id:"P0.1", phase:"P0", title:"Old", reqs:["R1"], files:["src/old.txt"], after:[], status:"done"},
                {id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
}

# retired_roadmap: the project's history starts again with an earlier roadmap's
# commits, whose trailers name P1.1 and change files today's P1.1 does not plan;
# then the record is born at approval and today's P1.1 is built through VBW.
retired_roadmap() {
  rm -rf .git src/pay.txt
  vbw_git_project
  mkdir -p legacy
  printf 'old\n' > legacy/app.txt
  git add legacy/app.txt
  git commit -q -m "feat: old" -m "VBW-Plan: P1.1"
  printf 'older\n' > legacy/app.txt
  git commit -q -am "feat: old again" -m "VBW-Plan: P1.1"
  edit_record '.plans[1].status = "planned"'
  "$VBW" approve > /dev/null
  git log --format=%s -- .vbw/record.json | grep -q . || { echo "approve did not commit the record"; false; }
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
}

@test "T162: a shipped milestone's commit outside its plan does not fail today's proof" {
  printf 'old\n' > src/elsewhere.txt
  git add src/elsewhere.txt
  git commit -q -m "feat(old): long ago" -m "VBW-Plan: P0.1"
  "$VBW" approve > /dev/null
  vbw_run prove
  [[ "$output" == *"scope ok"* ]] || { echo "$output"; false; }
  jq -e '(.evidence.scope // []) | length == 0' .vbw/record.json
}

@test "T162: the current milestone's commit outside its plan still fails the proof" {
  printf 'sneaky\n' > src/other.txt
  git add src/other.txt
  git commit -q -m "feat(pay): more" -m "VBW-Plan: P1.1"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"(P1.1) changed src/other.txt, which is not in the plan"* ]]
}

@test "a retired roadmap's commits, older than the record, are not judged by today's plan of the same id" {
  retired_roadmap
  vbw_run prove
  [[ "$output" == *"scope ok"* ]] || { echo "$output"; false; }
  jq -e '.evidence.scope == []' .vbw/record.json
}

@test "a commit after the record's birth outside its plan still fails the proof" {
  retired_roadmap
  printf 'sneaky\n' > src/other.txt
  git add src/other.txt
  git commit -q -m "feat(pay): more" -m "VBW-Plan: P1.1"
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"(P1.1) changed src/other.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  [[ "$output" != *"legacy/app.txt"* ]] || { echo "$output"; false; }
  jq -e '(.evidence.scope | length) == 1' .vbw/record.json
}
