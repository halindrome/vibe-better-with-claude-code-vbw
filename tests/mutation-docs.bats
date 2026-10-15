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
  run line_has rigor.md '`express`' "each rule"
  [ "$status" -ne 0 ]
  run line_has rigor.md '`standard`' "nothing"
  [ "$status" -ne 0 ]
}

@test "R188: docs/workflows.md says the command refuses when none of the named files differs from the last commit" {
  local t
  t=$(section "$DOCS/workflows.md" | tr '\n' ' ' | tr -s ' ')
  [[ "$t" == *"refuses"*"none of the named files differs from their last commit"* ]] || { echo "$t"; false; }
  [[ "$t" != *"if the plan's files differ"* ]]
}

@test "R188: docs/proof.md says the loop gives the approval and records a decision" {
  line_has proof.md "the loop gives" "records a decision"
}

@test "R188: docs/workflows.md Rigor section says the building bullet takes the tier for the mutation step" {
  local b
  b=$(awk '/^## Rigor/ {on=1; next} /^## / {on=0} on && /vbw:building/' "$DOCS/workflows.md")
  [[ "$b" == *tier* && "$b" == *mutation* ]] || { echo "$b"; false; }
}

# flat FILE: the mutation check section of FILE on one line, spaces squeezed.
flat() { section "$DOCS/$1" | tr '\n' ' ' | tr -s ' '; }
# has_sentence FILE TEXT: the section of FILE holds TEXT whole (reversing it fails).
has_sentence() {
  local t
  t=$(flat "$1")
  [[ "$t" == *"$2"* ]] || { echo "docs/$1 mutation check section lacks: $2"; return 1; }
}

@test "R188: docs/proof.md pins whole statements: survivor, where it is strengthened, blocking, tiers, one approval" {
  has_sentence proof.md "never another's, never weakened"
  has_sentence proof.md "After two attempts that stay green the Dev blocks the plan."
  has_sentence proof.md "At deep each task also needs a red break or a written reason."
  has_sentence proof.md "At express it asks for nothing."
  has_sentence proof.md "A survivor alone covers nothing."
  has_sentence proof.md "A strengthened check file adds one approval."
  has_sentence proof.md "asks you to approve the file before the proof"
}

@test "R188: docs/workflows.md says VBW undoes the break" {
  has_sentence workflows.md "**VBW undoes the break.**"
  has_sentence workflows.md "go back to their last commit"
}

@test "R188: docs/proof.md pins what a survivor is, the repeat until red, what plan done refuses and the approval's effect" {
  has_sentence proof.md "A test that cannot fail, because every check stays green, is a **survivor**."
  has_sentence proof.md "then repeats the same break until it is red."
  has_sentence proof.md "at standard it refuses until each approved rule of the requirements the plan completes has a red break, and lists the rules missing one."
  has_sentence proof.md "and \`vbw prove\` refuses until you do."
  has_sentence proof.md "one edited again after its red break, still waits for you."
  has_sentence proof.md "At standard and deep, the builder breaks the plan's code on purpose"
}

@test "R188: docs/rigor.md pins the tiers: standard is rules only, the builder runs it at standard and deep, a fix never does" {
  has_sentence rigor.md '| `standard` | each rule: one small break per rule |'
  has_sentence rigor.md '| `deep` | each rule, each task, and each error and edge case the rules state |'
  has_sentence rigor.md "At standard and deep, the builder breaks its own plan's code on purpose"
  has_sentence rigor.md "A fix never runs it."
}

@test "R188: docs/workflows.md pins which check runs, the exit code of a survivor, --none and the refusals" {
  has_sentence workflows.md "Only that rule's own check runs."
  has_sentence workflows.md "A survivor makes \`vbw mutate\` exit non-zero."
  has_sentence workflows.md "a rule cannot be recorded this way."
  has_sentence workflows.md "a file is outside the plan, or a check file is touched."
  has_sentence workflows.md "The command refuses, and writes nothing, if none of the named files differs from their last commit"
}
