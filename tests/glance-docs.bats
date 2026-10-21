#!/usr/bin/env bats
# R150 (decision D238): docs/guards.md and docs/record.md name the small side
# file .vbw/runtime/glance.json the guards read, and docs/record.md names the
# fields it holds (schema, lease, protected); no guide says the guards stream
# the record or read only its beginning. L1.

load helper

# paragraphs FILE: each paragraph (or table row block) of FILE on one line,
# with each bold list item ("- **Name:** ...") on a line of its own.
paragraphs() { awk 'BEGIN { RS = "" } { gsub(/\n/, " "); gsub(/ - \*\*/, "\n- **"); print }' "$1"; }

@test "R150: docs/guards.md names the glance and the record file" {
  local doc="$REPO_ROOT/docs/guards.md"
  grep -qF '.vbw/runtime/glance.json' "$doc"
  grep -qF '.vbw/record.json' "$doc"
}

@test "R150: docs/record.md names the glance's fields: schema, lease and protected" {
  paragraphs "$REPO_ROOT/docs/record.md" | grep -F '.vbw/runtime/glance.json' | grep -F '`schema`' | grep -F '`lease`' \
    | grep -qF '`protected`' || { echo "docs/record.md does not name the glance's fields"; false; }
}

@test "R150: no guide says the guards stream the record or read only its beginning" {
  local doc
  for doc in "$REPO_ROOT"/docs/*.md "$REPO_ROOT/README.md"; do
    ! paragraphs "$doc" | grep -iwE 'stream(s|ing|ed)?' | grep -iE 'guard' | grep -qi 'record' || { echo "$doc says the guards stream the record"; false; }
    ! paragraphs "$doc" | grep -iE '(beginning|start) of the record' || { echo "$doc says the guards read the beginning of the record"; false; }
  done
}
