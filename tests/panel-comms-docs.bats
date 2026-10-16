#!/usr/bin/env bats
# R189, phase P142 (L1): docs/panel.md names the strip above the prompt Comms and
# the pane Mission Control (D406), never "the band" or "Telemetry"; it shows the
# needs-you line, says it has no buttons, and says when each message clears.
# Facts a reader needs, not exact sentences (D400). The behaviour is in
# tests/panel/r189/comms-need.test.mjs and comms-crew.test.mjs.

load helper

DOC="$REPO_ROOT/docs/panel.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$1 lacks: $2"; return 1; }; }

@test "R189: docs/panel.md calls the strip Comms and the pane Mission Control, never the band or Telemetry" {
  has "$DOC" '\bcomms\b'
  has "$DOC" 'mission control'
  run grep -niE '\bband\b|telemetry' "$DOC"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R189: README.md and the skills never call the strip the band or the pane Telemetry" {
  run grep -rniE '\bthe band\b|telemetry' "$REPO_ROOT/README.md" "$PLUGIN_ROOT/skills"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R189: docs/panel.md shows the needs-you line and says it has no buttons" {
  grep -qE '[0-9]{2}:[0-9]{2} ⚑ VBW needs you · ' "$DOC" || { echo "docs/panel.md has no example of the needs-you line"; false; }
  has "$DOC" '(no|without) buttons?'
}

@test "R189: docs/panel.md says when each message clears, and how helpers come and go" {
  has "$DOC" '(clears|disappears|goes away)'
  has "$DOC" 'approv'
  has "$DOC" 'ship'
  has "$DOC" 'answer'
  has "$DOC" 'finish'
  has "$DOC" 'fail'
  has "$DOC" '\+[0-9n]+ more'
}

@test "R189: docs/panel.md ties each clearing to its event: ship, answer, a run starting, the run ending" {
  has "$DOC" 'ready to ship.{0,40}milestone ships|milestone ships.{0,40}ready to ship'
  has "$DOC" 'you answer'
  has "$DOC" 'a run starts'
  has "$DOC" 'run ends.{0,40}crew leaves comms|crew leaves comms.{0,40}run ends'
}

@test "R189: docs/panel.md states the helper-row facts: a finished helper leaves at once, a failed one stays red until opened" {
  has "$DOC" 'helper that finishes leaves comms at the next redraw, with no wait'
  has "$DOC" 'helper that fails stays as one red'
  has "$DOC" 'until you open it in mission control'
}

@test "R189: docs/panel.md says at most 3 working helpers get a figure at full motion and the rest are text rows" {
  has "$DOC" 'at most 3 working helpers get a figure at full motion'
  has "$DOC" 'other helpers are text rows'
}

@test "R189: docs/panel.md never draws a figure for every agent, nor a done, failed or quiet figure on Comms" {
  run grep -niE 'each agent in comms' "$DOC"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  run grep -niE 'posed by[^|]*(done|failed|quiet)' "$DOC"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  has "$DOC" 'never draws a done, failed or quiet figure'
}
