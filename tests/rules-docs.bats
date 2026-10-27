#!/usr/bin/env bats
# R211 and R212 (T187, T191): the user documentation names the two planning-time
# refusals of vbw apply. docs/proof.md's Rules section and docs/workflows.md's list
# of what vbw apply refuses name a check whose rules two plans own that build one
# after the other (the earlier plan's mutation step would find the check red on
# unbroken code); that list and docs/record.md's requirements row say a
# requirement's rules name a plan on every rule or on none. L1: the text of the
# documents (one line or sentence holds each fact; no exact wording).

load helper

DOCS="$REPO_ROOT/docs"

# section FILE HEADING_REGEX: the text of the section whose heading line matches
# HEADING_REGEX, up to the next heading of the same or a higher level, as one line.
section() {
  awk -v re="$2" '
    /^#{1,3} / { if (found) { n = length($1); if (n <= level) exit } else if ($0 ~ re) { found = 1; level = length($1); next } }
    found { printf "%s ", $0 }' "$DOCS/$1"
}

# refusal_list: docs/workflows.md's bullets of what vbw apply refuses when rules are given,
# from "When the key is present" to the next blank-line-separated paragraph after the bullets.
refusal_list() {
  awk '/^When the key is present/ { p = 1 } p && /^- / { b = 1 } p && b && /^[^- ]/ && !/^  / { exit } p { print }' "$DOCS/workflows.md"
}

@test "R211 R215: docs/proof.md's Rules bullet says vbw apply refuses a check whose rules two plans not yet built own, order or not, and names the race of a shared wave" {
  section proof.md '^## Rules' | grep -qi 'one after the other' || { echo "docs/proof.md, Rules: no sentence about plans that build one after the other"; false; }
  section proof.md '^## Rules' | grep -qi 'unbroken' || { echo "docs/proof.md, Rules: the reason (red on unbroken code) is missing"; false; }
  section proof.md '^## Rules' | grep -qi 'order or not' || { echo "docs/proof.md, Rules: the refusal is not said to cover any order"; false; }
  section proof.md '^## Rules' | grep -qi 'race' || { echo "docs/proof.md, Rules: the race of a shared wave is not named"; false; }
}

@test "R211 R215: docs/workflows.md's list of what vbw apply refuses covers any two plans not yet built, order or not, and names the race of a shared wave" {
  refusal_list | grep -qi 'one after the other' || { echo "the refusal list has no bullet for two plans building one after the other:"; refusal_list; false; }
  refusal_list | grep -qi 'order or not' || { echo "the refusal list does not say order or not:"; refusal_list; false; }
  refusal_list | grep -qi 'race' || { echo "the refusal list does not name the race of a shared wave:"; refusal_list; false; }
}

@test "R212: docs/workflows.md's list of what vbw apply refuses names a requirement whose rules name a plan on only some" {
  refusal_list | grep -qi 'only some' || { echo "the refusal list has no bullet for a requirement naming a plan on only some rules:"; refusal_list; false; }
}

@test "R212: docs/record.md's requirements row says plan is named on every rule of the requirement or on none" {
  grep '^| `requirements\[\]` |' "$DOCS/record.md" | grep -q 'every rule' || { echo "the requirements row does not say every rule"; false; }
  grep '^| `requirements\[\]` |' "$DOCS/record.md" | grep -q 'or on none' || { echo "the requirements row does not say or on none"; false; }
}

@test "R213: docs/record.md's plans row and docs/workflows.md's vbw apply row say a started plan keeps its note (the blocked reason) with its status and breaks across every vbw apply" {
  grep '^| `plans\[\]` |' "$DOCS/record.md" | grep -Eiq 'note[^.|]*vbw apply|vbw apply[^.|]*note' \
    || { echo "docs/record.md, plans row: no sentence says vbw apply keeps the note"; false; }
  grep '^| `vbw apply < plan.json` |' "$DOCS/workflows.md" | grep -qi 'note' \
    || { echo "docs/workflows.md, vbw apply row: the kept note is not named"; false; }
}

# refusal_row PATTERN: the "Next step" cell of the row of docs/workflows.md's refusal table
# whose "Refusal" cell matches PATTERN.
refusal_row() {
  awk '/^### Every refusal and its next step/ { p = 1; next } p && /^### / { exit } p && /^\| / { print }' "$DOCS/workflows.md" \
    | grep -E "^\| [^|]*($1)[^|]* \|" | sed -e 's/^| .* | //' -e 's/ |$//'
}

# kernel_next MESSAGE: what apply_next of the kernel answers to MESSAGE.
kernel_next() {
  bash -c 'VBW_LIB="$1/lib"; . "$VBW_LIB/cmd-apply.sh"; apply_next "$2"' _ "$PLUGIN_ROOT" "$1"
}

@test "R216: the refusal table's two-owner row (both wordings) and mixed-owner row carry the kernel's Next text" {
  local ordered beside mixed row
  ordered="C1 is owned by two plans that build one after the other (P1.2 builds after P1.1): P1.1 and P1.2; the earlier plan's mutation step would find C1 red on unbroken code"
  beside="C1 is owned by two plans that build beside each other (a shared wave): P1.1 and P1.2; the first Dev's mutation step would run C1 before the other Dev committed, a race that fails only sometimes"
  mixed="R1: 1 of 2 rules name a plan: name one on every rule or on none"
  row=$(refusal_row 'one after the other')
  [ -n "$row" ] || { echo "no two-owner row in the refusal table"; false; }
  [ "$(refusal_row 'beside each other')" = "$row" ] || { echo "the two-owner row does not name both wordings"; false; }
  [ "$(kernel_next "$ordered")" = "$(kernel_next "$beside")" ] || { echo "the kernel answers the two wordings differently"; false; }
  [ "$row" = "$(kernel_next "$ordered")" ] || { echo "two-owner row: '$row' differs from the kernel's '$(kernel_next "$ordered")'"; false; }
  row=$(refusal_row 'only some')
  [ -n "$row" ] || { echo "no mixed-owner row in the refusal table"; false; }
  [ "$row" = "$(kernel_next "$mixed")" ] || { echo "mixed-owner row: '$row' differs from the kernel's '$(kernel_next "$mixed")'"; false; }
}
