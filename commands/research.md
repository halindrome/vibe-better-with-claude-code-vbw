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

- No $ARGUMENTS: STOP "Usage: /vbw:research <topic> [--parallel]"

## Steps

1. **Parse:** Topic (required). --parallel: spawn multiple Scouts on sub-topics.
2. **Scope:** Single question = 1 Scout. Multi-faceted or --parallel = 2-4 sub-topics.
3. **Spawn Scout:** Spawn vbw-scout as subagent(s) via Task tool:
```
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
Return structured findings.
```
Parallel: up to 4 simultaneous Tasks. Model: fast/turbo → `Model: haiku`; thorough/balanced → inherit session model.
4. **Synthesize:** Single: present directly. Parallel: merge, note contradictions, rank by confidence.
5. **Persist:** Ask "Save findings? (y/n)". If yes: write to .vbw-planning/phases/{phase-dir}/RESEARCH.md or .vbw-planning/RESEARCH.md.
```
➜ Next Up
  /vbw:vibe --plan {N} -- Plan using research findings
  /vbw:vibe --discuss {N} -- Discuss phase approach
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
