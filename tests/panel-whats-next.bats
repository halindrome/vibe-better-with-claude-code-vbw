#!/usr/bin/env bats
# R124 (L1): the What's next section keeps the panel within its time budget: the
# panel bench measures a refresh that draws a stored recommendation (judged
# against VBW_PANEL_BUDGET_MS in the release run, R152, never in vbw prove).
# docs/panel.md describes the section and the Suggest next button.
# The section's behaviour is in tests/panel/whats-next.test.mjs.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

BENCH="$BATS_TEST_DIRNAME/../tools/bench-panel.sh"
DOC="$REPO_ROOT/docs/panel.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "docs/panel.md lacks: $2"; return 1; }; }

@test "R124: the panel bench measures a refresh that draws the What's next section" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel bench"; false; }
  VBW_PANEL_BUDGET_MS=100000 VBW_BENCH_RUNS=30 run bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"refresh with what's next: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
  grep -q 'recommendation' "$REPO_ROOT/tools/bench-panel.mjs"
}

@test "R124: docs/panel.md names the What's next section, the Suggest next button, its labels and /vbw:vibe what's next" {
  has "$DOC" "what's next"
  has "$DOC" 'suggest next'
  has "$DOC" 'top pick'
  has "$DOC" 'runners-up'
  has "$DOC" "/vbw:vibe what's next"
  has "$DOC" 'none yet'
}
