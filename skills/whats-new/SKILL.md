---
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# VBW What's New $ARGUMENTS

## Context

Loaded version (may be stale if just updated):
```
!`cat ${CLAUDE_PLUGIN_ROOT}/VERSION 2>/dev/null || echo "unknown"`
```

Latest cached version:
```
!`ls -d ~/.claude/plugins/cache/vbw-marketplace/vbw/*/ 2>/dev/null | sort -V | tail -1 | xargs -I{} cat {}.claude-plugin/plugin.json 2>/dev/null | jq -r '.version // "unknown"'`
```

## Guard

1. **Missing changelog:** Find CHANGELOG.md in the latest cache directory first, then fall back to `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md`. If neither exists, STOP: "No CHANGELOG.md found."

## Steps

### Step 1: Read versions

Detect the latest installed version by checking the newest directory in `~/.claude/plugins/cache/vbw-marketplace/vbw/`. Read its `.claude-plugin/plugin.json` for `current_version`. Fall back to `${CLAUDE_PLUGIN_ROOT}/VERSION` if the cache check fails.

### Step 2: Determine baseline

If $ARGUMENTS has a version string: use as `baseline_version`.
Otherwise: use `current_version`.

### Step 3: Parse changelog

Read CHANGELOG.md from the latest cached version directory first, falling back to `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md`. Split by `## [` headings. Collect entries newer than baseline.

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
