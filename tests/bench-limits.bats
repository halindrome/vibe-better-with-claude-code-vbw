#!/usr/bin/env bats
# R151 (CLAUDE.md hot paths, docs/guards.md, docs/statusline.md): the hook
# benchmark fails only on a real slowdown. A guard fails when its own cost (its
# CPU time minus the platform's sh and jq startup) is above 20 ms per call; the
# status line fails above 60 ms per call; the old relative limit (1x the
# startup) is gone. When the startup alone is above the hook limit the machine
# is too busy to measure: the bench says so, with the startup, and passes
# without judging anything. VBW_HOOK_BUDGET_MS and VBW_STATUSLINE_BUDGET_MS
# still override the limits. L1: the bench runs on a copy of the plugin whose
# hooks or status line burn a known amount of CPU, and a busy machine is
# simulated by a jq that burns CPU before it runs. Margins are wide (100 ms of
# extra work against a 20 ms limit); a test that needs a quiet machine is
# skipped when the bench itself reports the machine busy.

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  BENCH="$REPO_ROOT/tools/bench-hooks.sh"
}

teardown() { vbw_teardown; }

# burn MS: a shell command that spends at least MS ms of CPU (perl's own
# startup, about 8 ms on a Mac, comes on top).
burn() { printf "perl -e '1 while (times)[0] + (times)[1] < %s / 1000'" "$1"; }

# hooks_with MATCHER COMMAND: every PreToolUse hook whose matcher matches
# MATCHER first runs COMMAND, then runs as before.
hooks_with() {
  jq --arg m "$1" --arg b "$2; " \
    '(.hooks.PreToolUse[] | select(.matcher | test($m)) | .hooks[].command) |= ($b + .)' \
    "$PLUGIN_ROOT/hooks/hooks.json" > "$TEST_ROOT/plugin/hooks/hooks.json"
}

# statusline_burns MS: the copied status line first spends MS ms of CPU.
statusline_burns() {
  local f="$TEST_ROOT/plugin/scripts/vbw-statusline.sh"
  { sed -n 1p "$f"; burn "$1"; echo; sed -n '2,$p' "$f"; } > "$TEST_ROOT/sl.sh"
  cat "$TEST_ROOT/sl.sh" > "$f"
}

# slow_jq MS: a jq first on PATH that spends MS ms of CPU, then runs the real
# jq as its child (not exec: macOS drops the CPU time of a process that execs).
slow_jq() {
  local real
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/slow"
  printf '#!/bin/sh\n%s\n"%s" "$@"\n' "$(burn "$1")" "$real" > "$TEST_ROOT/slow/jq"
  chmod +x "$TEST_ROOT/slow/jq"
  SLOW_PATH="$TEST_ROOT/slow:$PATH"
}

# bench [ENV=VALUE...]: the benchmark on the copied plugin, two calls per input.
bench() {
  run env VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=2 "$@" bash "$BENCH"
}

# quiet_or_skip: a test that needs a quiet machine is skipped when the bench
# reported this one too busy to measure.
quiet_or_skip() {
  if printf '%s\n' "$output" | grep -qi 'too busy to measure'; then
    skip "the machine is too busy to measure: $(printf '%s\n' "$output" | grep -i 'too busy to measure')"
  fi
}

# line REGEX: the one output line matching REGEX (extended), or a failure.
line() {
  local l
  l=$(printf '%s\n' "$output" | grep -E -- "$1") || {
    echo "no line matches: $1"
    printf '%s\n' "$output"
    return 1
  }
  printf '%s\n' "$l"
}

@test "R151: a guard whose own cost is above 20 ms per call fails the bench, and the line names the input, the cost and the 20 ms limit" {
  hooks_with '^Bash$' "$(burn 100)"
  bench
  quiet_or_skip
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  local input l cost
  for input in git npm big interp "git, large record" "big, 2000 checks"; do
    l=$(line "^guard \\($input\\): [0-9.]+ ms own CPU per call.*; budget 20 ms: OVER$") || {
      echo "$l"
      false
    }
    cost=$(printf '%s\n' "$l" | sed -E 's/^[^:]*: ([0-9.]+) ms.*$/\1/')
    perl -e 'exit($ARGV[0] > 20 ? 0 : 1)' -- "$cost" || {
      echo "a 100 ms slowdown measured $cost ms: $l"
      false
    }
  done
}

@test "R151: a guard whose own cost is at or below 20 ms passes, however it compares with the startup (the old 1x limit no longer fails)" {
  # The file guard starts perl once more (about 8 ms of CPU on a Mac): its own
  # cost is above 8 ms and above the platform's startup on a quiet machine,
  # which the old limits (8 ms or 1x the startup) failed.
  hooks_with 'Read' 'perl -e 1'
  bench
  quiet_or_skip
  local l
  for l in "read" "read, large record" "read, 51 checks" "read, 2000 checks"; do
    line "^guard \\($l\\): [0-9.]+ ms own CPU per call.*; budget 20 ms$" > /dev/null || {
      line "^guard \\($l\\): " || true
      false
    }
  done
  ! grep -qE 'VBW_HOOK_BUDGET([^_]|$)' "$BENCH" || {
    echo "tools/bench-hooks.sh still reads the relative limit VBW_HOOK_BUDGET"
    false
  }
}

@test "R151: the status line above 60 ms per call fails the bench on the small and the large record, naming the cost and the 60 ms limit" {
  statusline_burns 100
  bench
  quiet_or_skip
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  local l cost
  for l in "status line" "status line \\(large record\\)"; do
    l=$(line "^$l: [0-9.]+ ms CPU per call; budget 60 ms: OVER$") || {
      echo "$l"
      false
    }
    cost=$(printf '%s\n' "$l" | sed -E 's/^.*: ([0-9.]+) ms CPU per call.*$/\1/')
    perl -e 'exit($ARGV[0] > 60 ? 0 : 1)' -- "$cost" || {
      echo "a 100 ms status line measured $cost ms: $l"
      false
    }
  done
}

@test "R151: without settings the limits are 20 ms per guard call and 60 ms for the status line, also in the bench's defaults" {
  bench
  quiet_or_skip
  local input
  for input in git npm big interp read answer; do
    line "^guard \\($input\\): -?[0-9.]+ ms own CPU per call.*; budget 20 ms(: OVER)?$" > /dev/null
  done
  line '^status line: [0-9.]+ ms CPU per call; budget 60 ms(: OVER)?$' > /dev/null
  line '^status line \(large record\): [0-9.]+ ms CPU per call; budget 60 ms(: OVER)?$' > /dev/null
  grep -qF 'VBW_HOOK_BUDGET_MS:-20}' "$BENCH"
  grep -qF 'VBW_STATUSLINE_BUDGET_MS:-60}' "$BENCH"
}

@test "R151: a machine too busy to measure is reported with its startup and the run passes without judging any guard" {
  slow_jq 40
  bench PATH="$SLOW_PATH"
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  local l
  l=$(printf '%s\n' "$output" | grep -iE 'too busy to measure') || {
    echo "no line says the machine is too busy to measure"
    printf '%s\n' "$output"
    false
  }
  # The line gives the measured startup (above the limit) and the 20 ms limit.
  printf '%s\n' "$l" | grep -qE '(^|[^0-9.])(2[1-9]|[3-9][0-9]|[1-9][0-9]{2,})(\.[0-9]+)? ms' || {
    echo "the busy line does not give a startup above 20 ms: $l"
    false
  }
  printf '%s\n' "$l" | grep -qE '(^|[^0-9.])20 ms' || {
    echo "the busy line does not name the 20 ms limit: $l"
    false
  }
  ! printf '%s\n' "$output" | grep -qE '^guard \(|^status line|OVER' || {
    echo "a busy machine was judged:"
    printf '%s\n' "$output"
    false
  }
}

@test "R151: the same run with a startup below the limit judges the guards and the status line as usual" {
  # The same slowed jq, with limits above its startup: nothing is busy.
  slow_jq 40
  bench PATH="$SLOW_PATH" VBW_HOOK_BUDGET_MS=1000 VBW_STATUSLINE_BUDGET_MS=1000
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  ! printf '%s\n' "$output" | grep -qi 'too busy to measure' || {
    printf '%s\n' "$output"
    false
  }
  local input
  for input in git npm big interp read answer; do
    line "^guard \\($input\\): -?[0-9.]+ ms own CPU per call.*; budget 1000 ms$" > /dev/null
    line "^guard \\($input, large record\\): -?[0-9.]+ ms own CPU per call.*; budget 1000 ms$" > /dev/null
  done
  line '^status line: [0-9.]+ ms CPU per call; budget 1000 ms$' > /dev/null
  line '^status line \(large record\): [0-9.]+ ms CPU per call; budget 1000 ms$' > /dev/null
}

@test "R151: VBW_HOOK_BUDGET_MS and VBW_STATUSLINE_BUDGET_MS override the two limits, the busy threshold following the hook limit" {
  hooks_with '^Bash$' "$(burn 100)"
  statusline_burns 100
  bench VBW_HOOK_BUDGET_MS=50 VBW_STATUSLINE_BUDGET_MS=1000
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^guard \(git\): [0-9.]+ ms own CPU per call.*; budget 50 ms: OVER$' > /dev/null
  line '^status line: [0-9.]+ ms CPU per call; budget 1000 ms$' > /dev/null
  bench VBW_HOOK_BUDGET_MS=1000 VBW_STATUSLINE_BUDGET_MS=50
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^guard \(git\): [0-9.]+ ms own CPU per call.*; budget 1000 ms$' > /dev/null
  line '^status line: [0-9.]+ ms CPU per call; budget 50 ms: OVER$' > /dev/null
  slow_jq 40
  bench PATH="$SLOW_PATH" VBW_HOOK_BUDGET_MS=30
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$output" | grep -iE 'too busy to measure' | grep -qE '(^|[^0-9.])30 ms' || {
    echo "with a 30 ms hook limit the busy line does not name it"
    printf '%s\n' "$output"
    false
  }
}
