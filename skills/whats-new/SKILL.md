---
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# VBW What's New $ARGUMENTS

## Guard

1. **Missing changelog:** If `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` does not exist, STOP: "No CHANGELOG.md found."

## Steps

### Step 1: Read version

Read `${CLAUDE_PLUGIN_ROOT}/VERSION` for `current_version`.

### Step 2: Determine mode

Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md`. Split by `## [` headings.

- If $ARGUMENTS has a version string: show all entries **newer than** that version.
- If no arguments: show the **current version's entry** (the entry matching `current_version`).

### Step 3: Display

If entries found:
```
╔═══════════════════════════════════════════╗
║  VBW Changelog                            ║
║  {If args: "Since {arg_version}" | If no args: "v{current_version}"}  ║
╚═══════════════════════════════════════════╝

{changelog entries}

➜ Next Up
  /vbw:help -- View all commands
```

If no matching entries:
```
✓ No changelog entry found for v{current_version}.

➜ Next Up
  /vbw:help -- View all commands
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Double-line box for header
- ✓ for up-to-date
- Next Up Block
- No ANSI color codes
