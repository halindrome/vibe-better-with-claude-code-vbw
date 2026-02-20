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
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; _p=$(ls -1d "$_d"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1 || true); [ -n "$_p" ] && [ -d "$_p" ] && echo "$_p" && break; done')}``

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Missing description:** STOP: "Usage: /vbw:todo <description> [--priority=high|normal|low]"

## Steps

1. **Resolve context:** Always use `.vbw-planning/STATE.md` for todos — project-level data lives at the root, not in milestone subdirectories. If `.vbw-planning/STATE.md` does not exist:
   - **Archived milestones exist** (any `.vbw-planning/milestones/*/STATE.md`): Recover by running `bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-orphaned-state.sh .vbw-planning` — this picks the most recent archived milestone by modification time and creates root STATE.md.
   - **No STATE.md anywhere:** STOP: "STATE.md not found. Run /vbw:init to set up your project."
2. **Parse args:** Description (non-flag text), --priority (default: normal). Format: high=`[HIGH]`, normal=plain, low=`[low]`. Append `(added {YYYY-MM-DD})`.
3. **Add to STATE.md:** Find `## Todos` section. Replace "None." / placeholder or append after last item.
4. **Confirm:** Display ✓ + formatted item + Next Up (/vbw:status).

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, Next Up, no ANSI.
