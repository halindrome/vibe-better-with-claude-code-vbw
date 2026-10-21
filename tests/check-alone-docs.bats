#!/usr/bin/env bats
# R45: the docs describe the alone marker, and the kernel code stays bash 3.2
# compatible.

load helper

@test "docs/proof.md names the alone marker of a check" {
  grep -qF '`alone`' "$REPO_ROOT/docs/proof.md"
}

@test "docs/record.md lists alone among a check's fields" {
  grep -E '^\| `checks\[\]`.*`alone`' "$REPO_ROOT/docs/record.md"
}

@test "the kernel code stays bash 3.2 compatible, without eval and without /tmp" {
  run bats --filter 'no eval|no bash-4-only|no predictable' "$REPO_ROOT/tests/standards.bats"
  [ "$status" -eq 0 ]
}

@test "docs/record.md says a record whose checks use alone is schema 2" {
  grep -i 'alone' "$REPO_ROOT/docs/record.md" | grep -qi 'schema 2'
}
