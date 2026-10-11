#!/usr/bin/env bats
# R175: docs/proof.md states the cause "nothing was committed since the last
# passing proof" in terms of the trees of the last passing proof (the record's
# evidence), never the subject of the last commit. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R175: the causes table keeps the message and states the rule as the trees of the last passing proof" {
  grep -qF '`nothing was committed since the last passing proof`' "$DOC"
  grep -qF 'the tree the last passing proof recorded' "$DOC"
  grep -qF '`evidence.tree`' "$DOC"
  grep -qF '`evidence.head`' "$DOC"
}

@test "R175: the D173 paragraph says VBW compares trees and never the subject of the last commit" {
  grep -qF 'never the subject of the last commit' "$DOC"
}
