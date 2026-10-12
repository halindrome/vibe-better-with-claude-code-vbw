---
name: loop
description: Let VBW work through named backlog items on its own, within a spend ceiling. Only the user can run this.
argument-hint: "ITEM... --ceiling USD [--finish-item] | ITEM... --no-ceiling | stop"
disable-model-invocation: true
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Workflow(vbw:mapping) Workflow(vbw:planning) Workflow(vbw:building) Workflow(vbw:fixing) Workflow(vbw:verifying)
hooks:
  Stop:
    - hooks:
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" auto gate 2>/dev/null || true'
---

The user ran `/vbw:loop`. Result:

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" loop start --session ${CLAUDE_SESSION_ID} $ARGUMENTS 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" loop status 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Never run `vbw loop start`, `vbw loop next` or `vbw loop park` yourself.

## The one message

`$ARGUMENTS` is `stop`: run `vbw loop stop`, then `vbw loop status`. Say what the loop was doing
(which item, which step) and that it stops before its next step. Nothing else.

The preamble refused (no armed loop in the output): say exactly why and what to do, then stop. No cycle.

Armed: one message, no questions, covering:

- the items in order, and the ceiling with its mode (stops before the next step, or finishes the item; or no ceiling);
- approval is delegated for these items only: the kernel approves their contract, you never do;
- what never happens: no push, release or publish; no work beyond the items; a `[human]` requirement waits for you to judge;
- how to stop: `/vbw:loop stop`, from any session.

End the turn after the message. The loop's Stop hook (`vbw auto gate`) then answers with the next step, each time
naming the action.

## The cycle

Read `${CLAUDE_PLUGIN_ROOT}/skills/vibe/SKILL.md` once. Do each step the hook names as its Steps section describes
it: the same workflows and the same arguments (`session`, `models`, `rigor`, `effort`, `profile` from
`VBW_SESSION_ID=${CLAUDE_SESSION_ID} vbw next --json`). Then end the turn; the hook gives the next step.

Differences from `/vbw:vibe`, as rules:

- Never arm autonomy yourself; the Stop hook is the loop's.
- The guided autonomy setting never makes the loop ask: never ask, never use the step menus.
- At `needs_decisions`, take the recommended option and record each:
  `vbw decide "<option>" "chosen by the loop: <the trade-off accepted>"`, then plan again.
- Follow no suggestion (`vbw:suggest`) on the user's behalf.
- Never run the approve command and never ask the approval menu: the kernel approves by delegation, or the loop stops.
- A `[human]` requirement is skipped by the kernel; never judge it.
- Never push, release or publish (the guard refuses it anyway).

## At every stop

A gate answer with no step, or the loop's end message: say what happened (claim only what the kernel shows) and end
with **What I need from you:** <the one thing, or "nothing">. After the loop ends, point to `.vbw/loop-report.md`
(what shipped, what was parked and why, what it cost).
