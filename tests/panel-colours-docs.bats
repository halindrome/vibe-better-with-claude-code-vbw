#!/usr/bin/env bats
# R189, phase P145 (L1): docs/panel.md and README.md describe the colours, Comms
# and Mission Control as they now behave (D406, D407): helper roles have colours
# of their own, never green, red, amber or grey, which keep one meaning each.
# Facts a reader needs, not exact sentences (D400). The behaviour is in
# tests/panel/r189/meaning.test.mjs and containment.test.mjs.

load helper

DOC="$REPO_ROOT/docs/panel.md"
README="$REPO_ROOT/README.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$1 lacks: $2"; return 1; }; }

@test "R189: docs/panel.md no longer gives a role a state's colour" {
  run grep -niE '^\| *(dev|debugger|qa) *\| *(green|red|yellow)' "$DOC"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R189: docs/panel.md says what each state colour means" {
  has "$DOC" 'green[^.|]*done'
  has "$DOC" 'red[^.|]*fail'
  has "$DOC" 'amber[^.|]*(needs you|running)'
  has "$DOC" 'gr[ae]y[^.|]*(idle|quiet)'
}

@test "R189: README.md names Comms and Mission Control" {
  has "$README" '\bcomms\b'
  has "$README" 'mission control'
}
