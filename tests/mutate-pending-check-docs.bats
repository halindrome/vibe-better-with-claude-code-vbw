#!/usr/bin/env bats
# R196 (T165): docs/proof.md's mutation section explains the sentence
# `survives the approved check; caught by the pending one` and that the pending
# file still needs the one approval before the proof. L1: the text of the document.

load helper

DOCS="$REPO_ROOT/docs"

# section FILE HEADING_REGEX: the text of the section whose heading line matches
# HEADING_REGEX, up to the next heading of the same or a higher level, as one line.
section() {
  awk -v re="$2" '
    /^#{1,3} / { if (found) { n = length($1); if (n <= level) exit } else if ($0 ~ re) { found = 1; level = length($1); next } }
    found { printf "%s ", $0 }' "$DOCS/$1"
}

@test "R196: docs/proof.md's mutation section gives the sentence in its exact words and says the pending file still needs the one approval before the proof" {
  local s
  s=$(section proof.md '^### The mutation check')
  printf '%s' "$s" | grep -qF 'survives the approved check; caught by the pending one' \
    || { echo "docs/proof.md, The mutation check: the sentence is not given in its words"; false; }
  printf '%s' "$s" | grep -Eiq 'pending[^.]*approv|approv[^.]*pending' \
    || { echo "docs/proof.md, The mutation check: no sentence ties the pending file to its approval"; false; }
}
