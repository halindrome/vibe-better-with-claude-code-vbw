#!/usr/bin/env bats
# R186 (L1, documents): docs/workflows.md and docs/rigor.md name Haiku as the
# closing step's model and model.lead as the Lead's own setting, and the help
# for vbw config model.lead never claims it sets the closing step's model.

load helper

@test "R186: docs/workflows.md and docs/rigor.md name Haiku and model.lead" {
  local f
  for f in "$REPO_ROOT/docs/workflows.md" "$REPO_ROOT/docs/rigor.md"; do
    grep -qF 'Haiku' "$f" || { echo "$f does not name Haiku"; false; }
    grep -qF 'model.lead' "$f" || { echo "$f does not name model.lead"; false; }
  done
}

@test "R186: the help for vbw config model.lead never claims it sets the closing step's model" {
  local line f
  run "$VBW" help < /dev/null
  [ "$status" -eq 0 ]
  line=$(printf '%s\n' "$output" | grep -E '^ +config ')
  [ -n "$line" ] || { echo "$output"; false; }
  if printf '%s\n' "$line" | grep -qi 'clos' && ! printf '%s\n' "$line" | grep -q 'Haiku'; then
    echo "vbw help: $line"
    false
  fi
  run "$VBW" config set < /dev/null
  if printf '%s\n' "$output" | grep -qi 'clos' && ! printf '%s\n' "$output" | grep -q 'Haiku'; then
    echo "vbw config set: $output"
    false
  fi
  # Every line of the config skill and the reference that describes model.lead or
  # model.<role>: a mention of closing must say it stays on Haiku.
  local bad
  for f in "$PLUGIN_ROOT/skills/config/SKILL.md" "$REPO_ROOT/docs/workflows.md" "$REPO_ROOT/docs/rigor.md"; do
    bad=$(grep -E 'model\.(lead|<role>|ROLE)' "$f" | grep -i 'clos' | grep -v 'Haiku' || true)
    [ -z "$bad" ] || { echo "$f: $bad"; false; }
  done
}
