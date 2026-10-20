#!/usr/bin/env bats
# R202 (tools/measure-proof-speed.sh, maintainers only; never shipped): the
# stand-in large project and the measurement. The tool generates a project of
# at least the asked size (--files N --folders N --units N; the defaults are
# 5,000 files, 500 folders and 200 units: half approved checks, half test files
# under an approved single-file form), where some units write hundreds of
# files into a git-ignored cache folder (.buildcache/, which the clean copy
# carries, as a compiler's build cache) and later units read them back. It runs
# vbw prove, then one small source change and vbw fix done, then vbw next
# --json, and prints one "name: value" line per figure: the two report lines of
# each command, wall-clock seconds, VBW's own work, the CPU seconds and count
# of jq processes, the size of the run store and of the written-file lists, how
# many units were reused and how many should have been (those whose read lists
# do not contain the changed file), and the time vbw next --json took.
# --generate DIR builds the stand-in at DIR in the caller's environment and
# stops. The fixture is generated: nothing of any real user project is in the
# tool or its output. L1: a small stand-in.

load helper

TOOL="$REPO_ROOT/tools/measure-proof-speed.sh"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# field NAME: the value of the "NAME: value" line of the last output.
field() { printf '%s\n' "$output" | sed -n "s/^$1: //p" | head -n 1; }

# numeric NAME: the field exists and is a number.
numeric() {
  local v
  v=$(field "$1")
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "field '$1' is not a number: '$v'"; echo "$output"; return 1; }
}

# folders DIR: how many distinct folders hold the tracked files of the project at DIR.
folders() { git -C "$1" ls-files | sed -n 's|/[^/]*$||p' | sort -u | wc -l | tr -d ' '; }

# units DIR: approved checks plus the test files the form matches.
units() {
  local checks files
  checks=$(jq '.checks | length' "$1/.vbw/record.json")
  files=$(git -C "$1" ls-files -- $(jq -r '.test_files.files[]' "$1/.vbw/record.json") | wc -l | tr -d ' ')
  echo $((checks + files))
}

@test "R202: --generate builds a stand-in of at least the asked size, approved, with cache-writing and cache-reading units" {
  run bash "$TOOL" --generate "$TEST_ROOT/gen" --files 120 --folders 24 --units 8 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(field fixture)" != "" ] || { echo "$output"; false; }
  [ "$(git -C "$TEST_ROOT/gen" ls-files | wc -l | tr -d ' ')" -ge 120 ] || { echo "fewer than 120 tracked files"; false; }
  [ "$(folders "$TEST_ROOT/gen")" -ge 24 ] || { echo "fewer than 24 folders: $(folders "$TEST_ROOT/gen")"; false; }
  [ "$(units "$TEST_ROOT/gen")" -eq 8 ] || { echo "units: $(units "$TEST_ROOT/gen")"; false; }
  grep -q 'buildcache' "$TEST_ROOT/gen/.gitignore" || { echo ".buildcache is not git-ignored"; cat "$TEST_ROOT/gen/.gitignore"; false; }
  # At least two unit scripts use the cache folder: one writes it, a later one reads it.
  [ "$(grep -l 'buildcache' "$TEST_ROOT/gen"/tests/*.sh | wc -l | tr -d ' ')" -ge 2 ] || { ls "$TEST_ROOT/gen/tests"; false; }
  [ -n "$(grep -l 'mkdir -p .buildcache' "$TEST_ROOT/gen"/tests/*.sh)" ] || { echo "no unit writes the cache"; false; }
  [ -n "$(grep -l 'cat .buildcache' "$TEST_ROOT/gen"/tests/*.sh)" ] || { echo "no unit reads the cache back"; false; }
  # Run every unit script in place once: the writers leave hundreds of cache files.
  (cd "$TEST_ROOT/gen" && for s in tests/*.sh; do sh "$s" > /dev/null 2>&1 || true; done)
  [ "$(find "$TEST_ROOT/gen/.buildcache" -type f | wc -l | tr -d ' ')" -ge 100 ] || { echo "the writers left fewer than 100 cache files"; false; }
  # The contract is approved: a proof can run at once.
  (cd "$TEST_ROOT/gen" && "$VBW" show contract > "$TEST_ROOT/contract.txt")
  grep -q 'APPROVED' "$TEST_ROOT/contract.txt" && ! grep -q 'NOT APPROVED' "$TEST_ROOT/contract.txt" || { cat "$TEST_ROOT/contract.txt"; false; }
}

@test "R202: the measurement prints every figure for a proof, a one-file fix round and vbw next" {
  VBW_MEASURE_DIR="$TEST_ROOT/measure" run bash "$TOOL" --files 120 --folders 24 --units 8 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f
  for f in files folders units 'prove wall seconds' 'prove own seconds' 'prove planning seconds' 'prove copies seconds' 'prove tracking seconds' \
    'prove saving seconds' 'prove record seconds' 'fix done wall seconds' 'fix done own minutes' reused 'reused expected' \
    'jq cpu seconds' 'jq processes' 'store bytes' 'written lists bytes' 'next seconds'; do
    numeric "$f"
  done
  [ "$(field files)" -ge 120 ] && [ "$(field folders)" -ge 24 ] && [ "$(field units)" -eq 8 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq "^prove: VBW's own work: [0-9]+\.[0-9] of [0-9]+\.[0-9] min$" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq '^prove: ran again: [0-9]+ of [0-9]+ units; top reasons: ' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq "^fix done: VBW's own work: [0-9]+\.[0-9] of [0-9]+\.[0-9] min$" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq '^fix done: ran again: [0-9]+ of [0-9]+ units; top reasons: ' || { echo "$output"; false; }
  [ "$(field 'jq processes')" -gt 0 ] && [ "$(field 'store bytes')" -gt 0 ] && [ "$(field 'written lists bytes')" -gt 0 ] || { echo "$output"; false; }
  # The first proof of a fresh clone runs every unit; the one-file change reuses the rest.
  [ "$(field 'reused expected')" -gt 0 ] || { echo "$output"; false; }
  # Those reused are exactly the units whose read lists do not hold the changed file.
  [ "$(field reused)" -eq "$(field 'reused expected')" ] || { echo "$output"; false; }
  # The clocks ran: wall seconds of each command and the time vbw next took are above zero.
  local c
  for c in 'prove wall seconds' 'fix done wall seconds' 'next seconds'; do
    awk -v v="$(field "$c")" 'BEGIN { exit !(v > 0) }' || { echo "$c is not above zero"; echo "$output"; false; }
  done
}

@test "R202: nothing of a real user project is in the tool or in what it generates" {
  run bash "$TOOL" --generate "$TEST_ROOT/gen" --files 60 --folders 12 --units 4 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! grep -rqi 'portfolium\|market_recorder' "$TOOL" "$TEST_ROOT/gen" --exclude-dir=.git
}
