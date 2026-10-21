#!/usr/bin/env bats
# R62: the user documentation of the tools offer names its commands:
# /vbw:skills runs it again, vbw tools holds the stored answer, and the README
# links docs/tools.md (L1: facts in the text).

load helper

DOC="$REPO_ROOT/docs/tools.md"

@test "R62: docs/tools.md names /vbw:skills and vbw tools" {
  [ -f "$DOC" ]
  grep -qF '/vbw:skills' "$DOC"
  grep -qF 'vbw tools' "$DOC"
}

@test "R62: the README links the page" {
  grep -qF 'docs/tools.md' "$REPO_ROOT/README.md"
}
