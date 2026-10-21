#!/usr/bin/env bats
# R55: the panel's node tests (every tests/panel/**/*.test.mjs, subfolders included)
# run as part of the suite, so a regression in the panel fails `bash tools/test.sh`.
# The files are found on disk and node's own list of the files it ran must equal
# them, so a test file can never be skipped silently. Skipped without node.

load helper

@test "R55: node --test passes over every node test under tests/panel, none missed" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  cd "$BATS_TEST_DIRNAME/.."
  files=()
  while IFS= read -r -d '' f; do files+=("$f"); done < <(find tests/panel -name '*.test.mjs' -print0 | sort -z)
  [ "${#files[@]}" -gt 0 ]
  run node --test --test-reporter=./tests/panel/helpers/files-ran-reporter.mjs "${files[@]}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ran=$(printf '%s\n' "$output" | grep -c '^FILE ')
  [ "$ran" -eq "${#files[@]}" ] || {
    echo "node ran $ran test files, ${#files[@]} are on disk"
    false
  }
  # every file on disk is among those node ran (equal counts alone could hide a swap)
  for f in "${files[@]}"; do
    printf '%s\n' "$output" | grep -q "^FILE .*/$f\$" || { echo "node did not run $f"; false; }
  done
}
