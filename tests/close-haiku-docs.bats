#!/usr/bin/env bats
# R186 (L1, documents): docs/workflows.md and docs/rigor.md say the step that
# closes a run runs on Haiku in every profile, separate from the Lead's model
# (model.lead), and the help for vbw config model.lead never claims it sets the
# closing step's model.

load helper

# sentences FILE: the file's text, one sentence per line (paragraphs joined, split at ". ").
sentences() {
  awk 'BEGIN { RS = "" } { gsub(/\n/, " "); n = split($0, s, /\. /); for (i = 1; i <= n; i++) print s[i] }' "$1"
}

# says_haiku_close FILE: one sentence names Haiku, the closing step and every profile,
# and one names Haiku and the Lead's own model setting.
says_haiku_close() {
  sentences "$1" | grep 'Haiku' | grep -i 'clos' | grep -qi 'every profile' || {
    echo "$1: no sentence says the closing step runs on Haiku in every profile"
    return 1
  }
  sentences "$1" | grep 'Haiku' | grep -qE "model\.lead|Lead's model" || {
    echo "$1: no sentence sets the closing step's Haiku apart from the Lead's model (model.lead)"
    return 1
  }
}

@test "R186: docs/workflows.md says the closing step runs on Haiku in every profile, separate from the Lead's model" {
  says_haiku_close "$REPO_ROOT/docs/workflows.md"
}

@test "R186: docs/rigor.md says the closing step runs on Haiku in every profile, separate from the Lead's model" {
  says_haiku_close "$REPO_ROOT/docs/rigor.md"
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
