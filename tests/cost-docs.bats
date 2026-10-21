#!/usr/bin/env bats
# R173: the user docs name the cost data and the command: docs/record.md the
# record field, docs/statusline.md the side file, docs/costs.md the command, its
# flags and every field of its JSON. L1.

load helper

@test "R173: docs/record.md names the costs field and lease.cost" {
  grep -qF '| `costs` |' "$REPO_ROOT/docs/record.md"
  grep -qF 'lease.cost' "$REPO_ROOT/docs/record.md"
}

@test "R173: docs/statusline.md documents the side file and no longer claims no temporary files" {
  grep -qF '.vbw/runtime/cost.' "$REPO_ROOT/docs/statusline.md"
  grep -qF 'vbw show costs' "$REPO_ROOT/docs/statusline.md"
  ! grep -qF 'no temporary files' "$REPO_ROOT/docs/statusline.md"
}

@test "R173: docs/costs.md names the command, its JSON and ceiling flags, the unknown value and vbw statusline on" {
  [ -f "$REPO_ROOT/docs/costs.md" ]
  grep -qF 'vbw show costs --json' "$REPO_ROOT/docs/costs.md"
  grep -qF 'vbw show costs --ceiling' "$REPO_ROOT/docs/costs.md"
  grep -qF 'unknown' "$REPO_ROOT/docs/costs.md"
  grep -qF 'vbw statusline on' "$REPO_ROOT/docs/costs.md"
}

@test "R173: docs/costs.md names every field of milestones[] and runs[] in a real vbw show costs --json" {
  load rigor-helper
  rigor_flow_setup
  rigor_flow_build
  "$VBW" qa record P1 pass quick > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start qa > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  local k
  for k in $("$VBW" show costs --json < /dev/null | jq -r '(.milestones[0], .runs[0]) | keys_unsorted[]' | sort -u); do
    grep -qF "\`$k\`" "$REPO_ROOT/docs/costs.md" || { echo "docs/costs.md lacks \`$k\`"; false; }
  done
  vbw_teardown
}
