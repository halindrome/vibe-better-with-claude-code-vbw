#!/usr/bin/env bats
# R168: docs/proof.md lists the causes that make a proof run everything,
# each with the message the user sees, and the counts every summary prints. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R168: docs/proof.md shows the ran-everything line and the list form for several causes" {
  grep -qF 'ran everything: ' "$DOC"
  grep -qF 'ran everything, because:' "$DOC"
}

@test "R168: docs/proof.md lists no changed approved command, single-file form or list of test files as a cause" {
  ! grep -qF 'command test changed' "$DOC" || { grep -n 'command test changed' "$DOC"; false; }
  ! grep -qF 'single-file form changed' "$DOC" || { grep -n 'single-file form changed' "$DOC"; false; }
  ! grep -qF 'list of test files changed' "$DOC" || { grep -n 'list of test files changed' "$DOC"; false; }
}

@test "R168: docs/proof.md no longer lists a file every test file reads as a cause" {
  ! grep -qF 'changed, and every test file reads it' "$DOC" || { grep -n 'every test file reads it' "$DOC"; false; }
}

@test "R168: docs/proof.md lists an added or deleted file no recorded run saw, with its messages" {
  grep -qF 'was added, and no recorded run read it or listed its folder' "$DOC"
  grep -qF 'was deleted, and no recorded run read it or listed its folder' "$DOC"
}

@test "R168: docs/proof.md lists a file system that cannot record reads, no earlier run in the clone and a proof cut short, with their messages" {
  grep -qF 'does not record which files are read' "$DOC"
  grep -qF 'this clone has no earlier recorded run' "$DOC"
  grep -qF 'the last proof was cut short' "$DOC"
}

@test "R168: docs/proof.md shows both count lines" {
  grep -qE 'checks: N ran, M reused' "$DOC"
  grep -qE 'test files: N ran, M reused' "$DOC"
}
