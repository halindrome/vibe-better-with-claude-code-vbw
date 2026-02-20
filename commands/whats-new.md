---
name: vbw:whats-new
category: advanced
disable-model-invocation: true
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# VBW What's New $ARGUMENTS

## Context

Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}``

## Guard

1. **Missing changelog:** `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` missing → STOP: "No CHANGELOG.md found."

## Steps

1. Read `${CLAUDE_PLUGIN_ROOT}/VERSION` for current_version.
2. Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md`, split by `## [` headings.
   - With version arg: show entries newer than that version.
   - No args: show current version's entry.
3. Display Phase Banner "VBW Changelog" with version context, entries, Next Up (/vbw:help). No entries: "✓ No changelog entry found for v{version}."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ✓ up-to-date, Next Up, no ANSI.
