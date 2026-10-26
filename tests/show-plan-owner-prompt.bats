#!/usr/bin/env bats
# R209 (D504): plugin/agents/dev.md tells the Dev that red-first and green use
# only the plan's own checks (those vbw show plan leaves unmarked), that a check
# marked another plan's stays red until that plan is built, is never a blocker
# and never DEVN-04, and is at most named in notes; and the DEVN-04 row no longer
# reads a file another plan owns for its own marked rule as a plan that cannot
# work as written. L1: the words of the prompt (one line holds each fact; no
# exact wording). tests/mutate-prompts.bats and the prompt case of
# tests/mutate-own-rules.bats pin the mutation words this file leaves alone.

load helper

DEV="$PLUGIN_ROOT/agents/dev.md"

# step N: the numbered step N of Stage 2 (one line).
step() { grep -E "^$1\. \*\*" "$DEV"; }
# holds TEXT WORD...: TEXT holds every WORD (case-insensitive).
holds() {
  local lines="$1" w
  shift
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line holds all of: $*"; return 1; }; done
}

@test "R209: the red-first step runs vbw check --expect-red on the plan's own checks only, those vbw show plan leaves unmarked" {
  holds "$(step 1)" "red first" "--expect-red" "own" "unmarked"
}

@test "R209: the green step ends when every own check passes" {
  holds "$(step 3)" "green" "own check"
}

@test "R209: one sentence says a check marked another plan's stays red until that plan is built, is never a blocker nor DEVN-04, and is at most named in notes" {
  holds "$(cat "$DEV")" "another plan" "red until" "never a blocker" "DEVN-04" "notes"
}

@test "R209: the DEVN-04 row keeps 'plan cannot work as written' but excludes a file another plan owns for its own marked rule" {
  local row
  row=$(grep -E '^\| DEVN-04' "$DEV")
  holds "$row" "plan cannot work as written"
  holds "$row" "another plan" "marked"
}
