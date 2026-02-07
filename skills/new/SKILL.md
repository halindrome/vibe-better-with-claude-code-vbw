---
description: Define your project — name, requirements, roadmap, and initial state.
argument-hint: [project-description]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW New: $ARGUMENTS

## Context

Working directory: `!`pwd``

Existing state:
```
!`ls -la .vbw-planning 2>/dev/null || echo "No .vbw-planning directory"`
```

Project definition:
```
!`head -20 .vbw-planning/PROJECT.md 2>/dev/null || echo "No PROJECT.md"`
```

Project files:
```
!`ls package.json pyproject.toml Cargo.toml go.mod *.sln Gemfile build.gradle pom.xml 2>/dev/null || echo "No detected project files"`
```

## Guard

1. **Not initialized:** If .vbw-planning/ directory doesn't exist, STOP: "Run /vbw:init first to set up your environment."
2. **Already defined:** If .vbw-planning/PROJECT.md exists AND does NOT contain the template placeholder `{project-description}`, the project has already been defined. STOP: "Project already defined. Use /vbw:plan to plan your next phase, or pass --re-scope to redefine from scratch."
3. **Re-scope mode:** If $ARGUMENTS contains `--re-scope`, skip guard 2 and proceed (allows redefining an existing project).
4. **Brownfield detection:** If project files AND source files (*.ts, *.js, *.py, *.go, *.rs, *.java, *.rb) exist, set BROWNFIELD=true.

## Steps

### Step 1: Fill PROJECT.md

If $ARGUMENTS provided (excluding flags like --re-scope), use as project description. Otherwise ask:
- "What is the name of your project?"
- "Describe your project's core purpose in 1-2 sentences."

Fill placeholders: {project-name}, {core-value}, {date}.

### Step 2: Gather requirements

Ask 3-5 focused questions:
1. Must-have features for first release?
2. Primary users/audience?
3. Technical constraints (language, framework, hosting)?
4. Integrations or external services?
5. What is out of scope?

Populate REQUIREMENTS.md with REQ-ID format, organized into v1/v2/out-of-scope.

### Step 3: Create roadmap

Suggest 3-5 phases based on requirements. Each phase: name, goal, mapped requirements, success criteria. Fill ROADMAP.md.

### Step 4: Initialize state

Update STATE.md: project name, Phase 1 position, today's date, empty decisions, 0% progress.

### Step 4.5: Brownfield codebase summary

If BROWNFIELD=true:
1. Count source files by extension (Glob)
2. Check for test files, CI/CD, Docker, monorepo indicators
3. Add Codebase Profile section to STATE.md (if not already present from /vbw:init)

### Step 5: Generate CLAUDE.md

Follow `${CLAUDE_PLUGIN_ROOT}/references/memory-protocol.md`. Write CLAUDE.md at project root with:
- Project header (name, core value)
- Active Context (milestone, phase, next action)
- Key Decisions (empty)
- Installed Skills (from STATE.md Skills section, if exists)
- Learned Patterns (empty)
- VBW Commands section (static)

Keep under 200 lines.

### Step 6: Brownfield auto-map

If BROWNFIELD=true:
```
  ⚠ Existing codebase detected ({file-count} source files)
  ➜ Auto-launching /vbw:map to analyze your codebase...
```
Then immediately invoke `/vbw:map` by following `@${CLAUDE_PLUGIN_ROOT}/skills/map/SKILL.md`.

### Step 7: Present summary

```
╔══════════════════════════════════════════╗
║  VBW Project Defined                     ║
║  {project-name}                          ║
╚══════════════════════════════════════════╝

  ✓ .vbw-planning/PROJECT.md
  ✓ .vbw-planning/REQUIREMENTS.md
  ✓ .vbw-planning/ROADMAP.md
  ✓ .vbw-planning/STATE.md
  ✓ CLAUDE.md
```

If greenfield:
```
➜ Next Up
  /vbw:plan -- Plan your first phase
```

If brownfield and map was launched, the map skill handles its own next-up.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Phase Banner (double-line box) for completion
- File Checklist (✓ prefix) for created/updated files
- ○ for pending items
- Next Up Block for navigation
- No ANSI color codes
