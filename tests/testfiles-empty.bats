#!/usr/bin/env bats
# R169 (docs/proof.md): a declared test-file form that leaves no file to run
# as a unit of its own. When every file the form matches already runs as an
# approved check (D179: nothing runs twice), the proof records no nameless
# unit, counts the test command as covered by those checks and says so. When
# the form matches no tracked file at all, the proof fails the test command,
# names the form and opens its fix. A matching file added later runs as a
# unit. Found by the qafix real-user scenario of 2.0.32, where the proof
# recorded a unit named "" and the summary stopped on a jq error. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'echo t_a >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\n' > tests/t_b.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  STORE="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  export STORE
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# plan CHECKS_JSON: one done plan and the given checks, committed and approved.
plan() {
  edit_record ".checks = $1
    | .phases = [{id:\"P1\", title:\"Shop\", reqs:[\"R1\"], milestone:\"M1\"}]
    | .plans = [{id:\"P1.1\", phase:\"P1\", title:\"Shop\", reqs:[\"R1\"], files:[\"src/a.txt\"], after:[], status:\"done\"}]"
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# prove: vbw prove with its error output kept apart (ERR), as bats' run.
prove() {
  status=0
  output=$("$VBW" prove 2> "$TEST_ROOT/err" < /dev/null) || status=$?
  ERR=$(cat "$TEST_ROOT/err")
}

@test "R169: every file the form matches runs as a check: no nameless unit, the test command counts as covered, the summary says so" {
  plan '[{id:"C1", req:"R1", run:["sh","tests/t_a.sh"], files:["tests/t_a.sh"]}, {id:"C2", req:"R1", run:["sh","tests/t_b.sh"], files:["tests/t_b.sh"]}]'
  prove
  [ "$status" -eq 0 ] || { echo "$output"; echo "$ERR"; false; }
  [[ "$ERR" != *"jq: error"* ]] || { echo "$ERR"; false; }
  [ "$(ran)" = "t_a t_b " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.test_files == {}' .vbw/record.json || { jq -c .evidence.test_files .vbw/record.json; false; }
  jq -e '.evidence.commands.test | .status == "pass" and .exit == 0 and .of_files == true and (.tail | test("runs as an approved check"))' .vbw/record.json \
    || { jq -c .evidence.commands.test .vbw/record.json; false; }
  jq -e '[.runs | keys[] | select(startswith("file:"))] == []' "$STORE" || { jq -c '.runs | keys' "$STORE"; false; }
  [[ "$output" == *"test files: 0 ran, 0 reused"* ]] || { echo "$output"; false; }
  [[ "$output" == *"runs as an approved check"* ]] || { echo "$output"; false; }
  jq -e '[.fixes[]? | select(.command == "test")] == []' .vbw/record.json
}

@test "R169: a form that matches no tracked file fails the test command, names the form and opens its fix" {
  mv tests/t_a.sh tests/a.sh && mv tests/t_b.sh tests/b.sh
  plan '[{id:"C1", req:"R1", run:["sh","tests/a.sh"], files:["tests/a.sh"]}]'
  prove
  [ "$status" -ne 0 ]
  [[ "$ERR" != *"jq: error"* ]] || { echo "$ERR"; false; }
  jq -e '.evidence.test_files == {}' .vbw/record.json
  jq -e '.evidence.commands.test | .status == "fail" and .exit == 1 and .of_files == true and (.tail | test("matches no tracked file") and test("tests/t_\\*\\.sh"))' .vbw/record.json \
    || { jq -c .evidence.commands.test .vbw/record.json; false; }
  [[ "$output" == *"matches no tracked file"* ]] || { echo "$output"; false; }
  jq -e '[.fixes[] | select(.command == "test" and .status == "open")] | length == 1' .vbw/record.json
}

@test "R169: a matching file added later runs as a unit of its own" {
  plan '[{id:"C1", req:"R1", run:["sh","tests/t_a.sh"], files:["tests/t_a.sh"]}, {id:"C2", req:"R1", run:["sh","tests/t_b.sh"], files:["tests/t_b.sh"]}]'
  prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  : > "$RANLOG"
  printf 'echo t_c >> "$RANLOG"\n' > tests/t_c.sh
  git add tests/t_c.sh && git commit -q -m "test: t_c"
  prove
  [ "$status" -eq 0 ] || { echo "$output"; echo "$ERR"; false; }
  [ "$(ran)" = "t_c " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.test_files | keys == ["tests/t_c.sh"] and .["tests/t_c.sh"].status == "pass"' .vbw/record.json
  jq -e '.evidence.commands.test | .status == "pass" and .of_files == true' .vbw/record.json
  [[ "$output" == *"test files: 1 ran, 0 reused"* ]] || { echo "$output"; false; }
}
