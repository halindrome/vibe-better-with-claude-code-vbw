#!/usr/bin/env bats
# R202: docs/proof.md describes the two report lines of vbw prove and vbw fix
# done (VBW's own work, ran again with the top reasons) and what own work
# means; docs/record.md describes the evidence fields that keep them
# (evidence.own with its five steps and the wall time, evidence.causes) and
# that an older record shows "not recorded". L1.

load helper

PROOF="$REPO_ROOT/docs/proof.md"
RECORD="$REPO_ROOT/docs/record.md"

@test "R202: docs/proof.md describes both report lines and what own work means" {
  grep -qF "VBW's own work: " "$PROOF"
  grep -qF "ran again: " "$PROOF"
  grep -qF "VBW's own work: X of Y min" "$PROOF"
  grep -qF "ran again: N of M units; top reasons: " "$PROOF"
  grep -qF "ran again: 0 of 52 units; top reasons: none" "$PROOF"
  grep -qE '^VBW.s own work: [0-9.]+ of [0-9.]+ min$' "$PROOF"
  grep -qF "top reasons" "$PROOF"
  grep -qi 'read tracking' "$PROOF"
  grep -qF 'vbw fix done' "$PROOF"
  # What own work counts, honestly: the scope check is planning, the wall ends with the
  # record step, and tracking summed over side-by-side units can exceed the wall.
  grep -qF 'the scope check' "$PROOF"
  grep -qF 'end of its record step' "$PROOF"
  grep -qF 'own work can exceed the wall time' "$PROOF"
}

@test "R202: docs/record.md describes evidence.own, evidence.causes and the not-recorded case" {
  grep -qF '`own`' "$RECORD"
  grep -qF '`causes`' "$RECORD"
  for step in planning copies tracking saving record wall; do
    grep -qF "\`$step\`" "$RECORD" || { echo "docs/record.md does not name the own-work field $step"; false; }
  done
  grep -qF 'not recorded' "$RECORD"
}
