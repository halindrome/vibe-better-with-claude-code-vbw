---
name: vbw:research
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch
---

# VBW Research: $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT}``

Current project:
```
!`cat .vbw-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

- No $ARGUMENTS: STOP "Usage: /vbw:research <topic> [--parallel]"

## Steps

1. **Parse:** Topic (required). --parallel: spawn multiple Scouts on sub-topics.
2. **Scope:** Single question = 1 Scout. Multi-faceted or --parallel = 2-4 sub-topics.
3. **Spawn Scout:**
   - Resolve Scout model:
     ```bash
    RESEARCH_EFFORT=$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null)
     SCOUT_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh scout .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
     if [ $? -ne 0 ]; then echo "$SCOUT_MODEL" >&2; exit 1; fi
    SCOUT_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh scout .vbw-planning/config.json "$RESEARCH_EFFORT")
    if [ $? -ne 0 ]; then echo "$SCOUT_MAX_TURNS" >&2; exit 1; fi
     ```
   - Display: `◆ Spawning Scout (${SCOUT_MODEL})...`
  - Spawn vbw-scout as subagent(s) via Task tool. **Add `model: "${SCOUT_MODEL}"` and `maxTurns: ${SCOUT_MAX_TURNS}` parameters.**
```
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
Return structured findings.
```
  - Parallel: up to 4 simultaneous Tasks, each with same `model: "${SCOUT_MODEL}"` and `maxTurns: ${SCOUT_MAX_TURNS}`.
4. **Synthesize:** Single: present directly. Parallel: merge, note contradictions, rank by confidence.
5. **Persist:** Ask "Save findings? (y/n)". If yes: write to .vbw-planning/phases/{phase-dir}/RESEARCH.md or .vbw-planning/RESEARCH.md.
```
➜ Next Up
  /vbw:vibe --plan {N} -- Plan using research findings
  /vbw:vibe --discuss {N} -- Discuss phase approach
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
