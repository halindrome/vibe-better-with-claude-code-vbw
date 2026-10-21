#!/usr/bin/env bats
# R160 (docs/proof.md): vbw fix check FIX registers a regression test only for
# an open fix QA opened, with a test file that exists and a well-formed check
# document; every other case is refused with what to do instead, and the
# record stays as it was. L1.

load helper
load fixture-helper

# The built and proved shop with a QA finding open, built once per file.
setup_file() { fixture_build refusals refusals_project; }
setup() { fixture_copy refusals; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

refusals_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "Customers pay", criteria: ["paid"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "a customer can pay", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null 2>&1 || true
  "$VBW" qa finding R1 "a payment of zero is accepted" > /dev/null
  F_QA=$(jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json)
  export F_QA
  printf 'grep -qx paid src/pay.txt\n' > tests/r1-regression.sh
  DOC='{"run": ["sh", "tests/r1-regression.sh"], "files": ["tests/r1-regression.sh"]}'
  export DOC
}

# refused FIX DOC TEXT: vbw fix check fails, says TEXT, and the record is unchanged.
refused() {
  local before
  before=$(cksum < .vbw/record.json)
  run bash -c 'printf "%s" "$2" | "$1" fix check "$3"' _ "$VBW" "$2" "$1"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"$3"* ]] || { echo "$output"; return 1; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { echo "the record changed"; return 1; }
}

@test "R160: the fix QA opened registers its test; the check names the requirement and the fix" {
  run bash -c 'printf "%s" "$2" | "$1" fix check "$3"' _ "$VBW" "$DOC" "$F_QA"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e --arg f "$F_QA" '.checks[-1] | .req == "R1" and .fix == $f and .run == ["sh", "tests/r1-regression.sh"]' .vbw/record.json
}

@test "R160: an unknown fix is refused" {
  refused F99 "$DOC" "unknown fix F99"
}

@test "R160: a fix that is no longer open is refused, saying QA opens a new one if the problem remains" {
  jq --arg f "$F_QA" '(.fixes[] | select(.id == $f)).status = "fixed"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  refused "$F_QA" "$DOC" "is fixed, not open"
}

@test "R160: a fix QA did not open is refused: a proof failure is fixed in the code its check already tests" {
  jq '.fixes += [{id: "F77", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  refused F77 "$DOC" "was not opened by QA"
}

@test "R160: a test file that does not exist is refused: create it first" {
  refused "$F_QA" '{"run": ["sh", "tests/nope.sh"], "files": ["tests/nope.sh"]}' "tests/nope.sh does not exist"
}

@test "R160: a malformed check document is refused with the shape it needs" {
  refused "$F_QA" '{"run": "sh tests/r1-regression.sh"}' "run (argv array), files"
  refused "$F_QA" '{"run": ["sh", "tests/r1-regression.sh"], "files": []}' "run (argv array), files"
  refused "$F_QA" '{"run": ["sh", "tests/r1-regression.sh"], "files": ["tests/r1-regression.sh"], "colour": "red"}' "run (argv array), files"
}
