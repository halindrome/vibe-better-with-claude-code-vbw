#!/usr/bin/env bats
# The proof's scope check (docs/proof.md, Scope) judges each plan commit by what
# its plan allowed when it was made, not only by today's record: a plan's own
# file, or a check file a mutation survivor let it strengthen, that a later
# change renamed or dropped (a check's test file renamed for the project's test
# runner, found 2026-10-25 in a user project) stays in scope. A file no version
# of the record since the commit allowed is still a violation, and the user can
# accept one: a decision recorded after the commit that names both its commit
# (the 12 characters the violation shows) and the file. L1: the kernel on a
# fixture project, the record's versions committed as VBW commits them.

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
    | (.requirements[] | select(.id == "R1")).rules = [{text:"a customer can pay", check:"C1", plan:"P1.1"}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:.milestone.id}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done",
        mutations:[{rule:{req:"R1", text:"a customer can pay"}, what:"pay prints unpaid", files:["src/pay.txt"], checks:{C1:"green"},
          result:"survivor", at:"2026-10-25T10:00:00Z", head:"0000000000000000000000000000000000000000"}]}]'
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
}

# plan_commit FILE TEXT: P1.1 changes FILE through a plan commit.
plan_commit() {
  printf '%s\n' "$2" >> "$1"
  git add "$1" && git commit -q -m "feat(pay): $1" -m "VBW-Plan: P1.1"
}

# record_commit FILTER: the record changes as VBW changes it, and is committed.
record_commit() { edit_record "$1" && git commit -q -m "chore(vbw): record" -- .vbw/record.json; }

@test "a check file a survivor let the plan strengthen, renamed afterwards, keeps that commit in scope" {
  plan_commit tests/pay.sh '# stronger'
  git mv tests/pay.sh tests/pay.test.sh && git commit -q -m "test: the runner's name"
  record_commit '.checks[0].files = ["tests/pay.test.sh"] | .checks[0].run = ["sh", "tests/pay.test.sh"]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [[ "$output" == *"scope ok"* ]] || { echo "$output"; false; }
  jq -e '.evidence.scope == []' .vbw/record.json
}

@test "a plan file the plan no longer lists keeps its earlier commit in scope" {
  plan_commit src/pay.txt 'paid'
  git mv src/pay.txt src/paid.txt && git commit -q -m "refactor: rename"
  record_commit '.plans[0].files = ["src/paid.txt"] | .checks[0].run = ["sh", "tests/pay.sh"]'
  printf 'grep -qx paid src/paid.txt\n' > tests/pay.sh && git commit -q -am "test: follow the rename"
  "$VBW" approve > /dev/null
  vbw_run prove
  [[ "$output" == *"scope ok"* ]] || { echo "$output"; false; }
}

@test "a file no version of the record allowed the plan stays a violation; the user's decision naming the commit and the file accepts it, and nothing else" {
  plan_commit src/other.txt 'sneaky'
  plan_commit src/third.txt 'also'
  local h1 h2
  h1=$(git rev-parse HEAD~1 | cut -c1-12)
  h2=$(git rev-parse HEAD | cut -c1-12)
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"$h1 (P1.1) changed src/other.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  "$VBW" decide "Accept $h1: it adds src/other.txt for the receipts" "the user's choice" > /dev/null
  "$VBW" decide "Accept src/third.txt" > /dev/null
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" != *"src/other.txt"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$h2 (P1.1) changed src/third.txt, which is not in the plan"* ]] || { echo "$output"; false; }
  jq -e --arg h "$h2" '.evidence.scope == ["\($h) (P1.1) changed src/third.txt, which is not in the plan"]' .vbw/record.json
}

@test "the docs say how a commit is judged and how the user accepts a violation" {
  grep -q 'what its plan allowed when it was made' "$REPO_ROOT/docs/proof.md"
  grep -q 'names both the commit' "$REPO_ROOT/docs/proof.md"
  sed -n '/^\*\*scope\*\*/,/^\*\*/p' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -q 'vbw decide'
}
