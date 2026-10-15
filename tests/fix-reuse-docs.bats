#!/usr/bin/env bats
# R43: docs/proof.md shows the reused line of vbw fix done and names the store
# of recorded runs (runs.json); the old passes cache is gone; the kernel stays
# within budget.

load helper

@test "docs/proof.md shows the reused line of vbw fix done" {
  grep -q 'unchanged since its pass' "$REPO_ROOT/docs/proof.md"
  ! grep -qiE 'vbw prove.*(still runs|runs) every check, except|does not use this cache' "$REPO_ROOT/docs/proof.md"
}

@test "docs/proof.md names runs.json as the store of passes, and the passes cache is gone from proof.md and record.md" {
  grep -q 'runs.json' "$REPO_ROOT/docs/proof.md"
  ! grep -q 'passes.json' "$REPO_ROOT/docs/proof.md"
  ! grep -E '^\| `passes`' "$REPO_ROOT/docs/record.md"
}

@test "the kernel stays within its line budget" {
  run bats --filter 'kernel stays within' "$REPO_ROOT/tests/standards.bats"
  [ "$status" -eq 0 ]
}
