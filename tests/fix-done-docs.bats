#!/usr/bin/env bats
# R176: docs/proof.md's vbw fix done section shows the output form: one line per
# check and per test file that ran (the proof summary's form), the reused lines
# with the time of the pass, the cause line, and the two count lines. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R176: docs/proof.md shows a check line and a test file line that ran, with why" {
  grep -qE '^C[0-9]+ pass [0-9]+s ran: ' "$DOC"
  grep -qE '^tests/[A-Za-z0-9_.-]+ pass [0-9]+s ran: ' "$DOC"
}

@test "R176: docs/proof.md shows the reused line with the time of the pass and the cause line" {
  grep -qE '^C[0-9]+ unchanged since its pass \([0-9]{4}-' "$DOC"
  grep -qF 'every candidate check runs: ' "$DOC"
}

@test "R176: docs/proof.md shows both count lines in the fix done output, printed every time" {
  grep -qE '^checks: [0-9]+ ran, [0-9]+ reused$' "$DOC"
  grep -qE '^test files: [0-9]+ ran, [0-9]+ reused$' "$DOC"
  grep -qF '0 ran, 0 reused' "$DOC"
}
