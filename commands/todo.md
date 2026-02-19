---
name: vbw:todo
category: supporting
disable-model-invocation: true
description: Add an item to the persistent backlog in STATE.md.
argument-hint: <todo-description> [--priority=high|normal|low]
allowed-tools: Read, Edit
---

# VBW Todo: $ARGUMENTS

## Context

Working directory: `!`pwd``
Active milestone: `!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Missing description:** STOP: "Usage: /vbw:todo <description> [--priority=high|normal|low]"

## Steps

1. **Resolve context:** Always use `.vbw-planning/STATE.md` for todos — project-level data lives at the root, not in milestone subdirectories. If `.vbw-planning/STATE.md` does not exist, STOP: "STATE.md not found. Run /vbw:init to set up your project."
2. **Parse args:** Description (non-flag text), --priority (default: normal). Format: high=`[HIGH]`, normal=plain, low=`[low]`. Append `(added {YYYY-MM-DD})`.
3. **Add to STATE.md:** Find `## Todos` section. Replace "None." / placeholder or append after last item.
4. **Confirm:** Display ✓ + formatted item + Next Up (/vbw:status).

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, Next Up, no ANSI.
