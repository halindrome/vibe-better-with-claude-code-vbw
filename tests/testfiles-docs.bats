#!/usr/bin/env bats
# R167: the Lead proposes the single-file test form through vbw apply
# ("test_files", with the {file} placeholder). docs/proof.md shows the Test
# files section with its run and files lines and the count line; docs/workflows.md
# names test_files. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"
FLOW="$REPO_ROOT/docs/workflows.md"
LEAD="$PLUGIN_ROOT/agents/lead.md"

@test "R167: the Lead proposes the single-file form through vbw apply: test_files and {file}" {
  grep -qF 'test_files' "$LEAD"
  grep -qF '{file}' "$LEAD"
}

@test "R167: docs/proof.md shows the Test files section with its run and files lines" {
  grep -qx '## Test files' "$DOC"
  grep -qF -- '- run: ' "$DOC"
  grep -qF -- '- files: ' "$DOC"
  grep -qF '{file}' "$DOC"
}

@test "R167: docs/proof.md shows the test files count line" {
  grep -qE 'test files: N ran, M reused' "$DOC"
}

@test "R167: docs/workflows.md names test_files" {
  grep -qF 'test_files' "$FLOW"
}

@test "R167 (#721): the map's tests scout finds the command that runs one test file, runs it once, and says what a new test file needs" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local prompt
  prompt=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$PLUGIN_ROOT/workflows/mapping.js" '{}' '{}' | jq -r '.calls[] | select(.opts.label == "scout tests") | .prompt')
  printf '%s' "$prompt" | grep -q 'one test file' || { echo "the tests scout is not asked for the one-file command"; false; }
  printf '%s' "$prompt" | grep -q 'run it once' || { echo "the one-file command is not run"; false; }
  printf '%s' "$prompt" | grep -q 'new test file' || { echo "what a new test file needs is not asked"; false; }
  printf '%s' "$prompt" | grep -q 'each subproject' || { echo "the command is not asked per subproject"; false; }
  printf '%s' "$prompt" | grep -q 'Never guess' || { echo "the scout may guess a form"; false; }
}

@test "R167 (#721): the Lead takes the one-file form from the map before working one out, and the docs say the map records it" {
  grep -E '^8\. \*\*One-file test form' "$LEAD" | grep -qF '.vbw/map.md'
  grep -E '^\| `vbw:mapping`' "$FLOW" | grep -q 'one test file'
}
