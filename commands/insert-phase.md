---
description: Insert an urgent phase between existing phases, renumbering subsequent phases.
argument-hint: <position> <phase-name> [--goal="phase goal description"]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Insert-Phase: $ARGUMENTS

## Context

Working directory: `!`pwd``

Active milestone:
```
!`cat .planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"`
```

Planning structure:
```
!`ls .planning/ 2>/dev/null || echo "Not initialized"`
```

## Guard

1. **Not initialized:** If `.planning/` directory doesn't exist, STOP: "Run /vbw:init first."

2. **Missing arguments:** If `$ARGUMENTS` doesn't include both a position number and phase name, STOP: "Usage: /vbw:insert-phase <position> <phase-name> [--goal=\"description\"]"

3. **Invalid position:** If position is less than 1 or greater than (total phases + 1), STOP: "Position {N} is out of range. Valid range: 1 to {max+1}."

4. **Position conflicts with completed phases:** If the phase at position N or any phase before it is already complete (has all SUMMARY.md files for every plan), WARN: "Phase {N} is already complete. Inserting before it will renumber completed work. Are you sure?" Require explicit confirmation before proceeding.

## Steps

### Step 1: Resolve milestone context

Determine which milestone's roadmap to modify:

1. Check if `.planning/ACTIVE` exists
2. If ACTIVE exists: read the slug, set:
   - `ROADMAP_PATH=.planning/{slug}/ROADMAP.md`
   - `PHASES_DIR=.planning/{slug}/phases`
   - `MILESTONE_NAME={slug}`
3. If ACTIVE does NOT exist (single-milestone mode): set:
   - `ROADMAP_PATH=.planning/ROADMAP.md`
   - `PHASES_DIR=.planning/phases`
   - `MILESTONE_NAME=default`
4. Read the resolved ROADMAP.md

### Step 2: Parse arguments

Extract from `$ARGUMENTS`:
- **Position:** First argument, must be a valid integer
- **Phase name:** Everything after position and before `--` flags
- **--goal flag:** Optional, extract the quoted value after `--goal=`
- **Slug generation:** Lowercase the phase name, replace spaces with hyphens, strip special characters except hyphens

### Step 3: Identify phases to renumber

1. Parse the existing ROADMAP.md to list all phases with their numbers, names, and slugs
2. Identify all phases with number >= position -- these must be renumbered
3. Each affected phase's number increases by 1 (e.g., Phase 3 becomes Phase 4)
4. The new phase takes the specified position number

Build a renumbering map:
```
Phase {position}   -> Phase {position+1}   (was: {name})
Phase {position+1} -> Phase {position+2}   (was: {name})
...
Phase {last}       -> Phase {last+1}       (was: {name})
NEW Phase {position}: {new-phase-name}
```

### Step 4: Renumber phase directories

Process in REVERSE order (rename highest-numbered first to avoid collisions):

For each phase to renumber, starting from the highest number down to `position`:

**4a. Rename directory:**
```bash
mv {PHASES_DIR}/{NN}-{slug} {PHASES_DIR}/{NN+1}-{slug}
```

**4b. Rename internal PLAN.md and SUMMARY.md files:**
Each file inside the directory follows the pattern `{phase}-{plan}-PLAN.md` or `{phase}-{plan}-SUMMARY.md`. Rename them to use the new phase number:
```bash
mv {PHASES_DIR}/{NN+1}-{slug}/{old-NN}-01-PLAN.md {PHASES_DIR}/{NN+1}-{slug}/{new-NN}-01-PLAN.md
mv {PHASES_DIR}/{NN+1}-{slug}/{old-NN}-01-SUMMARY.md {PHASES_DIR}/{NN+1}-{slug}/{new-NN}-01-SUMMARY.md
```
Repeat for all plan numbers (01, 02, 03, etc.) found in the directory.

**4c. Update YAML frontmatter in renamed files:**
For each renamed PLAN.md and SUMMARY.md file, update:
- `phase:` field to reflect the new phase directory name (e.g., `07-concurrent-milestones` instead of `06-concurrent-milestones`)

**4d. Update depends_on references:**
For each PLAN.md file that has `depends_on` entries referencing other renumbered phases within this milestone, update the references:
- `"06-01"` becomes `"07-01"` if Phase 06 was renumbered to Phase 07

**CRITICAL:** Reverse order prevents directory name collisions. If Phase 3, 4, 5 all need to shift up by 1, rename Phase 5 to Phase 6 first, then Phase 4 to Phase 5, then Phase 3 to Phase 4. Forward order would fail because renaming Phase 3 to Phase 4 would collide with the existing Phase 4 directory.

### Step 5: Update ROADMAP.md

Edit the resolved ROADMAP.md with the following changes:

**5a. Phase list:** Insert the new phase entry at the correct position and renumber all subsequent entries:
```
- [ ] **Phase {N}: {new-phase-name}** - {goal or "Urgent work -- to be planned"}
```
Update every subsequent phase entry: `Phase {old-N}` becomes `Phase {new-N}`.

**5b. Phase Details sections:** Insert a new Phase Details section at the correct position:
```markdown
### Phase {N}: {new-phase-name}
**Goal**: {goal from --goal flag, or "Urgent work -- to be planned"}
**Depends on**: Phase {N-1} ({previous phase name}, if exists)
**Requirements**: TBD
**Success Criteria** (what must be TRUE):
  1. TBD -- define via /vbw:discuss or /vbw:plan
**Plans**: 0 plans

Plans:
- [ ] TBD -- created by /vbw:plan
```

Renumber all subsequent Phase Details headers: `### Phase {old-N}:` becomes `### Phase {new-N}:`.

**5c. Update cross-references in Phase Details:**
- `Depends on:` references that point to renumbered phases must be updated
- Plan name references like `{old-NN}-01-PLAN.md` must become `{new-NN}-01-PLAN.md`

**5d. Progress table:** Insert a new row for the inserted phase and renumber subsequent rows:
```
| {N}. {new-phase-name} | 0/0 | Not started | - |
```

### Step 6: Create phase directory

Create the directory for the new phase:

```bash
mkdir -p {PHASES_DIR}/{NN}-{slug}/
```

Where `{NN}` is the zero-padded position number and `{slug}` is the generated slug.

### Step 7: Present summary

Display using brand formatting:

```
╔═══════════════════════════════════════════╗
║  Phase Inserted: {phase-name}             ║
║  Position: {N} of {total}   INSERTED      ║
╚═══════════════════════════════════════════╝

  Milestone:   {MILESTONE_NAME}
  Renumbered:  {count} phase(s) shifted

  Phase Changes:
    Phase {old} -> Phase {new}: {name}
    Phase {old} -> Phase {new}: {name}
    ...
    NEW Phase {N}: {new-phase-name}

  ✓ Updated {ROADMAP_PATH}
  ✓ Created {PHASES_DIR}/{NN}-{slug}/
  ✓ Renumbered {count} phase directories and artifacts

➜ Next Up
  /vbw:discuss {N} -- Define this urgent phase
  /vbw:plan {N} -- Plan this phase
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Use the **Phase Banner** template (double-line box) for the phase inserted banner
- Use the **Metrics Block** template for milestone/renumbered display
- Use the **File Checklist** template for the created/updated files list (✓ prefix)
- Use the **Next Up Block** template for navigation (➜ header, indented commands with --)
- Show the full renumbering map under "Phase Changes:" so the user sees what moved
- No ANSI color codes
- Keep lines under 80 characters inside boxes
