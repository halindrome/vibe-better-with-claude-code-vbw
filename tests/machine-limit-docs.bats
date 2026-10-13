#!/usr/bin/env bats
# R181 (docs/proof.md, docs/guards.md, CLAUDE.md): the user documentation
# explains the computer-wide limit in current-behaviour terms: what it counts
# (each check or test unit, one slot each), where the slot store lives, how
# turns are shared (fewest held first), that waiting never changes results or
# timeouts, how slots of a killed run come back, and what happens when the
# store cannot be written (the sandbox case) and how to tell from the output.
# The "Nothing outside the project" rule in CLAUDE.md names the slot store as
# its second exception, with R181 as its source, and the user docs say the
# same. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R181: docs/proof.md names the computer-wide limit: three quarters of the cores, shared by every project, not a setting" {
  grep -qi 'computer-wide limit' "$DOC"
  grep -qi 'machine limit' "$DOC"
  grep -qiE 'every VBW project on (this|the|your) computer' "$DOC"
  grep -qiE 'not a setting' "$DOC"
  grep -qiE 'check_jobs[^.]*(below|under|per[- ]run)' "$DOC"
}

@test "R181: docs/proof.md says what takes a slot and where the slot store lives" {
  grep -qiE 'one slot' "$DOC"
  grep -qiE 'test file' "$DOC"
  grep -qiE 'project command' "$DOC"
  grep -qF '<claude-config-dir>/vbw/slots.json' "$DOC"
  grep -qF 'CLAUDE_CONFIG_DIR' "$DOC"
  # shellcheck disable=SC2088 # the literal text the docs show
  grep -qF '~/.config/claude-code' "$DOC"
}

@test "R181: docs/proof.md explains equal turns and that waiting changes no result or timeout" {
  grep -qiE 'fewest' "$DOC"
  grep -qiE 'waited longest|longest wait' "$DOC"
  grep -qiE 'timeout counts from (when|the moment) (its|the) command (really )?starts' "$DOC"
  grep -qiE 'same result' "$DOC"
}

@test "R181: docs/proof.md explains how slots of a killed or interrupted run come back" {
  grep -qiE 'killed' "$DOC"
  grep -qiE 'Ctrl-C' "$DOC"
  grep -qiE 'taken over' "$DOC"
}

@test "R181: docs/proof.md explains the unwritable or damaged store, the sandbox case, and the lines a run prints" {
  grep -qi 'sandbox' "$DOC"
  grep -qi 'damaged' "$DOC"
  grep -qF 'the computer-wide limit was not in force' "$DOC"
  grep -qF 'for other VBW runs on this computer' "$DOC"
  grep -qF 'machine limit:' "$DOC"
}

@test "R181: CLAUDE.md names the slot store as the second exception to 'Nothing outside the project', with R181 as its source" {
  local rule
  rule=$(grep '^- \*\*Nothing outside the project:\*\*' "$REPO_ROOT/CLAUDE.md")
  [ -n "$rule" ]
  [[ "$rule" == *"settings.json"* ]] || { echo "$rule"; false; }
  [[ "$rule" == *"<claude-config-dir>/vbw/"* ]] || { echo "$rule"; false; }
  [[ "$rule" == *"slot store"* ]] || { echo "$rule"; false; }
  [[ "$rule" == *"R181"* ]] || { echo "$rule"; false; }
  [[ "$rule" != *"The one exception"* ]] || { echo "$rule"; false; }
}

@test "R181: the user docs say VBW writes the slot store outside the project and nothing else" {
  run grep -hiE 'outside the project[^.]*slot store|slot store[^.]*outside the project' "$REPO_ROOT/docs/guards.md" "$DOC"
  [ "$status" -eq 0 ] || { echo "no sentence in docs/guards.md or docs/proof.md says so"; false; }
}
