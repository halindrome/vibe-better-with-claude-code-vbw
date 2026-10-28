#!/usr/bin/env bats
# R167 (docs/proof.md): a project declares, next to its commands, how its test
# runner runs one test file and which files are its test files, in a
# `## Test files` section of .vbw/spec.md:
#
#   ## Test files
#
#   - run: sh {file}
#   - files: tests/t_*.sh
#
# The user approves it like any command (consent by content hash); VBW never
# runs a form that is not approved and never guesses one. With an approved
# form each test file runs on its own and the whole test command does not;
# without one the test command runs whole and the proof summary says so. The
# Lead proposes a form through vbw apply ("test_files"), which writes it into
# the spec for the user to approve. Scripts log their runs to $RANLOG. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'echo "t_a$1" >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/t_a.sh
  printf 'echo "t_b$1" >> "$RANLOG"\ngrep -q . src/b.txt\n' > tests/t_b.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  printf 'echo C1 >> "$RANLOG"\n' > tests/c1.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# spec FORM: write the spec with the test command and, when FORM is not
# empty, a Test files section holding FORM's lines; then sync it.
spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  [ -z "$1" ] || printf '\n## Test files\n\n%s\n' "$1" >> .vbw/spec.md
  "$VBW" spec sync
}

# project FORM: the spec, one check and one done plan, committed and approved.
project() {
  spec "$1" > /dev/null || return 1
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

FORM='- run: sh {file}
- files: tests/t_*.sh'

@test "R167: with an approved single-file form each test file runs on its own and the whole test command does not run" {
  project "$FORM"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 t_a t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 2 ran, 0 reused$' || { echo "$output"; false; }
}

@test "R167: an edited form never runs before the user approves it again, and runs once approved" {
  project "$FORM"
  "$VBW" prove > /dev/null
  spec '- run: sh {file} again
- files: tests/t_*.sh' > /dev/null
  git commit -q -am "chore(vbw): run each test file again"
  : > "$RANLOG"
  run "$VBW" prove < /dev/null
  [[ "$(ran)" != *again* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ " $(ran)" == *" t_aagain "* && " $(ran)" == *" t_bagain "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R167: without a declared form the test command runs whole, and the proof summary says so" {
  project ""
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 all " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 0 ran, 0 reused' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'test command ran whole: no single-file form' || { echo "$output"; false; }
}

@test "R167: VBW never guesses a form: vbw init writes no Test files section" {
  rm -rf .vbw
  "$VBW" init > /dev/null
  ! grep -q '^## Test files' .vbw/spec.md
}

@test "R167: a form whose run does not name {file} exactly once is refused when the spec is synced" {
  run spec '- run: sh tests/t_a.sh
- files: tests/t_*.sh'
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"{file}"* ]] || { echo "$output"; false; }
  run spec '- run: sh {file} {file}
- files: tests/t_*.sh'
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

@test "R167: a form with no test files is refused when the spec is synced" {
  run spec '- run: sh {file}'
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"files"* ]] || { echo "$output"; false; }
}

@test "R167: the Lead's proposal through vbw apply writes the form into the spec's Test files section, for the user to approve" {
  spec "" > /dev/null
  git add -A && git commit -q -m "chore: project"
  printf '%s' '{"phases": [{"id": "P1", "title": "Shop", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/a.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/c1.sh"], "files": ["tests/c1.sh"]}],
    "rules": [{"req": "R1", "text": "a customer can pay", "check": "C1"}],
    "test_files": {"run": ["sh", "{file}"], "files": ["tests/t_*.sh"]}}' | "$VBW" apply
  grep -qx '## Test files' .vbw/spec.md
  grep -qxF -- '- run: sh {file}' .vbw/spec.md
  grep -qxF -- '- files: tests/t_*.sh' .vbw/spec.md
  vbw_run show contract
  [[ "$output" == *"{file}"* ]] || { echo "$output"; false; }
}
