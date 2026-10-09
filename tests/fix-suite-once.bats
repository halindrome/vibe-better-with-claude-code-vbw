#!/usr/bin/env bats
# R148 (plugin/workflows/fixing.js, plugin/agents/dev.md): in a fix round with
# several fix groups, the Devs do not each run the project's test command or
# quick command: each runs its own checks (vbw check), and the project test
# command runs once, in the single proof after the round. A fix for a failure
# of the test command itself may run the failing tests it needs. The Dev
# instructions and the fixing workflow say so (the user docs:
# tests/check-jobs-docs.bats). L1, with stubbed agents
# (tests/helpers/run-workflow.js).

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/fixing.js"
DEV="$PLUGIN_ROOT/agents/dev.md"

setup() {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
}

# fix_prompts: the prompt of every Dev of a round of three fix groups, as JSON strings, one per line.
fix_prompts() {
  node "$RUN" "$WF" '{"groups": [["F1", "F3"], ["F2"], ["F4"]]}' '{}' | jq -c '[.calls[] | select(.opts.agentType == "vbw:dev") | .prompt]'
}

@test "R148: every Dev of a fix round is told not to run the project's test command or its quick command" {
  run fix_prompts
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e 'length == 3' > /dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e 'all(.[]; contains("Do not run the project'"'"'s test command or its quick command"))' > /dev/null \
    || { echo "$output"; false; }
}

@test "R148: every Dev of a fix round is told to run its own checks with vbw check" {
  run fix_prompts
  printf '%s' "$output" | jq -e 'all(.[]; contains("vbw check"))' > /dev/null || { echo "$output"; false; }
}

@test "R148: every Dev of a fix round is told the whole test command runs once, in the proof after the round" {
  run fix_prompts
  printf '%s' "$output" | jq -e 'all(.[]; contains("runs once, in the proof after this round"))' > /dev/null || { echo "$output"; false; }
}

@test "R148: a Dev fixing a failure of the test command itself may run only the failing tests it needs" {
  run fix_prompts
  printf '%s' "$output" | jq -e 'all(.[]; contains("only the failing tests"))' > /dev/null || { echo "$output"; false; }
}

@test "R148: the Dev instructions say a fix never runs the test command or quick command, and the round's proof runs it once" {
  grep -qF "never run the project's test command or its quick command" "$DEV"
  grep -qiE "once.{0,60}proof|proof.{0,60}once" "$DEV"
  grep -qiE "only the failing tests" "$DEV"
}
