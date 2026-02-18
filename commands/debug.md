---
name: vbw:debug
category: supporting
description: Investigate a bug using the Debugger agent's scientific method protocol.
argument-hint: "<bug description or error message>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Debug: $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

Recent commits:
```
!`git log --oneline -10 2>/dev/null || echo "No git history"`
```

## Guard

- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- No $ARGUMENTS: STOP "Usage: /vbw:debug \"description of the bug or error message\""

## Steps

1. **Parse + effort:** Entire $ARGUMENTS = bug description. Map effort: thorough=high, balanced/fast=medium, turbo=low. Keep effort profile as `EFFORT_PROFILE` (thorough|balanced|fast|turbo). Read `${CLAUDE_PLUGIN_ROOT}/references/effort-profile-{profile}.md`.

2. **Classify ambiguity:** 2+ signals = ambiguous: "intermittent/sometimes/random/unclear/inconsistent/flaky/sporadic/nondeterministic" keywords, multiple root cause areas, generic/missing error, previous reverted fixes in git log. Overrides: `--competing`/`--parallel` = always ambiguous; `--serial` = never.

3. **Routing decision:** Read prefer_teams config:
```bash
PREFER_TEAMS=$(jq -r '.prefer_teams // "always"' .vbw-planning/config.json 2>/dev/null)
```

Decision tree:
- `prefer_teams='always'`: Use Path A (team) for ALL bugs, regardless of effort or ambiguity
- `prefer_teams='when_parallel'`: Use Path A (team) only if effort=high AND ambiguous, else Path B
- `prefer_teams='auto'`: Same as when_parallel (single debugger is low-risk for non-ambiguous bugs)

4. **Spawn investigation:**

**Path A: Competing Hypotheses** (prefer_teams='always' OR (effort=high AND ambiguous)):
- Generate 3 hypotheses (cause, codebase area, confirming evidence)
- Resolve Debugger model:
  ```bash
  DEBUGGER_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
  if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
  DEBUGGER_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh debugger .vbw-planning/config.json "$EFFORT_PROFILE")
  if [ $? -ne 0 ]; then echo "$DEBUGGER_MAX_TURNS" >&2; exit 1; fi
  ```
- Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
- Create Agent Team "debug-{timestamp}" via TeamCreate
- Create 3 tasks via TaskCreate, each with: bug report, ONE hypothesis only (no cross-contamination), working dir, codebase bootstrap instruction ("If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating"), instruction to report via `debugger_report` schema (see `${CLAUDE_PLUGIN_ROOT}/references/handoff-schemas.md`). **Include `[analysis-only]` in each task subject** (e.g., "Hypothesis 1: race condition in sync handler [analysis-only]") so the TaskCompleted hook skips the commit-verification gate for report-only tasks.
- Spawn 3 vbw-debugger teammates, one task each. **Add `model: "${DEBUGGER_MODEL}"` and `maxTurns: ${DEBUGGER_MAX_TURNS}` parameters to each Task spawn.**
- Wait for completion. Synthesize: strongest evidence + highest confidence wins. Multiple confirmed = contributing factors.
- Winning hypothesis with fix: apply + commit `fix({scope}): {description}`
- **HARD GATE — Shutdown before presenting results:** Send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true), re-request if rejected, then TeamDelete. Only THEN present results to user. Failure to shut down leaves agents running and consuming API credits.

**Path B: Standard** (all other cases):
- Resolve Debugger model:
  ```bash
  DEBUGGER_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
  if [ $? -ne 0 ]; then echo "$DEBUGGER_MODEL" >&2; exit 1; fi
  DEBUGGER_MAX_TURNS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh debugger .vbw-planning/config.json "$EFFORT_PROFILE")
  if [ $? -ne 0 ]; then echo "$DEBUGGER_MAX_TURNS" >&2; exit 1; fi
  ```
- Display: `◆ Spawning Debugger (${DEBUGGER_MODEL})...`
- Spawn vbw-debugger as subagent via Task tool. **Add `model: "${DEBUGGER_MODEL}"` and `maxTurns: ${DEBUGGER_MAX_TURNS}` parameters.**
```
Bug investigation. Effort: {DEBUGGER_EFFORT}.
Bug report: {description}.
Working directory: {pwd}.
If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before investigating.
Follow protocol: bootstrap (if codebase mapping exists), reproduce, hypothesize, gather evidence, diagnose, fix, verify, document.
If you apply a fix, commit with: fix({scope}): {description}.
```

4. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
```
┌──────────────────────────────────────────┐
│  Bug Investigation Complete              │
└──────────────────────────────────────────┘

  Mode:       {Path A: "Competing Hypotheses (3 parallel)" + hypothesis outcomes | Path B: "Standard (single debugger)"}
  Issue:      {one-line summary}
  Root Cause: {from report}
  Fix:        {commit hash + message, or "No fix applied"}

  Files Modified: {list}

➜ Next: /vbw:status -- View project status
```
