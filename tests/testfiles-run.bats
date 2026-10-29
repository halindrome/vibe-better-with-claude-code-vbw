#!/usr/bin/env bats
# R167 (docs/proof.md): with an approved single-file form, each test file runs
# on its own and its read list is recorded as for checks. A test file runs when
# it is new or changed, its last result failed, it never passed, it has no
# read list, a file it read was changed, deleted or renamed, or a file was
# added to or removed from a folder it listed; every other test file reuses its
# passing result. Test files run several at a time. A failing test file fails
# the proof, which names it. A test file an approved check runs runs only as
# that check (D179: nothing runs twice), and the quick command never stands in
# for an approved form. The test files' units are built in one pass, never a
# jq run or a hash per test file (T179). Scripts log their runs to $RANLOG. L1.

load helper
load fixture-helper

setup_file() { fixture_build shop testfiles_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# testfiles_project: the project every test starts from, with the outcome of
# its first proof (FIRST_STATUS, FIRST_OUTPUT, FIRST_RAN), built once per file.
testfiles_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src/dir tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'unread\n' > src/other.txt
  printf '1\n' > src/dir/one.txt
  printf 'echo t_a >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\ngrep -q . src/b.txt\n[ ! -e "$TEST_ROOT/fail_b" ]\n' > tests/t_b.sh
  printf 'echo t_d >> "$RANLOG"\nls src/dir > /dev/null\n' > tests/t_d.sh
  printf 'echo t_k >> "$RANLOG"\n' > tests/t_k.sh
  # t_p and t_q pass only when they run at the same time (each waits up to 20 s for the other).
  printf 'echo t_p >> "$RANLOG"\n: > "$SYNC/p"\ni=0\nwhile [ ! -e "$SYNC/q" ]; do i=$((i + 1)); [ "$i" -lt 200 ] || exit 1; sleep 0.1; done\n' > tests/t_p.sh
  printf 'echo t_q >> "$RANLOG"\n: > "$SYNC/q"\ni=0\nwhile [ ! -e "$SYNC/p" ]; do i=$((i + 1)); [ "$i" -lt 200 ] || exit 1; sleep 0.1; done\n' > tests/t_q.sh
  printf 'echo "all$1" >> "$RANLOG"\n' > tests/all.sh
  export RANLOG="$TEST_ROOT/ran.log" SYNC="$TEST_ROOT/sync"
  mkdir -p "$SYNC"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n- quick: sh tests/all.sh quick\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  # C1 runs tests/t_k.sh, which is also one of the declared test files.
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/t_k.sh"], files:["tests/t_k.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 2 > /dev/null
  run "$VBW" prove < /dev/null
  FIRST_STATUS=$status FIRST_OUTPUT=$output
  FIRST_RAN=$(ran)
  FIRST=$(jq -r '.evidence.at' .vbw/record.json)
  rm -f "$SYNC"/*
  : > "$RANLOG"
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

# counted: jq and the hashing tools first on PATH, each counting its runs in $PROCLOG
# ("jq" or "sha" per line) before it runs the real one.
counted() {
  local bin="$TEST_ROOT/countbin" tool real
  PROCLOG="$TEST_ROOT/procs.log"
  mkdir -p "$bin"
  for tool in jq sha256sum shasum; do
    real=$(command -v "$tool") || continue
    case "$tool" in jq) printf '#!/bin/sh\necho jq >> "$PROCLOG"\nexec "%s" "$@"\n' "$real" ;; *) printf '#!/bin/sh\necho sha >> "$PROCLOG"\nexec "%s" "$@"\n' "$real" ;; esac > "$bin/$tool"
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  export PROCLOG PATH
}

# tf_run PATH...: testfiles_run for those test files, in place (no copies): "jq N sha M",
# the processes it took; its result in $TEST_ROOT/tf.json.
tf_run() {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/checks.sh"; . "$VBW_LIB/testfiles.sh"; mkdir -p "$VBW_RUNTIME"
    CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX"); record=$(cat "$VBW_RECORD"); TF_TODO=('"$*"')
    : > "$PROCLOG"; testfiles_run "$record" > "$TEST_ROOT/tf.json"
    echo "jq $(grep -c "^jq$" "$PROCLOG") sha $(grep -c "^sha$" "$PROCLOG")"'
}

@test "R167: each test file runs once on its own; the one a check runs runs only as that check; neither the test nor the quick command runs" {
  [ "$FIRST_STATUS" -eq 0 ] || { echo "$FIRST_OUTPUT"; false; }
  [ "$FIRST_RAN" = "t_a t_b t_d t_k t_p t_q " ] || { echo "ran: $FIRST_RAN"; echo "$FIRST_OUTPUT"; false; }
}

@test "R167: test files run several at a time" {
  [ "$FIRST_STATUS" -eq 0 ] || { echo "$FIRST_OUTPUT"; false; }
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(ran)" == *"t_p t_q"* ]] || { echo "ran: $(ran)"; false; }
}

@test "R167: a commit that changes a file one test file read runs only that test file and reuses the others, naming the proof" {
  change src/b.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 1 ran, 4 reused$' || { echo "$output"; false; }
  line 'tests/t_a\.sh' | grep -qF "reused (proof of $FIRST)" || { echo "$output"; false; }
}

@test "R167: a new test file runs, and only it" {
  printf 'echo t_e >> "$RANLOG"\n' > tests/t_e.sh
  git add tests/t_e.sh && git commit -q -m "test: t_e"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_e " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R167: a changed test file runs again, and only it" {
  printf '# edited\n' >> tests/t_a.sh
  git add tests/t_a.sh && git commit -q -m "test: edit t_a"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R167: a test file whose last result failed runs again though nothing it read changed" {
  : > "$TEST_ROOT/fail_b"
  "$VBW" prove --full > /dev/null || true
  rm -f "$TEST_ROOT/fail_b" "$SYNC"/*
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line 'tests/t_b\.sh' | grep -q 'ran: last result failed' || { echo "$output"; false; }
}

@test "R167: deleting a file a test file read runs that test file, and the check of the requirement whose plan delivers it (R168)" {
  git rm -q src/a.txt && git commit -q -m "feat: drop a"
  vbw_run prove
  # t_a read src/a.txt. C1 (tests/t_k.sh) never did, but P1.1 (R1) delivers it, so the contract ties C1 to it.
  [ "$(ran)" = "t_a t_k " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +tests/t_a\.sh fail .*ran: src/a\.txt deleted' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +C1 pass .*ran: src/a\.txt deleted' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +tests/t_b\.sh pass .*reused' || { echo "$output"; false; }
}

@test "R167: adding a file to a folder a test file listed runs that test file" {
  printf '2\n' > src/dir/two.txt
  git add src/dir/two.txt && git commit -q -m "feat: two"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_d " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R167: a failing test file fails the proof, and the proof names it" {
  : > "$TEST_ROOT/fail_b"
  change src/b.txt
  vbw_run prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +tests/t_b\.sh fail' || { echo "$output"; false; }
  [[ "$output" == *"not proved"* ]] || { echo "$output"; false; }
}

@test "T179: the units of the test files come from one pass: no jq run or hash per test file but each one's result, and the same unit names" {
  counted
  local two four
  two=$(tf_run tests/t_a.sh tests/t_b.sh)
  four=$(tf_run tests/t_a.sh tests/t_b.sh tests/t_d.sh tests/t_k.sh)
  [[ "$two" =~ ^jq\ ([0-9]+)\ sha\ ([0-9]+)$ ]] || { echo "$two"; false; }
  local jq2=${BASH_REMATCH[1]} sha2=${BASH_REMATCH[2]}
  [[ "$four" =~ ^jq\ ([0-9]+)\ sha\ ([0-9]+)$ ]] || { echo "$four"; false; }
  # Two test files more: at most two jq runs more (each one's result object), no hash more.
  [ $((BASH_REMATCH[1] - jq2)) -le 2 ] && [ "${BASH_REMATCH[2]}" -eq "$sha2" ] || { echo "two files: $two; four files: $four"; false; }
  # Each result names the unit testfiles_id names, and every one passed.
  local p id
  for p in tests/t_a.sh tests/t_b.sh tests/t_d.sh tests/t_k.sh; do
    # shellcheck disable=SC2016 # expanded by vbw_kernel
    id=$(vbw_kernel '. "$VBW_LIB/checks.sh"; . "$VBW_LIB/testfiles.sh"; testfiles_id '"$p")
    jq -e --arg p "$p" --arg id "$id" '.[$p].id == $id and .[$p].status == "pass"' "$TEST_ROOT/tf.json" > /dev/null || { echo "$p ($id):"; cat "$TEST_ROOT/tf.json"; false; }
  done
}

@test "R167: vbw prove --full runs every test file on its own and reuses none" {
  change src/other.txt
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a t_b t_d t_k t_p t_q " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +test files: 5 ran, 0 reused$' || { echo "$output"; false; }
}
