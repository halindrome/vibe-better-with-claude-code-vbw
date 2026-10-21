#!/usr/bin/env bats
# R168 (docs/proof.md): the wiring of the causes and counts. The clone's store
# holds runs only; a changed approved command re-runs that command and nothing
# else, in vbw prove as in vbw fix done (which honours the same causes as vbw
# prove: a cause runs every candidate check); a failing test file is re-run on
# its own through the single-file form, never as the whole test command.
# Scripts log their runs to $RANLOG. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'echo t_a >> "$RANLOG"\n[ ! -e "$RANLOG.fail" ] || exit 1\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/t_b.sh
  printf 'echo C1 >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/c1.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  printf 'echo lint >> "$RANLOG"\n' > tests/lint.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  spec 'sh tests/lint.sh' > /dev/null
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n- lint: %s\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' "$1" > .vbw/spec.md
  "$VBW" spec sync
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

store() { cat "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"; }

ran() { sort "$RANLOG" | tr '\n' ' '; }

@test "R168: the clone's store holds the recorded runs and nothing else" {
  store | jq -e '(keys == ["runs"]) and (.runs | type == "object") and (.runs | has("check:C1") and has("command:lint") and has("file:tests/t_a.sh"))' > /dev/null || { store; false; }
}

@test "R168: a changed approved command re-runs that command only: vbw fix done re-runs no check for it, the next vbw prove runs the command and says why" {
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'
  spec 'sh tests/lint.sh x' > /dev/null
  git add -A && git commit -q -m "chore(vbw): commands"
  "$VBW" approve > /dev/null
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'C1 unchanged since its pass' || { echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'every candidate check runs' || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "lint " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^ +lint pass .*ran: definition changed' || { echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'ran everything' || { echo "$output"; false; }
}

# A failing test file opens a fix for the test command.
fail_t_a() {
  : > "$RANLOG.fail"
  printf "echo changed > /dev/null\n" >> tests/t_a.sh
  git add tests/t_a.sh && git commit -q -m "feat: t_a"
  vbw_run prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  jq -e 'any(.fixes[]; .command == "test" and .status == "open")' .vbw/record.json > /dev/null || { cat .vbw/record.json; false; }
  : > "$RANLOG"
}

@test "R168: vbw fix done re-runs a failing test file on its own, never the whole test command, and closes the fix when it passes" {
  fail_t_a
  rm "$RANLOG.fail"
  printf 'echo fixed\n' >> tests/t_a.sh
  git add tests/t_a.sh && git commit -q -m "fix: t_a"
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a " ] || { echo "ran: $(ran)"; false; }
  jq -e 'any(.fixes[]; .id == "F1" and .status == "fixed")' .vbw/record.json > /dev/null || { cat .vbw/record.json; false; }
}

@test "R168: vbw fix done leaves the fix open and names the test file when it still fails" {
  fail_t_a
  vbw_run fix done F1
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'tests/t_a.sh fail' || { echo "$output"; false; }
  [ "$(ran)" = "t_a " ] || { echo "ran: $(ran)"; false; }
  jq -e 'any(.fixes[]; .id == "F1" and .status == "open")' .vbw/record.json > /dev/null || { cat .vbw/record.json; false; }
}

@test "R168: both savers of the store go through one locking function" {
  [ "$(grep -c 'vbw_lock_take' "$REPO_ROOT/plugin/lib/proofreuse.sh" "$REPO_ROOT/plugin/lib/testfiles.sh" | grep -v ':0' | wc -l | tr -d ' ')" = 1 ]
  grep -q 'proofreuse_merge' "$REPO_ROOT/plugin/lib/testfiles.sh"
}
