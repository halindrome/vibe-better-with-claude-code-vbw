---
name: suggest
description: Offer the user at most three suggestions at three moments: when requirements are proposed (spec proposal), right after triage adds requirements to the active milestone, and when a plan is presented for approval. Used by the vibe router at those moments only.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *)
effort: low
---

# Suggest

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" suggest list 2>&1 || true
```

Above: the user's answers (level, explanation depth, involvement) and the
suggestions already declined in this project.

## When

Three moments, named:

- At spec proposal (with the proposed requirements).
- Right after triage adds requirements to the active milestone, before the first planning run.
- At plan approval (with the plan).

Never offer or ask mid-run, mid-build, during a run, or while a step is working;
the user is not interrupted for ideas.

## What

At most three suggestions, each one yes or no. None is required: zero is valid,
and when nothing worth raising exists, say nothing about suggestions. Never pad
to reach three.

Match them to the user's level and explanation depth: for a first-time builder,
plain outcomes ("Should visitors be able to find the page by searching?"); for a
senior engineer, terse technical ones (rate limiting, migrations, observability).
With no interview answers, stay neutral: plain and brief.

Before offering, read `vbw show requirements` and `vbw show decisions`. Never
offer a duplicate of a requirement or a decision, and never offer one whose text
matches the declined list above.

## Answers

Ask with AskUserQuestion, one question per suggestion. The user may decline any.

At spec proposal and after triage the options stay "Yes", "No": a yes costs
nothing there, because the first planning run has not started. Say so when it
helps the user decide. A yes to a testable outcome: `vbw spec add auto|human
"statement"` (as the router does for any requirement).

At plan approval a suggestion that would add a requirement costs a new planning
run. The question states the cost of a yes: `a new planning run: <detail.replan
from vbw next --json>` (the sentence the router passes in). It offers exactly:

- add to the backlog (Recommended): `vbw todo add --sort next --size <small|medium|large> "<text>"`.
- add to this milestone (replan): `vbw spec add auto|human "statement"`, then
  planning again and a new approval.
- no: `vbw suggest decline "<the suggestion's exact text>"`.

A choice or constraint costs no replan, so it keeps "Yes", "No" at every moment:

- Yes: `vbw decide "<what>" "<why: accepted on suggestion>"`.
- No: `vbw suggest decline "<the suggestion's exact text>"`.

A declined suggestion is never offered again in this project; never offer it
again, reworded or not.
