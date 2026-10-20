#!/usr/bin/env bats
# R188 (P141): the user documentation names the facts of the mutation check:
# the command (vbw mutate), the rigor levels it runs at, what each level breaks
# (docs/rigor.md's table: nothing at express, each rule at standard, each rule
# at deep plus a task whose behaviour no rule's check covers, T174), the
# survivor and the vbw plan done gate. L1: the text of the documents.

load helper

DOCS="$REPO_ROOT/docs"

# says FILE WORD...: FILE holds every WORD (case-insensitive).
says() {
  local f=$1 w
  shift
  for w in "$@"; do
    grep -qiF -- "$w" "$DOCS/$f" || { echo "docs/$f does not name: $w"; return 1; }
  done
}

# row LEVEL: the line of docs/rigor.md that starts the table row of LEVEL and names the mutation check's content.
row() { grep -E "^\| \`$1\` \|" "$DOCS/rigor.md" | grep -iE 'rule|nothing'; }

@test "R188: docs/workflows.md names vbw mutate and the levels it runs at" {
  says workflows.md "vbw mutate" standard deep express
}

@test "R188: docs/proof.md names the survivor and vbw plan done" {
  says proof.md survivor "vbw plan done"
}

@test "T174: docs/rigor.md's table gives each level what it breaks: nothing at express, each rule at standard, each rule and only an uncovered task at deep" {
  row express | grep -qi 'nothing' || { echo "express: $(row express)"; false; }
  ! row express | grep -qi 'each rule'
  row standard | grep -qi 'each rule' || { echo "standard: $(row standard)"; false; }
  ! row standard | grep -qi 'task'
  row deep | grep -qi 'each rule' || { echo "deep: $(row deep)"; false; }
  row deep | grep -qi "a task whose behaviour no rule's check covers" || { echo "deep: $(row deep)"; false; }
  ! row deep | grep -qiE 'each task|edge case' || { echo "deep: $(row deep)"; false; }
}
