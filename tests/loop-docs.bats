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
