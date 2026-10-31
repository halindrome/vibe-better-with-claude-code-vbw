#!/usr/bin/env bats
# R109 (L1): vbw init's notice about detected project commands points to the
# approval menu and never tells the user to type /vbw:approve (R83).

load helper

setup() {
  vbw_setup
  vbw_git_project
  printf '{"scripts":{"test":"node test.js"}}\n' > package.json
  git add package.json && git commit -q -m "chore: package"
}
teardown() { vbw_teardown; }

@test "R109: the detected-commands notice names the approval menu, not /vbw:approve" {
  run "$VBW" init < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Detected project commands"* ]] || { echo "$output"; false; }
  [[ "$output" != *"/vbw:approve"* ]] || { echo "$output"; false; }
  [[ "$output" == *"approval menu"* ]] || { echo "$output"; false; }
}

# R225 (#693): vbw init says once which branch VBW commits its plan of record and the
# checks it plans to, naming the branch checked out (or the commit, with no branch);
# nothing refuses, asks or adds a setting.

# branch_lines: init's lines that name a branch.
branch_lines() { printf '%s\n' "$output" | grep -E 'branch' || true; }

@test "R225: vbw init states exactly once that VBW commits its plan of record and its checks to the branch checked out, naming it; it still succeeds on main and vbw config knows no branch key" {
  run "$VBW" init < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(branch_lines | wc -l | tr -d ' ')" -eq 1 ] || { echo "lines naming a branch:"; branch_lines; echo "$output"; false; }
  local l
  l=$(branch_lines)
  [[ "$l" == *commit* && "$l" == *record* && "$l" == *check* && "$l" =~ (^|[^a-zA-Z0-9_-])main($|[^a-zA-Z0-9_-]) ]] || { echo "the line does not say VBW commits its record and checks to the branch main: $l"; false; }
  run "$VBW" config < /dev/null
  [[ "$output" != *branch* ]] || { echo "vbw config has a branch setting:"; echo "$output"; false; }
}

@test "R225: init on a branch other than main names that branch" {
  git checkout -q -b feature/xyz
  run "$VBW" init < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(branch_lines)" == *"feature/xyz"* ]] || { echo "the line does not name feature/xyz:"; echo "$output"; false; }
}

@test "R225: with no branch checked out, init's line says so and names the commit" {
  git checkout -q --detach
  run "$VBW" init < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(branch_lines | wc -l | tr -d ' ')" -eq 1 ] || { echo "lines naming a branch:"; branch_lines; echo "$output"; false; }
  local l
  l=$(branch_lines)
  [[ "$l" == *detached* && "$l" == *"$(git rev-parse HEAD | cut -c1-12)"* ]] || { echo "the line does not say HEAD is detached and name the commit: $l"; false; }
}

@test "R225 docs: docs/diagnostics.md lists doctor's branch line, and docs/record.md says VBW commits to the branch checked out" {
  grep -qiE 'branch' "$REPO_ROOT/docs/diagnostics.md" || { echo "docs/diagnostics.md does not list the branch line"; false; }
  tr '\n' ' ' < "$REPO_ROOT/docs/record.md" | tr -s ' ' | grep -qiE 'commits? [^.]*branch (that is )?checked out|checked-out branch' || { echo "docs/record.md does not say VBW commits to the branch checked out"; false; }
}
