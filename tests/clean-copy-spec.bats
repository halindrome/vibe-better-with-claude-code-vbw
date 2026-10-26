#!/usr/bin/env bats
# R205 (docs/proof.md): the `## Clean copy` section of .vbw/spec.md names the
# git-ignored paths every clean copy leaves out, one per line ("- data/"),
# relative to the project root. vbw spec sync copies them into the record
# (project.leave_out, validated by record.jq; a record without the field still
# validates). vbw spec check and vbw spec sync refuse a listed path that git does
# not ignore (tracked, or untracked but not ignored), naming the spec line and
# the path, and leave the record unchanged, while a path with nothing at it is
# accepted (nothing to leave out) and vbw spec check names it; an absolute
# path, a path with '..', or one under .vbw/ or .git/ is refused like a bad Test
# results folder. vbw init's starting spec.md explains the section. The
# contract side (fingerprint, vbw show contract, --changes, approve and next) is
# tests/clean-copy-contract.bats. L1: the kernel on a fixture project.

load helper
load fixture-helper

# shop: an initialized project with two ignored folders (data/, cache/), a
# tracked folder (src/) and an untracked, unignored folder (notes/).
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'data/\ncache/\n' > .gitignore
  mkdir -p data cache src notes tests
  printf 'big\n' > data/a.bin
  printf 'c\n' > cache/c.txt
  printf 'paid\n' > src/pay.txt
  printf 'todo\n' > notes/todo.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  git add .gitignore src tests && git commit -q -m "feat(shop): start"
}

setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# spec LINES: the spec with one requirement, a check-less plan is added by plan;
# LINES (when not empty) are the bullets of a Clean copy section. The section
# starts on line 7, so its first bullet is line 9.
spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  [ -z "$1" ] || printf '\n## Clean copy\n\n%s\n' "$1" >> .vbw/spec.md
}

record_sum() { cksum < .vbw/record.json; }
parsed() { jq -Rs -f "$PLUGIN_ROOT/lib/spec.jq" < .vbw/spec.md; }

# refused SUM: the last run failed and the record is byte-identical to SUM.
refused() {
  [ "$status" -ne 0 ] || { echo "not refused: $output"; return 1; }
  [ "$(record_sum)" = "$1" ] || { echo "the record changed: $output"; return 1; }
}

@test "R205: the parser reads the section as paths with their lines, as written" {
  spec '- data/
- cache'
  parsed | jq -e '.errors == [] and .leave_out == [{path: "data/", line: 9}, {path: "cache", line: 10}]' || { parsed; false; }
}

@test "R205: a spec without the section has no list, and the record then has no field: nothing is left out" {
  spec ''
  parsed | jq -e '.leave_out == null and .errors == []' || { parsed; false; }
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.project | has("leave_out") | not' .vbw/record.json
  [[ "$output" != *"leaves out"* && "$output" != *"clean copy"* ]] || { echo "$output"; false; }
  spec '- data/'
  "$VBW" spec sync > /dev/null
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"clean copy"* ]] || { echo "$output"; false; }
}

@test "R205: vbw spec sync copies the listed paths into project.leave_out and names the list; removing the section removes the field" {
  spec '- data/
- cache/'
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.project.leave_out' .vbw/record.json)" = '["data/","cache/"]' ] || { jq .project .vbw/record.json; false; }
  printf '%s\n' "$output" | grep -q '^clean copy leaves out: data/, cache/$' || { echo "$output"; false; }
  spec ''
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.project | has("leave_out") | not' .vbw/record.json
  printf '%s\n' "$output" | grep -q '^removed the clean copy list$' || { echo "$output"; false; }
}

@test "R205: vbw spec check accepts a good list and counts it" {
  spec '- data/'
  run "$VBW" spec check
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"1 path left out of the clean copy"* ]] || { echo "$output"; false; }
}

@test "R205: an absolute path, a path with '..', or one under .vbw/ or .git/ is refused with its line, like a bad Test results folder" {
  local sum bad
  sum=$(record_sum)
  for bad in '/data' '../data' 'a/../data' '.vbw/runtime' '.git/objects' './data'; do
    spec "- $bad"
    run "$VBW" spec sync
    refused "$sum" || { echo "accepted: $bad"; false; }
    [[ "$output" == *"line 9"* ]] || { echo "$bad: $output"; false; }
    parsed | jq -e '.errors | length == 1' || { echo "$bad: no parse error"; parsed; false; }
  done
}

@test "R205: a path named twice (with or without its trailing slash) is refused with the second line" {
  local sum
  sum=$(record_sum)
  spec '- data/
- data'
  run "$VBW" spec sync
  refused "$sum"
  [[ "$output" == *"line 10"* && "$output" == *"twice"* ]] || { echo "$output"; false; }
}

@test "R205: a tracked path is refused by name, saying only ignored paths are copied in, and the record is unchanged" {
  local sum
  sum=$(record_sum)
  spec '- data/
- src/'
  run "$VBW" spec sync
  refused "$sum"
  [[ "$output" == *"line 10"* && "$output" == *"src/"* ]] || { echo "$output"; false; }
  [[ "$output" == *"is not git-ignored: only ignored paths are copied in, so only they can be left out"* ]] || { echo "$output"; false; }
  jq -e '.project | has("leave_out") | not' .vbw/record.json
  run "$VBW" spec check
  refused "$sum"
  [[ "$output" == *"src/"* && "$output" == *"is not git-ignored"* ]] || { echo "$output"; false; }
}

@test "R205: an ignored folder holding a force-added tracked file is refused" {
  local sum
  sum=$(record_sum)
  git add -f data/a.bin && git commit -q -m "feat(shop): data tracked"
  printf "more\n" > data/b.bin
  spec '- data/'
  run "$VBW" spec sync
  refused "$sum"
  [[ "$output" == *"line 9"* && "$output" == *"data/"* && "$output" == *"is not git-ignored"* ]] || { echo "$output"; false; }
}

@test "R205: an untracked path that git does not ignore is refused the same way" {
  local sum
  sum=$(record_sum)
  spec '- notes/'
  run "$VBW" spec sync
  refused "$sum"
  [[ "$output" == *"line 9"* && "$output" == *"notes/"* && "$output" == *"is not git-ignored"* ]] || { echo "$output"; false; }
}

@test "R205: a path with nothing at it is accepted (nothing to leave out), vbw spec check names it as not here now, and the record keeps it" {
  spec '- data/
- gone/'
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.project.leave_out' .vbw/record.json)" = '["data/","gone/"]' ] || { jq .project .vbw/record.json; false; }
  [[ "$output" != *"does not exist"* ]] || { echo "$output"; false; }
  run "$VBW" spec check
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"gone/"* && "$output" == *"not here now"* ]] || { echo "$output"; false; }
}

@test "R205: a folder whose files alone are ignored, with nothing tracked or stray inside, is accepted" {
  printf 'data/\ncache/\nblobs/*.bin\n' > .gitignore
  git add .gitignore && git commit -q -m "chore: ignore blobs"
  mkdir -p blobs
  printf 'x\n' > blobs/one.bin
  spec '- blobs/'
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.project.leave_out' .vbw/record.json)" = '["blobs/"]' ]
}

@test "R205: the validator accepts a record without the field and refuses a malformed list" {
  spec '- data/'
  "$VBW" spec sync > /dev/null
  local good bad
  good=$(cat .vbw/record.json)
  run "$VBW" show roadmap
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for bad in '.project.leave_out = []' '.project.leave_out = ["/data"]' '.project.leave_out = ["a/../b"]' \
             '.project.leave_out = [".vbw/runtime"]' '.project.leave_out = [".git/objects"]' '.project.leave_out = ["data/", "data/"]' \
             '.project.leave_out = "data/"' '.project.leave_out = [""]'; do
    printf '%s\n' "$good" | jq "$bad" > "$TEST_ROOT/bad.json" && cp "$TEST_ROOT/bad.json" .vbw/record.json
    rm -f .vbw/runtime/glance.json
    run "$VBW" show roadmap
    [ "$status" -ne 0 ] || { echo "accepted: $bad"; false; }
    [[ "$output" == *corrupt* && "$output" == *leave_out* ]] || { echo "$bad: $output"; false; }
  done
  printf '%s\n' "$good" | jq 'del(.project.leave_out)' > "$TEST_ROOT/old.json" && cp "$TEST_ROOT/old.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  run "$VBW" show roadmap
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R205: vbw init's starting spec.md explains the section in the comment style of the other sections, and it names no path" {
  vbw_teardown
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  grep -q '^## Clean copy$' .vbw/spec.md || { cat .vbw/spec.md; false; }
  # The explanation is an HTML comment right after the heading, with an example bullet inside it.
  sed -n '/^## Clean copy$/,$p' .vbw/spec.md | sed -n '3p' | grep -q '^<!--' || { cat .vbw/spec.md; false; }
  sed -n '/^## Clean copy$/,/-->/p' .vbw/spec.md | grep -qi 'git-ignored' || { cat .vbw/spec.md; false; }
  sed -n '/^## Clean copy$/,/-->/p' .vbw/spec.md | grep -q 'vbw spec sync' || { cat .vbw/spec.md; false; }
  sed -n '/^## Clean copy$/,/-->/p' .vbw/spec.md | grep -q '^- [a-z]*/$' || { cat .vbw/spec.md; false; }
  parsed | jq -e '.leave_out == null and .errors == []' || { parsed; false; }
}
