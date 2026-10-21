#!/usr/bin/env bats
# R142 (L1): bash tools/test.sh --shard K/N runs shard K of N of the suite, so
# CI can split the slow macOS /bin/bash 3.2 run across N machines.
# --shard K/N --list prints what shard K would run, one stage or test file per
# line (stages first, then the parallel batch, then the timed files), and runs
# nothing. Shares come from tests/*.bats at run time and are the same for the
# same inputs; together the shards run every file exactly once, the timed
# files (tests/timed-*.bats, R152) alone after each shard's batch. Shard 1 alone
# runs the tool lint and the hook and panel benchmarks. The unsharded runs are
# tests/release-run.bats's (R152). The real repository's lists are made once
# for the file (setup_file); runs below use a copy of the
# script in a scratch repository whose bats, shellcheck, parallel, node and
# getconf are stand-ins that only log their arguments.

load helper

TIMED='tests/timed-speed.bats tests/timed-cost.bats'

# The script runs the whole suite when it does not know its arguments: never call it before it has shards.
has_shards() {
  grep -q -- '--shard' "$REPO_ROOT/tools/test.sh" || {
    echo "tools/test.sh has no --shard mode yet"
    return 1
  }
}

# setup_file: what tools/test.sh --shard K/N --list prints in the real
# repository, for N from 1 to 5, in $LISTS/K-N, and each share of 4 once more,
# from a run of its own, in $LISTS/K-4.again. The runs are independent and run
# side by side; any that fails fails the file.
setup_file() {
  has_shards
  LISTS="$BATS_FILE_TMPDIR/lists"
  export LISTS
  mkdir -p "$LISTS"
  local n k p pids=()
  for n in 1 2 3 4 5; do
    for k in $(seq 1 "$n"); do
      (cd "$REPO_ROOT" && bash tools/test.sh --shard "$k/$n" --list < /dev/null) > "$LISTS/$k-$n" &
      pids+=("$!")
    done
  done
  for k in 1 2 3 4; do
    (cd "$REPO_ROOT" && bash tools/test.sh --shard "$k/4" --list < /dev/null) > "$LISTS/$k-4.again" &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p"; done
}

setup() {
  vbw_setup
  has_shards
}

teardown() { vbw_teardown; }

# real_files K N: the test files share K of N lists in the real repository.
real_files() {
  grep -E '^tests/[^/]+\.bats$' "$LISTS/$1-$2"
}

# shard_files DIR K N: the test files shard K of N lists, run from DIR.
shard_files() {
  (cd "$1" && bash tools/test.sh --shard "$2/$3" --list < /dev/null) | grep -E '^tests/[^/]+\.bats$'
}

# fake_repo: a scratch repository holding a copy of tools/test.sh, stand-in
# benchmark scripts, a few test files (two timed ones among them) and a
# bin folder of stand-in tools that log every call to $LOG.
fake_repo() {
  FAKE="$TEST_ROOT/fake repo"
  LOG="$TEST_ROOT/calls.log"
  STUBS="$TEST_ROOT/stubs"
  export FAKE LOG STUBS
  mkdir -p "$FAKE/tools" "$FAKE/tests" "$STUBS"
  cp "$REPO_ROOT/tools/test.sh" "$FAKE/tools/test.sh"
  printf '#!/usr/bin/env bash\necho bench-hooks >> "$LOG"\n' > "$FAKE/tools/bench-hooks.sh"
  printf '#!/usr/bin/env bash\necho bench-panel >> "$LOG"\n' > "$FAKE/tools/bench-panel.sh"
  local f t
  for f in a b c d e prove-parallel guard-cost bench-hooks big-record-hooks bench-protected proof-stale-links timed-speed timed-cost z; do
    printf '#!/usr/bin/env bats\n@test "%s" { true; }\n' "$f" > "$FAKE/tests/$f.bats"
  done
  for t in bats shellcheck parallel node; do
    printf '#!/usr/bin/env bash\n{ printf %%s %s; printf " %%s" "$@"; echo; } >> "$LOG"\n' "$t" > "$STUBS/$t"
    chmod +x "$STUBS/$t"
  done
  printf '#!/usr/bin/env bash\necho 8\n' > "$STUBS/getconf"
  chmod +x "$STUBS/getconf"
  : > "$LOG"
}

# fake_run ARGS...: run the copied script in the scratch repository with the stand-ins first on PATH.
fake_run() {
  : > "$LOG"
  (cd "$FAKE" && PATH="$STUBS:$PATH" bash tools/test.sh "$@" < /dev/null) > /dev/null 2>&1
}

@test "R142: for 1 to 5 shards, together the shards list every tests/*.bats file exactly once" {
  local n k all expect dups
  expect=$(cd "$REPO_ROOT" && ls tests/*.bats | LC_ALL=C sort)
  for n in 1 2 3 4 5; do
    all=""
    for k in $(seq 1 "$n"); do
      all="$all$(real_files "$k" "$n")"$'\n'
    done
    dups=$(printf '%s' "$all" | grep . | LC_ALL=C sort | uniq -d)
    [ -z "$dups" ] || {
      echo "$n shards: listed twice: $dups"
      false
    }
    [ "$(printf '%s' "$all" | grep . | LC_ALL=C sort)" = "$expect" ] || {
      echo "$n shards: the union differs from tests/*.bats"
      false
    }
  done
}

@test "R142: the same inputs give the same shares" {
  local k first second
  for k in 1 2 3 4; do
    first=$(cat "$LISTS/$k-4")
    second=$(cat "$LISTS/$k-4.again")
    [ -n "$first" ] && [ "$first" = "$second" ] || {
      echo "shard $k/4 differs between two runs"
      false
    }
  done
}

@test "R142: shares are balanced by test count: no shard of 4 holds much more than a quarter of the tests" {
  local k f n count total=0 max=0 big=0 counts
  # Each file's test count, "tests/NAME.bats:N", from one grep over them all.
  counts=$(cd "$REPO_ROOT" && grep -cH '^@test' tests/*.bats || true)
  while IFS=: read -r f n; do
    total=$((total + n))
    [ "$n" -le "$big" ] || big=$n
  done <<< "$counts"
  for k in 1 2 3 4; do
    count=$(real_files "$k" 4 | awk -F: 'NR == FNR { c[$1] = $2; next } { s += c[$0] } END { print s + 0 }' <(printf '%s\n' "$counts") -)
    [ "$count" -le "$max" ] || max=$count
  done
  [ "$max" -le $(((total + 3) / 4 + big)) ] || {
    echo "largest shard has $max of $total tests"
    false
  }
}

@test "R142: a newly added test file lands in exactly one shard, with no list to edit" {
  fake_repo
  printf '#!/usr/bin/env bats\n@test "new" { true; }\n' > "$FAKE/tests/new-feature.bats"
  local k hits=0
  for k in 1 2 3; do
    if shard_files "$FAKE" "$k" 3 | grep -qx 'tests/new-feature.bats'; then hits=$((hits + 1)); fi
  done
  [ "$hits" -eq 1 ] || {
    echo "tests/new-feature.bats is in $hits shards"
    false
  }
}

@test "R142: the tool lint and the hook and panel benchmarks are listed by shard 1 only" {
  local k out
  for k in 1 2 3 4; do
    out=$(cat "$LISTS/$k-4")
    if [ "$k" -eq 1 ]; then
      printf '%s\n' "$out" | grep -qi 'shellcheck'
      printf '%s\n' "$out" | grep -q 'bench-hooks.sh'
      printf '%s\n' "$out" | grep -q 'bench-panel.sh'
    else
      ! printf '%s\n' "$out" | grep -qiE 'shellcheck|bench-hooks\.sh|bench-panel\.sh' || {
        echo "shard $k/4 lists: $out"
        false
      }
    fi
  done
}

@test "R142: a shard runs its share in one parallel batch, then its timed files alone, and only shard 1 lints and benchmarks" {
  fake_repo
  local k bats_lines batch timed listed ran
  ran=""
  for k in 1 2; do
    fake_run --shard "$k/2"
    bats_lines=$(grep '^bats ' "$LOG" || true)
    batch=$(printf '%s\n' "$bats_lines" | grep -e '--jobs 4' || true)
    timed=$(printf '%s\n' "$bats_lines" | grep -v -e '--jobs' || true)
    [ "$(printf '%s\n' "$batch" | grep -c .)" -le 1 ] && [ "$(printf '%s\n' "$timed" | grep -c .)" -le 1 ] || {
      cat "$LOG"
      false
    }
    # The timed files run after the batch, never inside it.
    for f in $TIMED; do
      [[ " $batch " != *" $f "* ]] || {
        echo "shard $k: $f is in the parallel batch"
        false
      }
    done
    if [ -n "$timed" ] && [ -n "$batch" ]; then
      [ "$(grep -n '^bats ' "$LOG" | tail -n 1 | cut -d: -f2-)" = "$timed" ] || {
        cat "$LOG"
        false
      }
    fi
    if [ "$k" -eq 1 ]; then
      grep -q '^shellcheck ' "$LOG" && grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || {
        cat "$LOG"
        false
      }
    else
      ! grep -qE '^shellcheck |^bench-hooks$|^bench-panel$' "$LOG" || {
        cat "$LOG"
        false
      }
    fi
    # What the shard runs is what it lists.
    listed=$(shard_files "$FAKE" "$k" 2 | LC_ALL=C sort)
    [ "$(printf '%s\n%s\n' "$batch" "$timed" | tr ' ' '\n' | grep -E '^tests/' | LC_ALL=C sort)" = "$listed" ] || {
      echo "shard $k ran other files than it lists"
      cat "$LOG"
      false
    }
    ran="$ran$listed"$'\n'
  done
  [ "$(printf '%s' "$ran" | grep . | LC_ALL=C sort)" = "$(cd "$FAKE" && ls tests/*.bats | LC_ALL=C sort)" ]
}

@test "R142: a failing test file in a shard makes the shard fail, in the batch and in the timed files" {
  fake_repo
  local which code
  for which in batch timed; do
    if [ "$which" = batch ]; then
      printf '#!/usr/bin/env bash\ncase " $* " in *" --jobs "*) exit 1 ;; esac\n' > "$STUBS/bats"
    else
      printf '#!/usr/bin/env bash\ncase " $* " in *" --jobs "*) exit 0 ;; esac\nexit 1\n' > "$STUBS/bats"
    fi
    chmod +x "$STUBS/bats"
    for k in 1 2; do
      code=0
      (cd "$FAKE" && PATH="$STUBS:$PATH" bash tools/test.sh --shard "$k/2" < /dev/null) > /dev/null 2>&1 || code=$?
      # A shard with no timed file never runs the failing timed call.
      if [ "$which" = timed ] && ! shard_files "$FAKE" "$k" 2 | grep -q 'tests/timed-'; then
        continue
      fi
      [ "$code" -ne 0 ] || {
        echo "shard $k/2 passed with a failing $which"
        false
      }
    done
  done
}

@test "R142: an invalid shard argument exits 2 with the usage line and runs nothing" {
  fake_repo
  local arg out code
  for arg in "--shard 0/4" "--shard 5/4" "--shard a/4" "--shard 1/0" "--shard 1/x" "--shard -1/4" "--shard 1/4/2" "--shard" "--shard 1/4 --bogus" "--list --shard 1/4"; do
    : > "$LOG"
    code=0
    # shellcheck disable=SC2086 # each arg string is several arguments on purpose
    out=$(cd "$FAKE" && PATH="$STUBS:$PATH" bash tools/test.sh $arg 2>&1 < /dev/null) || code=$?
    [ "$code" -eq 2 ] || {
      echo "$arg: exit $code: $out"
      false
    }
    [[ "$out" == *"usage: tools/test.sh"*"--shard K/N"* ]] || {
      echo "$arg: $out"
      false
    }
    [ ! -s "$LOG" ] || {
      echo "$arg ran: $(cat "$LOG")"
      false
    }
  done
}
