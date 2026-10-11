#!/usr/bin/env bats
# R144 (D260): docs/proof.md explains that a change to files the test command
# did not read (documentation included) lets the next proof reuse its earlier
# passing result, that what counts is what the command read and never the kind
# of file, what still makes it run, and that vbw prove --full reuses nothing.
# The old documentation-only rule and its limit are gone. docs/record.md names
# what the evidence keeps for a reused result. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R144: docs/proof.md says a proof reuses the test command's passing result when nothing it read changed" {
  grep -qiE 'reuses? the test command|test command.{0,80}reused' "$DOC"
  grep -qi 'read list' "$DOC"
  grep -qi 'documentation' "$DOC"
}

@test "R144: docs/proof.md says vbw prove --full reuses nothing" {
  grep -qiE 'vbw prove --full`? (reuses nothing|runs everything)' "$DOC" || { grep -n 'vbw prove --full' "$DOC"; false; }
  ! grep -qi 'reuses no check and no other command' "$DOC" || { grep -ni 'reuses no check and no other command' "$DOC"; false; }
}

@test "R144: docs/proof.md names what still makes the test command run" {
  grep -qiE 'test file' "$DOC"
  grep -qiE 'uncommitted' "$DOC"
  grep -qiE 'quick command' "$DOC"
  grep -qiE 'unfinished|interrupted' "$DOC"
}

@test "R144: docs/proof.md no longer describes the documentation-only rule or its limit" {
  ! grep -qi 'not listed by any check' "$DOC" || { grep -ni 'not listed by any check' "$DOC"; false; }
  ! grep -qi 'only documentation changed since' "$DOC" || { grep -ni 'only documentation changed since' "$DOC"; false; }
  grep -qi 'never from file names' "$DOC"
}

@test "R144: docs/record.md describes how a reused test-command result is marked in the evidence" {
  grep -qiE 'test command' "$REPO_ROOT/docs/record.md"
  grep -qE 'reused' "$REPO_ROOT/docs/record.md"
}
