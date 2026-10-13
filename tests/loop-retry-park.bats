#!/usr/bin/env bats
# R179 (P129; docs/loop.md, Retry once, then park): at the escalate step, the
# first time for an item, the loop runs vbw fix retry for each escalated fix
# and continues, recording the retry against the item; a blocked plan is
# likewise reset once. A second escalation of the same item, a plan blocked
# again, or a scope violation parks the item through vbw loop park: it reverts
# the item's commits made since its milestone began with git revert commits
# (history kept, nothing rewritten; a file the user staged or edited by hand is
# left as it is); removes the item's requirement, phases, plans, checks, rules
# and fixes from the record and its line from .vbw/spec.md; marks the milestone
# parked with the reason and freezes its cost as a ship does; records a
# decision naming the item, the reason, the revert commits and how to bring the
# work back; leaves the backlog entry open; commits the record; then the loop
# starts the next item. After a park the project proves as before the item
# started. L1.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }

# built_and_broken: T1 planned, approved, built, then broken by a later commit, so the proof opens a fix.
built_and_broken() {
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  loop_break P2
  [ "$(step)" = prove ]
  loop_prove
  [ "$(step)" = fix ] || { cat "$TEST_ROOT/step.json"; return 1; }
  jq -e '.fixes[0].status == "open"' .vbw/record.json
}

escalated() { edit_record '(.fixes[] | select(.id == "F1")).status = "escalated"'; }

# parked_clean: the item's work is gone from the record and the spec, its milestone is parked, and nothing of VBW's is left uncommitted.
parked_clean() {
  jq -e '([.requirements[] | select(.text == "Visitors can read a greeting")] | length) == 0
    and ([.phases[] | select(.id == "P2")] | length) == 0 and ([.plans[] | select(.id == "P2.1")] | length) == 0
    and ([.checks[] | select(.id == "C2")] | length) == 0 and ([.fixes[] | select(.id == "F1")] | length) == 0
    and (.protected | index("tests/greet.sh") | not)' .vbw/record.json || { jq '{requirements, phases, plans, checks, fixes}' .vbw/record.json; return 1; }
  ! grep -q 'Visitors can read a greeting' .vbw/spec.md
  jq -e '.parked[0] | .id == "M2" and .title == "Visitors can read a greeting" and (.at | type == "string") and (.reason | length > 0)' .vbw/record.json || { jq .parked .vbw/record.json; return 1; }
  jq -e '.loop.items[0] | .status == "parked" and (.reason | length > 0)' .vbw/record.json
  jq -e '.todos[] | select(.id == "T1") | .status == "open"' .vbw/record.json
  [ -z "$(git status --porcelain -- .vbw)" ]
}

@test "R179: the first escalation of an item is retried (vbw fix retry) and recorded; the second parks it" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 50 > /dev/null
  built_and_broken
  escalated
  [ "$(next_action)" = escalate ]
  [ "$(step)" = fix ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.fixes[0].status == "open" and .loop.items[0].retried.fixes == ["F1"]' .vbw/record.json || { jq '{fixes, loop}' .vbw/record.json; false; }
  escalated
  figures s1 4 2000 200
  printf 'a note\n' >> README.md
  : > scratch.txt
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  parked_clean
  jq -e '.parked[0].reason | test("escalat")' .vbw/record.json
  # The commits were reverted with git revert: history kept, the files back as before the item.
  git log --format=%s | grep -q '^Revert "feat(greet): bye"'
  git log --format=%s | grep -q '^Revert "feat(greet): hello"'
  git log --format=%s | grep -q '^feat(greet): hello$'
  [ ! -f src/greet.txt ]
  [ ! -f tests/greet.sh ]
  [ -z "$(git ls-files -- src/greet.txt tests/greet.sh)" ]
  # The user's own edits and untracked files are left as they are: no reset --hard, no clean.
  grep -q 'a note' README.md
  [ -f scratch.txt ]
  # The cost is frozen as a ship freezes it; the decision names the item, the reason, the revert commits and how to bring the work back.
  jq -e '.costs.milestones.M2.total.usd == 2' .vbw/record.json || { jq .costs .vbw/record.json; false; }
  jq -e '[.decisions[] | select(.text | test("park"))] | last | .text | test("T1") and test("escalat") and test("[0-9a-f]{7}") and test("revert") and test("again")' .vbw/record.json \
    || { jq '.decisions[-3:]' .vbw/record.json; false; }
  # The loop went on to the next item.
  jq -e '.milestone.id == "M3" and .milestone.title == "Visitors can read a farewell" and .loop.items[1].status == "in_progress"' .vbw/record.json
}

@test "R179: after a park the project proves as before the item started, and the parked milestone is left behind like a shipped one" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 50 > /dev/null
  built_and_broken
  escalated
  step > /dev/null
  escalated
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  parked_clean
  jq -e '.milestone.id == "M2" and .milestone.status == "parked"' .vbw/record.json
  run env VBW_SESSION_ID=s1 "$VBW" prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true and .evidence.checks.C1.status == "pass" and (.evidence.checks | has("C2") | not)' .vbw/record.json
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "milestone" and .gate == true and (.instruction | test("parked"))' || { echo "$output"; false; }
  run "$VBW" status
  [[ "$output" == *"parked"* ]] || { echo "$output"; false; }
  run "$VBW" show roadmap
  [[ "$output" == *"M2"*"parked"* ]] || { echo "$output"; false; }
  "$VBW" milestone start "After the loop" > /dev/null
  jq -e '.milestone.id == "M3"' .vbw/record.json
}

@test "R179: a blocked plan is reset once; blocked again, the item is parked" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  "$VBW" plan block P2.1 "needs a decision" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  [ "$(next_action)" = unblock ]
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.plans[] | select(.id == "P2.1") | .status == "planned"' .vbw/record.json
  jq -e '.loop.items[0].retried.plans == ["P2.1"]' .vbw/record.json
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  "$VBW" plan block P2.1 "still needs a decision" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  parked_clean
  jq -e '.parked[0].reason | test("block")' .vbw/record.json
  jq -e '.milestone.id == "M3"' .vbw/record.json
}

@test "R179: a scope violation parks the item" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  [ "$(step)" = prove ]
  loop_prove
  edit_record '.evidence.scope = ["abc1234 feat(greet): hello changed src/other.txt outside P2.1"]'
  [ "$(next_action)" = scope ]
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  parked_clean
  jq -e '.parked[0].reason | test("scope")' .vbw/record.json
}

@test "R179: vbw loop park by hand with no item in progress refuses and names what to do" {
  run "$VBW" loop park
  [ "$status" -eq 1 ]
  [[ "$output" == *"Next: "* ]] || { echo "$output"; false; }
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  run "$VBW" loop park
  [ "$status" -eq 1 ]
  [[ "$output" == *"Next: "* ]] || { echo "$output"; false; }
  jq -e '.loop.items[0].status == "waiting" and (has("parked") | not)' .vbw/record.json
}

@test "R179 (F166): a commit that changes code and a .vbw file together is left in place and named, never skipped in silence" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 50 > /dev/null
  built_and_broken
  printf 'other\n' > src/other.txt
  printf 'note\n' > .vbw/notes.md
  git add -f src/other.txt .vbw/notes.md && git commit -q -m "chore: code and record together"
  escalated
  [ "$(step)" = fix ] || { cat "$TEST_ROOT/step.json"; false; }
  escalated
  figures s1 4 2000 200
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  # The item's own commits are reverted; the mixed one stays, its code in place, and the decision names it.
  git log --format=%s | grep -q '^Revert "feat(greet): bye"'
  ! git log --format=%s | grep -q 'Revert "chore: code and record together"'
  [ -f src/other.txt ] && grep -q other src/other.txt
  jq -e '[.decisions[] | select(.text | test("park"))] | last | .text | test("changes the record too")' .vbw/record.json \
    || { jq '.decisions[-2:]' .vbw/record.json; false; }
}

@test "R179 (F181): a commit touching a file the user edited by hand is left in place and named; the user's edit stays" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 50 > /dev/null
  built_and_broken
  escalated
  [ "$(step)" = fix ] || { cat "$TEST_ROOT/step.json"; false; }
  escalated
  figures s1 4 2000 200
  printf 'mine\n' >> src/greet.txt
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  grep -q mine src/greet.txt
  ! git log --format=%s | grep -q '^Revert "feat(greet): bye"'
  jq -e '[.decisions[] | select(.text | test("park"))] | last | .text | test("you changed src/greet.txt")' .vbw/record.json \
    || { jq '.decisions[-2:]' .vbw/record.json; false; }
}

@test "R179 (F185): a file you staged stays staged and the commit touching it is left and named; a check file you edited by hand stays" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 50 > /dev/null
  built_and_broken
  escalated
  [ "$(step)" = fix ] || { cat "$TEST_ROOT/step.json"; false; }
  escalated
  figures s1 4 2000 200
  printf 'staged\n' >> src/greet.txt && git add src/greet.txt
  printf '# mine\n' >> tests/greet.sh
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  git diff --cached --name-only | grep -qx src/greet.txt
  grep -q staged src/greet.txt
  [ -f tests/greet.sh ] && grep -q '# mine' tests/greet.sh
  ! git log --format=%s | grep -q '^Revert "feat(greet): bye"'
  jq -e '[.decisions[] | select(.text | test("park"))] | last | .text | test("you changed src/greet.txt")' .vbw/record.json \
    || { jq '.decisions[-2:]' .vbw/record.json; false; }
}

@test "R179 (F185): a commit that does not revert cleanly is left in place and named; the clean ones are reverted" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 50 > /dev/null
  built_and_broken
  # A later commit on the same file, changing code and a .vbw file together: left (D326), and it makes the oldest revert conflict.
  printf 'extra\n' >> src/greet.txt
  printf 'note\n' > .vbw/notes.md
  git add -f src/greet.txt .vbw/notes.md && git commit -q -m "chore: code and record together"
  escalated
  [ "$(step)" = fix ] || { cat "$TEST_ROOT/step.json"; false; }
  escalated
  figures s1 4 2000 200
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  # The mixed commit is left; the two older ones conflict with it (git treats a change next to another as a conflict) and are left too, each named.
  ! git log --format=%s | grep -q '^Revert '
  grep -q extra src/greet.txt
  jq -e '[.decisions[] | select(.text | test("park"))] | last | .text | test("does not revert cleanly") and test("changes the record too")' .vbw/record.json \
    || { jq '.decisions[-2:]' .vbw/record.json; false; }
  grep -q 'does not revert cleanly' .vbw/loop-report.md
}
