#!/usr/bin/env bats
# R150 (decision D238): docs/guards.md and docs/record.md say the guards read
# the small side file .vbw/runtime/glance.json, when they read the record
# instead, and that the side file is never the source of truth; no guide says
# the guards stream the record or read only its beginning. L1.

load helper

# paragraphs FILE: each paragraph (or table row block) of FILE on one line,
# with each bold list item ("- **Name:** ...") on a line of its own.
paragraphs() { awk 'BEGIN { RS = "" } { gsub(/\n/, " "); gsub(/ - \*\*/, "\n- **"); print }' "$1"; }

@test "R150: docs/guards.md says the guards read the glance and read the record when it is missing or not newer" {
  local doc="$REPO_ROOT/docs/guards.md"
  paragraphs "$doc" | grep -F '.vbw/runtime/glance.json' | grep -iE 'guards? (read|reads)' | grep -qi 'record' \
    || { echo "docs/guards.md does not say the guards read .vbw/runtime/glance.json"; false; }
  paragraphs "$doc" | grep -i 'glance' | grep -i 'missing' | grep -iE 'older|newer' | grep -iE 'checkout|hand edit|by hand' \
    | grep -qF '.vbw/record.json' || { echo "docs/guards.md does not say when the guards read the record instead"; false; }
}

@test "R150: docs/guards.md and docs/record.md say the glance is never the source of truth" {
  local doc
  for doc in "$REPO_ROOT/docs/guards.md" "$REPO_ROOT/docs/record.md"; do
    paragraphs "$doc" | grep -i 'glance' | grep -qiE 'never (the|a) source of truth' \
      || { echo "$doc does not say the glance is never the source of truth"; false; }
  done
}

@test "R150: docs/record.md says the glance holds the record's schema, lease and protected list for the guards" {
  paragraphs "$REPO_ROOT/docs/record.md" | grep -F '.vbw/runtime/glance.json' | grep -F '`schema`' | grep -F '`lease`' \
    | grep -F '`protected`' | grep -qi 'guard' || { echo "docs/record.md does not describe what the glance holds for the guards"; false; }
}

@test "R150: no guide says the guards stream the record or read only its beginning" {
  local doc
  for doc in "$REPO_ROOT"/docs/*.md "$REPO_ROOT/README.md"; do
    ! grep -niwE 'stream(s|ing|ed)?' "$doc" || { echo "$doc mentions streaming"; false; }
    ! paragraphs "$doc" | grep -iE '(beginning|start) of the record' || { echo "$doc says the guards read the beginning of the record"; false; }
  done
}
