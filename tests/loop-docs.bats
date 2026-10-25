#!/usr/bin/env bats
# R179 (P128): docs/loop.md describes the cycle, the stops, the report and the
# skill; docs/next.md names the loop step and says vbw next is unchanged;
# docs/workflows.md and the autonomy section of the docs say the loop's steps
# are not counted against autonomy_cap. L1.

load helper

@test "R179: docs/loop.md describes the cycle, the stops, the report and the skill" {
  local f="$REPO_ROOT/docs/loop.md" w
  [ -f "$f" ]
  for w in "vbw loop next" "/vbw:loop" "/vbw:loop stop" ".vbw/loop-report.md" "end of" "--finish-item" "cannot tell" "vbw req skip" "needs_decisions" "Stop hook" "autonomy_cap" "vbw milestone start" "vbw ship"; do
    grep -qF -- "$w" "$f" || { echo "docs/loop.md lacks: $w"; false; }
  done
  grep -qiE '^## .*(cycle)' "$f"
  grep -qiE '^## .*(stop)' "$f"
  grep -qiE '^## .*(report)' "$f"
}

@test "R179: docs/next.md names the loop step and that vbw next is unchanged" {
  grep -qF 'vbw loop next' "$REPO_ROOT/docs/next.md"
  grep -n 'vbw loop next' "$REPO_ROOT/docs/next.md" | head -n 1 > /dev/null
  grep -qiE 'unchanged|pure' <(grep -iA3 'vbw loop next' "$REPO_ROOT/docs/next.md")
}

@test "R179: docs/workflows.md and the autonomy section say the loop's steps are not counted against autonomy_cap" {
  grep -i 'loop' "$REPO_ROOT/docs/workflows.md" | grep -q 'autonomy_cap'
  grep -i 'loop' "$REPO_ROOT/README.md" | grep -q 'autonomy_cap'
}

@test "R179 (F187): docs/next.md row 1 names a parked milestone beside a shipped one" {
  grep -E '^\| 1 \|' "$REPO_ROOT/docs/next.md" | grep -q 'shipped'
  grep -E '^\| 1 \|' "$REPO_ROOT/docs/next.md" | grep -q 'parked'
}

@test "R179 (F192): docs/loop.md names the three kinds of commit a park leaves in place, and says they are named" {
  grep -q 'left in place and named' "$REPO_ROOT/docs/loop.md"
  grep -q 'staged or edited' "$REPO_ROOT/docs/loop.md"
  grep -q 'code and a `.vbw/` file together' "$REPO_ROOT/docs/loop.md"
  grep -q 'does not revert cleanly' "$REPO_ROOT/docs/loop.md"
}

@test "T156: docs/loop.md says the budget is set from the plan's road, once, with a floor, and the basis names which was used" {
  local f="$REPO_ROOT/docs/loop.md"
  tr '\n' ' ' < "$f" | grep -Eq 'From the plan\..*twice the time so far plus +that road, at least 30 minutes.*set once' || { echo "docs/loop.md lacks the plan rule"; false; }
  tr '\n' ' ' < "$f" | grep -Eq 'The basis says which of the three below was used' || { echo "docs/loop.md lacks the basis"; false; }
  grep -qF 'planned: true' "$REPO_ROOT/docs/record.md" || grep -qF '`planned: true`' "$REPO_ROOT/docs/record.md" || { echo "docs/record.md lacks planned"; false; }
}

@test "T156: docs/loop.md says what counts as the item's time and how an item resumes; docs/record.md names stepped_at and away" {
  local f="$REPO_ROOT/docs/loop.md"
  tr '\n' ' ' < "$f" | grep -Eq 'What counts as the item.s time\.\*\* Only the time the loop is working on it' || { echo "docs/loop.md lacks what counts"; false; }
  tr '\n' ' ' < "$f" | grep -Eq 'from the loop.s last step on the item until the step that resumes +it' || { echo "docs/loop.md lacks the stopped stretch"; false; }
  grep -qF 'Resuming an item' "$f" || { echo "docs/loop.md lacks resuming"; false; }
  grep -qF 'StopFailure' "$f" || { echo "docs/loop.md lacks the StopFailure hook"; false; }
  grep -qF '`stepped_at`' "$REPO_ROOT/docs/record.md" && grep -qF '`away`' "$REPO_ROOT/docs/record.md" || { echo "docs/record.md lacks stepped_at or away"; false; }
}
