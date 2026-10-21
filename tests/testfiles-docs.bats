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
