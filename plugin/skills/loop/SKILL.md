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

Tell the user in one or two sentences what the kernel answered: the loop is
armed (which items, which ceiling), it refused (say exactly why and what to
do), or `stop` was given (the loop is off). Never run `vbw loop start`,
`vbw loop next` or `vbw loop park` yourself.
