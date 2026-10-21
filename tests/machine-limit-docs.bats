#!/usr/bin/env bats
# R181 (docs/proof.md, CLAUDE.md): the user documentation names the facts of the
# computer-wide limit: where the slot store lives, the folders it uses, and the
# lines a run prints about it. The "Nothing outside the project" rule in
# CLAUDE.md names the slot store as an exception, with R181 as its source. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R181: docs/proof.md names where the slot store lives" {
  grep -qF '<claude-config-dir>/vbw/slots.json' "$DOC"
  grep -qF 'CLAUDE_CONFIG_DIR' "$DOC"
  # shellcheck disable=SC2088 # the literal text the docs show
  grep -qF '~/.config/claude-code' "$DOC"
}

@test "R181: docs/proof.md shows the lines a run prints about the limit" {
  grep -qF 'the computer-wide limit was not in force' "$DOC"
  grep -qF 'for other VBW runs on this computer' "$DOC"
  grep -qF 'machine limit:' "$DOC"
}

@test "R181: CLAUDE.md names the slot store as an exception to 'Nothing outside the project', with R181 as its source" {
  local rule
  rule=$(grep '^- \*\*Nothing outside the project:\*\*' "$REPO_ROOT/CLAUDE.md")
  [ -n "$rule" ]
  [[ "$rule" == *"settings.json"* ]] || { echo "$rule"; false; }
  [[ "$rule" == *"<claude-config-dir>/vbw/"* ]] || { echo "$rule"; false; }
  [[ "$rule" == *"R181"* ]] || { echo "$rule"; false; }
}
