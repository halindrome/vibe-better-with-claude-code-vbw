#!/usr/bin/env bats
# R202 (docs/proof.md, plugin/lib/reads.sh): collecting a unit's read list
# (reads_collect) spawns a fixed number of jq processes whatever the number of
# folders the unit listed (no process per listed folder), and its work grows
# with files plus folders, never files times folders. The list it gives is the
# one the earlier code gave: the files opened, each listed folder with the
# fingerprint of its listing (the SHA-256 of the compact JSON text
# ["<folder>",["<name>",...]]: the sorted, unique names of the tracked files
# and folders directly inside it; "." for the project root) and the git flag.
# L1: a counting stand-in jq on PATH; 300 folders of one file each.

load helper

setup() {
  vbw_setup
  vbw_git_project
  local i
  mkdir -p src
  printf 'a\n' > src/a.txt
  for ((i = 1; i <= 300; i++)); do
    mkdir -p "$(printf 'd%03d' "$i")"
    printf '%s\n' "$i" > "$(printf 'd%03d/f' "$i")"
  done
  git add -A && git commit -q -m "chore(test): folders"
  REAL_JQ=$(command -v jq)
  mkdir -p "$TEST_ROOT/standin"
  cat > "$TEST_ROOT/standin/jq" << SH
#!/bin/sh
printf 'x\n' >> "\$JQ_COUNT"
exec "$REAL_JQ" "\$@"
SH
  chmod +x "$TEST_ROOT/standin/jq"
  export JQ_COUNT="$TEST_ROOT/jq.count"
  : > "$JQ_COUNT"
  PATH="$TEST_ROOT/standin:$PATH"
  export PATH
}

teardown() { vbw_teardown; }

# lib SNIPPET: SNIPPET with the kernel, the clean copy and the reads libraries loaded (the stand-in jq is first on PATH).
lib() {
  vbw_kernel '. "$VBW_LIB/proofcopy.sh"; . "$VBW_LIB/reads.sh"; mkdir -p "$VBW_RUNTIME"
    count() { wc -l < "$JQ_COUNT" | tr -d " "; }
    '"$1"
}

# The 300 folders by name: a glob (d*) would list the root as well.
ALL_DIRS=$(seq -f 'd%03g' 1 300 | tr '\n' ' ')

# sha: SHA-256 of stdin, as vbw_sha256 computes it.
sha() {
  if command -v sha256sum > /dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1
}

@test "R202: collecting the read list spawns the same number of jq processes for 1 listed folder and for 300" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && ls d001 > /dev/null)
    : > "$JQ_COUNT"; reads_collect "$c" "$s" > /dev/null; one=$(count)
    reads_reset "$c" "$s"; (cd "$c" && ls '"$ALL_DIRS"' > /dev/null)
    : > "$JQ_COUNT"; reads_collect "$c" "$s" > /dev/null; many=$(count)
    echo "$one $many"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  read -r one many <<< "$output"
  [ "$one" -gt 0 ] || { echo "the stand-in jq counted nothing: $output"; false; }
  [ "$one" -eq "$many" ] || { echo "jq processes: $one for one folder, $many for 300"; false; }
}

@test "R202: the list for 300 listed folders is the one the earlier code gave: each folder with its listing's fingerprint, no file, no git" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && ls '"$ALL_DIRS"' > /dev/null)
    reads_collect "$c" "$s" | jq -c "[.files, .git, (.dirs | sort_by(.path) | map([.path, .fp]))]"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local i d expect='' fp
  for ((i = 1; i <= 300; i++)); do
    d=$(printf 'd%03d' "$i")
    fp=$(printf '%s' "[\"$d\",[\"f\"]]" | sha)
    expect="$expect,[\"$d\",\"$fp\"]"
  done
  [ "$output" = "[[],false,[${expect#,}]]" ] || { echo "got:  ${output:0:300}"; echo "want: [[],false,[${expect:1:280}..."; false; }
}

@test "R202: an opened file and the root listing keep their form: the root is \".\" and its fingerprint covers the names directly inside it" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && cat src/a.txt > /dev/null && ls > /dev/null)
    reads_collect "$c" "$s" | jq -c "[.files, .git, (.dirs | map([.path, .fp]))]"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local names='"README.md"' i fp
  for ((i = 1; i <= 300; i++)); do names="$names,\"$(printf 'd%03d' "$i")\""; done
  names="$names,\"src\""
  fp=$(printf '%s' "[\".\",[$names]]" | sha)
  [ "$output" = "[[\"src/a.txt\"],false,[[\".\",\"$fp\"]]]" ] || { echo "got: $output"; false; }
}
