#!/usr/bin/env bats
# R202 (docs/proof.md, plugin/lib/reads.sh): the files a unit writes are
# remembered once per run, not as one copy of its read list per written file.
# The copy's written-file store (written.json) holds every run's read list once
# under "lists" (keyed by a run id) and, under "files", each written path with
# the ids of the runs that wrote it, so it grows with the number of runs plus
# the number of written names: a unit that writes 1,000 generated files adds
# 1,000 names and one list. A later unit that reads any of them still inherits
# the writer's list, and a file two runs wrote carries both lists, so reuse
# decisions do not change. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  mkdir -p src
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  git add -A && git commit -q -m "chore(test): files"
}

teardown() { vbw_teardown; }

lib() {
  vbw_kernel '. "$VBW_LIB/proofcopy.sh"; . "$VBW_LIB/reads.sh"; mkdir -p "$VBW_RUNTIME"
    '"$1"
}

@test "R202: a unit that writes 1,000 files adds 1,000 names and one list; the next unit that reads one inherits the writer's list" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"
    (cd "$c" && mkdir -p gen && cat src/a.txt > /dev/null && i=0 && while [ "$i" -lt 1000 ]; do printf "%s\n" "$i" > "gen/f$i"; i=$((i + 1)); done)
    reads_collect "$c" "$s" > /dev/null
    jq -c "[(.lists | length), (.files | length), ([.files[] | type] | unique), ([.files[] | length] | unique)]" "$s/written.json"
    reads_reset "$c" "$s"; (cd "$c" && cat gen/f500 > /dev/null)
    reads_collect "$c" "$s" | jq -cS "[.files, (.dirs | map(.path)), .git]"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local shape list
  shape=$(printf '%s\n' "$output" | sed -n 1p)
  list=$(printf '%s\n' "$output" | sed -n 2p)
  [ "$shape" = '[1,1000,["array"],[1]]' ] || { echo "written.json shape: $shape"; false; }
  [ "$list" = '[["src/a.txt"],[],false]' ] || { echo "the reader's list: $list"; false; }
}

@test "R202: a file two runs wrote carries both lists" {
  # Read through a pipe: a copy into a file can be a clone that reads nothing (the probe's case).
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && cat src/a.txt | cat > out.txt); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat src/b.txt >> out.txt); reads_collect "$c" "$s" > /dev/null
    jq -c "[(.lists | length), (.files[\"out.txt\"] | length)]" "$s/written.json"
    reads_reset "$c" "$s"; (cd "$c" && cat out.txt > /dev/null); reads_collect "$c" "$s" | jq -cS ".files"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = '[2,2]' ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = '["src/a.txt","src/b.txt"]' ] || { echo "$output"; false; }
}

@test "R202: inherited lists still pass on through a chain of runs" {
  run lib 'proofcopy_create_slots 1; c=$PROOF_COPY; s=$(dirname "$c")/reads
    reads_reset "$c" "$s"; (cd "$c" && cat src/c.txt | cat > one.out); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat one.out | cat > two.out); reads_collect "$c" "$s" > /dev/null
    reads_reset "$c" "$s"; (cd "$c" && cat two.out > /dev/null); reads_collect "$c" "$s" | jq -cS ".files"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = '["src/c.txt"]' ] || { echo "$output"; false; }
}
