#!/usr/bin/env bats
# R167: the `## Test files` section of .vbw/spec.md (docs/proof.md): parsing,
# refusals, the record's test_files field, and its approval like a command
# (part of the contract hash; shown by vbw show contract). L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# spec FORM: the spec with one requirement, a test command and, when FORM is
# not empty, a Test files section holding FORM's lines.
spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  [ -z "$1" ] || printf '\n## Test files\n\n%s\n' "$1" >> .vbw/spec.md
}

FORM='- run: sh {file}
- files: tests/t_*.sh'

@test "spec check accepts a run line with {file} once and files lines, several lines and several patterns" {
  spec '- run: ["sh", "{file}"]
- files: tests/t_*.sh src/*.t
- files: more/*.t'
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.test_files' .vbw/record.json)" = '{"run":["sh","{file}"],"files":["tests/t_*.sh","src/*.t","more/*.t"]}' ]
}

@test "the spec parser returns the form as run argv and files" {
  spec "$FORM"
  jq -Rs -f "$PLUGIN_ROOT/lib/spec.jq" < .vbw/spec.md | jq -e '.test_files == {run: ["sh","{file}"], files: ["tests/t_*.sh"]} and .errors == []'
}

@test "a spec without the section has no form" {
  spec ""
  jq -Rs -f "$PLUGIN_ROOT/lib/spec.jq" < .vbw/spec.md | jq -e '.test_files == null'
}

@test "a run line without {file}, or with it twice, is refused naming its line" {
  spec '- run: sh tests/t_a.sh
- files: tests/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 13"* && "$output" == *"{file}"* ]] || { echo "$output"; false; }
  spec '- run: sh {file} {file}
- files: tests/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 13"* ]] || { echo "$output"; false; }
}

@test "a section without files, or without a run line, is refused naming the section's line" {
  spec '- run: sh {file}'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 11"* && "$output" == *"files"* ]] || { echo "$output"; false; }
  spec '- files: tests/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 11"* && "$output" == *"run"* ]] || { echo "$output"; false; }
}

@test "a second run line and an unknown line are refused" {
  spec '- run: sh {file}
- run: bash {file}
- files: a'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"two run lines"* ]] || { echo "$output"; false; }
  spec '- run: sh {file}
- files: a
- other: b'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 15"* ]] || { echo "$output"; false; }
}

@test "sync removes the field when the section goes, and an older record without it opens as before" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  jq -e 'has("test_files")' .vbw/record.json > /dev/null
  spec ""
  "$VBW" spec sync > /dev/null
  jq -e 'has("test_files") | not' .vbw/record.json > /dev/null
  run "$VBW" status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "sync says when the form is added, changed or removed" {
  spec "$FORM"
  run "$VBW" spec sync
  [[ "$output" == *"added test file form"* ]] || { echo "$output"; false; }
  spec '- run: sh {file} x
- files: tests/t_*.sh'
  run "$VBW" spec sync
  [[ "$output" == *"changed test file form"* ]] || { echo "$output"; false; }
  spec ""
  run "$VBW" spec sync
  [[ "$output" == *"removed test file form"* ]] || { echo "$output"; false; }
}

@test "the form is part of the contract: editing it changes the hash and needs a new approval" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: spec"
  vbw_run show contract
  h1=$(printf '%s\n' "$output" | grep -oE '[0-9a-f]{12}' | head -1)
  spec '- run: sh {file} again
- files: tests/t_*.sh'
  "$VBW" spec sync > /dev/null
  vbw_run show contract
  h2=$(printf '%s\n' "$output" | grep -oE '[0-9a-f]{12}' | head -1)
  [ -n "$h1" ] && [ "$h1" != "$h2" ] || { echo "$h1 $h2"; false; }
}

@test "vbw approve grants the form like a command, and vbw show contract lists it among the commands that will run" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","c.sh"], files:["c.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["a.txt"], after:[], status:"planned"}]
    | del(.requirements[]?.rules) | .protected = ["c.sh"] | .schema = 4' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  : > c.sh
  git add -A && git commit -q -m "chore: project"
  vbw_run show contract
  [[ "$output" == *"test file form"* && "$output" == *"sh {file}"* && "$output" == *"tests/t_*.sh"* ]] || { echo "$output"; false; }
  run "$VBW" approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"approved test file form"* ]] || { echo "$output"; false; }
  jq -e 'any(.granted[]; .kind == "test_files")' "$(git rev-parse --git-common-dir)/vbw/consent.json" > /dev/null
}
