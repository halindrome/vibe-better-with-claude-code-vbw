---
name: implement
description: Plan and execute a phase in one command.
argument-hint: "[phase-number] [--effort turbo|fast|balanced|thorough] [--skip-qa]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# VBW Implement: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current state:
```
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

Phase directories:
```
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Codebase map staleness:
```
!`if [ -f .vbw-planning/codebase/META.md ]; then head -5 .vbw-planning/codebase/META.md; else echo "No codebase map"; fi`
```

## Guard

1. **Not initialized:** Follow the Initialization Guard in `${CLAUDE_PLUGIN_ROOT}/references/shared-patterns.md`.
2. **ROADMAP.md missing:** If `.vbw-planning/ROADMAP.md` does not exist, STOP: "No roadmap found. Run /vbw:new first."

3. **Auto-detect phase (if omitted):** If `$ARGUMENTS` does not contain an integer phase number:
   1. Read `${CLAUDE_PLUGIN_ROOT}/references/phase-detection.md` and follow the **Resolve Phases Directory** section.
   2. Use the **Implement Command** dual-condition detection:
      - Scan phase directories in numeric order. For each directory:
        - If NO `*-PLAN.md` files exist: this phase needs both planning and execution. Target it.
        - If `*-PLAN.md` files exist but at least one plan lacks a corresponding `*-SUMMARY.md`: this phase needs execution only. Target it.
      - The first directory matching either condition is the target.
   3. If found: announce "Auto-detected Phase {N} ({slug})" and whether it needs "plan + execute" or "execute only".
   4. If all phases are fully built: STOP: "All phases are implemented. Specify a phase: `/vbw:implement N`"

4. **Phase does not exist:** If no matching directory in `.vbw-planning/phases/`, STOP: "Phase {N} not found in roadmap."
5. **Already implemented:** If ALL plans have SUMMARY.md, WARN: "Phase {N} already implemented. Re-running will create new commits. Continue?"

## Steps

### Step 1: Parse arguments

- **Phase number** (optional; auto-detected if omitted): integer matching `.vbw-planning/phases/{NN}-*`
- **--effort** (optional): thorough|balanced|fast|turbo. Overrides config for this run only.
- **--skip-qa** (optional): skip post-build verification

### Step 2: Determine planning state

Check the phase directory for existing `*-PLAN.md` files.

- **No plans exist:** Phase needs both planning and execution. Proceed to Step 3 (Planning).
- **Plans exist but not all have SUMMARY.md:** Phase is already planned. Skip to Step 4 (Execution).
- **All plans have SUMMARY.md:** Phase is fully built. Show warning from Guard step 5.

### Step 3: Planning Phase

> This step is skipped entirely if plans already exist (Step 2 detected them).

Reference the full planning protocol from `@${CLAUDE_PLUGIN_ROOT}/commands/plan.md`.

Execute the planning flow:
1. Parse effort and resolve context (same as `/vbw:plan` Steps 1-2).
2. At **Turbo** effort: use the turbo shortcut (direct plan generation without Lead agent).
3. At all other effort levels: spawn the Lead agent for research, decomposition, and self-review.
4. Validate that PLAN.md files were produced.
5. Display a brief planning summary:

```
  Planning Complete:
    ✓ Plan 01: {title}
    ✓ Plan 02: {title}
```

**Important:** Do NOT update STATE.md to "Planned". The implement command skips the intermediate "Planned" state and goes directly to "Built" after execution completes.

### Step 4: Execution Phase

Reference the full execution protocol from `@${CLAUDE_PLUGIN_ROOT}/commands/execute.md`.

Execute the build flow:
1. Parse effort and load plans (same as `/vbw:execute` Steps 1-2).
2. Detect resume state from existing SUMMARY.md files and git log.
3. Create Agent Team and execute plans with Dev teammates (same as `/vbw:execute` Step 3).
4. Run post-build QA unless `--skip-qa` or Turbo effort (same as `/vbw:execute` Step 4).
5. Update STATE.md: mark the phase as "Built" (skipping "Planned" intermediate state).
6. Update ROADMAP.md: mark completed plans.
7. Clean up execution state.

### Step 5: Present summary

Follow the Agent Teams Shutdown Protocol in `${CLAUDE_PLUGIN_ROOT}/references/shared-patterns.md` before presenting results.

Display using `${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md`:

```
╔═══════════════════════════════════════════════╗
║  Phase {N}: {name} -- Implemented             ║
╚═══════════════════════════════════════════════╝

  Planning:
    ✓ Plan 01: {title}
    ✓ Plan 02: {title}

  Execution:
    ✓ Plan 01: {title}
    ✓ Plan 02: {title}
    ✗ Plan 03: {title} (failed)

  Metrics:
    Plans:      {completed}/{total}
    Effort:     {profile}
    Deviations: {count from SUMMARYs}

  QA:         {PASS|PARTIAL|FAIL|skipped}

➜ Next Up
  /vbw:implement {N+1} -- Implement the next phase
  /vbw:qa {N} -- Verify this phase (if QA skipped)
  /vbw:ship -- Complete the milestone (if last phase)
```

If the phase only needed execution (plans already existed), omit the Planning section from the banner.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
- Phase Banner (double-line box) for completion
- Execution Progress symbols: ◆ running, ✓ complete, ✗ failed, ○ skipped
- Metrics Block for stats
- Next Up Block for navigation
- No ANSI color codes
