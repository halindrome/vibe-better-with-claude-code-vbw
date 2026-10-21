#!/usr/bin/env bats
# R202: docs/proof.md ("Reusing results") describes how a file a unit writes
# carries that unit's read list (kept once per run, by name, in the copy's
# written-file store) and what vbw next caches; docs/next.md names the cached
# proof sizing (.vbw/runtime/proof-units.json), its key (the committed tree,
# the record's fingerprint, the run store's digest) and when it is recomputed. L1.

load helper

PROOF="$REPO_ROOT/docs/proof.md"
NEXT="$REPO_ROOT/docs/next.md"

@test "R202: docs/proof.md says how written files carry read lists" {
  grep -qi 'a file a unit writes' "$PROOF" || grep -qi 'files a unit writes' "$PROOF"
  grep -qF 'written.json' "$PROOF"
}

@test "R202: docs/proof.md and docs/next.md name the cached proof sizing and when it is recomputed" {
  grep -qF 'proof-units.json' "$PROOF"
  grep -qF 'proof-units.json' "$NEXT"
  grep -qi 'committed tree' "$NEXT"
  grep -qi 'fingerprint' "$NEXT"
  grep -qi 'digest' "$NEXT"
  grep -qi 'recomputed' "$NEXT"
}
