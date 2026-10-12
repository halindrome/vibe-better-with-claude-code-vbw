#!/usr/bin/env bats
# R168 (docs/proof.md): the library that names why a proof runs everything
# (plugin/lib/proofcauses.sh). The store of recorded runs is written by hand
# here, on the committed code, the way a proof leaves it. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'unread\n' > src/unread.txt
  printf 'ready=1\n' > tests/helper.sh
  printf 'x\n' > tests/t_a.sh
  printf 'x\n' > tests/t_b.sh
  printf 'x\n' > tests/c1.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n- lint: sh tests/lint.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt"], after:[], status:"done"}]
    | .commands = {test: ["sh","tests/all.sh"], lint: ["sh","tests/lint.sh"]}
    | .test_files = {run: ["sh","{file}"], files: ["tests/t_*.sh"]}
    | .checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]'
  git add -A && git commit -q -m "chore: files"
  store
}

teardown() { vbw_teardown; }

# store: the clone's store of runs, as a proof of the committed code leaves it:
# both test files read the helper and src/a.txt, the check read its own file,
# and every run listed the folder src.
store() {
  local tree common
  tree=$(vbw_kernel 'vbw_head_tree')
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  mkdir -p "$common/vbw"
  jq -n --arg t "$tree" '
    def run($reads): {fp: "x", tree: $t, status: "pass", at: "t", seconds: 1, tail: "", reads: $reads, dirs: [{path: "src", fp: "f"}], git: false};
    {runs: {"file:tests/t_a.sh": run(["tests/t_a.sh","tests/helper.sh","src/a.txt"]),
            "file:tests/t_b.sh": run(["tests/t_b.sh","tests/helper.sh"]),
            "check:C1": run(["tests/c1.sh"])}}' > "$common/vbw/runs.json"
}

# edit_record FILTER: change the record, keeping the protected list in step.
edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# causes [FULL]: the causes for the committed code, one per line.
# causes [FULL] [KIND]: the causes proofcauses_find prints for this project (KIND: prove or fix).
causes() {
  vbw_kernel '. "$VBW_LIB/proofcauses.sh"; VBW_COMMAND_TIMEOUT=3600; mkdir -p "$VBW_RUNTIME"; proofcauses_find "$(record_read)" "'"${1:-0}"'" "$(vbw_head_tree)" "'"${2:-prove}"'"'
}

change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

noreads() {
  local real
  real=$(command -v touch)
  mkdir -p "$TEST_ROOT/noreads"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -*a*) exit 0 ;; esac; done\nexec %s "$@"\n' "$real" > "$TEST_ROOT/noreads/touch"
  chmod +x "$TEST_ROOT/noreads/touch"
}

@test "R168: nothing changed and every run recorded: no cause" {
  run causes
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: vbw prove --full is a cause" {
  run causes 1
  [ "$output" = "vbw prove --full" ]
}

@test "R168: a proof cut short is a cause" {
  mkdir -p .vbw/runtime && : > .vbw/runtime/prove.unfinished
  run causes
  [ "$output" = "the last proof was cut short" ] || { echo "$output"; false; }
}

@test "R168: a clone with no recorded run is a cause" {
  rm "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  run causes
  [ "$output" = "this clone has no earlier recorded run" ] || { echo "$output"; false; }
}

@test "R168: a file system that does not record reads is a cause" {
  noreads
  PATH="$TEST_ROOT/noreads:$PATH" run causes
  [ "$output" = "this file system does not record which files are read" ] || { echo "$output"; false; }
}

# prove_passed: the record says a proof passed on the project as it is now (R175):
# code tree, committed tree, contract and the record itself (its fingerprint
# without the evidence, evidence.record) are as that proof left them.
prove_passed() {
  local code head con fp
  code=$(vbw_kernel 'vbw_code_tree'); head=$(vbw_kernel 'vbw_head_tree')
  edit_record '.evidence = {at: "2026-10-11T00:00:00Z", contract: "0000000000000000000000000000000000000000000000000000000000000000", passed: true, checks: {}, commands: {}, scope: [], tree: "'"$code"'", head: "'"$head"'"}'
  con=$(vbw_kernel 'contract_hash "$(record_read)"')
  edit_record '.evidence.contract = "'"$con"'"'
  fp=$(vbw_kernel 'jq -c "del(.evidence)" "$VBW_RECORD" | vbw_sha256')
  edit_record '.evidence.record = "'"$fp"'"'
}

@test "R168: nothing committed since the last passing proof is a cause" {
  prove_passed
  run causes
  [ "$output" = "nothing was committed since the last passing proof" ] || { echo "$output"; false; }
}

@test "R175: a record changed since the last passing proof (a decision, a verdict, a backlog item) is no cause: the proof reuses by read lists" {
  prove_passed
  edit_record '.phases[0].title = "Shop and pay"'
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175 (D302): the cause has no condition beyond the trees and the record fingerprint: a stale evidence.contract or a stale command fingerprint in the store still names it" {
  prove_passed
  edit_record '.evidence.contract = "1111111111111111111111111111111111111111111111111111111111111111"'
  run causes
  [ "$output" = "nothing was committed since the last passing proof" ] || { echo "$output"; false; }
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  jq '.runs["command:lint"] = {fp: "stale", tree: "t", status: "pass", at: "t", seconds: 1, tail: "", reads: [], dirs: [], git: false}' "$common/vbw/runs.json" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$common/vbw/runs.json"
  run causes
  [ "$output" = "nothing was committed since the last passing proof" ] || { echo "$output"; false; }
}

@test "R175 (F151): an uncommitted edit to a project file is no cause: the project's files differ from the tree the proof recorded while HEAD and the record are unchanged" {
  prove_passed
  run causes
  [ "$output" = "nothing was committed since the last passing proof" ] || { echo "$output"; false; }
  printf 'more\n' >> src/a.txt
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175: a passing proof that recorded no fingerprint of the record (an older VBW) is no cause" {
  prove_passed
  edit_record 'del(.evidence.record)'
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: for vbw fix done, nothing committed since the last passing proof is no cause: that proof is what it wants" {
  prove_passed
  run causes 0 fix
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a changed approved command, single-file form or list of test files is no cause: each unit re-runs by its own definition" {
  edit_record '.commands.lint = ["sh","tests/lint.sh","x"]'
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
  edit_record '.test_files.run = ["sh","-e","{file}"]'
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
  edit_record '.test_files.files = ["tests/t_*.sh","tests/u_*.sh"]'
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a store from an older VBW that still carries a form is read as its runs" {
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  jq '.form = {commands: {}}' "$common/vbw/runs.json" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$common/vbw/runs.json"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a changed file that every test file reads is no cause: each file re-runs by its own read list" {
  change tests/helper.sh
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a changed file that only one test file reads is no cause" {
  change src/a.txt
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a content change to a file no recorded run read is no cause" {
  change src/unread.txt
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: an added file that no run read and no run listed the folder of is a cause, and names it" {
  mkdir -p other
  printf 'n\n' > other/new.txt
  git add other/new.txt && git commit -q -m "feat: new"
  run causes
  [ "$output" = "other/new.txt was added, and no recorded run read it or listed its folder" ] || { echo "$output"; false; }
}

@test "R168: a deleted file that no run read and no run listed the folder of is a cause, and names it" {
  mkdir -p other
  printf 'n\n' > other/old.txt
  git add other/old.txt && git commit -q -m "feat: old"
  store
  git rm -q other/old.txt && git commit -q -m "feat: drop old"
  run causes
  [ "$output" = "other/old.txt was deleted, and no recorded run read it or listed its folder" ] || { echo "$output"; false; }
}

@test "R168: a deletion that a later recorded run already ran without is no cause" {
  local common tree
  mkdir -p other
  printf 'n\n' > other/old.txt
  git add other/old.txt && git commit -q -m "feat: old"
  store
  git rm -q other/old.txt && git commit -q -m "feat: drop old"
  # One run re-ran on the code without the file, as a proof that judged the deletion leaves it.
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  tree=$(vbw_kernel 'vbw_head_tree')
  jq --arg t "$tree" '.runs["check:C1"].tree = $t' "$common/vbw/runs.json" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$common/vbw/runs.json"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: an added file in a folder a recorded run listed is no cause" {
  printf 'n\n' > src/new.txt
  git add src/new.txt && git commit -q -m "feat: new"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: an added file that a recorded run read is no cause" {
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  jq '.runs["file:tests/t_a.sh"].reads += ["other/new.txt"]' "$common/vbw/runs.json" > "$TEST_ROOT/s.json" && cp "$TEST_ROOT/s.json" "$common/vbw/runs.json"
  mkdir -p other
  printf 'n\n' > other/new.txt
  git add other/new.txt && git commit -q -m "feat: new"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a new test file is a run of its own, not an unknown file" {
  printf 'x\n' > tests/t_c.sh
  git add tests/t_c.sh && git commit -q -m "feat: test c"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a new check file is a run of its own, not an unknown file" {
  mkdir -p checks
  printf 'x\n' > checks/c2.sh
  edit_record '.checks += [{id:"C2", req:"R1", run:["sh","checks/c2.sh"], files:["checks/c2.sh"]}]'
  git add checks/c2.sh && git commit -q -m "feat: check 2"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: a deleted test file is no unknown file" {
  git rm -q tests/t_b.sh && git commit -q -m "feat: drop test b"
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R168: several causes are all named, one per line" {
  mkdir -p .vbw/runtime && : > .vbw/runtime/prove.unfinished
  mkdir -p other
  printf 'n\n' > other/new.txt
  git add other/new.txt && git commit -q -m "feat: new"
  run causes 1
  [ "${#lines[@]}" -eq 3 ] || { echo "$output"; false; }
  [ "${lines[0]}" = "vbw prove --full" ]
  [ "${lines[1]}" = "the last proof was cut short" ]
}
