#!/usr/bin/env bats
# R175: docs/proof.md's causes table keeps the message "nothing was committed
# since the last passing proof" and names the record's evidence fields the rule
# compares (evidence.tree, evidence.head). L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R175: the causes table keeps the message and names evidence.tree and evidence.head" {
  grep -qF '`nothing was committed since the last passing proof`' "$DOC"
  grep -qF '`evidence.tree`' "$DOC"
  grep -qF '`evidence.head`' "$DOC"
}
