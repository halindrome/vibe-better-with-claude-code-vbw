---
name: update
description: Update VBW to the latest version.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Bash(claude plugin *)
---

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Write to the user's level, explanation depth and involvement (above; "-": plain words).

Update with Claude Code's own plugin commands, one at a time:

1. `claude plugin marketplace update vbw-marketplace`
2. `claude plugin update vbw@vbw-marketplace`

Then tell the user to run `/reload-plugins` (or restart Claude Code) so the new
version loads, and to run `/vbw:whats-new` to see what changed. If a command
fails, show its output and suggest `/plugin` to update from the menu.

VBW never checks for a new version itself. Claude Code can, with auto-update, but
it is off by default for a marketplace like VBW's. Tell the user once, after the
update: with auto-update on, Claude Code updates VBW in the background and says
"Plugin updated: vbw"; they turn it on in `/plugin` (Marketplaces tab,
`vbw-marketplace`, Enable auto-update). It is their choice, since it changes VBW's
files on disk without asking; `/vbw:doctor` shows whether it is on. Never switch it
for them.
