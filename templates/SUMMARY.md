---
phase: {NN} # bare integer, no quotes
plan: {plan-number}
title: {plan-title}
status: {complete|partial|failed}
completed: {YYYY-MM-DD}
tasks_completed: {N}
tasks_total: {N}
commit_hashes:
  - {hash}
deviations:
  - "{deviation-description}"
# Authoritative no-known-issues signal. When present, consumers must not fall back to a legacy body section.
pre_existing_issues: []
# Harness/orchestration/environment workarounds that are NOT plan deviations (e.g.
# workflow-worker registration, build-race retries, sandbox/hook-robust invocations,
# a commit re-applied after parallel-plan branch interleaving). Informational only —
# NOT counted by the deviation gate. Keep genuine plan/convention divergences in
# `deviations:` above. Default to [] when there are none.
environment_notes: []
# Acceptance criteria reconciliation. Omit ac_results entirely when plan has no must_haves.
ac_results:
  - criterion: "{from must_haves: truths[] text, artifacts[] path+provides, or key_links[] from→to}"
    verdict: "{pass|fail|partial}"
    evidence: "{commit hash, file path, or test name}"
---

{one-line-substantive-summary}

## What Was Built

- {deliverable-1}
- {deliverable-2}

## Files Modified

- `{file-path}` -- {action}: {purpose}

## Deviations

{deviations-or-none}

## Environment Notes

{environment-notes-or-none}
