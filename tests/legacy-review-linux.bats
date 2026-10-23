#!/usr/bin/env bats
# R68: the review of a VBW 1 folder works on Linux. GNU stat reads `stat -f` as
# "file system status" and succeeds with other output, so a file's time must
# come from the kernel's one portable reader, vbw_mtime. Found by CI (Linux,
# bash 5) on the 2.0.19 push: every untracked or non-git review gave up.
# A GNU-like stat on PATH reproduces Linux on macOS (L1).

load helper

setup() {
  vbw_setup
  vbw_git_project
  export GIT_CEILING_DIRECTORIES="$TEST_ROOT"
  # A stat that answers like GNU coreutils: -c %Y is the time; -f is file
  # system status, printed and successful whatever follows it.
  mkdir -p "$TEST_ROOT/gnu"
  cat > "$TEST_ROOT/gnu/stat" <<'EOS'
#!/bin/sh
case "$1" in
  -c) shift 2; exec /usr/bin/env perl -e 'print((lstat($_))[9], "\n") for @ARGV' "$@" ;;
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\n' "$3"; exit 0 ;;
esac
exit 1
EOS
  chmod +x "$TEST_ROOT/gnu/stat"
}

teardown() { vbw_teardown; }

untracked_folder() {
  mkdir -p .vbw-planning/phases/01-a src
  printf -- '---\nphase: 1\nfiles_modified:\n  - src/a.sh\n---\n# Plan\n' > .vbw-planning/phases/01-a/01-01-PLAN.md
  printf '# Done\n' > .vbw-planning/phases/01-a/01-01-SUMMARY.md
  printf 'a\n' > src/a.sh
}

@test "R68: with GNU stat, an untracked folder is reviewed: readable, last use from its newest file" {
  untracked_folder
  PATH="$TEST_ROOT/gnu:$PATH" run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.readable == true and (.last_used | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and .days_ago <= 1 and .finished == {done: 1, total: 1}' \
    || { echo "$output"; false; }
}

@test "R68: with GNU stat, the newest time under a folder is read in one pass, folders and links not counted" {
  mkdir -p "$TEST_ROOT/tree/a"
  printf x > "$TEST_ROOT/tree/a/old" && touch -t 200001010000 "$TEST_ROOT/tree/a/old"
  printf x > "$TEST_ROOT/tree/new" && touch -t 200101010000 "$TEST_ROOT/tree/new"
  ln -s /nonexistent "$TEST_ROOT/tree/gone" && touch -h -t 199901010000 "$TEST_ROOT/tree/gone"
  want=$(perl -e 'print((lstat($ARGV[0]))[9])' "$TEST_ROOT/tree/new")
  PATH="$TEST_ROOT/gnu:$PATH" run bash -c '. "$1/lib/core.sh"; vbw_mtime_newest "$2"' _ "$PLUGIN_ROOT" "$TEST_ROOT/tree"
  [ "$status" -eq 0 ] && [ "$output" = "$want" ] || { echo "$output (want $want)"; false; }
}

@test "R68: file times in the kernel come only from core.sh, whose readers try GNU stat first" {
  run grep -rnE '(^|[[:space:];|&({$])stat ' "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts"
  # vbw_mtime and vbw_mtime_newest in core.sh are the only readers; comments aside.
  [ -z "$(printf '%s\n' "$output" | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v '/lib/core.sh:')" ] || { echo "$output"; false; }
}
