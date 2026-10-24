#!/usr/bin/env bash
# The Stop hook (T150, T147; docs/loop.md): the one driver of a loop and of an autonomous run. It is the
# plugin's own, declared once in hooks.json, so it lives through a resumed session and never runs twice.
# Inert unless this session has a loop on (the mark vbw loop start leaves) or an armed autonomous run in
# this project: no kernel starts otherwise. Its answer is vbw auto gate's.
# Also the StopFailure hook (T156): a turn that ended on an API error drives nothing, so the loop stops
# until the session goes on. For the loop's session it leaves the time on the away mark (an earlier
# mark stays), for the loop's next step to leave the time stopped out of the item's time. It answers
# nothing (Claude Code ignores this event's answer).
in=$(cat)
v=$(printf '%s' "$in" | jq -r '"\(.session_id | if type == "string" and test("^[A-Za-z0-9_-]+$") then . else "" end) \(.hook_event_name // "")"' 2> /dev/null) || exit 0
s=${v%% *}
case "$s" in '' | *[!A-Za-z0-9_-]*) exit 0 ;; esac
rt="${CLAUDE_PROJECT_DIR:-$PWD}/.vbw/runtime"
if [ "${v#* }" = StopFailure ]; then
  [ ! -f "$rt/loop.$s" ] || [ -e "$rt/loop-away.$s" ] || date -u +%Y-%m-%dT%H:%M:%SZ > "$rt/loop-away.$s"
  exit 0
fi
[ -f "$rt/loop.$s" ] || [ -f "$rt/auto.$s.json" ] || exit 0
printf '%s' "$in" | "$(dirname "$0")/../bin/vbw" auto gate 2> /dev/null || true
