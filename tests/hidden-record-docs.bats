#!/usr/bin/env bats
# R208: the docs state the un-hide lines VBW keeps in .vbw/.gitignore for its own
# plan files, the whole-folder case (a rule such as .vbw/ or * that no line inside
# can undo), what vbw init, vbw doctor and vbw approve say then, and the fix.
# docs/record.md where it lists VBW's own files; docs/diagnostics.md where it
# documents vbw doctor. L1: the text of the docs (one line holds each fact; no
# exact wording).

load helper

RECORD="$REPO_ROOT/docs/record.md"
DIAG="$REPO_ROOT/docs/diagnostics.md"

# has_line FILE WORD...: one line of FILE holds every WORD (case-insensitive).
has_line() {
  local f="$1" lines w
  shift
  lines=$(cat "$f")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of $f holds all of: $*"; return 1; }; done
}

@test "R208: docs/record.md names the un-hide lines of .vbw/.gitignore for the record, the spec and the map, and that .gitignore un-hides itself" {
  has_line "$RECORD" '.vbw/.gitignore' '!record.json' '!spec.md' '!map.md' '!.gitignore'
  has_line "$RECORD" 'runtime/' '.vbw/.gitignore'
}

@test "R208: docs/record.md says vbw init writes them, an existing project gets them at its next VBW commit, and the project's .gitignore is never edited" {
  has_line "$RECORD" 'vbw init' '.vbw/.gitignore'
  has_line "$RECORD" 'next' 'commit' 'un-hide'
  has_line "$RECORD" 'never' "project's .gitignore"
}

@test "R208: docs/record.md states the whole-folder case: a rule such as .vbw/ or * hides the folder, nothing inside can undo it, and the fix" {
  has_line "$RECORD" '.vbw/' 'whole' 'folder'
  has_line "$RECORD" 'remove that line, or change it to .vbw/runtime/'
  has_line "$RECORD" 'check-ignore'
  has_line "$RECORD" 'approve' 'refuse'
  has_line "$RECORD" 'warning' 'hidden'
}

@test "R208: docs/diagnostics.md documents the doctor's fail line for a hidden own file and its fix" {
  sed -n '/^### vbw doctor/,/^### /p' "$DIAG" | grep -qi 'hidden from git' || { echo "the doctor section says nothing about a hidden own file"; false; }
  has_line "$DIAG" 'remove that line, or change it to .vbw/runtime/'
  has_line "$DIAG" 'check-ignore'
}
