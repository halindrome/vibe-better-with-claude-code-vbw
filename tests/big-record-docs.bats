#!/usr/bin/env bats
# R149: the user documentation says a record of any size is supported: the
# record guide states it, and why (record-sized data never reaches a helper
# program as a command-line argument). L1.

load helper

@test "R149: docs/record.md says a record of any size is supported" {
  grep -qiE 'any size' "$REPO_ROOT/docs/record.md" || { echo "docs/record.md does not say a record of any size is supported"; false; }
  grep -qiE 'command[- ]line' "$REPO_ROOT/docs/record.md" || { echo "docs/record.md does not say why (the command-line limit)"; false; }
}
