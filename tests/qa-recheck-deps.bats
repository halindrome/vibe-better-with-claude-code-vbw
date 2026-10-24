#!/usr/bin/env bats
# R49 (docs/proof.md): a phase is also checked again when the tests of a phase
# it builds on changed, even if its own inputs did not. A phase builds on
# another when one of its plans comes after a plan of the other. The rule is
# transitive and survives an interrupted QA round. Phases may interleave (a
# plan of one comes after a plan of the other, and the reverse): the plans stay
# acyclic (the record refuses a plan cycle), so that is no problem; vbw next
# lists such phases in qa.interleaved and vbw show qa notes them, and each is
# still checked again for the other's tests.

load helper
load qa-recheck-helper
load fixture-helper

# The projects the tests start from, each built once per file.
setup_file() {
  fixture_build p2chain qa_project 2 chain
  fixture_build p3chain qa_project 3 chain
  fixture_build base2 qa_base 2
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# retest N: a stricter check file for phase N, still passing; approve and prove.
retest() {
  printf '# stricter\n' >> "tests/p$1.sh"
  git add "tests/p$1.sh" && git commit -q -m "test(p$1): stricter"
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
}

@test "R49: a phase whose dependency's tests changed is checked again though its own inputs did not change" {
  fixture_copy p2chain
  qa_pass P1 P2
  retest 1
  [ "$(listed)" = '["P1","P2"]' ]
  next_json | jq -e '.qa.recheck.P2 | any(.[]; contains("P1"))'
  next_json | jq -e '.qa.recheck.P2 | any(.[]; test("builds on P1"))'
}

@test "R49: it is transitive: A changes, B builds on A, C builds on B, and all three are checked again" {
  fixture_copy p3chain
  qa_pass P1 P2 P3
  retest 1
  [ "$(listed)" = '["P1","P2","P3"]' ]
  next_json | jq -e '.qa.recheck.P3 | length > 0'
}

@test "R49: a change in the middle checks it and what builds on it, not what it builds on" {
  fixture_copy p3chain
  qa_pass P1 P2 P3
  retest 2
  [ "$(listed)" = '["P2","P3"]' ]
  next_json | jq -e '.qa.standing == ["P1"]'
}

@test "R49: a dependency on a phase that is not re-checked adds nothing" {
  fixture_copy p3chain
  qa_pass P1 P2 P3
  qa_touch 3
  [ "$(listed)" = '["P3"]' ]
  next_json | jq -e '.qa.standing == ["P1","P2"]'
}

@test "R49: a dependent that has itself never passed is already included and listed once" {
  fixture_copy p3chain
  qa_pass P1 P3
  retest 1
  [ "$(listed)" = '["P1","P2","P3"]' ]
  next_json | jq -e '.qa.recheck.P2 | length >= 1'
}

@test "R49: when the changed phase passes again but its dependent was not recorded, the dependent is still checked" {
  fixture_copy p2chain
  qa_pass P1 P2
  retest 1
  qa_pass P1
  [ "$(listed)" = '["P2"]' ]
  next_json | jq -e '.qa.recheck.P2 | any(.[]; contains("P1"))'
}

@test "R49: when both are checked again, every pass stands and the milestone can ship" {
  fixture_copy p2chain
  qa_pass P1 P2
  retest 1
  qa_pass P1 P2
  [ "$(listed)" = '[]' ]
  next_json | jq -e '.action == "ship" and .qa.standing == ["P1","P2"]'
}

@test "R49: interleaved phases (each builds on the other through acyclic plans) are no problem: noted, not hung, still checked for each other" {
  fixture_copy base2
  jq -nc '{phases: [{id: "P1", title: "One", reqs: ["R1"], tier: "standard"}, {id: "P2", title: "Two", reqs: ["R2"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "a", reqs: ["R1"], files: ["src/p1.txt"], after: ["P2.1"]},
            {id: "P1.2", phase: "P1", title: "b", reqs: ["R1"], files: ["src/p1b.txt"], after: []},
            {id: "P2.1", phase: "P2", title: "c", reqs: ["R2"], files: ["src/p2.txt"], after: []},
            {id: "P2.2", phase: "P2", title: "d", reqs: ["R2"], files: ["src/p2b.txt"], after: ["P1.2"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/p1.sh"], files: ["tests/p1.sh"]}, {id: "C2", req: "R2", run: ["sh", "tests/p2.sh"], files: ["tests/p2.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  local f
  for f in p1 p1b p2 p2b; do printf 'x\n' > "src/$f.txt"; done
  printf 'part1\n' > src/p1.txt
  printf 'part2\n' > src/p2.txt
  git add -A && git commit -q -m "feat: all"
  edit_record '.plans |= map(.status = "done")'
  "$VBW" prove --full > /dev/null
  qa_pass P1 P2
  printf 'extra\n' >> src/p1.txt
  git add src/p1.txt && git commit -q -m "fix: touch"
  "$VBW" prove --full > /dev/null
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.qa.problems == [] and .qa.interleaved == ["P1", "P2"]' || { printf '%s' "$output" | jq .qa; false; }
  vbw_run show qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"note: phases P1 and P2 build on each other through their plans"* ]] || { echo "$output"; false; }
  [[ "$output" != *"problem:"* ]] || { echo "$output"; false; }
}

@test "R49: a plan that comes after a plan or a phase that does not exist is reported by name, not silently dropped" {
  fixture_copy p2chain
  edit_record '(.plans[] | select(.id == "P2.1")).after = ["P9.9"]'
  vbw_run next --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"P9.9"* ]]
  edit_record '(.plans[] | select(.id == "P2.1")).after = ["P1.1"] | (.plans[] | select(.id == "P2.1")).phase = "P9"'
  vbw_run next --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"P9"* ]]
}

@test "R49: docs/next.md names qa.interleaved and no longer counts interleaving among the problems" {
  local t
  t=$(tr '\n' ' ' < "$REPO_ROOT/docs/next.md" | tr -s ' ')
  [[ "$t" == *'`{recheck, standing, interleaved, problems}`'* ]] || { echo "docs/next.md lacks the key"; false; }
  [[ "$t" == *'`problems` lists plan links that point nowhere, and a loop among the plans themselves.'* ]] || { echo "docs/next.md does not say what a problem is"; false; }
  ! grep -qF 'QA reports interleaved phases as a cycle' "$REPO_ROOT/docs/ideas.md" || { echo "the built idea is still listed"; false; }
}
