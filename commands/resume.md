---
name: vbw:resume
category: supporting
disable-model-invocation: true
description: Restore project context from .vbw-planning/ state.
argument-hint:
allowed-tools: Read, Bash, Glob
---

# VBW Resume

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; _p=$(ls -1d "$_d"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1 || true); [ -n "$_p" ] && [ -d "$_p" ] && echo "$_p" && break; done')}``

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **No roadmap:** ROADMAP.md missing → STOP: "No roadmap found. Run /vbw:vibe."

## Steps

1. **Read ground truth:** PROJECT.md (name, core value), STATE.md (decisions, todos, blockers), ROADMAP.md (phases), Glob *-PLAN.md + *-SUMMARY.md (plan/completion counts), .execution-state.json (interrupted builds), most recent SUMMARY.md (last work), RESUME.md (session notes). Skip missing files.
2. **Compute progress:** Per phase: count PLANs vs SUMMARYs → not started | planned | in progress | complete. Current phase = first incomplete.
3. **Detect interrupted builds:** If .execution-state.json status="running": all SUMMARYs present = completed since last session; some missing = interrupted.
4. **Present dashboard:** Phase Banner "Context Restored / {project name}" with: core value, phase/progress, overall progress bar, key decisions, todos, blockers (⚠), last completed, build status (✓ completed / ⚠ interrupted), session notes. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh resume`.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, Metrics Block, ⚠ warnings, ✓ completions, ➜ Next Up, no ANSI.
