#!/usr/bin/env bash
# The Stop hook (T150, T147; docs/loop.md): the one driver of a loop and of an autonomous run. It is the
# plugin's own, declared once in hooks.json, so it lives through a resumed session and never runs twice.
# Inert unless this session has a loop on (the mark vbw loop start leaves) or an armed autonomous run in
# this project: no kernel starts otherwise. Its answer is vbw auto gate's.
in=$(cat)
s=$(printf '%s' "$in" | jq -r '.session_id // empty' 2> /dev/null) || exit 0
case "$s" in '' | *[!A-Za-z0-9_-]*) exit 0 ;; esac
rt="${CLAUDE_PROJECT_DIR:-$PWD}/.vbw/runtime"
[ -f "$rt/loop.$s" ] || [ -f "$rt/auto.$s.json" ] || exit 0
printf '%s' "$in" | "$(dirname "$0")/../bin/vbw" auto gate 2> /dev/null || true
