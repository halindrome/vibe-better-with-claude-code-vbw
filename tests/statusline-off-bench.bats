#!/usr/bin/env bats
# R184 (with R151): tools/bench-hooks.sh measures the hand-back too. In a
# project that turns VBW off, the statusLine setting VBW writes runs VBW's
# script (which says "off") and then the user's earlier status line; the bench
# runs that setting as Claude Code does, with the bench's own plugin installed
# where the setting looks for it, and judges its CPU per call against the
# status line's 60 ms limit, on a line of its own: 'status line (VBW off)'.
# It fails when the earlier status line did not show, so the measure cannot
# leave the hand-back out. A machine too busy to measure is reported, not
# failed. L1: the bench runs on a copy of the plugin, two calls per input.

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  BENCH="$REPO_ROOT/tools/bench-hooks.sh"
  SCRIPT="$TEST_ROOT/plugin/scripts/vbw-statusline.sh"
}

teardown() { vbw_teardown; }

burn() { printf "perl -e '1 while (times)[0] + (times)[1] < %s / 1000'" "$1"; }

bench() {
  run env VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=2 "$@" bash "$BENCH"
}

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

@test "R184: the bench measures the hand-back where VBW is off against the 60 ms status line limit, and passes" {
  bench
  quiet_or_skip
  line '^status line \(VBW off\): [0-9.]+ ms CPU per call; budget 60 ms(: OVER)?$' > /dev/null
  bench VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  line '^status line \(VBW off\): [0-9.]+ ms CPU per call; budget 100000 ms$' > /dev/null
  [[ "$output" != *"earlier status line did not show"* ]]
  # Where VBW is on, the status line is still measured on both records.
  line '^status line: [0-9.]+ ms CPU per call; budget 100000 ms$' > /dev/null
  line '^status line \(large record\): [0-9.]+ ms CPU per call; budget 100000 ms$' > /dev/null
}

@test "R184: VBW's script above 60 ms makes the hand-back fail the bench, naming the cost and the limit" {
  {
    sed -n 1p "$SCRIPT"
    burn 100
    echo
    sed -n '2,$p' "$SCRIPT"
  } > "$TEST_ROOT/sl.sh"
  cat "$TEST_ROOT/sl.sh" > "$SCRIPT"
  bench
  quiet_or_skip
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  local l cost
  l=$(line '^status line \(VBW off\): [0-9.]+ ms CPU per call; budget 60 ms: OVER$')
  cost=$(printf '%s\n' "$l" | sed -E 's/^.*: ([0-9.]+) ms CPU per call.*$/\1/')
  perl -e 'exit($ARGV[0] > 60 ? 0 : 1)' -- "$cost" || {
    echo "a 100 ms script measured $cost ms in the hand-back: $l"
    false
  }
}

@test "R184: a hand-back that never shows the earlier status line fails the bench" {
  # A script that never says VBW is off: the setting never hands over.
  printf '#!/usr/bin/env bash\nwhile IFS= read -t 1 -r l; do :; done\necho "[VBW] always"\n' > "$SCRIPT"
  bench VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000
  [ "$status" -eq 1 ] || {
    printf '%s\n' "$output"
    false
  }
  [[ "$output" == *"status line (VBW off): the earlier status line did not show"* ]] || {
    printf '%s\n' "$output"
    false
  }
}

@test "R184: on a machine too busy to measure, the hand-back is not judged either" {
  local real
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/slow"
  printf '#!/bin/sh\n%s\n"%s" "$@"\n' "$(burn 40)" "$real" > "$TEST_ROOT/slow/jq"
  chmod +x "$TEST_ROOT/slow/jq"
  bench PATH="$TEST_ROOT/slow:$PATH"
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$output" | grep -qi 'too busy to measure'
  if printf '%s\n' "$output" | grep -q '^status line (VBW off)'; then
    echo "a busy machine was judged:"
    printf '%s\n' "$output"
    false
  fi
}
