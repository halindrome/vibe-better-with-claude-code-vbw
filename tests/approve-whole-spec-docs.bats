#!/usr/bin/env bats
# R174: docs/proof.md's approval section names the four spec sections the
# approval compares with the record and says an unsynced spec cannot be
# approved. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R174: docs/proof.md names the four sections compared at approval" {
  grep -qF 'Requirements, Commands, Test files and Test results' "$DOC"
}

@test "R174: docs/proof.md says an unsynced spec cannot be approved and shows the refusal line" {
  grep -qF 'cannot be approved' "$DOC"
  grep -qF 'spec.md and the record differ (vbw spec sync)' "$DOC"
}
