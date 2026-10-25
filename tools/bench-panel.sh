#!/usr/bin/env bash
# Panel cost budget (R55): the panel (plugin/hooks/panel.js) runs inside Claude
# Code for the whole session, so each refresh must stay cheap. tools/bench-panel.mjs
# mounts it on the test stand-in for Claude Code and measures the CPU time
# (user + system, not time spent waiting) of one refresh, averaged over
# VBW_BENCH_RUNS (default 200):
#   - tick, nothing changed: the timer fires, the files are only checked;
#   - refresh, state changed: a file changed, is read, and the panel redraws;
#   - step, a running step: the kernel's note changed, is read and Mission Control draws it;
#   - render, Comms and Mission Control: five helpers at work, both drawn on each refresh.
# The stand-in's own work is inside the numbers, so they are an upper bound: about
# 40 percent of a render figure (by a profile) is the stand-in's and the test's file writes. Each case is
# warmed up for 1000 refreshes (V8 compiles the panel in the first hundreds, on
# threads that count as CPU) and reported as the median of 5 windows, so one
# garbage collection counts once. VBW_BENCH_WARM=20 measures a freshly loaded panel.
# Measured 2026-10-24 on an Apple M1 Max (node 22.22, load 4 to 6 from other work):
# tick 0.04 to 0.07 ms, refresh 0.11 to 0.14 ms, render 0.22 to 0.32 ms. The budget
# is VBW_PANEL_BUDGET_MS per refresh (default 0.5, a margin for a loaded machine);
# a real regression (reading every file on every tick, a subprocess, a redraw per
# tick) costs several times more than that.
# CI sets a looser value for its slower machines. Needs node; skips without it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_MS="${VBW_PANEL_BUDGET_MS:-0.5}"

if ! command -v node > /dev/null 2>&1; then
  echo "node not installed; skipping the panel cost budget" >&2
  exit 0
fi

out="$(node "$ROOT/tools/bench-panel.mjs")"
tick="$(printf '%s\n' "$out" | awk '$1 == "tick" { print $2 }')"
refresh="$(printf '%s\n' "$out" | awk '$1 == "refresh" { print $2 }')"
sound="$(printf '%s\n' "$out" | awk '$1 == "sound" { print $2 }')"
stepped="$(printf '%s\n' "$out" | awk '$1 == "step" { print $2 }')"
glance="$(printf '%s\n' "$out" | awk '$1 == "glance" { print $2 }')"
render="$(printf '%s\n' "$out" | awk '$1 == "render" { print $2 }')"
whats_next="$(printf '%s\n' "$out" | awk '$1 == "whats-next" { print $2 }')"
[ -n "$stepped" ] && [ -n "$render" ] && [ -n "$whats_next" ] && [ -n "$glance" ] && [ -n "$sound" ] && [ -n "$tick" ] && [ -n "$refresh" ] || { echo "bench-panel: the driver printed no measurement: $out" >&2; exit 1; }

printf 'tick, nothing changed: %s ms CPU\n' "$tick"
printf 'refresh, state changed: %s ms CPU\n' "$refresh"
printf 'render, Comms and Mission Control: %s ms CPU\n' "$render"
printf 'sound, need raised: %s ms CPU\n' "$sound"
printf 'refresh with a running step: %s ms CPU\n' "$stepped"
printf 'refresh with cost and estimates: %s ms CPU\n' "$glance"
printf "refresh with what's next: %s ms CPU\n" "$whats_next"
printf 'budget: %s ms\n' "$BUDGET_MS"

status=0
for v in "$tick" "$refresh" "$sound" "$glance" "$whats_next" "$render" "$stepped"; do
  perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$v" "$BUDGET_MS" || status=1
done
[ "$status" -eq 0 ] || echo "bench-panel: a refresh is over the budget of $BUDGET_MS ms" >&2
exit "$status"
