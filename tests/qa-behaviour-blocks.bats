#!/usr/bin/env bats
# D400: only behaviour blocks shipping. QA's finding (which fails a phase and
# opens a fix) is kept for behaviour: code that does something wrong or misses a
# promised behaviour, a test of a behaviour that is missing or cannot fail, a
# false or missing fact in a document (a command, setting, number, file, limit),
# a deviation from the plan or a recorded decision. Wording, tone, style, naming
# and a test that does not pin a sentence's exact words are notes in the
# summary, never findings, and never fail a phase. L1: the text of
# plugin/agents/qa.md.

load helper

QA="$PLUGIN_ROOT/agents/qa.md"

# has_line WORD...: one line of qa.md holds every WORD (case-insensitive).
has_line() {
  local lines w
  lines=$(cat "$QA")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of qa.md holds all of: $*"; return 1; }; done
}

@test "D400: only behaviour is a finding; a finding fails the phase" {
  has_line "only behaviour" finding
}

@test "D400: a false or missing fact in a document is a finding" {
  has_line fact command setting finding
}

@test "D400: wording, style and exact-sentence pinning are notes, never findings" {
  has_line wording style note "never a finding"
  has_line "exact words" note
}

@test "D400: notes go in the summary and never fail a phase" {
  has_line notes summary "never fail"
}
