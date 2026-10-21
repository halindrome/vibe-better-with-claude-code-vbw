#!/usr/bin/env bats
# R148 (plugin/workflows/fixing.js, plugin/agents/dev.md): in a fix round with
# several fix groups, the Devs do not each run the project's test command or
# quick command: each runs its own checks (vbw check), and the project test
# command runs once, in the single proof after the round. A fix for a failure
# of the test command itself may run the failing tests it needs. The Dev
# instructions and the fixing workflow carry the prohibition and name vbw
# check. L1, with stubbed agents
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

@test "R148: the Dev instructions keep the prohibition: a fix never runs the test command or quick command" {
  grep -qF "never run the project's test command or its quick command" "$DEV"
}
