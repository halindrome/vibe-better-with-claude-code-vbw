#!/usr/bin/env bats
# R149 and R202 (docs/proof.md): what grows with the project never travels on a
# command line, which the system caps (about 1 MB on macOS, 128 KB per argument
# on Linux). vbw fix done prints its two report lines when the reused test
# files' read lists are large, and a commit that adds thousands of files no run
# has seen and no plan lists runs nothing and records no cause: nothing of it
# reaches the record or a command line. L1: the kernel on fixture projects; the
# read lists are made large in the clone's run store.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'b\n' > src/b.txt
  printf '[ ! -e "$TEST_ROOT/fail_a" ] || { echo "t_a broken"; exit 1; }\n' > tests/t_a.sh
  printf 'grep -q . src/b.txt\n' > tests/t_b.sh
  printf 'grep -q . src/b.txt\n' > tests/t_c.sh
  printf 'grep -q . src/b.txt\n' > tests/c1.sh
  printf 'true\n' > tests/all.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = 4 else . end' \
    .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
}

teardown() { vbw_teardown; }

@test "R202: vbw fix done prints both report lines when the reused test files carry read lists larger than a command line" {
  # The second proof fails on tests/t_a.sh and opens a fix for the test command.
  : > "$TEST_ROOT/fail_a"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 1 ] || { echo "the second proof did not fail: $output"; false; }
  local fix store
  fix=$(jq -r '.fixes[0].id' .vbw/record.json)
  rm -f "$TEST_ROOT/fail_a"
  # Each reused file read 12,000 files (names that never change): together well over 1 MB.
  store="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  jq -c '([range(0; 12000) | "src/generated/a-rather-long-folder-name/module-\(.)/a-file-read-by-the-test.txt"]) as $many
    | .runs["file:tests/t_b.sh"].reads += $many | .runs["file:tests/t_c.sh"].reads += $many' "$store" > "$TEST_ROOT/runs.json"
  cp "$TEST_ROOT/runs.json" "$store"
  [ "$(wc -c < "$store")" -gt 1500000 ] || { echo "the store is not large: $(wc -c < "$store") bytes"; false; }
  vbw_run fix done "$fix"
  [ "$status" -eq 0 ] || { echo "$output" | tail -20; false; }
  [[ "$output" == *$'test files: 1 ran, 2 reused\nVBW\'s own work: '* ]] || { echo "$output" | tail -20; false; }
  [[ "$output" == *"ran again: 1 of 4 units; top reasons: last result failed (1)"* ]] || { echo "$output" | tail -20; false; }
  [[ "$output" == *"$fix fixed: vbw prove decides"* ]] || { echo "$output" | tail -20; false; }
}

@test "R202: a commit that adds thousands of files no run has seen and no plan lists runs nothing, and the record keeps no cause" {
  local dir i name
  # 3,000 new files deep in a folder no run listed and no plan lists (P1.1 delivers src/): one cause
  # each would be over 1 MB of text; no run could see them, so nothing runs and nothing is recorded.
  name="a-generated-source-file-of-the-vendored-library-with-a-long-and-descriptive-name-that-tools-like-to-produce-for-every-module-and-every-target-platform-they-build"
  dir="vendor/a-vendored-library-with-a-rather-long-name/and-a-deep-folder-below-it/of-generated-sources/that-nobody-reads-or-lists"
  mkdir -p "$dir"
  for ((i = 0; i < 3000; i++)); do : > "$dir/$name-$i.txt"; done
  git add vendor && git commit -q -m "chore: vendor a library"
  "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 < /dev/null || { tail -20 "$TEST_ROOT/prove.out"; false; }
  [ "$(tail -n 1 "$TEST_ROOT/prove.out")" = proved ] || { tail -20 "$TEST_ROOT/prove.out"; false; }
  grep -qE '^ +checks: 0 ran, 1 reused$' "$TEST_ROOT/prove.out" || { tail -20 "$TEST_ROOT/prove.out"; false; }
  grep -qE '^ +test files: 0 ran, 3 reused$' "$TEST_ROOT/prove.out" || { tail -20 "$TEST_ROOT/prove.out"; false; }
  ! grep -q 'ran everything' "$TEST_ROOT/prove.out" || { tail -20 "$TEST_ROOT/prove.out"; false; }
  jq -e '.evidence.causes == []' .vbw/record.json > /dev/null || { jq '.evidence.causes' .vbw/record.json | head -c 2000; false; }
}
