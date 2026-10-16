#!/usr/bin/env bats
# R190, phase P146 (L1): docs/panel.md describes Comms, Mission Control, the Now
# box, the clock times and the three motion settings as the panel behaves after
# M34, and says nothing about a feature that no longer exists (a gate card with
# buttons, a Later button, a Telemetry pane, the running-person animation).
# Facts a reader needs, not exact sentences (D400). The behaviour is in
# tests/panel/r190/*.test.mjs and tests/panel/r189/*.test.mjs.

load helper

DOC="$REPO_ROOT/docs/panel.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$1 lacks: $2"; return 1; }; }
hasnt() {
  local hit
  hit=$(flat "$1" | grep -oE -- "$2" | head -n 1)
  [ -z "$hit" ] || { echo "$1 still says: $hit"; return 1; }
}

@test "R190: docs/panel.md calls the strip above the prompt Comms and the pane Mission Control, never the other way round" {
  has "$DOC" 'comms\*{0,2},? the strip (directly )?above the prompt'
  has "$DOC" 'mission control\*{0,2},? (a|the) pane'
  hasnt "$DOC" 'mission control\*{0,2},? the strip'
  hasnt "$DOC" 'comms\*{0,2},? (a|the) (side )?pane'
}

@test "R190: docs/panel.md puts the what's happening now box first on the Now tab, nowhere a list of sentences before it" {
  has "$DOC" 'now\*{0,2} tab opens on (a|the) framed'
  hasnt "$DOC" 'tab (starts|begins|opens) with these sentences'
}

@test "R190: every time-left and needs-you sentence docs/panel.md shows starts with its [HH:MM] stamp" {
  run grep -nE '^ *(About [0-9]+ min left|This step is taking longer than usual|Please approve|Please check the result|The milestone is ready|VBW has a question|A decision is needed|Work is blocked)' "$DOC"
  [ "$status" -ne 0 ] || { echo "example sentences without their [HH:MM] stamp:"; echo "$output"; false; }
  grep -qE '^ *\[[0-9]{2}:[0-9]{2}\] About [0-9]+ min left' "$DOC" || { echo "docs/panel.md has no stamped time-left example"; false; }
  grep -qE '^ *\[[0-9]{2}:[0-9]{2}\] Please approve' "$DOC" || { echo "docs/panel.md has no stamped needs-you example"; false; }
}

@test "R190: docs/panel.md says a stamp stays while the clock alone moves, and a sentence with no known start time has none" {
  has "$DOC" 'clock alone'
  has "$DOC" 'no known (start )?time'
  has "$DOC" '(without|no) (a |any |its )?(\[hh:mm\] )?(stamp|clock time)'
  has "$DOC" 'no estimate yet'
}

@test "R190: docs/panel.md describes the three motion settings: figures for at most 3 at full, one text row per helper at calm, nothing moving when off" {
  has "$DOC" 'at most 3 working helpers get a figure at full motion'
  has "$DOC" 'calm[^.|]{0,40}(every|each) helper[^.|]{0,30}one (text )?(row|line)'
  has "$DOC" 'off[^.|]{0,40}nothing (moves|animates)'
}

@test "R190: docs/panel.md says nothing about a feature that no longer exists" {
  hasnt "$DOC" 'telemetry'
  hasnt "$DOC" '/vbw-telemetry'
  hasnt "$DOC" '\bthe band\b'
  hasnt "$DOC" 'gate card'
  hasnt "$DOC" 'needs you.? card'
  hasnt "$DOC" 'card with (its )?buttons'
  hasnt "$DOC" '(\[later\]|later button|button[^.]{0,30} later\b)'
  hasnt "$DOC" 'running (person|man)'
  hasnt "$DOC" 'big (running )?(figure|animation)'
}
