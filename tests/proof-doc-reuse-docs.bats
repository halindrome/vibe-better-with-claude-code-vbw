#!/usr/bin/env bats
# R144 (D260): docs/proof.md names the read list and vbw prove --full; the old
# documentation-only rule and its limit are gone. docs/record.md names how a
# reused result is marked in the evidence. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R144: docs/proof.md names the read list and vbw prove --full" {
  grep -qi 'read list' "$DOC"
  grep -qF 'vbw prove --full' "$DOC"
  ! grep -qi 'reuses no check and no other command' "$DOC" || { grep -ni 'reuses no check and no other command' "$DOC"; false; }
}

@test "R144: docs/proof.md no longer describes the documentation-only rule or its limit" {
  ! grep -qi 'not listed by any check' "$DOC" || { grep -ni 'not listed by any check' "$DOC"; false; }
  ! grep -qi 'only documentation changed since' "$DOC" || { grep -ni 'only documentation changed since' "$DOC"; false; }
}

@test "R144: docs/record.md names the reused mark of a reused test-command result" {
  grep -qF 'reused: true' "$REPO_ROOT/docs/record.md"
}
