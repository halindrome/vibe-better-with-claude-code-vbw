#!/usr/bin/env bats
# R147 (docs/proof.md): the user docs state the machine-sized default for
# check_jobs (three quarters of the processor cores, at least 1, at most 64)
# and the command that returns to it; the old default of 4 is gone from docs,
# help and code comments; the config skill lists check_jobs. The shared limit
# (R148) and the single test command run of a fix round are behaviour, pinned
# by check-jobs-shared.bats and fix-suite-once.bats. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R147: docs/proof.md describes the machine-sized default of check_jobs" {
  grep -qiE 'three quarters' "$DOC"
  grep -qiE 'processor cores|cores' "$DOC"
  grep -qiE 'at least 1|at least one' "$DOC"
  grep -qiE 'at most 64' "$DOC"
  grep -qF 'vbw config set check_jobs default' "$DOC"
}

@test "R147: the old default of 4 is gone from the docs, the help and the code comments" {
  local f
  for f in "$DOC" "$PLUGIN_ROOT/lib/core.sh" "$PLUGIN_ROOT/lib/cmd-config.sh" "$PLUGIN_ROOT/lib/checks.sh" "$PLUGIN_ROOT/bin/vbw"; do
    run grep -nE 'default 4|default: 4|means 4|defaults? to 4|four at a time' "$f"
    [ "$status" -ne 0 ] || { echo "$f: $output"; false; }
  done
  run "$VBW" help
  [[ "$output" != *"default 4"* ]] || { echo "$output"; false; }
}

@test "B2: the config skill lists check_jobs with its range and default, so /vbw:config can change it" {
  local skill="$PLUGIN_ROOT/skills/config/SKILL.md"
  grep -qE '^- `check_jobs`:' "$skill"
  grep -E '^- `check_jobs`:' "$skill" | grep -qE '1 to 64'
  grep -E '^- `check_jobs`:' "$skill" | grep -qiE 'three quarters'
  grep -E '^- `check_jobs`:' "$skill" | grep -qF '`default`'
}
