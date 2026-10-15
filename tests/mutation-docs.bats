#!/usr/bin/env bats
# R188 (P141): the user documentation describes the mutation check. Each of
# docs/workflows.md, docs/proof.md and docs/rigor.md has a section whose heading
# names the mutation check. Together they say when it runs (standard and deep
# only, never at express, never in a fix), what is broken at each level (each
# rule at standard; each rule, each task and each error and edge case at deep),
# that vbw mutate records each break and VBW undoes it, what happens to a test
# that cannot fail (a survivor, strengthened in place in its own check file),
# that vbw plan done waits for the breaks, and the one approval it can add
# (asked before the proof; under a loop the loop gives it and records a
# decision). L1: the text of the documents.

load helper

DOCS="$REPO_ROOT/docs"

# section FILE: the section of FILE whose heading names the mutation check, up
# to the next heading of the same or a higher level.
section() {
  awk '/^#+ / { lvl = index($0, " ") - 1
      if (on && lvl <= depth) exit
      if (!on && tolower($0) ~ /mutation check/) { on = 1; depth = lvl } }
    on { print }' "$1"
}
# says FILE WORD...: the section of FILE holds every WORD (case-insensitive).
says() {
  local f=$1 s w
  shift
  s=$(section "$DOCS/$f")
  [ -n "$s" ] || { echo "docs/$f has no section whose heading names the mutation check"; return 1; }
  for w in "$@"; do
    printf '%s' "$s" | grep -qiF -- "$w" || { echo "the mutation check section of docs/$f does not say: $w"; return 1; }
  done
}

@test "R188: docs/workflows.md says when the mutation step runs and how a builder runs it" {
  says workflows.md "vbw mutate" standard deep express fix undo
}

@test "R188: docs/rigor.md says what is broken at each level" {
  says rigor.md "each rule" "each task" error edge standard deep express
}

@test "R188: docs/proof.md says what happens to a test that cannot fail and what vbw plan done waits for" {
  says proof.md survivor "cannot fail" strengthen "in place" "vbw plan done" red
}

@test "R188: docs/proof.md says the one approval it can add, and that a loop gives it with a decision" {
  says proof.md approval "before the proof" loop decision
}

# line_has FILE WORD...: one line of the mutation check section of FILE holds every WORD.
line_has() {
  local f=$1 l w
  shift
  l=$(section "$DOCS/$f")
  for w in "$@"; do l=$(printf '%s\n' "$l" | grep -iF -- "$w") || { echo "no line of the mutation check section of docs/$f holds all of: $*"; return 1; }; done
}

@test "R188: docs/workflows.md says it runs at standard and deep, never at express, never in a fix" {
  line_has workflows.md "at standard and deep" "never at express" "never in a fix"
}

@test "R188: docs/rigor.md gives express, standard and deep each its own content" {
  line_has rigor.md '`express`' "nothing"
  line_has rigor.md '`standard`' "each rule" "one small break per rule"
  line_has rigor.md '`deep`' "each rule" "each task" "edge case"
  ! line_has rigor.md '`express`' "each rule" > /dev/null
  ! line_has rigor.md '`standard`' "nothing" > /dev/null
}

@test "R188: docs/proof.md says the loop gives the approval and records a decision" {
  line_has proof.md "the loop gives" "records a decision"
}

@test "R188: docs/workflows.md Rigor section says the building bullet takes the tier for the mutation step" {
  local b
  b=$(awk '/^## Rigor/ {on=1; next} /^## / {on=0} on && /vbw:building/' "$DOCS/workflows.md")
  [[ "$b" == *tier* && "$b" == *mutation* ]] || { echo "$b"; false; }
}
