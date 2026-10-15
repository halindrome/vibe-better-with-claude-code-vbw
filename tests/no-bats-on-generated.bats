#!/usr/bin/env bats
# R172 (QA finding F121): no test runs the real bats on a bats file it wrote.
# In 2.0.32 a test wrote a small bats file and ran it with the real bats inside
# its own test; on Linux's bats-core the outer run lost a test ("bats: unknown
# test name", Executed N-1 of N, exit 1) while macOS passed it. The cause is
# not proven; this pattern is the only one that failed. Running the real bats
# on an existing file of the suite with --filter, as a dozen tests do, has
# passed on Linux and macOS in every CI run, and a test that writes bats files
# for a stand-in bats (the release and shard fixtures) is fine. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# writes_bats FILE: the test file writes a *.bats file (redirect or here-document).
writes_bats() {
  grep -vE '^[[:space:]]*#' "$1" | grep -qE '>>?[[:space:]]*"?[^ ]*\.bats|\.bats"?[[:space:]]*<<|tee [^ ]*\.bats'
}

# runs_real_bats FILE: a line that starts the real bats (not a stand-in, a title,
# a grep over a log): run/env/bash -c followed by bats and an argument.
runs_real_bats() {
  grep -vE '^[[:space:]]*#' "$1" | grep -E "(run |run env [^ ]+ |env [^ ]+ |bash -c '.*&& |[A-Z_]+=[^ ]+ )bats[[:space:]]+[-\"\$a-z./]" | grep -vE 'STUBS|LOG|@test'
}

@test "R172: no test file writes a bats file and also starts the real bats" {
  local f bad=""
  for f in "$REPO_ROOT"/tests/*.bats; do
    [ "$(basename "$f")" != no-bats-on-generated.bats ] || continue
    if writes_bats "$f" && [ -n "$(runs_real_bats "$f")" ]; then bad="$bad $(basename "$f")"; fi
  done
  [ -z "$bad" ] || { printf 'writes a bats file and runs the real bats (nested bats on a generated file lost a test on Linux):%s\n' "$bad"; false; }
}

@test "R172: the rule sees the pattern that failed on Linux, and passes the filter form and the stand-in form" {
  printf '%s\n' '@test "x" {' '  cat > "$repo/tests/one.bats" << '"'"'BATS'"'"'' '  run bash -c '"'"'cd "$1" && bats tests/one.bats'"'"' _ "$repo"' '}' > "$TEST_ROOT/bad.bats"
  writes_bats "$TEST_ROOT/bad.bats"
  [ -n "$(runs_real_bats "$TEST_ROOT/bad.bats")" ]
  printf '%s\n' '@test "y" {' '  run bats --filter "no eval" "$REPO_ROOT/tests/standards.bats"' '}' > "$TEST_ROOT/ok.bats"
  ! writes_bats "$TEST_ROOT/ok.bats"
  printf '%s\n' '@test "z" {' '  printf "x" > "$FAKE/tests/a.bats"' '  PATH="$STUBS:$PATH" bash tools/test.sh' '}' > "$TEST_ROOT/stub.bats"
  writes_bats "$TEST_ROOT/stub.bats"
  [ -z "$(runs_real_bats "$TEST_ROOT/stub.bats")" ]
}
