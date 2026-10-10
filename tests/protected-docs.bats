#!/usr/bin/env bats
# R150 (decisions D226, D229): docs/record.md documents schema 4, the protected
# field, the 50-check threshold and why ordinary projects keep their older
# format; docs/guards.md says what the guards read on each format. L1.

load helper

# paragraphs FILE: each paragraph (or table row block) of FILE on one line.
paragraphs() { awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$1"; }

@test "R150: docs/record.md documents the protected field, its place after lease and schema 4" {
  local doc="$REPO_ROOT/docs/record.md"
  grep -q '`protected`' "$doc"
  paragraphs "$doc" | grep -i 'protected' | grep -i 'schema 4' | grep -q 'lease'
  grep -q '`VBW_SCHEMA_MAX`, currently 4' "$doc"
}

@test "R150: docs/record.md names the 50-check threshold and why ordinary projects keep their format" {
  local doc="$REPO_ROOT/docs/record.md"
  paragraphs "$doc" | grep -i 'more than 50 checks' | grep -qi 'protected'
  paragraphs "$doc" | grep -i '50 checks or fewer' | grep -qi 'older VBW'
}

@test "R150: docs/guards.md says what the guards read on schema 4 and on older formats" {
  local doc="$REPO_ROOT/docs/guards.md"
  paragraphs "$doc" | grep -i 'protected' | grep -i 'schema 4' | grep -qi 'checks'
  paragraphs "$doc" | grep -iE 'schemas? 1 to 3|schema 1, 2 or 3' | grep -qi 'checks'
}
