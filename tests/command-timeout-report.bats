#!/usr/bin/env bats
# R153, F108 (docs/proof.md): a project command stopped by its time limit is
# reported with the limit in use, never with its measured seconds, even when
# the measured run is longer than the limit (a command that ignores the stop
# signal is killed only after the grace period). Regression test for the fix
# of the stop line of prove_summary. L1: a stand-in timeout first on PATH
# behaves as timeout -k GRACE does for such a command: given 2 seconds, it
# returns after 4 with the kill status; every other run goes through as is.

load helper

# Hand edits of the record keep the protected list in step with the checks (R150).
KEEP_PROTECTED='if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src "$TEST_ROOT/bin"
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | .commands = {test: ["sh","-c","trap \"\" TERM; sleep 30"]}' .vbw/record.json > "$TEST_ROOT/edit.json"
  jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  cat > "$TEST_ROOT/bin/timeout" << 'SH'
#!/bin/sh
# timeout -k GRACE LIMIT ARGV...
shift 2
limit=$1
shift
if [ "$limit" = 2 ]; then
  sleep 4
  exit 137
fi
exec "$@"
SH
  chmod +x "$TEST_ROOT/bin/timeout"
  PATH="$TEST_ROOT/bin:$PATH"
  export PATH
}

teardown() { vbw_teardown; }

@test "R153: a command stopped by a 2-second limit after a longer run is reported with the limit, not its measured seconds" {
  "$VBW" config set command_timeout 2 > /dev/null
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.commands.test.status == "timeout"' .vbw/record.json || {
    jq '.evidence.commands' .vbw/record.json
    false
  }
  local secs l
  secs=$(jq -r '.evidence.commands.test.seconds | floor' .vbw/record.json)
  [ "$secs" -gt 2 ] || {
    echo "the measured run ($secs s) is not longer than the limit: the test proves nothing"
    false
  }
  l=$(printf '%s\n' "$output" | grep -iE 'test[^.]*stopped[^.]*time limit') || {
    echo "the report does not say the test command was stopped by its time limit:"
    echo "$output"
    false
  }
  [[ "$l" == *"(2 s)"* ]] || {
    echo "the report does not name the 2-second limit: $l"
    false
  }
  if printf '%s\n' "$l" | grep -qE "(^|[^0-9])$secs ?s([^a-z]|$)"; then
    echo "the report names the measured $secs seconds: $l"
    false
  fi
}
