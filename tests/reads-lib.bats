#!/usr/bin/env bats
# R166 (docs/proof.md): the library that records what each run opens and lists
# in its own clean copy (plugin/lib/reads.sh, slots in plugin/lib/proofcopy.sh).
# Access time (atime) is set back with touch -a, the run reads, and what moved
# forward was read. Every snippet runs in one process: the copies are removed
# when it exits. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  mkdir -p src docs
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'doc\n' > docs/guide.txt
  printf 'ignored\n' > .gitignore
  printf 'env\n' > ignored
  printf 'node_modules/\n' >> .gitignore
  git add .gitignore src docs
  git commit -q -m "chore(test): files"
}

teardown() { vbw_teardown; }

# lib SNIPPET: SNIPPET with the kernel, the clean copy and the reads libraries loaded.
lib() {
  vbw_kernel '. "$VBW_LIB/proofcopy.sh"; . "$VBW_LIB/reads.sh"; mkdir -p "$VBW_RUNTIME"
    at() { stat -c %X "$1" 2> /dev/null || stat -f %a "$1"; }
    '"$1"
}

@test "R166: the probe passes on a file system that records reads" {
  run lib 'reads_probe "$VBW_RUNTIME"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R166: the probe leaves nothing behind" {
  run lib 'mkdir -p "$VBW_RUNTIME/p"; reads_probe "$VBW_RUNTIME/p"; ls -A "$VBW_RUNTIME/p" | wc -l'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d ' ')" = 0 ]
}

@test "R166: the probe reports a file system that does not record reads (access time never moves)" {
  mkdir -p "$TEST_ROOT/stub"
  # A find that never sees an access time past the yardstick: nothing reads as read.
  printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/stub/find"
  chmod +x "$TEST_ROOT/stub/find"
  run lib 'PATH="'"$TEST_ROOT"'/stub:$PATH"; reads_probe "$VBW_RUNTIME"'
  [ "$status" -ne 0 ]
  [[ "$output" == *'this file system does not record which files are read'* ]]
}

@test "R166: the probe reports a file system where the access time cannot be set back" {
  mkdir -p "$TEST_ROOT/stub"
  printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/stub/touch"
  chmod +x "$TEST_ROOT/stub/touch"
  run lib 'PATH="'"$TEST_ROOT"'/stub:$PATH"; reads_probe "$VBW_RUNTIME"'
  [ "$status" -ne 0 ]
  [[ "$output" == *'this file system does not record which files are read'* ]]
}

@test "R166: the probe reports a folder it cannot write to" {
  mkdir -p "$TEST_ROOT/nowhere"
  chmod 500 "$TEST_ROOT/nowhere"
  run lib 'reads_probe "'"$TEST_ROOT"'/nowhere"'
  chmod 700 "$TEST_ROOT/nowhere"
  [ "$status" -ne 0 ]
  [[ "$output" == *'this file system does not record which files are read'* ]]
}

@test "R166: one clean copy per slot, as many as check_jobs allows and the work needs" {
  "$VBW" init > /dev/null
  "$VBW" config set check_jobs 3 > /dev/null
  run lib 'proofcopy_slots 10; proofcopy_slots 2; proofcopy_slots 0'
  [ "$status" -eq 0 ]
  [ "$output" = $'3\n2\n1' ]
}

@test "R166: each slot copy is made like the single copy and all are removed on exit" {
  run lib 'proofcopy_create_slots 3
    [ "${#PROOF_COPIES[@]}" -eq 3 ] || exit 1
    for c in "${PROOF_COPIES[@]}"; do
      [ -f "$c/src/a.txt" ] && [ -f "$c/ignored" ] && [ ! -e "$c/.vbw" ] || exit 2
      [ "$(git -C "$c" rev-parse HEAD)" = "$(git rev-parse HEAD)" ] || exit 3
      printf "%s\n" "$c"
    done | sort -u | wc -l
    printf "%s\n" "${PROOF_COPIES[@]}" > "'"$TEST_ROOT"'/copies"'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d ' ')" = 3 ]
  while IFS= read -r c; do [ ! -e "$c" ]; done < "$TEST_ROOT/copies"
  git worktree prune
  [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]
}

@test "R166: one slot is what proofcopy_create makes, and proofcopy_remove removes every slot" {
  run lib 'proofcopy_create_slots 2; d1=$(dirname "${PROOF_COPIES[0]}"); d2=$(dirname "${PROOF_COPIES[1]}")
    proofcopy_remove; [ ! -e "$d1" ] && [ ! -e "$d2" ] && [ -z "$PROOF_COPY" ] && printf gone'
  [ "$status" -eq 0 ]
  [ "$output" = gone ]
}

@test "R166: the reset sets back the access time of every tracked file and folder, and of the copy's .git file" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    [ -f "$c/.git" ] || { echo "the copy has no .git file"; exit 3; }
    cat "$c/src/a.txt" > /dev/null; ls "$c/src" > /dev/null; git -C "$c" ls-files > /dev/null; git -C "$c" show HEAD:src/a.txt > /dev/null
    reads_reset "$c" "$s" || exit 1
    for p in "$c/src/a.txt" "$c/src/b.txt" "$c/docs/guide.txt" "$c/.gitignore" "$c/src" "$c/docs" "$c" "$c/.git"; do
      [ "$(at "$p")" -lt 1000000000 ] || { echo "not set back: $p"; exit 2; }
    done
    [ "$(at "$c/ignored")" -gt 1000000000 ] && echo ok'
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "R166: a run's reads are collected: files it opened, folders it listed with a fingerprint, no git" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s" || exit 1
    (cd "$c" && cat src/a.txt > /dev/null && ls docs > /dev/null)
    reads_collect "$c" "$s" | jq -cS "{files, git, dirs: [.dirs[] | {path, fp: (.fp | length)}]}"'
  [ "$status" -eq 0 ]
  [ "$output" = '{"dirs":[{"fp":64,"path":"docs"}],"files":["src/a.txt"],"git":false}' ]
}

@test "R166: the next run starts from a clean slate" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && cat src/a.txt > /dev/null && ls src > /dev/null); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat src/b.txt > /dev/null)
    reads_collect "$c" "$s" | jq -c "[.files, (.dirs | map(.path))]"'
  [ "$status" -eq 0 ]
  [ "$output" = '[["src/b.txt"],[]]' ]
}

@test "R166: a run that reads nothing lists nothing" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; reads_collect "$c" "$s" | jq -c .'
  [ "$status" -eq 0 ]
  [ "$output" = '{"files":[],"dirs":[],"git":false}' ]
}

@test "R166: reading the project through git sets the git flag" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && git show HEAD:src/b.txt > /dev/null); reads_collect "$c" "$s" | jq -c .git
    reads_reset "$c" "$s"; (cd "$c" && git ls-files > /dev/null); reads_collect "$c" "$s" | jq -c .git
    reads_reset "$c" "$s"; (cd "$c" && git status --short > /dev/null); reads_collect "$c" "$s" | jq -c .git'
  [ "$status" -eq 0 ]
  [ "$output" = $'true\ntrue\ntrue' ]
}

@test "R166: git run in the user's checkout, or from another copy, while a run runs does not set the git flag" {
  # The copy is a worktree of the user's repository: git worktree list, git branch, a new
  # worktree (another proof making its copy), gc and fetch there read its HEAD and index,
  # but none of them opens the copy's own .git file, which every git command run inside
  # the copy reads first.
  run lib 'proofcopy_create_slots 2; c=${PROOF_COPIES[0]}; o=${PROOF_COPIES[1]}; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"
    (cd "$c" && cat src/a.txt > /dev/null)
    (cd "$VBW_ROOT" && git worktree list --porcelain && git branch --list && git branch -av \
      && git worktree add -q --detach "$VBW_RUNTIME/other" HEAD && git worktree remove --force "$VBW_RUNTIME/other" \
      && git gc --quiet && git fetch -q . HEAD:refs/heads/side) > /dev/null 2>&1 || { echo "a git command failed"; exit 1; }
    (cd "$o" && git worktree list && git branch && git status --short) > /dev/null 2>&1 || exit 1
    reads_collect "$c" "$s" | jq -c "[.files, .git]"
    reads_reset "$c" "$s"; (cd "$c/src" && git log -1 > /dev/null); reads_collect "$c" "$s" | jq -c .git'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = $'[["src/a.txt"],false]\ntrue' ] || { echo "$output"; false; }
}

@test "R166: a folder's fingerprint follows the names of its tracked files, not their content" {
  run lib 'proofcopy_create_slots 1; c1=$PROOF_COPY; s1=$(dirname "$c1")/reads
    printf "changed\n" > "$VBW_ROOT/src/a.txt"; git -C "$VBW_ROOT" commit -q -am "chore(test): content"
    printf "new\n" > "$VBW_ROOT/src/c.txt"; git -C "$VBW_ROOT" add src/c.txt; git -C "$VBW_ROOT" commit -q -m "chore(test): name"
    PROOF_COPIES=(); proofcopy_create_slots 1; c2=$PROOF_COPY; s2=$(dirname "$c2")/reads
    fp() { reads_reset "$1" "$2"; (cd "$1" && ls src docs > /dev/null); reads_collect "$1" "$2" | jq -r --arg p "$3" ".dirs[] | select(.path == \$p) | .fp"; }
    [ -n "$(fp "$c1" "$s1" src)" ] || exit 1
    [ "$(fp "$c1" "$s1" docs)" = "$(fp "$c2" "$s2" docs)" ] || exit 2
    [ "$(fp "$c1" "$s1" src)" != "$(fp "$c2" "$s2" src)" ] || exit 3
    echo ok'
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "R166: a file a run writes remembers that run's read list, and a later run that reads it inherits it" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && mkdir -p gen && cat src/a.txt > gen/out.txt && ls docs > /dev/null && git show HEAD:src/b.txt > /dev/null); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat gen/out.txt > /dev/null); reads_collect "$c" "$s" | jq -cS "[.files, (.dirs | map(.path)), .git]"
    reads_reset "$c" "$s"; (cd "$c" && cat src/b.txt > /dev/null); reads_collect "$c" "$s" | jq -cS "[.files, (.dirs | map(.path)), .git]"'
  [ "$status" -eq 0 ]
  [ "$output" = $'[["src/a.txt"],["docs"],true]\n[["src/b.txt"],[],false]' ]
}

@test "R166: build output an earlier run wrote is gone before the next run, so no read list passes through it" {
  # A Python run writes __pycache__ and .pytest_cache files that the next run in the same
  # copy would read: each next run starts without them, as in a fresh copy.
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"
    (cd "$c" && cat src/a.txt > /dev/null && mkdir -p src/__pycache__ .pytest_cache/v/cache && printf "pyc\n" > src/__pycache__/a.pyc \
      && printf "ids\n" > .pytest_cache/v/cache/nodeids && ls docs > /dev/null && git show HEAD:src/b.txt > /dev/null)
    reads_collect "$c" "$s" | jq -c "[.files, (.dirs | map(.path)), .git]"
    reads_reset "$c" "$s"
    [ ! -e "$c/src/__pycache__" ] && [ ! -e "$c/.pytest_cache" ] && [ -f "$c/src/a.txt" ] || { echo "build output left in the copy"; exit 1; }
    jq -c "[(.lists | length), (.files | length)]" "$s/written.json"
    (cd "$c" && { cat src/__pycache__/a.pyc .pytest_cache/v/cache/nodeids; cat src/b.txt; } > /dev/null 2>&1)
    reads_collect "$c" "$s" | jq -c "[.files, (.dirs | map(.path)), .git]"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = $'[["src/a.txt"],["docs"],true]\n[0,0]\n[["src/b.txt"],[],false]' ]
}

@test "R166: a file in a build folder that the copy was made with stays, and still passes on the list of a run that changed it" {
  # bin/tool.sh is tracked, node_modules/pkg/dist/x.js came in with an ignored folder: neither
  # is build output a run made. A file a run adds beside x.js is, and goes; its folder stays.
  mkdir -p bin node_modules/pkg/dist
  printf 'tool\n' > bin/tool.sh
  printf 'x\n' > node_modules/pkg/dist/x.js
  git add bin && git commit -q -m "chore(test): tool"
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"
    (cd "$c" && cat src/a.txt > /dev/null && printf "a\n" >> bin/tool.sh && printf "a\n" >> node_modules/pkg/dist/x.js && printf "a\n" > node_modules/pkg/dist/new.js)
    reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"
    [ -f "$c/bin/tool.sh" ] && [ -f "$c/node_modules/pkg/dist/x.js" ] && [ ! -e "$c/node_modules/pkg/dist/new.js" ] || { ls -R "$c/bin" "$c/node_modules"; exit 1; }
    (cd "$c" && cat node_modules/pkg/dist/x.js > /dev/null); reads_collect "$c" "$s" | jq -c .files
    reads_reset "$c" "$s"; (cd "$c" && cat bin/tool.sh > /dev/null); reads_collect "$c" "$s" | jq -c .files'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = $'["src/a.txt"]\n["bin/tool.sh","src/a.txt"]' ] || { echo "$output"; false; }
}

@test "R166: inherited lists pass on through a chain of runs" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && cat src/a.txt > one.out); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat one.out > two.out); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat two.out > /dev/null); reads_collect "$c" "$s" | jq -cS ".files"'
  [ "$status" -eq 0 ]
  [ "$output" = '["src/a.txt"]' ]
}

@test "R166: the library is bash 3.2 clean and writes nothing outside the slot" {
  ! grep -nE 'mapfile|readarray|declare -A|eval |bash -c' "$PLUGIN_ROOT/lib/reads.sh" || false
  ! grep -n '/tmp' "$PLUGIN_ROOT/lib/reads.sh"
}

@test "R166: a run's mark is the moment it names, also in the hour a clock change repeats, under any time zone" {
  # 2026-10-25 00:30 and 01:30 UTC are both 02:30 in Zurich: a local stamp names only one of them.
  run lib 'mt() { stat -c %Y "$1" 2> /dev/null || stat -f %m "$1"; }
    export TZ=Europe/Zurich
    for e in 1792888200 1792891800; do
      : > "$TEST_ROOT/m"
      reads_mark "$TEST_ROOT/m" 0 "$e" || exit 1
      [ "$(mt "$TEST_ROOT/m")" = "$e" ] || { echo "$e marked as $(mt "$TEST_ROOT/m")"; exit 1; }
      reads_mark "$TEST_ROOT/m" 5 "$e" || exit 1
      [ "$(mt "$TEST_ROOT/m")" = "$((e - 5))" ] || { echo "$e - 5 marked as $(mt "$TEST_ROOT/m")"; exit 1; }
    done'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
