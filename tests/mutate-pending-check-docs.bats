#!/usr/bin/env bats
# R196 (T165): docs/proof.md's mutation section explains the sentence
# `survives the approved check; caught by the pending one` and that the pending
# file still needs the one approval before the proof. L1: the text of the document.

load helper

DOCS="$REPO_ROOT/docs"

# section FILE HEADING_REGEX: the text of the section whose heading line matches
# HEADING_REGEX, up to the next heading of the same or a higher level, as one line.
section() {
  awk -v re="$2" '
    /^#{1,3} / { if (found) { n = length($1); if (n <= level) exit } else if ($0 ~ re) { found = 1; level = length($1); next } }
    found { printf "%s ", $0 }' "$DOCS/$1"
}

@test "R196: docs/proof.md's mutation section gives the sentence in its exact words and says the pending file still needs the one approval before the proof" {
  local s
  s=$(section proof.md '^### The mutation check')
  printf '%s' "$s" | grep -qF 'survives the approved check; caught by the pending one' \
    || { echo "docs/proof.md, The mutation check: the sentence is not given in its words"; false; }
  printf '%s' "$s" | grep -Eiq 'pending[^.]*approv|approv[^.]*pending' \
    || { echo "docs/proof.md, The mutation check: no sentence ties the pending file to its approval"; false; }
}

# R210 (T192): the documentation and the prompts say the strengthening rule in
# the same words: a Dev may strengthen a check file named by a check of one of the
# plan's own rules, shared with other requirements' checks or not; a check file that
# no check of the plan's own rules names is refused by name; the whole diff is shown
# at the approval.

# has_line FILE WORD...: one line of FILE holds every WORD (case-insensitive).
has_line() {
  local lines w
  lines=$(cat "$1")
  shift
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line holds all of: $*"; return 1; }; done
}

@test "R210: docs/proof.md, docs/record.md, docs/guards.md, the Dev prompt and the router say the strengthening rule in the same words: own rules' checks, shared files included, the rest refused by name, the whole diff at the approval" {
  local s
  s=$(section proof.md '^### The mutation check')
  printf '%s' "$s" | grep -Eiq "own rules[^.]*(shared|other requirements)|(shared|other requirements)[^.]*own rules" \
    || { echo "docs/proof.md, The mutation check: the survivor paragraph does not say the file may be one shared with other requirements, named by a check of the plan's own rules"; false; }
  printf '%s' "$s" | grep -qi 'never weaken' || { echo "docs/proof.md, The mutation check: never weaken is gone"; false; }
  grep -i 'vbw commit' "$DOCS/proof.md" | grep -i 'own rules' | grep -qi 'refused' \
    || { echo "docs/proof.md: no vbw commit sentence says a check file no check of the plan's own rules names is refused"; false; }
  has_line "$DOCS/record.md" '`editable`' "own rules" "survivor"
  has_line "$DOCS/record.md" '`editable`' "survivor" "shared with other requirements"
  has_line "$DOCS/guards.md" "survivor" "own rules"
  has_line "$DOCS/guards.md" "survivor" "shared with other requirements"
  has_line "$DOCS/workflows.md" "vbw commit" "own rules" "refused"
  ! grep -qi "no other requirement uses" "$DOCS/record.md" "$DOCS/guards.md" || { echo "the old rule (that no other requirement uses) is still worded in docs/record.md or docs/guards.md"; false; }
  has_line "$PLUGIN_ROOT/agents/dev.md" "survivor" "own rules" "never weaken"
  grep -E '^\| DEVN-04' "$PLUGIN_ROOT/agents/dev.md" | grep -qi 'survivor' || { echo "dev.md: the DEVN-04 row does not exclude a check file a survivor opened"; false; }
  ! grep -q "never another requirement's" "$PLUGIN_ROOT/agents/dev.md" || { echo "dev.md still forbids another requirement's check file"; false; }
  has_line "$PLUGIN_ROOT/skills/vibe/SKILL.md" "detail.files" "--changes" "diff"
}

# R217 (M45): the pending and strengthened files of a break are among the files
# the plan may strengthen (the files of its own rules' checks), and the documents
# say so where they describe them.

# paragraph FILE TEXT: the paragraph of FILE (lines up to a blank one) holding
# TEXT, as one line.
paragraph() {
  awk -v t="$2" 'BEGIN { RS = "" } index($0, t) { gsub(/\n/, " "); print; exit }' "$DOCS/$1"
}

@test "R217: docs/proof.md's 'caught by the pending one' paragraph and docs/record.md's mutations description say the pending and strengthened files are among the files the plan may strengthen, those of its own rules' checks" {
  local p cell
  p=$(paragraph proof.md 'caught by the pending one')
  [ -n "$p" ] || { echo "docs/proof.md: no paragraph holds 'caught by the pending one'"; false; }
  printf '%s' "$p" | grep -Eiq "pending[^.]*own rules|own rules[^.]*pending" \
    || { echo "docs/proof.md, the pending paragraph: no sentence ties the pending file to the plan's own rules' checks"; false; }
  printf '%s' "$p" | grep -Eiq "strengthened[^.]*own rules|own rules[^.]*strengthened" \
    || { echo "docs/proof.md, the pending paragraph: no sentence ties the strengthened files to the plan's own rules' checks"; false; }
  cell=$(grep -F '`strengthened`' "$DOCS/record.md" | tr '|' '\n' | grep -F '`pending`')
  [ -n "$cell" ] || { echo "docs/record.md: no table cell describes strengthened and pending"; false; }
  printf '%s' "$cell" | grep -Eiq "(strengthened|pending)[^.]*own rules|own rules[^.]*(strengthened|pending)" \
    || { echo "docs/record.md, the mutations description: no sentence ties strengthened and pending to the plan's own rules' checks"; false; }
}
