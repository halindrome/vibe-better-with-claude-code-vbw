#!/usr/bin/env bats
# The environment a proof's units run in (docs/proof.md): a check or project
# command never sees the session that runs the proof (VBW_SESSION_ID), so a
# project's tests give one result whoever proves them; the figures a test
# records under a session id are its own, never the prover's (R173). L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'printf "%%s" "${VBW_SESSION_ID-unset}" > "$TEST_ROOT/check.env"\ngrep -q paid src/pay.txt\n' > tests/pay.sh
  printf 'printf "%%s" "${VBW_SESSION_ID-unset}" > "$TEST_ROOT/command.env"\n' > tests/all.sh
  git add -A && git commit -q -m "chore: files"
  printf '%s' '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" plan "done" P1.1 > /dev/null 2>&1 || true
  git add -A && git commit -q -m "chore(vbw): plan" || true
}

teardown() { vbw_teardown; }

@test "R173: a check and a project command run without the VBW_SESSION_ID of the session that proves" {
  VBW_SESSION_ID=s1 "$VBW" prove > /dev/null || { echo "the proof failed"; false; }
  [ "$(cat "$TEST_ROOT/check.env")" = unset ]
  [ "$(cat "$TEST_ROOT/command.env")" = unset ]
}

@test "R173: vbw fix done runs its checks the same way" {
  "$VBW" prove > /dev/null
  rm -f "$TEST_ROOT/check.env"
  jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "pay"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  printf 'paid\nmore\n' > src/pay.txt
  git commit -q -am "fix: pay"
  VBW_SESSION_ID=s1 "$VBW" fix "done" F1 > /dev/null || { echo "fix done failed"; false; }
  [ "$(cat "$TEST_ROOT/check.env")" = unset ]
}
