#!/usr/bin/env bats
# R173: the user docs describe the cost data and the command in current-behaviour
# terms: docs/record.md the record field and its schema, docs/statusline.md the
# side file, docs/costs.md the command. L1.

load helper

@test "R173: docs/record.md documents the costs field, the lease's opening figures and the schema" {
  grep -qF '| `costs` |' "$REPO_ROOT/docs/record.md"
  grep -qF 'lease.cost' "$REPO_ROOT/docs/record.md"
  grep -qF 'Added within schema 4' "$REPO_ROOT/docs/record.md"
}

@test "R173: docs/statusline.md documents the side file and no longer claims no temporary files" {
  grep -qF '.vbw/runtime/cost.' "$REPO_ROOT/docs/statusline.md"
  grep -qF 'vbw show costs' "$REPO_ROOT/docs/statusline.md"
  ! grep -qF 'no temporary files' "$REPO_ROOT/docs/statusline.md"
}

@test "R173: docs/costs.md documents the command, its JSON, the ceiling and what unknown means" {
  [ -f "$REPO_ROOT/docs/costs.md" ]
  grep -qF 'vbw show costs --json' "$REPO_ROOT/docs/costs.md"
  grep -qF 'vbw show costs --ceiling' "$REPO_ROOT/docs/costs.md"
  grep -qF 'cannot tell' "$REPO_ROOT/docs/costs.md"
  grep -qF 'unknown' "$REPO_ROOT/docs/costs.md"
  grep -qF 'vbw statusline on' "$REPO_ROOT/docs/costs.md"
}
