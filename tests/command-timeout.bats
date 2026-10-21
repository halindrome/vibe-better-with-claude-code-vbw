#!/usr/bin/env bats
# R153 (docs/proof.md): vbw prove gives a project command (its test command
# above all) 3600 seconds (60 minutes) before stopping it, instead of 900, and
# a project can set its own limit: vbw config set command_timeout SECONDS (a
# whole number from 1 to 86400), shown by vbw config, kept between runs, and
# back to 3600 with default. A command stopped by the limit is recorded as
# timeout and the proof's report says so, with the limit in use and how to
# raise it. A command that ends in time is recorded as before, and a check's
# own timeout is unchanged. L1: a fixture project; a stand-in timeout program
# first on PATH logs the limit each run gets.

load helper

# Hand edits of the record keep the protected list in step with the checks (R150).
KEEP_PROTECTED='if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/edit.json" > .vbw/record.json
}

# with_test ARGV_JSON: the project's test command is ARGV_JSON, approved.
with_test() {
  edit_record ".commands = {test: $1}"
  git add -A && git commit -q -m "chore(vbw): test command"
  "$VBW" approve > /dev/null
}

# logged_limits: a stand-in timeout first on PATH that logs "LIMIT ARGV..." of
# every run to $TEST_ROOT/limits, then runs it.
logged_limits() {
  mkdir -p "$TEST_ROOT/bin"
  cat > "$TEST_ROOT/bin/timeout" << SH
#!/bin/sh
# timeout [--foreground] -k GRACE LIMIT ARGV... (T148: VBW passes --foreground)
[ "\$1" != --foreground ] || shift
[ "\$1" != -k ] || shift 2
limit=\$1
shift
echo "\$limit \$*" >> "$TEST_ROOT/limits"
exec "\$@"
SH
  chmod +x "$TEST_ROOT/bin/timeout"
  : > "$TEST_ROOT/limits"
  PATH="$TEST_ROOT/bin:$PATH"
  export PATH
}

# config_line: the command_timeout line of vbw config.
config_line() {
  vbw_run config
  [ "$status" -eq 0 ] || {
    echo "$output"
    return 1
  }
  printf '%s\n' "$output" | grep -E '^command_timeout: ' || {
    echo "vbw config shows no command_timeout line: $output"
    return 1
  }
}

@test "R153: without a setting vbw config shows 3600 seconds and vbw prove gives the test command 3600 seconds, a check still 300" {
  local l
  l=$(config_line)
  [[ "$l" =~ ^command_timeout:\ 3600([^0-9]|$) ]] || {
    echo "the default is not 3600 seconds: $l"
    false
  }
  with_test '["sh","-c","echo ok"]'
  logged_limits
  vbw_run prove
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  grep -qx '3600 sh -c echo ok' "$TEST_ROOT/limits" || {
    echo "the test command did not get 3600 seconds:"
    cat "$TEST_ROOT/limits"
    false
  }
  grep -qx '300 sh tests/pay.sh' "$TEST_ROOT/limits" || {
    echo "the check's own default timeout changed:"
    cat "$TEST_ROOT/limits"
    false
  }
}

@test "R153: a project sets its own limit: vbw config shows it, later runs keep and use it, and default returns to 3600" {
  vbw_run config set command_timeout 7200
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  local l
  l=$(config_line)
  [[ "$l" =~ ^command_timeout:\ 7200([^0-9]|$) ]] || {
    echo "vbw config does not show the setting: $l"
    false
  }
  with_test '["sh","-c","echo ok"]'
  logged_limits
  vbw_run prove
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  grep -qx '7200 sh -c echo ok' "$TEST_ROOT/limits" || {
    echo "the test command did not get the project's 7200 seconds:"
    cat "$TEST_ROOT/limits"
    false
  }
  vbw_run config set command_timeout default
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  l=$(config_line)
  [[ "$l" =~ ^command_timeout:\ 3600([^0-9]|$) ]] || {
    echo "default did not return to 3600: $l"
    false
  }
  : > "$TEST_ROOT/limits"
  vbw_run prove --full
  grep -qx '3600 sh -c echo ok' "$TEST_ROOT/limits" || {
    echo "after default the test command did not get 3600 seconds:"
    cat "$TEST_ROOT/limits"
    false
  }
}

@test "R153: vbw prove stops the test command at the project's limit, records timeout and says it was stopped by the limit, the limit and how to raise it" {
  "$VBW" config set command_timeout 2 > /dev/null
  with_test '["sh","-c","sleep 30"]'
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.commands.test.status == "timeout"' .vbw/record.json || {
    jq '.evidence.commands' .vbw/record.json
    false
  }
  local l
  l=$(printf '%s\n' "$output" | grep -iE 'test[^.]*stopped[^.]*time limit') || {
    echo "the report does not say the test command was stopped by its time limit:"
    echo "$output"
    false
  }
  printf '%s\n' "$l" | grep -qE '(^|[^0-9])2 ?(s|sec|seconds?)([^a-z]|$)' || {
    echo "the report does not name the 2-second limit: $l"
    false
  }
  printf '%s\n' "$output" | grep -qF 'vbw config set command_timeout' || {
    echo "the report does not say how to raise the limit:"
    echo "$output"
    false
  }
}

@test "R153: an invalid limit is refused with the allowed range and changes nothing" {
  "$VBW" config set command_timeout 7200 > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  local v
  for v in abc 0 -5 1.5 86401 "" 10m; do
    vbw_run config set command_timeout "$v"
    [ "$status" -ne 0 ] || {
      echo "'$v' accepted"
      false
    }
    [[ "$output" == *"1 to 86400"* ]] || {
      echo "'$v': the message does not name the range 1 to 86400: $output"
      false
    }
  done
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  local l
  l=$(config_line)
  [[ "$l" =~ ^command_timeout:\ 7200([^0-9]|$) ]] || {
    echo "a refused value changed the setting: $l"
    false
  }
  vbw_run config set command_timeout 86400
  [ "$status" -eq 0 ]
  vbw_run config set command_timeout 1
  [ "$status" -eq 0 ]
}

@test "R153: a test command that ends within the limit is recorded as before, and a check's own timeout still stops the check" {
  "$VBW" config set command_timeout 600 > /dev/null
  with_test '["sh","-c","echo 2 failing; exit 3"]'
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.evidence.commands.test.status == "fail" and .evidence.commands.test.exit == 3' .vbw/record.json || {
    jq '.evidence.commands' .vbw/record.json
    false
  }
  [[ "$output" != *"time limit"* ]] || {
    echo "a failing command was reported as stopped by the limit: $output"
    false
  }
  with_test '["sh","-c","echo ok"]'
  edit_record '.checks[0] = {id:"C1", req:"R1", run:["sleep","30"], files:["tests/pay.sh"], timeout: 1}'
  git add -A && git commit -q -m "chore(vbw): slow check"
  "$VBW" approve > /dev/null
  vbw_run prove --full
  [ "$status" -ne 0 ]
  jq -e '.evidence.commands.test.status == "pass" and .evidence.commands.test.exit == 0' .vbw/record.json
  jq -e '.evidence.checks.C1.status == "timeout"' .vbw/record.json
}
