---
name: todo
description: Add an item to the persistent backlog in STATE.md.
argument-hint: <todo-description> [--priority=high|normal|low]
allowed-tools: Read, Edit
---

# VBW Todo: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current state:
```
!`cat .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

## Guard

1. **Not initialized:** If .vbw-planning/ doesn't exist, STOP: "Run /vbw:init first."
2. **Missing description:** If $ARGUMENTS is empty, STOP: "Usage: /vbw:todo <description> [--priority=high|normal|low]"

## Steps

### Step 1: Resolve milestone context

If ACTIVE exists: use milestone-scoped STATE_PATH.
Otherwise: .vbw-planning/STATE.md.

### Step 2: Parse arguments

Extract description (non-flag text) and optional --priority (default: normal).

Format:
- high: `- [HIGH] {description} (added {YYYY-MM-DD})`
- normal: `- {description} (added {YYYY-MM-DD})`
- low: `- [low] {description} (added {YYYY-MM-DD})`

### Step 3: Add to STATE.md

Find `### Pending Todos` section. Replace "None." with the item, or append after last existing item.

### Step 4: Confirm

```
✓ Todo added to backlog

  {formatted todo item}

➜ Next Up
  /vbw:status -- View all todos and project state
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- ✓ for success
- Next Up Block
- No ANSI color codes
