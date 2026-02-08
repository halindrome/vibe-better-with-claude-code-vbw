---
name: research
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch
---

# VBW Research: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current project:
```
!`cat .vbw-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

1. **No topic:** If $ARGUMENTS is empty, STOP: "Usage: /vbw:research <topic> [--parallel]"

## Steps

### Step 1: Parse arguments

- **Topic**: required, free text
- **--parallel**: spawn multiple Scout agents on sub-topics

### Step 2: Determine scope

Single focused question = one Scout. Multi-faceted or --parallel = decompose into 2-4 sub-topics.

### Step 3: Spawn Scout agent(s)

Spawn vbw-scout as subagent(s) via Task tool with thin context:

```
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
Return structured findings.
```

For parallel: spawn up to 4 Task calls simultaneously.

### Step 4: Synthesize

Single Scout: present directly.
Parallel: merge overlapping findings, note contradictions, rank by confidence.

### Step 5: Optionally persist

Ask user: "Save findings? (y/n)"
If yes: write to .vbw-planning/phases/{phase-dir}/RESEARCH.md or .vbw-planning/RESEARCH.md.

```
➜ Next Up
  /vbw:plan {N} -- Plan using research findings
  /vbw:discuss {N} -- Discuss phase approach
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Single-line box for finding sections
- ✓ high confidence, ○ medium, ⚠ low
- Next Up Block
- No ANSI color codes
