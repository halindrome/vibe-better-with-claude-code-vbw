#!/usr/bin/env bats
# R111: the user docs show the quick command's spec line, vbw prove --full and
# the two refusal messages. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R111: docs/proof.md shows how a project names its quick command" {
  grep -qF -- '- quick:' "$DOC"
}

@test "R111: docs/proof.md names vbw prove --full and its usage line" {
  grep -qF 'vbw prove --full' "$DOC"
  grep -qF 'usage: vbw prove [--full]' "$DOC"
}

@test "R111: docs/proof.md quotes the two refusal messages" {
  grep -qF 'the last proof was partial: run vbw prove --full, then record the verdict again' "$DOC"
  grep -qF 'Run vbw prove --full' "$DOC"
}

@test "R111: docs/proof.md no longer says a proof that reuses results is a full proof" {
  ! grep -q 'A proof that reuses results is a full proof' "$DOC"
}

@test "R111: docs/next.md and docs/record.md describe the full-proof step and the evidence's full field" {
  grep -qF 'vbw prove --full' "$REPO_ROOT/docs/next.md"
  grep -qF '`full`' "$REPO_ROOT/docs/record.md"
}
