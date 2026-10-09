#!/usr/bin/env bats
# R146 (docs/triage.md): vbw todo add, sort, done and drop commit the record
# when they change it, through VBW's one commit path for its own files
# (record_commit), so the project is left clean. The user's staged files stay
# staged and out of the commit, and so do files the user changed but did not
# stage. vbw todo list, a command that changes nothing and a refused command
# commit nothing. A commit that cannot be made (no git identity, a failing
# hook) keeps the change, succeeds, and warns with git's own reason. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  "$VBW" todo add "Dark mode" > /dev/null
  git add .vbw && git commit -q -m "chore(vbw): init"
}

teardown() { vbw_teardown; }

# clean: the record has no change git has not committed.
clean() { [ -z "$(git status --porcelain -- .vbw/record.json)" ] || { git status --porcelain; return 1; }; }
subject() { git log -1 --format=%s; }
commits() { git rev-list --count HEAD; }

@test "R146: vbw todo add commits the record and names the new item" {
  vbw_run todo add "Gift cards"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  clean
  [[ "$(subject)" == "chore(vbw): "* ]] || { subject; false; }
  [[ "$(subject)" == *T2* ]] || { subject; false; }
  git show --name-only --format= HEAD | grep -qx .vbw/record.json
  [ "$(git show HEAD:.vbw/record.json | jq -r '.todos[-1].text')" = "Gift cards" ]
}

@test "R146: vbw todo add with --sort and --size commits the record and names the new item" {
  vbw_run todo add --sort next --size small "CSV export"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  clean
  [[ "$(subject)" == *T2* ]] || { subject; false; }
  git show HEAD:.vbw/record.json | jq -e '.todos[-1] | .sort == "next" and .size == "small"'
}

@test "R146: vbw todo sort commits the record, naming the item and its new sort and size" {
  vbw_run todo sort T1 later large
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  clean
  [[ "$(subject)" == *T1* && "$(subject)" == *later* && "$(subject)" == *large* ]] || { subject; false; }
}

@test "R146: vbw todo done and vbw todo drop commit the record, naming the item and what happened to it" {
  "$VBW" todo add "Gift cards" > /dev/null
  vbw_run todo "done" T1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  clean
  [[ "$(subject)" == *T1* && "$(subject)" == *done* ]] || { subject; false; }
  vbw_run todo drop T2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  clean
  [[ "$(subject)" == *T2* && "$(subject)" == *dropped* ]] || { subject; false; }
}

@test "R146: files the user staged stay staged, unchanged, and are not part of VBW's commit" {
  printf 'mine\n' > notes.txt
  git add notes.txt
  printf 'seed\nmine too\n' > README.md
  git add README.md
  local before
  before=$(git diff --cached | git hash-object --stdin)
  vbw_run todo add "Gift cards"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git diff --cached --name-only | sort | tr '\n' ' ')" = "README.md notes.txt " ] || { git diff --cached --name-only; false; }
  [ "$(git diff --cached | git hash-object --stdin)" = "$before" ]
  [ "$(git show --name-only --format= HEAD)" = ".vbw/record.json" ] || { git show --name-only --format= HEAD; false; }
}

@test "R146: files the user changed but did not stage are not part of VBW's commit and stay changed" {
  printf 'seed\nedited\n' > README.md
  printf '# Notes\n\nmy own edit\n' >> .vbw/spec.md
  vbw_run todo add "Gift cards"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = ".vbw/record.json" ] || { git show --name-only --format= HEAD; false; }
  git status --porcelain | grep -q ' README.md$'
  git status --porcelain | grep -q ' .vbw/spec.md$'
}

@test "R146: vbw todo list never commits" {
  local n
  n=$(commits)
  vbw_run todo list
  [ "$status" -eq 0 ]
  vbw_run todo
  [ "$status" -eq 0 ]
  [ "$(commits)" = "$n" ]
}

@test "R146: a command that changes nothing makes no commit" {
  "$VBW" todo sort T1 next small > /dev/null
  local n
  n=$(commits)
  vbw_run todo sort T1 next small
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(commits)" = "$n" ]
  clean
}

@test "R146: a refused command changes nothing and commits nothing" {
  "$VBW" todo "done" T1 > /dev/null
  local n before args
  n=$(commits)
  before=$(cksum < .vbw/record.json)
  for args in "done T9" "drop T9" "sort T9 next small" "sort T1 next small" "sort T1 soon small" "add" "frobnicate"; do
    # shellcheck disable=SC2086 # each case is several arguments on purpose
    run "$VBW" todo $args < /dev/null
    [ "$status" -ne 0 ] || { echo "accepted: vbw todo $args"; false; }
  done
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  [ "$(commits)" = "$n" ]
}

@test "R146: when a git hook refuses the commit, the item is kept, the command succeeds and git's reason is shown" {
  local hook
  hook="$(git rev-parse --git-path hooks)/pre-commit"
  mkdir -p "$(dirname "$hook")"
  printf '#!/bin/sh\necho "refused by the project hook: lint failed" >&2\nexit 1\n' > "$hook"
  chmod +x "$hook"
  local n
  n=$(commits)
  vbw_run todo add "Gift cards"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"lint failed"* ]] || { echo "$output"; false; }
  [[ "$output" == *"commit"*"yourself"* ]] || { echo "$output"; false; }
  [ "$(commits)" = "$n" ]
  jq -e '.todos[-1].text == "Gift cards"' .vbw/record.json
}

@test "R146: with no git identity, the item is kept, the command succeeds and git's reason is shown" {
  git config --global --unset user.email
  git config --global --unset user.name
  git config --global user.useConfigOnly true
  local n
  n=$(commits)
  vbw_run todo add "Gift cards"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"warning"* && "$output" == *"yourself"* ]] || { echo "$output"; false; }
  [[ "$output" == *"identity"* || "$output" == *"user.email"* || "$output" == *"Please tell me who you are"* ]] || { echo "$output"; false; }
  [ "$(commits)" = "$n" ]
  jq -e '.todos[-1].text == "Gift cards"' .vbw/record.json
}

@test "R146: the commit goes through record_commit, VBW's one commit path for its own files" {
  grep -q 'record_commit' "$PLUGIN_ROOT/lib/cmd-todo.sh"
  run grep -nE 'git[[:space:]]+(commit|add)' "$PLUGIN_ROOT/lib/cmd-todo.sh"
  [ -z "$output" ] || { echo "$output"; false; }
}
