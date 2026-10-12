#!/usr/bin/env bash
# What a session, a run and a milestone cost (R173; docs/costs.md). Sourced by the commands that
# need it. The status line writes one side file per Claude Code session,
# $VBW_RUNTIME/cost.SESSION.json ({session, usd, in, out, at}); these functions read them, diff
# them and sum them. They never write. jq only; the record reaches jq as a --slurpfile.

# Round to micro-dollars so a difference of two floats prints as written.
COSTS_ROUND='def r: (. * 1000000 | round) / 1000000;'

# The one remedy text for a cost nobody could measure.
costs_remedy() { printf 'turn the VBW status line on: vbw statusline on'; }

# costs_figures SID: the session's latest figures as {usd, in, out}, or null when the side file
# is missing or malformed.
costs_figures() {
  local f="$VBW_RUNTIME/cost.${1:-}.json"
  [ -n "${1:-}" ] && [ -f "$f" ] || { printf 'null\n'; return 0; }
  jq -c "$COSTS_ROUND"'
    if type == "object" and all((.usd, .in, .out); type == "number" and . >= 0)
    then {usd: (.usd | r), in, out} else null end' "$f" 2> /dev/null || printf 'null\n'
}

# costs_diff END START: END minus START per field (JSON figures), null when either is null.
costs_diff() {
  jq -nc "$COSTS_ROUND"' $ARGS.positional[0] as $e | $ARGS.positional[1] as $s
    | if $e == null or $s == null then null
      else {usd: (($e.usd - $s.usd) | r), in: ($e.in - $s.in), out: ($e.out - $s.out)} end' \
    --jsonargs "${1:-null}" "${2:-null}"
}

# costs_sessions: every session id that has a side file, one per line.
costs_sessions() {
  local f b
  for f in "$VBW_RUNTIME"/cost.*.json; do
    [ -f "$f" ] || continue
    b=${f##*/}; b=${b#cost.}; printf '%s\n' "${b%.json}"
  done
}

# costs_milestone_total RECORD M: the milestone's cost as {usd, in, out, sessions}. The frozen total
# when the record (a file) has one; null for a shipped milestone without one (its ship saw no
# figures, and what is spent since belongs to the milestones after it); else the sum over the sessions with a side file of the latest
# figures minus the milestone's baseline for that session (a session without a baseline counts from
# its first figure, that is whole), with the number of sessions counted. null when no session has
# figures.
costs_milestone_total() {
  local rec=${1:-} m=${2:-} sid figs lines=""
  [ -f "$rec" ] || { printf 'null\n'; return 0; }
  if jq -e --arg m "$m" '.costs.milestones[$m].total? != null' "$rec" > /dev/null 2>&1; then
    jq -c --arg m "$m" '.costs.milestones[$m].total' "$rec"; return 0
  fi
  if jq -e --arg m "$m" 'any(.shipped[]?; .id == $m)' "$rec" > /dev/null 2>&1; then
    printf 'null\n'; return 0
  fi
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    figs=$(costs_figures "$sid")
    [ "$figs" = null ] && continue
    lines="$lines$(jq -nc --arg s "$sid" --argjson f "$figs" '{s: $s, f: $f}')"$'\n'
  done < <(costs_sessions)
  [ -n "$lines" ] || { printf 'null\n'; return 0; }
  printf '%s' "$lines" | jq -sc --slurpfile rec "$rec" --arg m "$m" "$COSTS_ROUND"'
    ($rec[0].costs.milestones[$m].baseline // {}) as $b
    | [.[] | .f as $f | ($b[.s] // {usd: 0, in: 0, out: 0}) as $z
        | {usd: ($f.usd - $z.usd), in: ($f.in - $z.in), out: ($f.out - $z.out)}]
    | {usd: (map(.usd) | add | r), in: (map(.in) | add), out: (map(.out) | add), sessions: length}'
}
