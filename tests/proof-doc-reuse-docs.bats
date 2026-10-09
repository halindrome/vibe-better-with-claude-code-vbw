#!/usr/bin/env bats
# R144: docs/proof.md explains when vbw prove --full reuses the test command's
# earlier passing result (only documentation or VBW's own .vbw/ files changed
# since), what still makes it run, and the limit of the rule: a test that reads
# a documentation file no check lists is not re-run by a documentation-only
# change. docs/record.md names what the evidence keeps for it. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R144: docs/proof.md says a full proof reuses the test command's passing result after a documentation-only change" {
  grep -qiE 'documentation-only change|only documentation (changed|or)' "$DOC"
  grep -qiE 'reuses? the test command|test command.{0,40}reused' "$DOC"
  grep -qF 'vbw prove --full' "$DOC"
}

@test "R144: docs/proof.md no longer says vbw prove --full reuses nothing" {
  run grep -n 'vbw prove --full` reuses nothing' "$DOC"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R144: docs/proof.md names what still makes the test command run" {
  grep -qiE 'test file' "$DOC"
  grep -qiE 'lists or runs|lists? or runs?' "$DOC"
  grep -qiE 'uncommitted' "$DOC"
  grep -qiE 'quick command' "$DOC"
  grep -qiE 'unfinished|interrupted' "$DOC"
}

@test "R144: docs/proof.md states the limit: a test reading a documentation file that no check lists is not re-run" {
  grep -qiE 'not listed by any check' "$DOC"
}

@test "R144: docs/record.md describes how a reused test-command result is marked in the evidence" {
  grep -qiE 'documentation' "$REPO_ROOT/docs/record.md"
  grep -qiE 'test command' "$REPO_ROOT/docs/record.md"
  grep -qE 'reused' "$REPO_ROOT/docs/record.md"
}
