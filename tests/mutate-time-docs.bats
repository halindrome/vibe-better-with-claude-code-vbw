#!/usr/bin/env bats
# R207: docs/workflows.md's mutation-check section shows the two lines vbw
# mutate ends with (VBW's own work: X of Y min, then the split by step) and
# names the steps: copies, unbroken, one entry per break named by its target,
# waits, saving; it says the figures are measured, that the breakdown changes no
# verdict, record or exit code, and that a refusal, --queue and --none print
# none. L1: the text of the doc (one line holds each fact; no exact wording).

load helper

DOC="$REPO_ROOT/docs/workflows.md"

section() { sed -n '/^## The mutation check/,/^## /p' "$DOC"; }

# has_line TEXT WORD...: one line of TEXT holds every WORD (case-insensitive).
has_line() {
  local lines="$1" w
  shift
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line holds all of: $*"; return 1; }; done
}

@test "R207: the section shows the own-work line and the steps line in the printed form" {
  section | grep -qE "^VBW's own work: [0-9]+\.[0-9] of [0-9]+\.[0-9] min$" || { echo "no own-work line shown"; false; }
  section | grep -qE '^  steps of [0-9]+\.[0-9] s: copies [0-9]+\.[0-9], unbroken [0-9]+\.[0-9], break R[0-9]+\.[0-9]+ [0-9]+\.[0-9], waits [0-9]+\.[0-9], saving [0-9]+\.[0-9]$' \
    || { echo "no steps line shown"; false; }
}

@test "R207: the section names each step: copies, unbroken, a break named by its target, waits for a slot, saving" {
  has_line "$(section)" "copies" "clean cop"
  has_line "$(section)" "unbroken"
  has_line "$(section)" "break" "target"
  has_line "$(section)" "waits" "slot"
  has_line "$(section)" "saving" "record"
  has_line "$(section)" "--run" "side by side" "breaks"
}

@test "R207: the section says the figures are measured, the steps sum to the wall, and the breakdown changes nothing" {
  has_line "$(section)" "measured"
  has_line "$(section)" "sum"
  has_line "$(section)" "verdict" "exit code"
}

@test "R207: the section says a refusal prints no breakdown, and neither do --queue and --none" {
  has_line "$(section)" "refus" "no breakdown"
  has_line "$(section)" "--queue" "--none" "none"
}
