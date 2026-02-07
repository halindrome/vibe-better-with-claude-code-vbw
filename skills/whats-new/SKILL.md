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

### Step 2: Determine baseline

If $ARGUMENTS has a version string: use as `baseline_version`.
Otherwise: use `current_version`.

### Step 3: Parse changelog

Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md`. Split by `## [` headings. Collect entries newer than baseline.

### Step 4: Display

If new entries:
```
╔═══════════════════════════════════════════╗
║  VBW Changelog                            ║
║  Since {baseline_version}                 ║
╚═══════════════════════════════════════════╝

{changelog entries}

➜ Next Up
  /vbw:update -- Update to latest version
```

If no new entries:
```
✓ You are on the latest version ({current_version}).

➜ Next Up
  /vbw:help -- View all commands
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md:
- Double-line box for header
- ✓ for up-to-date
- Next Up Block
- No ANSI color codes
