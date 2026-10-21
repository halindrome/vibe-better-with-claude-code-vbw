# Updating VBW

VBW makes no network call of its own: it does not look for new versions, send
anything anywhere, or run a background check. Updating is Claude Code's
plugin mechanism, and so is hearing that a new version is out.

## Update now

```
/vbw:update
```

It runs Claude Code's two plugin commands, one at a time:

```
claude plugin marketplace update vbw-marketplace
claude plugin update vbw@vbw-marketplace
```

Then run `/reload-plugins` (or restart Claude Code) so the new version loads. A
running session keeps the version it started with.

## Be told, and updated, without asking: auto-update

Claude Code can refresh a marketplace and update the plugins you installed from it
in the background. **For a marketplace like VBW's (`vbw-marketplace`) it is off
until you turn it on.** Only Anthropic's own marketplaces start with it on.
While it is off, nothing tells you a new VBW is out.

Turn it on in a Claude Code session:

```
/plugin
```

Open the **Marketplaces** tab, select `vbw-marketplace`, and select **Enable
auto-update**. (In a settings file, the same switch is `"autoUpdate": true` next to
`source` in the marketplace's `extraKnownMarketplaces` entry.)

With it on, after your first message in a session Claude Code waits a random time of
up to ten minutes, then refreshes the marketplace and updates VBW on disk. You see:

```
Plugin updated: vbw · Run /reload-plugins to apply
```

The running session keeps the old version; the next session loads the new one.

It is your choice, and VBW never switches it for you: an auto-updated plugin's files
change on disk without asking. Claude Code's own `DISABLE_UPDATES`,
`DISABLE_AUTOUPDATER` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` switch plugin
auto-update off too (unless `FORCE_AUTOUPDATE_PLUGINS=1` is set).

`/vbw:doctor` shows whether auto-update is on for `vbw-marketplace`, and what to do
when it is not. Without it, run `/vbw:update` now and then, or watch the
[releases](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases).

Claude Code's reference: [Keep plugins updated](https://code.claude.com/docs/en/plugins/install#keep-plugins-updated)
and [When auto-update runs](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs).

## After an update: what changed

The first time a session starts in a VBW project after VBW was updated, VBW says so
once:

```
VBW updated from 2.0.40 to 2.0.41. /vbw:whats-new shows what changed.
```

`/vbw:whats-new` reads the changelog in plain words: what you can do now that you
could not before, and anything you need to do.

How it works, with no network call: each session compares the version of the plugin it
runs with the highest version this clone's sessions have seen. The latter is one line in
the clone's git folder (`.git/vbw/seen-version`, shared by its worktrees and never
committed). A newer plugin offers `/vbw:whats-new` and records itself, so each update is
offered once per project. The first session in a clone only records. An older plugin
offers nothing and the highest version stays. A copy loaded with `claude --plugin-dir`
(a working tree) neither offers nor records.
