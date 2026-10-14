#!/usr/bin/env bats
# R188 (L1, documents): docs/workflows.md and docs/rigor.md say the step that
# closes a run runs on the Lead's model (model.lead), and no sentence of theirs
# says it runs on Haiku; the help for vbw config, the config skill and those
# documents never say model.lead leaves the closing step out.

load helper

# sentences FILE: the file's text, one sentence per line (paragraphs joined, split at ". ").
sentences() {
  awk 'BEGIN { RS = "" } { gsub(/\n/, " "); n = split($0, s, /\. /); for (i = 1; i <= n; i++) print s[i] }' "$1"
}

# says_lead_close FILE: one sentence names the closing step and the Lead's model, without
# Haiku and without a negation; no sentence names Haiku together with the closing step.
says_lead_close() {
  local haiku
  sentences "$1" | grep -iE 'closing step|close run|closes (each|a|the) run' | grep -E "model\.lead|Lead's model" \
    | grep -v 'Haiku' | grep -qviE "(^|[^a-z])(not|never)([^a-z]|$)|n't" || {
    echo "$1: no sentence says the closing step runs on the Lead's model (model.lead)"
    return 1
  }
  haiku=$(sentences "$1" | grep 'Haiku' | grep -iE 'closing|close run|closes (each|a|the) run|fix done' || true)
  [ -z "$haiku" ] || {
    echo "$1: a sentence still puts the closing step on Haiku: $haiku"
    return 1
  }
}

@test "R188: docs/workflows.md says the closing step runs on the Lead's model (model.lead), never on Haiku" {
  says_lead_close "$REPO_ROOT/docs/workflows.md"
}

@test "R188: docs/rigor.md says the closing step runs on the Lead's model (model.lead), never on Haiku" {
  says_lead_close "$REPO_ROOT/docs/rigor.md"
}

@test "R188: the help for vbw config model.lead, the config skill and the guides never say model.lead leaves out the closing step" {
  local line f bad
  run "$VBW" help < /dev/null
  [ "$status" -eq 0 ]
  line=$(printf '%s\n' "$output" | grep -E '^ +config ')
  [ -n "$line" ] || { echo "$output"; false; }
  if printf '%s\n' "$line" | grep -qi 'clos'; then
    echo "vbw help: $line"
    false
  fi
  run "$VBW" config set < /dev/null
  if printf '%s\n' "$output" | grep -qi 'clos'; then
    echo "vbw config set: $output"
    false
  fi
  for f in "$PLUGIN_ROOT/skills/config/SKILL.md" "$REPO_ROOT/docs/workflows.md" "$REPO_ROOT/docs/rigor.md"; do
    bad=$(sentences "$f" | grep -E 'model\.(lead|<role>|ROLE)' | grep -i 'clos' \
      | grep -iE "Haiku|(^|[^a-z])(not|never|except|apart)([^a-z]|$)|n't|exclud|separate" || true)
    [ -z "$bad" ] || { echo "$f: $bad"; false; }
  done
}

@test "R188: in docs/workflows.md the line ending 'With it:' is followed, after blank lines, by a list item" {
  local next
  next=$(awk '/With it:$/ { f = 1; next } f && NF { print; exit }' "$REPO_ROOT/docs/workflows.md")
  [[ "$next" =~ ^(-|\*|[0-9]+\.)[[:space:]] ]] || { echo "after 'With it:' comes: $next"; false; }
}
