---
name: plan
description: "Scope new work or plan a specific phase. No args with no phases starts scoping; otherwise plans the next unplanned phase."
argument-hint: [phase-number] [--effort=thorough|balanced|fast|turbo]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Plan: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current state:
```
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook (effort, autonomy, verification_tier). Override with --effort flag.

Phase directories:
```
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Active milestone:
```
!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "NO_ACTIVE_MILESTONE"`
```

Codebase map staleness:
```
!`bash -c 'f=$(ls -1 "$HOME"/.claude/plugins/cache/vbw-marketplace/vbw/*/scripts/map-staleness.sh 2>/dev/null | sort -V | tail -1); [ -f "$f" ] && exec bash "$f" || echo "status: no_script"'`
```

## Mode Detection

Resolve the phases directory first:
- If `.vbw-planning/ACTIVE` exists, read its contents for the milestone slug and use `.vbw-planning/{milestone-slug}/phases/`
- Otherwise use `.vbw-planning/phases/`

Evaluate in order. The FIRST matching condition determines the mode:

| # | Condition | Mode |
|---|-----------|------|
| 1 | $ARGUMENTS contains an integer phase number | Phase Planning Mode (skip to Phase Auto-Detection with that number) |
| 2 | No phase directories exist in the resolved phases path (empty or missing) | Scoping Mode |
| 3 | Phase directories exist | Phase Planning Mode (existing behavior via Phase Auto-Detection) |

## Scoping Mode

> Triggered when $ARGUMENTS has no phase number AND no phase directories exist.

### Scoping Guard

1. **Not initialized:** Follow the Initialization Guard in `${CLAUDE_PLUGIN_ROOT}/references/shared-patterns.md`.
2. **No project:** If .vbw-planning/PROJECT.md doesn't exist or contains template placeholder `{project-description}`, STOP: "No project defined. Run /vbw:implement to set up your project."

### Scoping Steps

**Step S1: Load project context**

Read `.vbw-planning/PROJECT.md` and `.vbw-planning/REQUIREMENTS.md` to understand the project. If `.vbw-planning/codebase/` exists, read INDEX.md and ARCHITECTURE.md for codebase context.

**Step S2: Gather scope**

If $ARGUMENTS provided (excluding flags like --effort), use as scope description. Otherwise ask:

"What do you want to build next? Describe the work you want to accomplish."

If REQUIREMENTS.md has uncovered requirements (not yet mapped to phases), present them as suggestions.

**Step S3: Decompose into phases**

Based on the user's answer and existing requirements:
1. Propose 3-5 phases with name, goal, and success criteria
2. Each phase should be independently plannable and executable
3. Map requirements (REQ-IDs) to phases where applicable

**Step S4: Write roadmap and create phase directories**

Update ROADMAP.md with the proposed phases. Create phase directories in the resolved phases path (`.vbw-planning/phases/{NN}-{slug}/` for each phase).

**Step S5: Update state**

Update STATE.md: set position to Phase 1, status to "Pending planning".

**Step S6: Transition**

Announce scoping complete and re-evaluate. Since phases now exist, announce readiness to plan:

```
Scoping complete. {N} phases created.

Next Up
  /vbw:plan -- Plan the first phase
  /vbw:implement -- Plan and execute the first phase
```

STOP here. Do NOT auto-continue to phase planning. The scoping flow is complete -- the user decides the next action.

## Phase Planning Mode

> Reached when Mode Detection routes to Phase Planning Mode (either explicit phase number or phases exist).

If `$ARGUMENTS` does not contain an integer phase number:

1. Read `${CLAUDE_PLUGIN_ROOT}/references/phase-detection.md` for the detection protocol
2. Resolve the phases directory: if `.vbw-planning/ACTIVE` exists, read its contents to get the milestone slug and use `.vbw-planning/{milestone-slug}/phases/`; otherwise use `.vbw-planning/phases/`
3. Scan phase directories in numeric order (`01-*`, `02-*`, ...). Find the first phase with NO `*-PLAN.md` files
4. If found: announce "Auto-detected Phase {N} ({slug}) -- next phase to plan" and proceed with that phase number
5. If all phases have plans: STOP and tell user "All phases are planned. Specify a phase to re-plan: `/vbw:plan N`"

## Guard

1. **Not initialized:** Follow the Initialization Guard in `${CLAUDE_PLUGIN_ROOT}/references/shared-patterns.md`.
2. **No roadmap:** If .vbw-planning/ROADMAP.md doesn't exist or still contains template placeholders, STOP: "No roadmap found. Run /vbw:implement to set up your project."
3. **Phase not in roadmap:** If phase {N} doesn't exist in ROADMAP.md, STOP: "Phase {N} not found in roadmap."
4. **Already planned:** If phase has PLAN.md files with SUMMARY.md files, WARN: "Phase {N} already has completed plans. Re-planning preserves existing plans with .bak extension."

## Staleness Check

Read the staleness data from the Context block above. This is advisory only — never block planning.

- `status: stale` → Print: `⚠ Codebase map is {staleness} stale ({changed} files changed). Consider /vbw:map before planning.`
- `status: no_map` → Print: `○ No codebase map. Run /vbw:map for better planning context.`
- `status: fresh` → Print: `✓ Codebase map is fresh ({staleness} changed)`
- `status: no_git` or `status: no_script` → Skip silently.

Then continue to Step 1.

## Steps

### Step 1: Parse arguments

- **Phase number** (optional — auto-detected if omitted): integer
- **--effort** (optional): thorough|balanced|fast|turbo. Falls back to config default.

### Step 2: Turbo mode shortcut

If effort = turbo: skip Lead agent. Read phase requirements from ROADMAP.md. Create a single lightweight PLAN.md with all tasks in one plan. Write to phase directory. Skip to Step 5.

### Step 3: Spawn Lead agent

Display:
```
◆ Planning Phase {N}: {phase-name}
  Effort: {level}
  Spawning Lead agent...
```

Spawn vbw-lead as a subagent via the Task tool with thin context:

```
Plan phase {N}: {phase-name}.
Roadmap: .vbw-planning/ROADMAP.md
Requirements: .vbw-planning/REQUIREMENTS.md
State: .vbw-planning/STATE.md
Project: .vbw-planning/PROJECT.md
Patterns: .vbw-planning/patterns/PATTERNS.md (if exists)
Codebase map: .vbw-planning/codebase/ (if exists)
  Read INDEX.md, ARCHITECTURE.md, CONCERNS.md for codebase context.
Effort: {level}
Output: Write PLAN.md files to .vbw-planning/phases/{phase-dir}/
```

The Lead reads all files itself -- no content embedding in the task description.

Display after Lead returns: `✓ Lead agent complete`

### Step 4: Validate Lead output

Display: `◆ Validating plan artifacts...`

Verify:
- At least one PLAN.md exists in the phase directory
- Each has valid YAML frontmatter (phase, plan, title, wave, depends_on, must_haves)
- Each has tasks with name, files, action, verify, done
- Wave assignments have no circular dependencies

If validation fails, report issues to user.

### Step 5: Update state and present summary

Update STATE.md: phase position, plan count, status = Planned.

Display using `${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md`:

```
╔═══════════════════════════════════════════╗
║  Phase {N}: {name} -- Planned             ║
╚═══════════════════════════════════════════╝

  Plans:
    ○ Plan 01: {title}  (wave {W}, {task-count} tasks)
    ○ Plan 02: {title}  (wave {W}, {task-count} tasks)

  Effort: {profile}

➜ Next Up
  /vbw:execute {N} -- Execute this phase
  /vbw:implement {N} -- Plan and execute (if using implement workflow)
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
- Phase Banner (double-line box) for completion
- File Checklist (✓ prefix) for validation
- ○ for plans ready to execute
- Next Up Block for navigation
- No ANSI color codes
