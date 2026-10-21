#!/usr/bin/env bats
# R193 (T165): the user documentation says what a task break runs: the checks of
# the plan's own rules. docs/proof.md's mutation section and docs/workflows.md's
# mutation section both say so. L1: the text of the documents.

load helper

DOCS="$REPO_ROOT/docs"

# section FILE HEADING_REGEX: the text of the section whose heading line matches
# HEADING_REGEX, up to the next heading of the same or a higher level, as one line.
section() {
  awk -v re="$2" '
    /^#{1,3} / { if (found) { n = length($1); if (n <= level) exit } else if ($0 ~ re) { found = 1; level = length($1); next } }
    found { printf "%s ", $0 }' "$DOCS/$1"
}

@test "R193: docs/proof.md's mutation section says a task break runs the checks of the plan's own rules" {
  section proof.md '^### The mutation check' | grep -Eiq 'task[^.]*own rules' \
    || { echo "docs/proof.md, The mutation check: no sentence says a task break runs the plan's own rules' checks"; false; }
}

@test "R193: docs/workflows.md's mutation section says the task form runs the checks of the plan's own rules" {
  section workflows.md '^## The mutation check' | grep -Eiq 'task[^.]*own rules' \
    || { echo "docs/workflows.md, The mutation check: no sentence says the task form runs the plan's own rules' checks"; false; }
}
