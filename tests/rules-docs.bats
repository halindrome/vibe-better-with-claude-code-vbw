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

@test "R211: docs/proof.md's Rules section says vbw apply refuses a check whose rules two plans own that build one after the other, because the earlier plan's mutation step finds it red on unbroken code" {
  section proof.md '^## Rules' | grep -qi 'one after the other' || { echo "docs/proof.md, Rules: no sentence about plans that build one after the other"; false; }
  section proof.md '^## Rules' | grep -qi 'unbroken' || { echo "docs/proof.md, Rules: the reason (red on unbroken code) is missing"; false; }
}

@test "R211: docs/workflows.md's list of what vbw apply refuses names a check whose rules name two plans that build one after the other" {
  refusal_list | grep -qi 'one after the other' || { echo "the refusal list has no bullet for two plans building one after the other:"; refusal_list; false; }
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
