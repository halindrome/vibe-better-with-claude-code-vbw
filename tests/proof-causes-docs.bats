#!/usr/bin/env bats
# R168: docs/proof.md lists the causes that make a proof run everything, each
# with the message the user sees, says what is no cause, and shows the counts
# every summary prints. L1.

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

@test "R168: docs/proof.md lists no added or deleted file as a cause: such a file re-runs only the units that listed its folder or read it" {
  ! grep -qF 'and no recorded run read it or listed its folder' "$DOC" || { grep -n 'no recorded run read it' "$DOC"; false; }
  ! grep -qF 'no recorded run read them or listed their folders' "$DOC" || { grep -n 'listed their folders' "$DOC"; false; }
  grep -qF 're-runs the units that listed its folder or read it' "$DOC"
  grep -qF 'checks of the requirement whose plans list it, nothing else' "$DOC"
  grep -qF 'unless a plan of the check'"'"'s requirement lists it' "$DOC"
}

@test "R168: docs/proof.md lists a file system that cannot record reads or copies and no earlier run in the clone, with their messages, and a proof cut short as no cause" {
  grep -qF 'does not record which files are read' "$DOC"
  grep -qF 'this file system does not record a copied file as read' "$DOC"
  grep -qF 'this clone has no earlier recorded run' "$DOC"
  ! grep -qF 'the last proof was cut short' "$DOC" || { grep -n 'cut short' "$DOC"; false; }
  grep -qF 'A proof cut short' "$DOC"
}

@test "R168: docs/proof.md shows both count lines" {
  grep -qE 'checks: N ran, M reused' "$DOC"
  grep -qE 'test files: N ran, M reused' "$DOC"
}
