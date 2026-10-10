#!/usr/bin/env bats
# R152 (docs/proof.md, CLAUDE.md testing): the timed speed checks run once per
# release, not in every vbw prove. bash tools/test.sh with no option (the test
# command vbw prove runs) runs neither benchmark and no timed test file; the
# release way, bash tools/test.sh --release, runs the lint, both benchmarks
# (tools/bench-hooks.sh, tools/bench-panel.sh), the suite in one parallel batch
# and then the timed test files (tests/timed-*.bats) alone; --quick and the CI
# shards keep working, the shards together making one release run. CI runs the
# release way. No test file of the default run measures a duration. L1: a copy
# of tools/test.sh runs in a scratch repository whose bats, shellcheck,
# parallel, node, getconf and benchmarks are stand-ins that log their calls;
# the repository's own files are read as text.

load helper

CI="$REPO_ROOT/.github/workflows/ci.yml"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# fake_repo: a scratch repository holding a copy of tools/test.sh, stand-in
# benchmarks, ordinary test files a, b, c and z, two timed ones and an empty
# record, with stand-in tools first on PATH that log every call to $LOG. A
# benchmark fails when FAIL names it; bats fails its batch (--jobs) or its
# timed call when FAIL is batch or timed.
fake_repo() {
  FAKE="$TEST_ROOT/fake repo"
  LOG="$TEST_ROOT/calls.log"
  STUBS="$TEST_ROOT/stubs"
  export FAKE LOG STUBS
  mkdir -p "$FAKE/tools" "$FAKE/tests" "$FAKE/.vbw" "$STUBS"
  cp "$REPO_ROOT/tools/test.sh" "$FAKE/tools/test.sh"
  local b f t
  for b in bench-hooks bench-panel; do
    printf '#!/usr/bin/env bash\necho %s >> "$LOG"\n[ "${FAIL:-}" != %s ]\n' "$b" "$b" > "$FAKE/tools/$b.sh"
  done
  for f in a b c z timed-speed timed-cost; do
    printf '#!/usr/bin/env bats\n@test "%s" { true; }\n' "$f" > "$FAKE/tests/$f.bats"
  done
  printf '{"schema": 4, "protected": [], "checks": []}\n' > "$FAKE/.vbw/record.json"
  for t in shellcheck parallel node; do
    printf '#!/usr/bin/env bash\n{ printf %%s %s; printf " %%s" "$@"; echo; } >> "$LOG"\n' "$t" > "$STUBS/$t"
  done
  cat > "$STUBS/bats" << 'SH'
#!/usr/bin/env bash
{ printf %s bats; printf " %s" "$@"; echo; } >> "$LOG"
case " $* " in
  *" --jobs "*) [ "${FAIL:-}" != batch ] ;;
  *) [ "${FAIL:-}" != timed ] ;;
esac
SH
  printf '#!/usr/bin/env bash\necho 8\n' > "$STUBS/getconf"
  chmod +x "$STUBS"/*
  : > "$LOG"
}

# fake_run ARGS...: run the copied script in the scratch repository; sets CODE.
fake_run() {
  : > "$LOG"
  CODE=0
  (cd "$FAKE" && PATH="$STUBS:$PATH" bash tools/test.sh "$@" < /dev/null) > "$TEST_ROOT/out" 2>&1 || CODE=$?
}

# bats_calls: the logged bats calls, one per line.
bats_calls() { grep '^bats ' "$LOG" || true; }

# files_of LINE: the test files a logged call names, sorted, one per line.
files_of() { printf '%s\n' "$1" | tr ' ' '\n' | grep -E '^tests/' | LC_ALL=C sort; }

PLAIN='tests/a.bats
tests/b.bats
tests/c.bats
tests/z.bats'
TIMED='tests/timed-cost.bats
tests/timed-speed.bats'

@test "R152: bash tools/test.sh with no option runs the lint and every test file except the timed ones, and neither benchmark" {
  fake_repo
  fake_run
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  ! grep -qE '^bench-(hooks|panel)$' "$LOG" || {
    echo "a benchmark ran:"
    cat "$LOG"
    false
  }
  grep -q '^shellcheck ' "$LOG" || {
    echo "no lint:"
    cat "$LOG"
    false
  }
  [ "$(bats_calls | grep -c .)" -eq 1 ] || {
    cat "$LOG"
    false
  }
  [ "$(files_of "$(bats_calls)")" = "$PLAIN" ] || {
    echo "the default run ran other files than the untimed ones:"
    cat "$LOG"
    false
  }
  bats_calls | grep -qe '--jobs 4' || {
    cat "$LOG"
    false
  }
}

@test "R152: bash tools/test.sh --release runs the lint, both benchmarks, the suite in one parallel batch, then the timed files alone" {
  fake_repo
  fake_run --release
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  grep -q '^shellcheck ' "$LOG" && grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || {
    echo "the lint or a benchmark did not run:"
    cat "$LOG"
    false
  }
  local calls batch timed
  calls=$(bats_calls)
  [ "$(printf '%s\n' "$calls" | grep -c .)" -eq 2 ] || {
    cat "$LOG"
    false
  }
  batch=$(printf '%s\n' "$calls" | sed -n 1p)
  timed=$(printf '%s\n' "$calls" | sed -n 2p)
  [[ "$batch" == *"--jobs 4"* ]] && [ "$(files_of "$batch")" = "$PLAIN" ] || {
    echo "the parallel batch is not the untimed files: $batch"
    false
  }
  [[ "$timed" != *"--jobs"* ]] && [ "$(files_of "$timed")" = "$TIMED" ] || {
    echo "the last call is not the timed files alone: $timed"
    false
  }
}

@test "R152: the release run fails when a benchmark, the batch or a timed file fails" {
  fake_repo
  fake_run --release
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  local what
  for what in bench-hooks bench-panel batch timed; do
    FAIL=$what fake_run --release
    [ "$CODE" -ne 0 ] || {
      echo "--release passed with a failing $what"
      cat "$LOG"
      false
    }
  done
}

@test "R152: --quick still runs without the benchmarks and without any timed file" {
  fake_repo
  fake_run --quick
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  ! grep -qE '^bench-(hooks|panel)$|tests/timed-' "$LOG" || {
    cat "$LOG"
    false
  }
  [ "$(files_of "$(bats_calls)")" = "$PLAIN" ] || {
    cat "$LOG"
    false
  }
  cd "$REPO_ROOT"
  run bash tools/test.sh --quick --list < /dev/null
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  ! printf '%s\n' "$output" | grep -qE 'tests/timed-|bench-(hooks|panel)\.sh' || {
    echo "$output"
    false
  }
}

@test "R152: the CI shards together make one release run: shard 1 runs both benchmarks, each shard runs its timed files alone after its batch" {
  fake_repo
  local k calls last all_timed="" all=""
  for k in 1 2; do
    fake_run --shard "$k/2"
    [ "$CODE" -eq 0 ] || {
      cat "$TEST_ROOT/out"
      false
    }
    if [ "$k" -eq 1 ]; then
      grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || {
        cat "$LOG"
        false
      }
    else
      ! grep -qE '^bench-(hooks|panel)$' "$LOG" || {
        cat "$LOG"
        false
      }
    fi
    calls=$(bats_calls)
    last=$(printf '%s\n' "$calls" | tail -n 1)
    if printf '%s\n' "$calls" | grep -q 'tests/timed-'; then
      [[ "$last" != *"--jobs"* ]] && ! files_of "$last" | grep -qv 'tests/timed-' || {
        echo "shard $k does not run its timed files alone, last:"
        cat "$LOG"
        false
      }
      ! printf '%s\n' "$calls" | grep -e '--jobs' | grep -q 'tests/timed-' || {
        echo "shard $k runs a timed file in its parallel batch"
        cat "$LOG"
        false
      }
      all_timed="$all_timed$(files_of "$last")"$'\n'
    fi
    all="$all$(files_of "$(printf '%s\n' "$calls" | tr '\n' ' ')")"$'\n'
  done
  [ "$(printf '%s' "$all_timed" | grep . | LC_ALL=C sort)" = "$TIMED" ] || {
    echo "the shards ran these timed files: $all_timed"
    false
  }
  [ "$(printf '%s' "$all" | grep . | LC_ALL=C sort)" = "$(printf '%s\n%s\n' "$PLAIN" "$TIMED" | LC_ALL=C sort)" ] || {
    echo "the shards together ran: $all"
    false
  }
}

@test "R152: tools/test.sh refuses --release with other arguments, naming the release way in its usage line, and runs nothing" {
  fake_repo
  local arg
  for arg in "--release --bogus" "--bogus --release" "--quick --release" "--release --quick"; do
    # shellcheck disable=SC2086 # each arg string is several arguments on purpose
    fake_run $arg
    [ "$CODE" -eq 2 ] || {
      echo "$arg: exit $CODE"
      false
    }
    grep -q 'usage: tools/test.sh.*--release' "$TEST_ROOT/out" || {
      echo "$arg: $(cat "$TEST_ROOT/out")"
      false
    }
    [ ! -s "$LOG" ] || {
      echo "$arg ran: $(cat "$LOG")"
      false
    }
  done
}

@test "R152: CI runs the release way: the jobs without a shard run --release, the shard jobs run their share" {
  grep -qF 'bash tools/test.sh --release' "$CI" || {
    echo "ci.yml never runs bash tools/test.sh --release"
    false
  }
  grep -qF 'bash tools/test.sh --shard "$SHARD/$SHARDS"' "$CI"
  ! grep -nE 'bash tools/test\.sh *($|;|&|\|| fi)' "$CI" || {
    echo "ci.yml still runs tools/test.sh without the release way"
    false
  }
}

@test "R152: no test file of the default run measures a duration; the timed tests live in tests/timed-*.bats" {
  cd "$REPO_ROOT"
  local f bad=""
  for f in tests/*.bats; do
    case "$f" in tests/timed-* | tests/release-run.bats) continue ;; esac
    # A duration: bash's SECONDS clock or the wall clock in seconds.
    if grep -vE '^[[:space:]]*#' "$f" | grep -qwE 'SECONDS|date \+%s'; then bad="$bad $f(clock)"; fi
    # A speed benchmark judged at its real limit: every run of one sets the
    # limit on the same line. tests/bench-limits.bats checks the limit logic
    # itself, with 100 ms of extra work against 20 ms.
    [ "$f" != tests/bench-limits.bats ] || continue
    grep -qE 'tools/bench-(hooks|panel)\.sh' "$f" || continue
    if grep -E 'bash +"?\$(BENCH|\{?REPO_ROOT\}?/tools/bench-|BATS_TEST_DIRNAME/\.\./tools/bench-)' "$f" \
      | grep -qv '_BUDGET_MS='; then bad="$bad $f(benchmark)"; fi
  done
  ! grep -q 'Time::HiRes' tests/proof-stale-links.bats || bad="$bad tests/proof-stale-links.bats(clock)"
  [ -z "$bad" ] || {
    echo "default-run test files that measure a duration:$bad"
    false
  }
  ls tests/timed-*.bats > /dev/null 2>&1 || {
    echo "no tests/timed-*.bats"
    false
  }
  grep -l '24 checks' tests/timed-*.bats > /dev/null || {
    echo "the 24-check proof time is not a timed test"
    false
  }
  grep -l '50,000 files' tests/timed-*.bats > /dev/null || {
    echo "the 50,000-file scan time is not a timed test"
    false
  }
}
