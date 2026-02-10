---
name: assumptions
description: Surface Claude's implicit assumptions about a phase before planning begins.
argument-hint: [phase-number]
allowed-tools: Read, Glob, Grep, Bash
---

# VBW Assumptions: $ARGUMENTS

## Context

Working directory: `!`pwd``

Roadmap:
```
!`head -50 .vbw-planning/ROADMAP.md 2>/dev/null || echo "No roadmap found"`
```

Codebase signals:
```
!`ls package.json pyproject.toml Cargo.toml go.mod 2>/dev/null || echo "No detected project files"`
```

Phase state:
```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase-detect.sh 2>/dev/null || echo "phase_detect_error=true"`
```

## Guard

- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- **Phase resolution** (no explicit number): Phase detection is pre-computed in Context above. Scan numerically for first phase with NO `*-PLAN.md`. Found: announce "Auto-detected Phase {N} ({slug})". All planned: STOP "All phases planned. Specify: `/vbw:assumptions N`"
- Phase not in roadmap: STOP "Phase {N} not found."

## Steps

1. **Load context:** Read ROADMAP.md, REQUIREMENTS.md, PROJECT.md, STATE.md, CONTEXT.md (if exists), codebase signals.
2. **Generate 5-10 assumptions** by impact: scope (included/excluded), technical (implied approaches), ordering (sequencing), dependency (prior phases), user preference (defaults without stated preference).
3. **Gather feedback:** Per assumption: "Confirm, correct, or expand?" Confirm=proceed, Correct=user provides answer, Expand=user adds nuance.
4. **Present:** Group by status (confirmed/corrected/expanded). This command does NOT write files. For persistence: "Run /vbw:discuss {N} to capture as CONTEXT.md." Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh assumptions` and display.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: numbered list (order=priority), ✓ confirmed, ✗ corrected, ○ expanded, Next Up Block, no ANSI.
