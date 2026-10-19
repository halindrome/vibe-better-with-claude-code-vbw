#!/usr/bin/env bats
# R194 (T124, T165): the user documentation says a requirement fix commits its
# own requirement's check files with vbw commit --fix, code goes through the
# plan, and the files wait for one approval before the proof: docs/workflows.md's
# `vbw commit --fix` row, docs/guards.md's fix-run row and docs/proof.md's fix
# section. L1: the text of the documents.

load helper

DOCS="$REPO_ROOT/docs"

# section FILE HEADING_REGEX: the text of the section whose heading line matches
# HEADING_REGEX, up to the next heading of the same or a higher level, as one line.
section() {
  awk -v re="$2" '
    /^#{1,3} / { if (found) { n = length($1); if (n <= level) exit } else if ($0 ~ re) { found = 1; level = length($1); next } }
    found { printf "%s ", $0 }' "$DOCS/$1"
}

@test "R194: docs/workflows.md's vbw commit --fix row: a requirement fix commits its requirement's check files with both trailers, code through the plan, one approval" {
  local row
  row=$(grep -E '^\| `vbw commit --fix' "$DOCS/workflows.md")
  [ -n "$row" ] || { echo "docs/workflows.md has no vbw commit --fix row"; false; }
  printf '%s' "$row" | grep -qi 'check file' || { echo "the row does not name check files: $row"; false; }
  printf '%s' "$row" | grep -q 'VBW-Req' || { echo "the row does not name the VBW-Req trailer: $row"; false; }
  printf '%s' "$row" | grep -qi 'approv' || { echo "the row does not name the approval: $row"; false; }
  printf '%s' "$row" | grep -q 'vbw commit P' || { echo "the row does not send code through the plan: $row"; false; }
}

@test "R194: docs/guards.md's fix-run row: every requirement fix's run opens its own requirement's check files, a proof's fix included" {
  local row
  row=$(grep -E '^\| Writing a protected check file during a `fix` run' "$DOCS/guards.md")
  [ -n "$row" ] || { echo "docs/guards.md has no row for check files during a fix run"; false; }
  printf '%s' "$row" | grep -qi 'own requirement\|its requirement\|the fix.s requirement' || { echo "the row does not say whose check files open: $row"; false; }
  printf '%s' "$row" | grep -qi 'approv' || { echo "the row does not name the approval: $row"; false; }
  ! grep -q 'stay fully protected' "$DOCS/guards.md" || { echo "docs/guards.md still says a failed proof's fix run stays fully protected"; false; }
}

@test "R194: docs/proof.md's fix section says a requirement fix commits its own check files with vbw commit --fix and that they wait for one approval" {
  local s
  s=$(section proof.md '^### Fix items')
  printf '%s' "$s" | grep -qF 'vbw commit --fix' || { echo "docs/proof.md, Fix items: vbw commit --fix is not mentioned"; false; }
  printf '%s' "$s" | grep -qi 'check file' || { echo "docs/proof.md, Fix items: check files are not mentioned"; false; }
  printf '%s' "$s" | grep -qi 'approv' || { echo "docs/proof.md, Fix items: the approval is not mentioned"; false; }
}
