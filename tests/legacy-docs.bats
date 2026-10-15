#!/usr/bin/env bats
# R65: the user documentation names the commands and settings of the review of
# an old VBW 1 folder and the choice after it: vbw legacy review, vbw legacy
# choose, /vbw:convert, project.legacy, the one-year age rule, and the links to
# docs/convert.md (L1: facts in the text).

load helper

DOC="$REPO_ROOT/docs/convert.md"
INTERVIEW="$REPO_ROOT/docs/interview.md"

@test "R65: docs/convert.md names the review and choice commands and the setting that stores the answer" {
  grep -qF 'vbw legacy review' "$DOC"
  grep -qF 'vbw legacy choose' "$DOC"
  grep -qF '/vbw:convert' "$DOC"
  grep -qF 'project.legacy' "$DOC"
}

@test "R65: docs/convert.md states the age limit behind the recommendation" {
  grep -qiE 'a year|365' "$DOC"
}

@test "R65: docs/interview.md and the README link docs/convert.md" {
  grep -qiE 'VBW 1' "$INTERVIEW"
  grep -qF 'docs/convert.md' "$INTERVIEW"
  grep -qF 'docs/convert.md' "$REPO_ROOT/README.md"
}
