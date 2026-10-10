#!/usr/bin/env bats
# R147 and R148 (docs/proof.md, docs/workflows.md): the user docs describe the
# machine-sized default for check_jobs (three quarters of the processor cores,
# rounded down, at least 1, at most 64; 1 when the count cannot be read) and
# the one limit shared by every VBW command running checks in the project at
# the same time; the old "default 4" wording is gone from docs, help and code
# comments; and docs/workflows.md says a fix round runs the project test
# command once, in the proof after the round. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R147: docs/proof.md describes the machine-sized default of check_jobs" {
  grep -qiE 'three quarters' "$DOC"
  grep -qiE 'processor cores|cores' "$DOC"
  grep -qiE 'at least 1|at least one' "$DOC"
  grep -qiE 'cannot be read|can.t be read|cannot read' "$DOC"
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

@test "R148: docs/proof.md says the limit is shared by every VBW command running checks in the project at once" {
  grep -qiE 'shared|share' "$DOC"
  grep -qiE 'at the same time|at once' "$DOC"
  grep -qiE 'parallel Devs|several (VBW )?commands|several Devs' "$DOC"
  grep -qiE 'waits? for a free slot|free slot' "$DOC"
}

@test "R148: docs/workflows.md says a fix round runs the project test command once, at the proof after the round" {
  local doc="$REPO_ROOT/docs/workflows.md"
  grep -qiE 'fix round' "$doc"
  grep -qiE "never (run|runs) the project's test command or (its|the) quick command" "$doc"
  grep -qiE 'once, in the proof after the round' "$doc"
  grep -qiE 'only the failing tests' "$doc"
}

@test "B2: the config skill lists check_jobs with its range and default, so /vbw:config can change it" {
  local skill="$PLUGIN_ROOT/skills/config/SKILL.md"
  grep -qE '^- `check_jobs`:' "$skill"
  grep -E '^- `check_jobs`:' "$skill" | grep -qE '1 to 64'
  grep -E '^- `check_jobs`:' "$skill" | grep -qiE 'three quarters'
  grep -E '^- `check_jobs`:' "$skill" | grep -qF '`default`'
}
