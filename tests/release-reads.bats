#!/usr/bin/env bats
# R166 with R170 (docs/proof.md): a proof that reused results is recorded as not
# full, and bash tools/test.sh --release reuses it all the same: a reused result
# is one the read lists still vouch for. A vbw prove --full is reused as before.
# L1: a real vbw prove in a scratch git project that holds a copy of
# tools/test.sh, with stand-ins for bats, the benchmarks and shellcheck that log
# their calls.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests tools
  LOG="$TEST_ROOT/calls.log"
  export LOG
  printf 'paid\n' > src/pay.txt
  printf 'unread\n' > src/other.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx paid src/pay.txt\n' > tests/all.sh
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  cp "$REPO_ROOT/tools/test.sh" "$REPO_ROOT/tools/bump-version.sh" tools/
  local b
  for b in bench-hooks bench-panel; do
    printf '#!/usr/bin/env bash\necho %s >> "$LOG"\n' "$b" > "tools/$b.sh"
  done
  printf '#!/usr/bin/env bash\n{ printf %%s bats; printf " %%s" "$@"; echo; } >> "$LOG"\n' > "$TEST_ROOT/bats"
  printf '#!/usr/bin/env bash\necho 8\n' > "$TEST_ROOT/getconf"
  chmod +x "$TEST_ROOT/bats" "$TEST_ROOT/getconf"
  git add -A && git commit -q -m "chore: files"
  printf '%s' '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  git add -A && git commit -q -m "chore(vbw): plan" || true
}

teardown() { vbw_teardown; }

change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "chore: change $1"
}

release_run() {
  : > "$LOG"
  mkdir -p "$TEST_ROOT/bin"
  cp "$TEST_ROOT/bats" "$TEST_ROOT/getconf" "$TEST_ROOT/bin/"
  run env PATH="$TEST_ROOT/bin:$PATH" bash tools/test.sh --release < /dev/null
}

@test "R170: a proof that reused results is recorded as not full, and the release run reuses it all the same" {
  "$VBW" prove --full > /dev/null || { echo "the full proof failed"; false; }
  change src/other.txt
  "$VBW" prove > /dev/null || { echo "the proof failed"; false; }
  jq -e '.evidence.full == false and .evidence.commands.test.reused == true' .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): record" || true
  release_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"reusing the passing proof"* ]] || { echo "$output"; false; }
  ! grep -q 'tests/a.bats' "$LOG" || { cat "$LOG"; false; }
}

@test "R166: after a full proof of the same code, the release run reuses it" {
  "$VBW" prove --full > /dev/null || { echo "the full proof failed"; false; }
  git add -A && git commit -q -m "chore(vbw): record" || true
  release_run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"reusing the passing proof"* ]] || { echo "$output"; false; }
  ! grep -q 'tests/a.bats' "$LOG" || { cat "$LOG"; false; }
}
