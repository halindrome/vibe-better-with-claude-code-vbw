#!/usr/bin/env bats
# R150 (decision D232): docs/record.md describes one format, 4, written for
# every record, with the protected list after lease, and says older records are
# still read and converted on their next write; docs/guards.md describes one
# read path, the protected list, and the refusal while an older record is not
# yet saved. Neither mentions a 50-check threshold, schemas 1 to 3 being
# written, or guards reading the checks. L1.

load helper

# paragraphs FILE: each paragraph (or table row block) of FILE on one line.
paragraphs() { awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$1"; }

@test "R150: docs/record.md documents the protected list, its place after lease and schema 4 for every record" {
  local doc="$REPO_ROOT/docs/record.md"
  grep -q '`protected`' "$doc"
  paragraphs "$doc" | grep -i 'protected' | grep -i 'schema 4' | grep -q 'lease'
  paragraphs "$doc" | grep -i 'protected' | grep -iE 'every record|every write|each write' | grep -qiE 'no checks|empty'
  grep -q '`VBW_SCHEMA_MAX`, currently 4' "$doc"
}

@test "R150: docs/record.md says records an older VBW wrote are read and become schema 4 on their next write, with no migration command" {
  local doc="$REPO_ROOT/docs/record.md"
  paragraphs "$doc" | grep -iE 'schemas? 1 to 3|schema 1, 2 or 3' | grep -i 'next write' | grep -i 'schema 4' | grep -qi 'migration'
}

@test "R150: docs/record.md and docs/guards.md no longer mention a 50-check threshold" {
  local doc
  for doc in "$REPO_ROOT/docs/record.md" "$REPO_ROOT/docs/guards.md"; do
    ! grep -niE '50 checks|more than 50|fewer than 50' "$doc" || { echo "$doc still names the threshold"; false; }
  done
}

@test "R150: docs/record.md no longer says this VBW writes schema 1, 2 or 3" {
  ! paragraphs "$REPO_ROOT/docs/record.md" | grep -iE 'kernel writes|vbw writes|is written|keeps? schema|stays? (at )?schema' \
    | grep -iE 'schemas? [123]([^0-9]|$)' | grep -viE 'older vbw|before (format|schema) 4|earlier' \
    || { echo "docs/record.md still says schemas 1 to 3 are written"; false; }
}

@test "R150: docs/guards.md describes one read path: the protected list, never the checks" {
  local doc="$REPO_ROOT/docs/guards.md"
  paragraphs "$doc" | grep -i 'protected' | grep -i 'schema 4' | grep -qiE 'never|only'
  ! paragraphs "$doc" | grep -iE 'schemas? 1 to 3|schema 1, 2 or 3' | grep -iE '(read|walk)(s|ing)? (the|its|their|every) (check|`checks`)' \
    || { echo "docs/guards.md still says the guards read the checks on older records"; false; }
}

@test "R150: docs/guards.md says a build or fix agent's write is refused on a record without the list until this VBW saves it" {
  local doc="$REPO_ROOT/docs/guards.md"
  paragraphs "$doc" | grep -i 'protected' | grep -i 'saved by this VBW' | grep -qiE 'build|fix'
}
