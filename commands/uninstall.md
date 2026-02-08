---
name: uninstall
disable-model-invocation: true
description: Cleanly remove all VBW traces from the system before plugin uninstall.
allowed-tools: Read, Write, Edit, Bash, Glob
---

# VBW Uninstall

## Context

Settings file:
```
!`cat ~/.claude/settings.json 2>/dev/null || echo "{}"`
```

Project planning directory:
```
!`ls -d .vbw-planning 2>/dev/null && echo "EXISTS" || echo "NONE"`
```

CLAUDE.md:
```
!`ls CLAUDE.md 2>/dev/null && echo "EXISTS" || echo "NONE"`
```

## Steps

### Step 1: Confirm intent

Display:
```
╔══════════════════════════════════════════╗
║  VBW Uninstall                           ║
╚══════════════════════════════════════════╝

This will remove all VBW system-level configuration.
Project files (.vbw-planning/, CLAUDE.md) are handled separately.
```

Ask the user to confirm they want to proceed.

### Step 2: Clean statusLine from settings.json

Read `~/.claude/settings.json`. Check if the `statusLine` field exists and its `command` value (or string value) contains `vbw-statusline`.

If it does:
1. Remove the entire `statusLine` key from the JSON
2. Write the file back
3. Display "✓ Statusline removed from settings.json"

If it doesn't contain `vbw-statusline`, skip: "○ Statusline is not VBW's — skipped"

If `statusLine` doesn't exist, skip silently.

### Step 3: Clean Agent Teams env var

Check if `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` exists in `~/.claude/settings.json`.

If it does, ask:
```
○ Agent Teams is enabled in settings.json. This was set by VBW but
  is a Claude Code feature that other tools may use.
  Remove it?
```

If user approves: remove `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from settings. If the `env` object is then empty, remove the `env` key entirely. Display "✓ Agent Teams setting removed"

If user declines: display "○ Agent Teams setting kept"

### Step 4: Project data

If `.vbw-planning/` exists, ask:
```
○ Found .vbw-planning/ in this project.
  This contains your project roadmap, requirements, and planning state.

  a) Keep it (recommended — your planning data is preserved)
  b) Delete it (permanently removes all VBW planning artifacts)
```

If user chooses delete: `rm -rf .vbw-planning/` and display "✓ .vbw-planning/ deleted"
If user chooses keep: display "○ .vbw-planning/ preserved"

If `.vbw-planning/` doesn't exist, skip silently.

### Step 5: CLAUDE.md cleanup

If `CLAUDE.md` exists at project root, ask:
```
○ Found CLAUDE.md with VBW content.

  a) Keep it (other tools may use CLAUDE.md)
  b) Delete it
```

If user chooses delete: remove the file. Display "✓ CLAUDE.md deleted"
If user chooses keep: display "○ CLAUDE.md preserved"

If `CLAUDE.md` doesn't exist, skip silently.

### Step 6: Summary and next step

Display:
```
╔══════════════════════════════════════════╗
║  VBW Cleanup Complete                    ║
╚══════════════════════════════════════════╝

  {✓ or ○ for each step performed}

➜ Final Step
  Run this command to remove the plugin:

  /plugin uninstall vbw@vbw-marketplace

  Then optionally remove the marketplace:

  /plugin marketplace remove vbw-marketplace
```

**IMPORTANT:** Do NOT run the plugin uninstall command yourself. The user must run it manually because `/vbw:uninstall` is part of the plugin — running the uninstall from within would remove itself mid-execution.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
- Phase Banner (double-line box) for header and completion
- File Checklist (✓ prefix) for completed cleanup steps
- ○ for skipped items
- Next Up Block for the final uninstall command
- No ANSI color codes
