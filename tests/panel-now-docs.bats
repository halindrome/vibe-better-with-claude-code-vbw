#!/usr/bin/env bats
# R189, phase P144 (L1): docs/panel.md describes the Now tab's "what's happening
# now" box, the clock times on events and messages, the What's next rows as
# buttons that fill the prompt, and the mark on new things that stays until
# seen. Facts a reader needs, not exact sentences (D400). The behaviour is in
# tests/panel/r189/now-box.test.mjs and next-buttons.test.mjs.

load helper

DOC="$REPO_ROOT/docs/panel.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$1 lacks: $2"; return 1; }; }

@test "R189: docs/panel.md describes the what's happening now box at the top of the Now tab" {
  has "$DOC" "what.s happening now"
  grep -qiE "^#+ what.s happening now" "$DOC" || { echo "docs/panel.md has no what's happening now heading"; false; }
  grep -qiE '^[|] +nothing (is )?running' "$DOC" || { echo "docs/panel.md has no idle example in the box"; false; }
}

@test "B5: docs/panel.md says the box draws the step's parts as a strip with its figure, and the milestone's end with its basis" {
  has "$DOC" 'strip[^.]*(parts|done)'
  has "$DOC" '[0-9]+ of [0-9]+ done'
  has "$DOC" "milestone.s end[^.]*basis|basis: "
}

@test "2.1.11: docs/panel.md says a time on another day names the day" {
  has "$DOC" 'another day names the day'
  has "$DOC" 'waiting since yesterday 21:38'
}

@test "R189: docs/panel.md shows events and messages starting with their clock time" {
  grep -qE '\[[0-9]{2}:[0-9]{2}\] ' "$DOC" || { echo "docs/panel.md has no [HH:MM] example"; false; }
}

@test "R189: docs/panel.md says each What's next row is a button that fills the prompt, with a size chip" {
  has "$DOC" "what.s next[^.]*(row|pick)[^.]*button|button[^.]*(row|pick)"
  has "$DOC" 'chip'
}

@test "R189: docs/panel.md says new things stay marked until you have seen them" {
  has "$DOC" 'until you (have )?(seen|see|open|press)'
  has "$DOC" "'new'|\"new\"|\`new\`"
}
