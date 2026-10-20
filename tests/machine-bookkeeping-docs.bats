#!/usr/bin/env bats
# R202: docs/proof.md ("The computer-wide limit") says that VBW's own
# bookkeeping steps take slots too, and names them: a unit's slot covers its
# read tracking, and the proof-wide steps hold one slot each as vbw:plan,
# vbw:copies and vbw:save; vbw next never waits for a slot. The wording of the
# "waited" line stays the same. L1.

load helper

PROOF="$REPO_ROOT/docs/proof.md"

@test "R202: docs/proof.md names the bookkeeping slots" {
  grep -qF 'vbw:plan' "$PROOF"
  grep -qF 'vbw:copies' "$PROOF"
  grep -qF 'vbw:save' "$PROOF"
  grep -qi 'read tracking' "$PROOF"
}

@test "R202: docs/proof.md says vbw next never waits for a slot and keeps the waited line's wording" {
  grep -qi 'vbw next.*never waits' "$PROOF" || grep -qi 'never waits.*vbw next' "$PROOF"
  grep -qF 'waited ... for other VBW runs on this computer' "$PROOF"
}
