---
name: vbw:list-todos
category: supporting
description: List pending todos from STATE.md and select one to act on.
argument-hint: [priority filter]
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# VBW List Todos $ARGUMENTS

## Context

Working directory: `!`pwd``
Active milestone: `!`cat .vbw-planning/ACTIVE 2>/dev/null || echo "No active milestone (single-milestone mode)"``

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."

## Steps

1. **Resolve STATE.md path:** If the active milestone above is blank/empty or says "No active milestone", use `.vbw-planning/STATE.md`. Otherwise treat the value as the milestone slug (trim whitespace; slugs are kebab-case — reject values containing `/` or other path separators) and use `.vbw-planning/milestones/{slug}/STATE.md`. If the resolved STATE.md does not exist, STOP: "STATE.md not found at {path}. Run /vbw:init or check .vbw-planning/ACTIVE."

2. **Read todos:** Read the resolved STATE.md. Find the `### Pending Todos` subsection and extract all lines under it (stop at the next `##` or `###` heading or end of file). If `### Pending Todos` does not exist, fall back to `## Todos` and extract lines directly under it (same stop rules). If the section contains only "None." or is empty (or neither heading exists), display:
   ```
   No pending todos.

   ➜ Next Up: /vbw:todo <description> to add one
   ```
   Exit.

3. **Parse and filter:** Each todo line starts with `- `. Extract: text, priority tag (`[HIGH]`, `[low]`, or plain for normal), and date from `(added YYYY-MM-DD)`. If arguments contain a priority filter (e.g., `/vbw:list-todos high`), match case-insensitively and show only matching priority items. If filtering yields zero results, display:
   ```
   No {priority}-priority todos found.

   ➜ Next Up: /vbw:list-todos to see all
   ```
   Exit.

4. **Display list:** Show numbered list with priority and age:
   ```
   ### Pending Todos

   1. [HIGH] Add auth token refresh (3d ago)
   2. Fix modal z-index issue (1d ago)
   3. [low] Update README screenshots (5h ago)

   Reply with a number to select, or `q` to exit.
   ```
   Format age as relative time from the `(added ...)` date. If no date is parseable, omit age.

5. **Handle selection:** Wait for user to reply with a number. If invalid: "Invalid selection. Reply with a number (1-N) or `q` to exit."

6. **Show selected todo:** Display the full todo text for the selected item.

7. **Offer actions:** Use AskUserQuestion:
   - header: "Action"
   - question: "What would you like to do with this todo?"
   - options:
     - "Work on it now" — remove from Pending Todos, begin working
     - "Remove it" — remove from Pending Todos (completed or no longer needed)
     - "Go back" — return to list

8. **Execute action:**
   - **Work on it now:** Remove the todo line from `### Pending Todos` in STATE.md. If no todos remain, replace with "None." Confirm: "✓ Removed todo — ready to work." Then present the todo context and ask how to proceed.
   - **Remove it:** Remove the todo line from `### Pending Todos` in STATE.md. If no todos remain, replace with "None." Confirm: "✓ Todo removed."
   - **Go back:** Return to step 4.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — ✓ success, ➜ Next Up, no ANSI.
