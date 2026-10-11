#!/usr/bin/env bats
# R167: vbw apply (full, --patch and --add) takes an optional "test_files"
# {run, files}, refuses a bad one before anything changes, writes a good one as
# the spec's `## Test files` section (replacing an older one) and syncs the spec.
# The user approves the form with the contract. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: project"
}

teardown() { vbw_teardown; }

FULL='"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "tier": "standard"}],
  "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/a.txt"]}],
  "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/c1.sh"], "files": ["tests/c1.sh"]}],
  "rules": [{"req": "R1", "text": "a customer can pay", "check": "C1"}]'

form() { printf '"test_files": {"run": %s, "files": %s}' "$1" "$2"; }

@test "R167: a full apply writes test_files as the Test files section and syncs it into the record" {
  printf '{%s, %s}' "$FULL" "$(form '["sh", "{file}"]' '["tests/t_*.sh"]')" | "$VBW" apply
  grep -qx '## Test files' .vbw/spec.md
  grep -qxF -- '- run: sh {file}' .vbw/spec.md
  grep -qxF -- '- files: tests/t_*.sh' .vbw/spec.md
  [ "$(jq -c '.test_files' .vbw/record.json)" = '{"run":["sh","{file}"],"files":["tests/t_*.sh"]}' ]
}

@test "R167: --patch takes test_files too" {
  printf '{%s}' "$FULL" | "$VBW" apply > /dev/null
  printf '{"plans": [], "checks": [], %s}' "$(form '["pytest", "{file}"]' '["tests/test_*.py", "more/*.py"]')" | "$VBW" apply --patch
  grep -qxF -- '- run: pytest {file}' .vbw/spec.md
  grep -qxF -- '- files: tests/test_*.py more/*.py' .vbw/spec.md
  [ "$(jq -c '.test_files.run' .vbw/record.json)" = '["pytest","{file}"]' ]
}

@test "R167: --add takes test_files too" {
  printf '{%s}' "$FULL" | "$VBW" apply > /dev/null
  printf '{"phases": [{"id": "P2", "title": "Refund", "reqs": ["R2"], "tier": "standard"}],
    "plans": [{"id": "P2.1", "phase": "P2", "title": "Refund", "reqs": ["R2"], "files": ["src/b.txt"]}],
    "checks": [{"id": "C2", "req": "R2", "run": ["sh", "tests/c2.sh"], "files": ["tests/c2.sh"]}],
    "rules": [{"req": "R2", "text": "a customer can refund", "check": "C2"}], %s}' "$(form '["sh", "{file}"]' '["tests/t_*.sh"]')" | "$VBW" apply --add
  grep -qxF -- '- run: sh {file}' .vbw/spec.md
  [ "$(jq -c '.test_files.files' .vbw/record.json)" = '["tests/t_*.sh"]' ]
}

@test "R167: a bad form is refused in every mode and nothing changes" {
  before=$(cat .vbw/spec.md)
  for bad in "$(form '["sh", "tests/t_a.sh"]' '["tests/t_*.sh"]')" \
             "$(form '["sh", "{file}", "{file}"]' '["tests/t_*.sh"]')" \
             "$(form '["sh", "{file}"]' '[]')" \
             "$(form '["sh", "{file}"]' '["has space/*.sh"]')" \
             '"test_files": "sh {file}"'; do
    run bash -c 'printf "%s" "$1" | "$2" apply' _ "{$FULL, $bad}" "$VBW"
    [ "$status" -ne 0 ] || { echo "$bad"; false; }
    [[ "$output" == *"test_files must be"* ]] || { echo "$output"; false; }
    run bash -c 'printf "%s" "$1" | "$2" apply --patch' _ "{\"plans\": [], $bad}" "$VBW"
    [ "$status" -ne 0 ] || { echo "$bad"; false; }
  done
  [ "$(cat .vbw/spec.md)" = "$before" ]
  [ "$(jq '.plans | length' .vbw/record.json)" -eq 0 ]
}

@test "R167: a later form replaces the older Test files section and keeps the other sections" {
  printf '{%s, %s}' "$FULL" "$(form '["sh", "{file}"]' '["tests/t_*.sh"]')" | "$VBW" apply > /dev/null
  printf '\n## Notes\n\nkeep me\n' >> .vbw/spec.md
  printf '{"plans": [], %s}' "$(form '["bats", "{file}"]' '["tests/*.bats"]')" | "$VBW" apply --patch > /dev/null
  [ "$(grep -c '^## Test files' .vbw/spec.md)" -eq 1 ]
  grep -qxF -- '- run: bats {file}' .vbw/spec.md
  ! grep -qF 'sh {file}' .vbw/spec.md
  grep -qx 'keep me' .vbw/spec.md
  grep -q 'R1 \[auto\]' .vbw/spec.md
}

@test "R167: without test_files the spec is left alone" {
  before=$(cat .vbw/spec.md)
  printf '{%s}' "$FULL" | "$VBW" apply > /dev/null
  [ "$(cat .vbw/spec.md)" = "$before" ]
}
