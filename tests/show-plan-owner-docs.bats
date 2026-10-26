#!/usr/bin/env bats
# R209 (D504): docs/workflows.md (the vbw show plan row and the mutation check's
# task-form bullet) and docs/proof.md (the paragraph on a rule that names its
# plan) show the two marks vbw show plan prints, as printed, name the ORDER words,
# and say the Dev's red-first and green steps use only the plan's own checks and
# that another plan's red check is no blocker. L1: the text of the docs (one line
# holds each fact; the marks in their printed form).

load helper

WF="$REPO_ROOT/docs/workflows.md"
PROOF="$REPO_ROOT/docs/proof.md"

RULE_MARK="'s, built after this plan]"
CHECK_MARK="'s: red until it is built, not this plan's to pass]"

mutation_section() { sed -n '/^## The mutation check/,/^## /p' "$WF"; }
proof_section() { sed -n '/^### The mutation check/,/^### /p' "$PROOF"; }
show_plan_row() { grep -E '^\| `vbw show plan' "$WF"; }

# holds TEXT WORD...: TEXT holds every WORD (case-insensitive).
holds() {
  local lines="$1" w
  shift
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line holds all of: $*"; return 1; }; done
}

@test "R209: docs/workflows.md's vbw show plan row names the marks for another plan's rules and checks" {
  holds "$(show_plan_row)" "another plan" "own"
  holds "$(show_plan_row)" "'s"
}

@test "R209: docs/workflows.md shows the two marks as printed and names the ORDER words" {
  grep -qF -- "$RULE_MARK" "$WF" || { echo "no rule mark as printed"; false; }
  grep -qF -- "$CHECK_MARK" "$WF" || { echo "no check mark as printed"; false; }
  local w
  for w in "built before this plan" "built after this plan" "built beside this plan" "'s, done]" "'s, blocked]"; do
    grep -qF -- "$w" "$WF" || { echo "workflows.md does not name: $w"; false; }
  done
}

@test "R209: docs/workflows.md's task-form bullet points at the unmarked rules, and the doc says red-first and green use only the plan's own checks and another plan's red check is no blocker" {
  holds "$(mutation_section)" "task" "show plan" "own"
  holds "$(cat "$WF")" "red" "own checks"
  holds "$(cat "$WF")" "another plan" "red" "blocker"
}

@test "R209: docs/proof.md's paragraph on a rule that names its plan shows the two marks, names the ORDER words, and says another plan's red check is no blocker" {
  local s
  s=$(proof_section)
  holds "$s" "names its plan"
  printf '%s\n' "$s" | grep -qF -- "$RULE_MARK" || { echo "no rule mark as printed in the mutation section"; false; }
  printf '%s\n' "$s" | grep -qF -- "$CHECK_MARK" || { echo "no check mark as printed in the mutation section"; false; }
  local w
  for w in "built before this plan" "built after this plan" "built beside this plan"; do
    printf '%s\n' "$s" | grep -qF -- "$w" || { echo "the section does not name: $w"; false; }
  done
  holds "$s" "another plan" "red" "blocker"
  holds "$s" "own checks"
}
