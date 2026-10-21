#!/usr/bin/env bats
# R195 (T165): docs/proof.md's kept-output section names vbw fix done and
# vbw check beside vbw prove as the commands that keep failing output, and
# docs/proof.md and the fixing workflow's Dev instruction point to vbw show fix
# for the full output and the failing test names. L1: the text of the documents
# and the workflow source.

load helper

DOCS="$REPO_ROOT/docs"
FIXING="$PLUGIN_ROOT/workflows/fixing.js"

# section_with FILE PATTERN: the text of the section (between headings) that
# holds the first line matching PATTERN, as one line.
section_with() {
  awk -v re="$2" '
    /^#{1,4} / { if (found) exit; buf = "" }
    { buf = buf $0 " " }
    $0 ~ re && !found { found = 1 }
    END { if (found) printf "%s", buf }' "$DOCS/$1"
}

@test "R195: docs/proof.md's kept-output section names vbw fix done and vbw check beside vbw prove, and points to vbw show fix for the failing test names" {
  local s
  s=$(section_with proof.md 'runtime/output/C1\.log')
  [ -n "$s" ] || { echo "docs/proof.md has no section naming .vbw/runtime/output/C1.log"; false; }
  printf '%s' "$s" | grep -qF 'vbw fix done' || { echo "the kept-output section does not name vbw fix done"; false; }
  printf '%s' "$s" | grep -qF 'vbw check' || { echo "the kept-output section does not name vbw check"; false; }
  printf '%s' "$s" | grep -qF 'vbw show fix' || { echo "the kept-output section does not point to vbw show fix"; false; }
  printf '%s' "$s" | grep -qi 'failing test' || { echo "the kept-output section does not mention the failing test names"; false; }
}

@test "R195: docs/proof.md's fix section says vbw show fix lists the failing test files and the failing test names" {
  local s
  s=$(section_with proof.md '^### Fix items')
  printf '%s' "$s" | grep -qi 'failing test' || { echo "docs/proof.md, Fix items: the failing test names are not mentioned"; false; }
  printf '%s' "$s" | grep -qi 'test file' || { echo "docs/proof.md, Fix items: failing test files are not mentioned"; false; }
}

@test "R195: the fixing workflow's Dev instruction points to vbw show fix for the full output and the failing test names" {
  grep -q 'vbw show fix' "$FIXING"
  grep -qi 'full output and the failing test names with vbw show fix' "$FIXING" || { echo "the Dev instruction does not point to vbw show fix for them"; false; }
  grep -qi 'full output' "$FIXING" || { echo "fixing.js does not mention the full output"; false; }
  grep -qi 'failing test' "$FIXING" || { echo "fixing.js does not mention the failing test names"; false; }
}

@test "R195: the vbw check reference entries say a failing check's output is kept, and a pass in vbw check leaves the file" {
  local e
  e=$(awk '/^### `vbw check/ { f = 1; next } /^#{1,3} / { f = 0 } f { printf "%s ", $0 }' "$DOCS/proof.md")
  printf '%s' "$e" | grep -qF 'runtime/output' || { echo "docs/proof.md's vbw check reference does not name the kept output"; false; }
  ! printf '%s' "$e" | grep -q 'writes nothing' || { echo "docs/proof.md's vbw check reference still says it writes nothing"; false; }
  grep -E '^\| `vbw check ' "$DOCS/workflows.md" | grep -qF 'runtime/output' || { echo "docs/workflows.md's vbw check row does not name the kept output"; false; }
  grep -qE 'a pass in `vbw check`[[:space:]]*$|a pass in `vbw check`' "$DOCS/proof.md" || { echo "docs/proof.md does not say a pass in vbw check leaves the file"; false; }
}
