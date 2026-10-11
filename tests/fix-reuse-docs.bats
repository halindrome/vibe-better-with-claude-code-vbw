#!/usr/bin/env bats
# R43: the docs describe the reuse rule of vbw fix done (the one rule vbw prove
# uses: a check's read list) and its wording; the kernel stays within budget.

load helper

# section TITLE: the docs/proof.md section whose heading is TITLE, up to the next heading.
section() {
  awk -v t="$1" '/^#+ / { on = (index($0, t) > 0) } on' "$REPO_ROOT/docs/proof.md"
}

@test "docs/proof.md describes when vbw fix done skips a check and what it says" {
  grep -q 'unchanged since its pass' "$REPO_ROOT/docs/proof.md"
  section 'Reusing an unchanged pass' | grep -qi 'read list' || { section 'Reusing an unchanged pass'; false; }
  ! grep -qiE 'vbw prove.*(still runs|runs) every check, except|does not use this cache' "$REPO_ROOT/docs/proof.md"
}

@test "docs/proof.md says passes are kept in the clone's store of recorded runs, outside the record, and a lost one only reruns checks" {
  grep -q 'runs.json' "$REPO_ROOT/docs/proof.md"
  ! grep -q 'passes.json' "$REPO_ROOT/docs/proof.md"
  grep -qi 'never in the record\|not in the record\|outside the record' "$REPO_ROOT/docs/proof.md"
  ! grep -E '^\| `passes`' "$REPO_ROOT/docs/record.md"
}

@test "the kernel stays within its line budget" {
  run bats --filter 'kernel stays within' "$REPO_ROOT/tests/standards.bats"
  [ "$status" -eq 0 ]
}
