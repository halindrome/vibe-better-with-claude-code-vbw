#!/usr/bin/env bats
# R176: docs/proof.md's vbw fix done section shows the output form: one line per
# check and per test file that ran (the proof summary's form), the reused lines
# with the time of the pass, the cause line, and the two count lines. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R176: docs/proof.md shows a check line and a test file line that ran, with why" {
  grep -qE '^C[0-9]+ pass [0-9]+s ran: ' "$DOC"
  grep -qE '^tests/[A-Za-z0-9_.-]+ pass [0-9]+s ran: ' "$DOC"
}

@test "R176: docs/proof.md shows the reused line with the time of the pass and the cause line" {
  grep -qE '^C[0-9]+ unchanged since its pass \([0-9]{4}-' "$DOC"
  grep -qF 'every candidate check runs: ' "$DOC"
}

@test "R176: docs/proof.md shows both count lines in the fix done output, printed every time" {
  grep -qE '^checks: [0-9]+ ran, [0-9]+ reused$' "$DOC"
  grep -qE '^test files: [0-9]+ ran, [0-9]+ reused$' "$DOC"
  grep -qF '0 ran, 0 reused' "$DOC"
}

@test "R176 (F146): every example block of the fix done section is output the code can produce: the count lines come after every unit line, and a cause line comes first" {
  local tmp="$TEST_ROOT"
  awk '/^### Reusing an unchanged pass/{on=1} on && /^### /{if (!/Reusing/) exit} on' "$DOC" \
    | awk 'BEGIN{b=0} /^```text/{b++; next} /^```/{next} b>0{print b": "$0}' > "$tmp/blocks.txt"
  [ "$(cut -d: -f1 "$tmp/blocks.txt" | sort -u | wc -l | tr -d " ")" -ge 2 ]
  local b
  for b in $(cut -d: -f1 "$tmp/blocks.txt" | sort -u); do
    grep "^$b: " "$tmp/blocks.txt" | cut -d' ' -f2- > "$tmp/block.txt"
    local units counts cause
    units=$(grep -nE '^(C[0-9]+|tests/[^ ]+) ' "$tmp/block.txt" | cut -d: -f1 | sort -n | tail -1)
    counts=$(grep -nE '^checks: ' "$tmp/block.txt" | cut -d: -f1)
    [ -n "$units" ] && [ -n "$counts" ] && [ "$units" -lt "$counts" ] || { cat "$tmp/block.txt"; false; }
    [ "$counts" -lt "$(grep -nE '^test files: ' "$tmp/block.txt" | cut -d: -f1)" ] || { cat "$tmp/block.txt"; false; }
    cause=$(grep -nE '^every candidate check runs: ' "$tmp/block.txt" | cut -d: -f1 || true)
    if [ -n "$cause" ]; then
      [ "$cause" -eq 1 ] || { cat "$tmp/block.txt"; false; }
      ! grep -qE ' ran: | unchanged since its pass' "$tmp/block.txt" || { cat "$tmp/block.txt"; false; }
    fi
  done
}
