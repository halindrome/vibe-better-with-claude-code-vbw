#!/usr/bin/env bats
# R195 (T165; docs/proof.md): vbw show fix F lists, under each failing check,
# failing single-form test file and failing project command of the fix,
# `full output: PATH` and `failing tests:` with one line per failing test name
# recognised in the kept output. Recognised forms: TAP/bats (`not ok N name`),
# cargo test (`test name ... FAILED` and the `failures:` list, each name once),
# pytest (`FAILED path::name`), go test (`--- FAIL: Name`), jest/vitest/mocha
# (`✕ name`, `× name`, `N) name`). When none is recognised it says
# `failing tests: none recognised in the output; read the full output file`;
# when the file is missing it keeps `full output not kept: run vbw prove again`.
# Failing test files are listed by their path with their kept file; --json
# carries `kept` and `failing_tests` for each failing unit. The names are read
# only when vbw show fix runs: no hook or status-line path reads the kept
# output. L1: the kernel on a fixture project with planted kept output.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'unpaid\n' > src/pay.txt
  local i
  for i in 1 2 3 4 5 6 7 8 9; do printf 'echo "C%s output"; exit 1\n' "$i" > "tests/c$i.sh"; done
  printf 'echo t_a; exit 1\n' > tests/t_a.sh
  printf 'echo all\n' > tests/all.sh
  edit_record '.checks = [range(1; 10) | {id: "C\(.)", req: "R1", run: ["sh", "tests/c\(.).sh"], files: ["tests/c\(.).sh"]}]
    | .phases = [{id: "P1", title: "Shop", reqs: ["R1"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], status: "done"}]'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  F_REQ=$(jq -r '[.fixes[] | select(.req == "R1")][0].id // empty' .vbw/record.json)
  F_TEST=$(jq -r '[.fixes[] | select(.command == "test")][0].id // empty' .vbw/record.json)
  [ -n "$F_REQ" ] && [ -n "$F_TEST" ] || { echo "the proof opened no fixes"; jq .fixes .vbw/record.json; return 1; }
  TA_LOG=$(find "$OUT" -maxdepth 1 -name 'file-*.log' -print | sed "s|^$OUT/||")
  [ "$(printf '%s\n' "$TA_LOG" | grep -c .)" -eq 1 ] || { echo "no single kept file for tests/t_a.sh: $TA_LOG"; return 1; }
  export F_REQ F_TEST TA_LOG
  plant
}

teardown() { vbw_teardown; }

OUT=.vbw/runtime/output

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

# plant: each kept file holds one runner's failure report; C8's names no test, C9's is gone.
plant() {
  printf '1..3\nok 1 pay accepts a coin\nnot ok 2 pay refuses zero\n# (in test file tests/pay.bats, line 12)\nok 3 pay prints a receipt\n' > "$OUT/C1.log"
  printf 'running 2 tests\ntest pay::coin ... ok\ntest pay::zero ... FAILED\n\nfailures:\n\n---- pay::zero stdout ----\nthread pay::zero panicked\n\nfailures:\n    pay::zero\n\ntest result: FAILED. 1 passed; 1 failed\n' > "$OUT/C2.log"
  printf '============ FAILURES ============\nFAILED tests/test_pay.py::test_zero - assert 0 == 1\n1 failed, 2 passed\n' > "$OUT/C3.log"
  printf '=== RUN   TestZero\n--- FAIL: TestZero (0.00s)\n    pay_test.go:12: zero accepted\nFAIL\n' > "$OUT/C4.log"
  printf 'PASS src/pay.test.js\n  pay\n    ✓ accepts a coin (2 ms)\n    ✕ refuses zero on jest (3 ms)\n' > "$OUT/C5.log"
  printf ' ❯ src/pay.test.ts (2)\n   ✓ accepts a coin\n   × refuses zero on vitest\n' > "$OUT/C6.log"
  printf '  pay\n    ✓ accepts a coin\n    1) refuses zero on mocha\n\n  1 passing\n  1 failing\n' > "$OUT/C7.log"
  printf 'boom: the runner crashed before any test\n' > "$OUT/C8.log"
  rm -f "$OUT/C9.log"
  printf '1..1\nnot ok 1 t_a pays\n' > "$OUT/$TA_LOG"
}
show() { "$VBW" show fix "$F_REQ" < /dev/null; }
# after ID: the lines of show fix after the line naming check ID's kept file, up to the next kept-file or heading line.
after() {
  show | awk -v f="full output: $OUT/$1.log" 'found && (/full output: / || /full output not kept/ || /^[a-z].*:$/) { exit } found { print } $0 ~ f { found = 1 }'
}
# has_name ID NAME: under check ID one line is NAME alone (indented).
has_name() { after "$1" | grep -qE "^ *$(printf '%s' "$2" | sed 's/[][\\.*^$/]/\\&/g')\$" || { echo "under $1, no line reads: $2"; after "$1"; return 1; }; }
json() { "$VBW" show fix "$F_REQ" --json < /dev/null; }
# check_json ID: the check's object from --json.
check_json() { json | jq -c --arg id "$1" '.checks[] | select(.id == $id)'; }

@test "R195: under each failing check, the kept file and the failing test names: TAP, cargo, pytest, go, jest, vitest and mocha" {
  show | grep -q "full output: $OUT/C1.log" || { show; false; }
  show | grep -q '^ *failing tests:' || { show; false; }
  has_name C1 'pay refuses zero'
  has_name C2 'pay::zero'
  [ "$(after C2 | grep -cE '^ *pay::zero$')" -eq 1 ] || { echo "cargo's name is not listed once:"; after C2; false; }
  has_name C3 'tests/test_pay.py::test_zero'
  has_name C4 'TestZero'
  has_name C5 'refuses zero on jest'
  has_name C6 'refuses zero on vitest'
  has_name C7 'refuses zero on mocha'
  check_json C1 | jq -e --arg o "$OUT" '.kept == "\($o)/C1.log" and .failing_tests == ["pay refuses zero"]'
  check_json C2 | jq -e '.failing_tests == ["pay::zero"]'
  check_json C3 | jq -e '.failing_tests == ["tests/test_pay.py::test_zero"]'
  check_json C4 | jq -e '.failing_tests == ["TestZero"]'
  check_json C5 | jq -e '.failing_tests == ["refuses zero on jest"]'
  check_json C6 | jq -e '.failing_tests == ["refuses zero on vitest"]'
  check_json C7 | jq -e '.failing_tests == ["refuses zero on mocha"]'
}

@test "R195: no name recognised says so and points to the file; a missing file keeps today's not-kept line" {
  show | grep -q "full output: $OUT/C8.log" || { show; false; }
  after C8 | grep -qF 'failing tests: none recognised in the output; read the full output file' || { after C8; false; }
  check_json C8 | jq -e --arg o "$OUT" '.kept == "\($o)/C8.log" and .failing_tests == []'
  show | grep -qF 'full output not kept: run vbw prove again' || { show; false; }
  check_json C9 | jq -e '.kept == null and .failing_tests == []'
}

@test "R195: failing test files are listed by their path with their kept file and failing tests, as text and as JSON" {
  show | grep -q 'tests/t_a\.sh' || { show; false; }
  show | grep -q "full output: $OUT/$TA_LOG" || { show; false; }
  json | jq -e --arg o "$OUT" --arg k "$TA_LOG" '[.test_files[] | select(.path == "tests/t_a.sh")] | length == 1 and .[0].kept == "\($o)/\($k)" and .[0].failing_tests == ["t_a pays"]'
  run "$VBW" show fix "$F_TEST" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"tests/t_a.sh"* && "$output" == *"full output: $OUT/$TA_LOG"* && "$output" == *"t_a pays"* ]] || { echo "$output"; false; }
  "$VBW" show fix "$F_TEST" --json < /dev/null | jq -e '[.test_files[] | select(.path == "tests/t_a.sh")] | length == 1 and .[0].failing_tests == ["t_a pays"]'
}

@test "R195: the names are read only when vbw show fix runs: no hook or status-line path reads the kept output" {
  ! grep -rl 'runtime/output' "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/lib/cmd-statusline.sh" || false
}
