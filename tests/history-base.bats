#!/usr/bin/env bats
# The record's own history (docs/proof.md, "Whose commits VBW judges"): the
# readers of VBW's trailers walk only the commits after the newest commit that
# added .vbw/record.json; a project whose record was never committed walks its
# whole history. L1: lib/history.sh on fixture repositories.

load helper

setup() { vbw_setup; vbw_git_project; }
teardown() { vbw_teardown; }

# hist: the commits the record's own history covers, oldest first, by subject.
hist() {
  bash -c 'VBW_ROOT=$PWD; . "$1/lib/history.sh"; history_args; git log --reverse --format=%s "${HISTORY_ARGS[@]}"' _ "$PLUGIN_ROOT"
}

commit_file() { printf '%s\n' "$2" > "$1"; git add "$1"; git commit -q -m "$3"; }

@test "history: without a committed record the whole history is the record's" {
  commit_file a.txt a "old: one"
  commit_file b.txt b "old: two"
  run hist
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"old: one"*"old: two"* ]] || { echo "$output"; false; }
}

@test "history: commits older than the record's first commit are not the record's" {
  commit_file a.txt a "old: one"
  mkdir -p .vbw && printf '{}\n' > .vbw/record.json && git add .vbw/record.json && git commit -q -m "chore(vbw): approve contract"
  commit_file b.txt b "new: two"
  run hist
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"old: one"* ]] || { echo "$output"; false; }
  [[ "$output" == *"chore(vbw): approve contract"*"new: two"* ]] || { echo "$output"; false; }
}

@test "history: a record removed and made again starts a new history" {
  mkdir -p .vbw && printf '{}\n' > .vbw/record.json && git add .vbw/record.json && git commit -q -m "first record"
  commit_file a.txt a "first roadmap: one"
  git rm -q .vbw/record.json && git commit -q -m "record removed"
  mkdir -p .vbw && printf '{}\n' > .vbw/record.json && git add .vbw/record.json && git commit -q -m "second record"
  commit_file b.txt b "second roadmap: two"
  run hist
  [[ "$output" != *"first roadmap: one"* && "$output" == *"second record"*"second roadmap: two"* ]] || { echo "$output"; false; }
}

@test "history: a record born in the very first commit covers everything" {
  rm -rf .git && git init -q
  mkdir -p .vbw && printf '{}\n' > .vbw/record.json
  git add .vbw/record.json && git commit -q -m "root with record"
  commit_file a.txt a "next"
  run hist
  [ "$status" -eq 0 ] && [[ "$output" == *"root with record"*"next"* ]] || { echo "$output"; false; }
}
