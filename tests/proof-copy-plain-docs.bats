#!/usr/bin/env bats
# R206: docs/proof.md names, beside its copy-on-write paragraph, the 500 MB
# threshold of plain-copied ignored data, the one vbw: line (the largest ignored
# folders with their sizes) and the way out (list them under ## Clean copy, then
# vbw spec sync). L1: the text of the doc (one line holds each fact; no exact
# wording).

load helper

PROOF="$REPO_ROOT/docs/proof.md"

# near: the twelve lines around the copy-on-write sentence of the clean-copy paragraph.
near() {
  local n
  n=$(grep -n 'copy-on-write clone where the file system offers one' "$PROOF" | head -n 1 | cut -d: -f1)
  [ -n "$n" ] || { echo "no copy-on-write paragraph"; return 1; }
  sed -n "$((n > 6 ? n - 6 : 1)),$((n + 12))p" "$PROOF"
}

@test "R206: the paragraph names the 500 MB threshold of a plain copy and that the line is printed once, on stderr, starting vbw:" {
  near | tr '\n' ' ' | grep -Eq 'more than 500 MB' || { near; false; }
  near | grep -q 'vbw:' || { near; false; }
  near | grep -qi 'once' || { near; false; }
}

@test "R206: the paragraph says the line names the largest ignored folders with their sizes" {
  near | grep -qi 'largest' || { near; false; }
  near | grep -qi 'size' || { near; false; }
}

@test "R206: the paragraph names the way out: list them under ## Clean copy, then vbw spec sync" {
  near | grep -qF '## Clean copy' || { near; false; }
  near | grep -qF 'vbw spec sync' || { near; false; }
}

@test "R206: the paragraph says a clone, less data or nothing ignored prints nothing, and the line changes no result" {
  near | grep -qi 'nothing' || { near; false; }
  near | grep -Eqi 'verdict|result|exit code' || { near; false; }
}
