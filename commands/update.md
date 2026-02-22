---
name: vbw:update
category: advanced
disable-model-invocation: true
description: Update VBW to the latest version with automatic cache refresh.
argument-hint: "[--check]"
allowed-tools: Read, Bash, Glob
---

# VBW Update $ARGUMENTS

## Context

Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(bash -c 'ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1')}``

**Resolve config directory:** Try in order: env var `CLAUDE_CONFIG_DIR` (if set and directory exists), `~/.config/claude-code` (if exists), otherwise `~/.claude`. Store result as `CLAUDE_DIR`. Use for all config paths below.

## Steps

### Step 1: Read current INSTALLED version

Read the **cached** version (what user actually has installed):
```bash
for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; v=$(cat "$_d"/plugins/cache/vbw-marketplace/vbw/*/VERSION 2>/dev/null | sort -V | tail -1 || true); [ -n "$v" ] && echo "$v" && break; done
```
Store as `old_version`. If empty, fall back to `${CLAUDE_PLUGIN_ROOT}/VERSION`.

**CRITICAL:** Do NOT read `${CLAUDE_PLUGIN_ROOT}/VERSION` as primary — in dev sessions it resolves to source repo (may be ahead), causing false "already up to date."

### Step 2: Handle --check

If `--check`: display version banner with installed version and STOP.

### Step 3: Check for update

```bash
curl -sf --max-time 5 "https://raw.githubusercontent.com/yidakee/vibe-better-with-claude-code-vbw/main/VERSION"
```
Store as `remote_version`. Curl fails → STOP: "⚠ Could not reach GitHub to check for updates."
If remote == old: display "✓ Already at latest (v{old_version}). Refreshing cache..." Continue to Step 4 for clean cache refresh.

### Step 4: Nuclear cache wipe

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-nuke.sh
```
Removes CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw/, CLAUDE_DIR/commands/vbw/, /tmp/vbw-* for pristine update.

### Step 5: Perform update

Same version: "Refreshing VBW v{old_version} cache..." Different: "Updating VBW v{old_version}..."

**CRITICAL: All `claude plugin` commands MUST be prefixed with `unset CLAUDECODE &&`** — without this, Claude Code detects the parent session's env var and blocks with "cannot be launched inside another Claude Code session."

**Refresh marketplace FIRST** (stale checkout → plugin update re-caches old code):
```bash
unset CLAUDECODE && claude plugin marketplace update vbw-marketplace 2>&1
```
If fails: "⚠ Marketplace refresh failed — trying update anyway..."

Try in order (stop at first success):
- **A) Platform update:** `unset CLAUDECODE && claude plugin update vbw@vbw-marketplace 2>&1`
- **B) Reinstall:** `unset CLAUDECODE && claude plugin uninstall vbw@vbw-marketplace 2>&1 && unset CLAUDECODE && claude plugin install vbw@vbw-marketplace 2>&1`
- **C) Manual fallback:** display commands for user to run manually, STOP.

**Clean stale global commands** (after A or B succeeds):
```bash
for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; rm -rf "$_d/commands/vbw" 2>/dev/null; done
```
This removes stale copies that break `${CLAUDE_PLUGIN_ROOT}` resolution. Commands load from the plugin cache where `${CLAUDE_PLUGIN_ROOT}` is guaranteed.

### Step 5.5: Ensure VBW statusline

Read `CLAUDE_DIR/settings.json`, check `statusLine` (string or object .command). If contains `vbw-statusline`: skip. Otherwise update to:
```json
{"type": "command", "command": "bash -c 'for _d in \"${CLAUDE_CONFIG_DIR:-}\" \"$HOME/.config/claude-code\" \"$HOME/.claude\"; do [ -z \"$_d\" ] && continue; f=$(ls -1 \"$_d\"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1 || true); [ -f \"$f\" ] && exec bash \"$f\"; done'"}
```
Use jq to write (backup, update, restore on failure). Display `✓ Statusline restored (restart to activate)` if changed.

### Step 6: Verify update

```bash
NEW_CACHED=$(for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; v=$(cat "$_d"/plugins/cache/vbw-marketplace/vbw/*/VERSION 2>/dev/null | sort -V | tail -1 || true); [ -n "$v" ] && echo "$v" && break; done)
```
Use NEW_CACHED as authoritative version. If empty or equals old_version when it shouldn't: "⚠ Update may not have applied. Try /vbw:update again after restart."

### Step 7: Display result

Use NEW_CACHED for all display. Same version = "VBW Cache Refreshed" banner + "Changes active immediately". Different = "VBW Updated" banner with old→new + "Changes active immediately" + "/vbw:whats-new" suggestion.

**Edge case:** If Step 6 verification failed (NEW_CACHED empty/unchanged when upgrade expected): keep restart suggestion as diagnostic fallback.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ✓ success, ⚠ fallback warning, Next Up, no ANSI.
