#!/usr/bin/env bats
# R167: when planning a project whose test runner can run one test file, the
# Lead proposes the single-file form, with that runner's documented syntax,
# through vbw apply ("test_files"). docs/proof.md (its project commands part)
# and docs/workflows.md explain the form, how it is approved, and what happens
# without it. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"
FLOW="$REPO_ROOT/docs/workflows.md"
LEAD="$PLUGIN_ROOT/agents/lead.md"

@test "R167: the Lead proposes the single-file form through vbw apply, with the runner's documented syntax" {
  grep -qF 'test_files' "$LEAD"
  grep -qF '{file}' "$LEAD"
  grep -qi 'documented' "$LEAD"
}

@test "R167: docs/proof.md shows the Test files section with its run and files lines" {
  grep -qx '## Test files' "$DOC"
  grep -qF -- '- run: ' "$DOC"
  grep -qF -- '- files: ' "$DOC"
  grep -qF '{file}' "$DOC"
}

@test "R167: docs/proof.md says the form is approved like a command and never guessed" {
  grep -qiE 'approv.*(form|single-file)|(form|single-file).*approv' "$DOC"
  grep -qiE 'never guess' "$DOC"
}

@test "R167: docs/proof.md says what happens without a form, and how the summary counts test files" {
  grep -qi 'runs whole' "$DOC"
  grep -qE 'test files: N ran, M reused' "$DOC"
}

@test "R167: docs/proof.md says a test file an approved check runs runs only as that check, and the quick command never stands in for a form" {
  grep -qiE 'only as (that|its) check' "$DOC"
  grep -qiE 'quick command never stands in' "$DOC"
}

@test "R167: docs/workflows.md says vbw apply takes the Lead's proposed form" {
  grep -qF 'test_files' "$FLOW"
}
