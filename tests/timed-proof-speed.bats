#!/usr/bin/env bats
# R202 (docs/proof.md, D245): the time of VBW's own work in a proof, measured in
# the release run (tests/timed-*.bats), never in vbw prove. Builds the scaled-down
# stand-in with tools/measure-proof-speed.sh --generate, proves it, and reads
# evidence.own from the record: read tracking per unit that ran and planning
# stay under their limits. A machine too busy to measure is reported and skipped,
# like tools/bench-hooks.sh does.

load helper

TRACKING_PER_UNIT_LIMIT=1
PLANNING_LIMIT=5
STARTUP_LIMIT_MS=20
RUNS=20

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# startup_ms: the mean CPU ms of RUNS runs of sh -c 'jq -n empty' (bash's times).
startup_ms() {
  local i log="$TEST_ROOT/times.log"
  : > "$log"
  for ((i = 0; i < RUNS; i++)); do
    times >> "$log"
    sh -c 'jq -n empty' < /dev/null > /dev/null 2>&1 || true
    times >> "$log"
  done
  awk -v runs="$RUNS" '
    function sec(s) { sub(/s$/, "", s); split(s, p, "m"); return p[1] * 60 + p[2] }
    NR % 2 == 0 { t[++n] = sec($1) + sec($2) }
    END { for (k = 1; k + 1 <= n; k += 2) sum += t[k + 1] - t[k]
          printf "%.1f\n", sum * 1000 / runs }' "$log"
}

@test "R202: read tracking stays under 1 s per unit and planning under 5 s on the scaled-down stand-in" {
  local startup
  startup=$(startup_ms)
  if awk -v a="$startup" -v b="$STARTUP_LIMIT_MS" 'BEGIN { exit !(a + 0 > b + 0) }'; then
    echo "machine too busy to measure: sh and jq startup takes $startup ms CPU per call, above $STARTUP_LIMIT_MS ms; nothing judged"
    skip "machine too busy to measure"
  fi
  local proj="$TEST_ROOT/stand-in" out ran tracking planning
  bash "$REPO_ROOT/tools/measure-proof-speed.sh" --generate "$proj" --files 2000 --folders 300 --units 40 > /dev/null
  cd "$proj"
  out=$("$VBW" prove < /dev/null 2>&1) || { echo "$out"; false; }
  ran=$(printf '%s\n' "$out" | sed -nE 's/^ran again: ([0-9]+) of [0-9]+ units.*/\1/p' | head -n 1)
  [ -n "$ran" ] && [ "$ran" -gt 0 ] || { echo "no 'ran again' line with units that ran:"; echo "$out"; false; }
  tracking=$(jq '.evidence.own.tracking' .vbw/record.json)
  planning=$(jq '.evidence.own.planning' .vbw/record.json)
  echo "read tracking $tracking s over $ran units, planning $planning s"
  awk -v t="$tracking" -v n="$ran" -v l="$TRACKING_PER_UNIT_LIMIT" 'BEGIN { exit !(t / n <= l) }' \
    || { echo "read tracking $tracking s over $ran units exceeds $TRACKING_PER_UNIT_LIMIT s per unit"; false; }
  awk -v p="$planning" -v l="$PLANNING_LIMIT" 'BEGIN { exit !(p + 0 <= l) }' \
    || { echo "planning $planning s exceeds $PLANNING_LIMIT s"; false; }
}

# Remaining cost (M42 after decision): collecting a read list rebuilt the folder-to-names map of
# every tracked path on every unit (0.34 s of 0.67 s on 5,206 files). The map never changes in a
# copy, so it is built once at the first reset and only looked up by a collection: a map put in
# the state after the first reset is the one the fingerprints are taken from.
@test "R202: a collection looks the folder names up in the map the first reset built, it does not rebuild it" {
  local copy="$TEST_ROOT/copy" st="$TEST_ROOT/state" want got
  mkdir -p "$copy/sub"
  git -C "$copy" init -q
  printf 'a\n' > "$copy/sub/a.txt"
  printf 'b\n' > "$copy/top.txt"
  git -C "$copy" add -A
  git -C "$copy" commit -q -m "feat: files"
  # shellcheck disable=SC1091
  source "$PLUGIN_ROOT/lib/reads.sh"
  reads_reset "$copy" "$st"
  [ -s "$st/kids.json" ] || { echo "the first reset left no folder map in the state"; false; }
  printf '{"kids":{"":["poison"]},"files":{"top.txt":true}}\n' > "$st/kids.json"
  ls "$copy" > /dev/null
  got=$(reads_collect "$copy" "$st" | jq -r '.dirs[] | select(.path == ".") | .fp')
  want=$(printf '%s' '[".",["poison"]]' | { if command -v sha256sum > /dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -d' ' -f1)
  [ "$got" = "$want" ] || { echo "fingerprint $got, wanted $want"; false; }
}

# Remaining cost (M42 after decision): every reset set the access time of all tracked files and
# folders back (0.13 to 0.27 s on 5,206 files), though a run moves only the ones it read. The
# collection leaves the paths that moved; the next reset sets back those and no others. A file
# nothing read keeps the time the earlier reset gave it (here a later one, marked by hand).
@test "R202: a reset after a collection sets back only the paths that moved, not every tracked file" {
  local copy="$TEST_ROOT/copy" st="$TEST_ROOT/state" marker="$TEST_ROOT/marker"
  mkdir -p "$copy/sub"
  git -C "$copy" init -q
  printf 'a\n' > "$copy/sub/a.txt"
  printf 'b\n' > "$copy/top.txt"
  git -C "$copy" add -A
  git -C "$copy" commit -q -m "feat: files"
  # shellcheck disable=SC1091
  source "$PLUGIN_ROOT/lib/reads.sh"
  : > "$marker" && touch -t 200001010030 "$marker"
  reads_reset "$copy" "$st"
  cat "$copy/sub/a.txt" > /dev/null
  # Nothing reads top.txt; its time is moved by hand to one a bit later than the set-back time (still before the yardstick).
  touch -a -t 200001010100 "$copy/top.txt"
  reads_collect "$copy" "$st" > "$TEST_ROOT/first.json"
  jq -e '.files == ["sub/a.txt"]' "$TEST_ROOT/first.json" > /dev/null || { cat "$TEST_ROOT/first.json"; false; }
  reads_reset "$copy" "$st"
  [ -z "$(find "$copy/sub/a.txt" -maxdepth 0 -anewer "$marker")" ] || { echo "the file the run read was not set back"; false; }
  [ -n "$(find "$copy/top.txt" -maxdepth 0 -anewer "$marker")" ] || { echo "a file nothing read was set back again"; false; }
  # The second run reads nothing: its list is empty, whatever the first one read.
  reads_collect "$copy" "$st" | jq -e '.files == []' > /dev/null
}

# Remaining cost (M42 after decision): a collection asked one find per list (every tracked file,
# every tracked folder, every written file), each one statting thousands of paths (0.09 s on 5,206
# files). One walk of the copy finds every path whose access time moved and a single jq sorts them
# into files read, folders listed and written files opened: three finds a collection, whatever the
# number of tracked paths (the git flag, the walk, the files the run wrote).
@test "R202: a collection walks the copy once for what moved: three finds, not one per list" {
  local copy="$TEST_ROOT/copy" st="$TEST_ROOT/state" real log="$TEST_ROOT/finds" n
  mkdir -p "$copy/sub" "$TEST_ROOT/shim"
  git -C "$copy" init -q
  printf 'a\n' > "$copy/sub/a.txt"
  printf 'b\n' > "$copy/top.txt"
  git -C "$copy" add -A
  git -C "$copy" commit -q -m "feat: files"
  real=$(command -v find)
  printf '#!/bin/sh\necho run >> "%s"\nexec "%s" "$@"\n' "$log" "$real" > "$TEST_ROOT/shim/find"
  chmod +x "$TEST_ROOT/shim/find"
  # shellcheck disable=SC1091
  source "$PLUGIN_ROOT/lib/reads.sh"
  reads_reset "$copy" "$st"
  # A run that read a file, listed a folder and wrote one that a later run reads.
  cat "$copy/sub/a.txt" > /dev/null
  ls "$copy/sub" > /dev/null
  printf 'w\n' > "$copy/w.txt"
  : > "$log"
  PATH="$TEST_ROOT/shim:$PATH" reads_collect "$copy" "$st" > "$TEST_ROOT/first.json"
  n=$(wc -l < "$log" | tr -d ' ')
  jq -e '.files == ["sub/a.txt"] and (.dirs | map(.path) == ["sub"])' "$TEST_ROOT/first.json" > /dev/null || { cat "$TEST_ROOT/first.json"; false; }
  [ "$n" -eq 3 ] || { echo "a collection ran find $n times, wanted 3"; false; }
  # The next run reads the file the first one wrote: it inherits that run's list.
  reads_reset "$copy" "$st"
  cat "$copy/w.txt" > /dev/null
  reads_collect "$copy" "$st" | jq -e '.files == ["sub/a.txt"] and (.dirs | map(.path) == ["sub"])' > /dev/null || { echo "the written file's list was not inherited"; false; }
}

# Remaining cost (M42 after decision): the first reset of every slot copy waited for the next whole
# second (half a second on average, once per copy, in the unit's own tracking) so that no file of
# a fresh copy could look written. On a file system with finer times the marks are exact and
# nothing needs to wait: the first reset sleeps only where the times are whole seconds.
@test "R202: the first reset of a fresh copy does not wait for the next second where times are finer than a second" {
  local copy="$TEST_ROOT/copy" st="$TEST_ROOT/state" i
  mkdir -p "$copy" "$TEST_ROOT/shim" "$TEST_ROOT/probe"
  # shellcheck disable=SC1091
  source "$PLUGIN_ROOT/lib/reads.sh"
  reads_subsecond "$TEST_ROOT/probe" || skip "this file system has whole-second times"
  git -C "$copy" init -q
  printf 'a\n' > "$copy/a.txt"
  git -C "$copy" add -A
  git -C "$copy" commit -q -m "feat: file"
  printf '#!/bin/sh\necho slept >> "%s/slept"\nexec /bin/sleep "$@"\n' "$TEST_ROOT" > "$TEST_ROOT/shim/sleep"
  chmod +x "$TEST_ROOT/shim/sleep"
  # Several fresh states: a wait that ends at once by luck (the second just changed) cannot hide it.
  for i in 1 2 3 4 5 6; do
    PATH="$TEST_ROOT/shim:$PATH" reads_reset "$copy" "$TEST_ROOT/state$i"
  done
  [ ! -e "$TEST_ROOT/slept" ] || { echo "the first resets slept $(wc -l < "$TEST_ROOT/slept" | tr -d ' ') times"; false; }
  # Nothing of the fresh copy looks written by a first run that reads one file.
  cat "$copy/a.txt" > /dev/null
  reads_collect "$copy" "$TEST_ROOT/state1" | jq -e '.files == ["a.txt"]' > /dev/null
  [ ! -s "$TEST_ROOT/state1/new" ] || { echo "files of the fresh copy look written: $(tr '\0' ' ' < "$TEST_ROOT/state1/new")"; false; }
}
