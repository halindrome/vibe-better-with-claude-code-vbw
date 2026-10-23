#!/usr/bin/env bats
# The record's own history (docs/proof.md "Whose commits VBW judges", docs/record.md):
# the docs say which commits the trailer readers read, why, the readers, the
# never-committed case and the merge limit. L1: the text of the documents.

load helper

folded() { tr '\n' ' ' < "$1" | tr -s ' '; }

@test "history: docs/proof.md says whose commits VBW judges, which readers, and the limits" {
  local f="$REPO_ROOT/docs/proof.md"
  grep -qx '### Whose commits VBW judges' "$f"
  folded "$f" | grep -qF 'the commits after the newest commit that added `.vbw/record.json`'
  folded "$f" | grep -qF 'ids start again when a project starts a new record'
  for w in 'the scope check' 'delivered files' '`vbw plan done`' '`vbw show`' "the loop's report"; do
    folded "$f" | grep -qF "$w" || { echo "docs/proof.md does not name $w"; false; }
  done
  folded "$f" | grep -qF 'A project whose record was never committed keeps its whole history'
  folded "$f" | grep -qF 'an older branch merged in after the record was born'
  folded "$f" | grep -qF "every commit of the record's own history"
}

@test "history: docs/record.md says only the record's own commits count" {
  folded "$REPO_ROOT/docs/record.md" | grep -qF 'Only the commits made since the record was first committed count as its own'
}
