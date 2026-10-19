#!/usr/bin/env bats
# R197 (T167): docs/proof.md's mutation section states that the broken file and
# its restore get a fresh modification time, so builds that decide by file times
# (make, cargo) rebuild. L1: the text of the document.

load helper

DOCS="$REPO_ROOT/docs"

# section FILE HEADING_REGEX: the text of the section whose heading line matches
# HEADING_REGEX, up to the next heading of the same or a higher level, as one line.
section() {
  awk -v re="$2" '
    /^#{1,3} / { if (found) { n = length($1); if (n <= level) exit } else if ($0 ~ re) { found = 1; level = length($1); next } }
    found { printf "%s ", $0 }' "$DOCS/$1"
}

@test "R197: docs/proof.md's mutation section says the broken file and its restore get a fresh modification time so time-based builds rebuild" {
  local s
  s=$(section proof.md '^### The mutation check')
  printf '%s' "$s" | grep -qi 'modification time' || { echo "docs/proof.md, The mutation check: 'modification time' is not mentioned"; false; }
  printf '%s' "$s" | grep -qi 'rebuil' || { echo "docs/proof.md, The mutation check: rebuilding is not mentioned"; false; }
  printf '%s' "$s" | grep -qi 'restore' || { echo "docs/proof.md, The mutation check: the restore is not mentioned"; false; }
}
