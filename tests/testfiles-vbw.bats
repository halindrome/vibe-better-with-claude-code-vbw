#!/usr/bin/env bats
# R167: VBW's own project declares its single-file form in .vbw/spec.md (bats
# runs one file; the test files are tests/*.bats without the timed speed files,
# which run once per release). Everything its test command checked before is
# still checked by a proof that a change can affect: the engineering rules and
# every test file through the form, and the shell lint of tools/ through its
# own project command, bash tools/test.sh --lint, which runs only that lint.
# L1: the lint run uses stand-ins for shellcheck and bats that log their calls.

load helper

SPEC="$REPO_ROOT/.vbw/spec.md"

# section NAME: the lines of one ## section of VBW's spec.
section() {
  awk -v h="## $1" '$0 == h {on = 1; next} /^## / {on = 0} on' "$SPEC"
}

@test "R167: VBW's spec declares its single-file form: bats on one file" {
  section 'Test files' | grep -qE '^- run: .*bats.* \{file\}' || { section 'Test files'; false; }
}

@test "R167: VBW's declared test files are every tracked tests/*.bats except the timed ones" {
  local words declared all
  words=$(section 'Test files' | sed -n 's/^- files: //p')
  [ -n "$words" ] || { echo "no files line"; false; }
  # shellcheck disable=SC2086 # the declared patterns are words
  declared=$(git -C "$REPO_ROOT" ls-files -- $words | LC_ALL=C sort)
  all=$(git -C "$REPO_ROOT" ls-files -- 'tests/*.bats' | grep -v '^tests/timed-' | LC_ALL=C sort)
  [ -n "$declared" ] && [ "$declared" = "$all" ] || { diff <(printf '%s\n' "$declared") <(printf '%s\n' "$all"); false; }
}

@test "R167: VBW's spec names the shell lint as its own project command" {
  section 'Commands' | grep -qxF -- '- lint: bash tools/test.sh --lint'
  section 'Commands' | grep -qxF -- '- test: bash tools/test.sh'
}

@test "R167: bash tools/test.sh --lint runs shellcheck on every shell file under tools/ and runs no test file" {
  local stubs="$BATS_TEST_TMPDIR/stubs" log="$BATS_TEST_TMPDIR/calls.log" t
  mkdir -p "$stubs"
  for t in shellcheck bats; do
    printf '#!/usr/bin/env bash\n{ printf %%s %s; printf " %%s" "$@"; echo; } >> "%s"\n' "$t" "$log" > "$stubs/$t"
  done
  chmod +x "$stubs"/*
  cd "$REPO_ROOT"
  PATH="$stubs:$PATH" run bash tools/test.sh --lint < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^shellcheck .*tools/test\.sh' "$log" || { cat "$log"; false; }
  grep -q '^shellcheck .*tools/bench-hooks\.sh' "$log" || { cat "$log"; false; }
  ! grep -q '^bats' "$log" || { cat "$log"; false; }
}

@test "R167: tools/test.sh keeps its usage line and documents --lint in it" {
  cd "$REPO_ROOT"
  run bash tools/test.sh --bogus < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: tools/test.sh [--quick [--list]]"* ]] || { echo "$output"; false; }
  [[ "$output" == *"--lint"* ]] || { echo "$output"; false; }
}
