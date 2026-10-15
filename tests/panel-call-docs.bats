#!/usr/bin/env bats
# R189, phase P143 (L1): docs/panel.md says when the needs-you sound and the
# native notification happen (once, when Claude Code's own question menu opens;
# the notification also for a new What's next recommendation) and how to turn
# them off. Facts a reader needs, not exact sentences (D400). The behaviour is
# in tests/panel/r189/call.test.mjs.

load helper

DOC="$REPO_ROOT/docs/panel.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$1 lacks: $2"; return 1; }; }

@test "R189: docs/panel.md ties the sound to Claude Code's own question menu, once per question" {
  has "$DOC" '(question menu|askuserquestion)'
  has "$DOC" 'once'
}

@test "R189: docs/panel.md describes the notification: when it comes, for a new recommendation too, and that it follows the sound switch" {
  has "$DOC" 'notification'
  has "$DOC" 'notification[^.]*(recommendation|what.s next)|(recommendation|what.s next)[^.]*notification'
  has "$DOC" '/vbw-sound off'
  has "$DOC" 'notification[^.]*(off|switch)|(off|switch)[^.]*notification'
}
