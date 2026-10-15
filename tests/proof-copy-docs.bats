#!/usr/bin/env bats
# R92 and R93: docs/proof.md names the facts of git-ignored files in the proof
# copy (copy-on-write, the pnpm example) and no longer says they are linked in;
# it names the proof.* folders and pnpm install for the warning about links. L1:
# the docs are read as text.

load helper

DOC="$BATS_TEST_DIRNAME/../docs/proof.md"

@test "R92: docs/proof.md names copy-on-write and the pnpm example, and no longer says git-ignored files are linked in" {
  grep -q 'pnpm' "$DOC"
  grep -qi 'copy-on-write' "$DOC"
  if grep -qiE 'links them in|files behind the links|linked in from the working folder' "$DOC"; then false; fi
}

@test "R93: docs/proof.md names the proof.* folders and pnpm install for the warning about links" {
  grep -q 'proof\.\*' "$DOC"
  grep -qi 'pnpm install' "$DOC"
}
