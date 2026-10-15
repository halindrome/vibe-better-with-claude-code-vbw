#!/usr/bin/env bats
# R174: docs/proof.md names the four spec sections the approval compares with
# the record and shows the refusal line of an unsynced spec. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R174: docs/proof.md names the four sections compared at approval" {
  local s
  for s in Requirements Commands 'Test files' 'Test results'; do
    grep -qF "$s" "$DOC" || { echo "docs/proof.md does not name $s"; false; }
  done
}

@test "R174: docs/proof.md shows the refusal line of an unsynced spec" {
  grep -qF 'spec.md and the record differ (vbw spec sync)' "$DOC"
}
