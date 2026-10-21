#!/usr/bin/env bats
# T111 (owner, 2026-10-11: no shortcuts, for every VBW user): the Architect and
# the Lead choose the optimal, future-proof design, never the merely safe or
# simple one, and name any known cost or debt instead of hiding it behind a
# fallback; the Lead's self-review refuses a design that pays a recurring cost
# (time, tokens, re-runs) to avoid thinking; QA fails a phase that introduces
# such a shortcut or unnamed debt. L1: the text of plugin/agents/architect.md,
# lead.md and qa.md (one line holds each rule's facts; D400: no exact wording).

load helper

# has_line AGENT WORD...: one line of agents/AGENT.md holds every WORD (case-insensitive).
has_line() {
  local f="$PLUGIN_ROOT/agents/$1.md" lines w
  shift
  lines=$(cat "$f")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of $f holds all of: $*"; return 1; }; done
}

@test "T111: the Architect chooses the optimal, future-proof design, never the merely safe or simple one" {
  has_line architect optimal future-proof safe simple
}

@test "T111: the Architect names known cost or debt, never hides it behind a fallback" {
  has_line architect cost debt fallback
}

@test "T111: the Lead chooses the optimal, future-proof design, never the merely safe or simple one" {
  has_line lead optimal future-proof safe simple
}

@test "T111: the Lead names known cost or debt, never hides it behind a fallback" {
  has_line lead cost debt fallback
}

@test "T111: the Lead's self-review refuses a recurring cost (time, tokens, re-runs) paid to avoid thinking" {
  has_line lead recurring time tokens re-run thinking
  grep -A3 -i '^## Stage 3' "$PLUGIN_ROOT/agents/lead.md" | grep -qi recurring
}

@test "T111: QA fails a phase that introduces a shortcut or unnamed debt" {
  has_line qa shortcut debt finding
}
