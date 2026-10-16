# The VBW status line

The status line is the user's live view of VBW. Setting up a project
(`/vbw:vibe` the first time, or `/vbw:init`) turns it on; it is a core part of
VBW, not an option. The same goes for Claude Code's Dynamic workflows, which
VBW plans and builds with: `/vbw:vibe` turns them on (`vbw workflows on`) unless
the user disabled them on purpose.

```
[VBW] expenses │ M1 First milestone │ ▓▓▓▓▓▓▓░░░ 4/6 done │ ▶ build P1.2, P2.1 · 1 of 2 · until 14:20 │ ⟳ auto 3/25
Agents ● dev P1.2 sonnet  ● dev P2.1 sonnet
Context ▓▓▓░░░░░░░ 31% 62K/200K │ Tokens 2 in 195 out │ Cache 93% hit 3.8K write 55.5K read │ Cost $1.42 │ +303 −12
Limits 5h ▓▓░░░░░░░░ 23% (resets 2h13m) │ 7d ▓▓▓▓░░░░░░ 41% (resets 3d)
Sonnet 5.5 │ 10m22s (API 5m55s) │ main │ VBW 2.0.6 │ CC 2.1.286
```

1. **VBW:** the project, the milestone, a progress bar of requirements proven
   or accepted, and what is happening: a step in progress with what it is doing and when it should end
   (`▶ build P1.2, P2.1 · 1 of 2 · until 14:20`; a background proof:
   `▶ proving 12 of 40 checks · until 14:20`, counting up; an end on another day
   reads `until tomorrow 00:20`). A step with parts past its time reads
   `until 14:35, later than usual`; one without reads `until 14:20, 6 min late`.
   With fewer than 3 finished steps of the kind there is no time: `▶ build P1.2,
   P2.1 · 1 of 2`. The status line reads the time from the running step's note
   and never works it out itself (see [Time left](panel.md#time-left)). Other states: a step that needs
   the user (`needs you: approve`), or the next step (`next: prove`, from the
   last `vbw next`). `⟳ auto 3/25` while this session's autonomous run is armed (another session's is not shown). Outside a
   VBW project: `/vbw:vibe to start` (this line, then lines 3 to 5).
2. **Agents or team** (VBW projects, Claude Code before 2.1.287 only): while agents work, each one in its role's
   colour (architect magenta, lead blue, dev green, qa yellow, scout cyan,
   debugger red, docs pink) with its label and model. Otherwise the team: each role's model from the profile and
   any per-role override (`/vbw:config`), the profile, and how much VBW does on
   its own. An agent counts as working when its transcript, next to the
   session's, changed in the last minute; its `.meta.json` names its role,
   label and model. From Claude Code 2.1.287 this line is left out, because
   Claude Code itself shows the live agents and the team there; line 1 still
   counts the agents working, so the status line is four lines everywhere. The
   version comes from Claude Code's status line input (`CC` on the last line);
   when it is missing, the line stays.
3. **Context, tokens, prompt cache and cost:** the context used, the last
   request's tokens, the prompt cache hit rate with what was written and read,
   the session cost and the lines it changed.
4. **Plan limits** (5-hour and 7-day), for Pro and Max accounts.
5. **Model, time, git branch, versions.**

## How it is installed

A plugin cannot set the main status line, so `vbw statusline on` writes the
user's `settings.json` (`$CLAUDE_CONFIG_DIR`, else `~/.config/claude-code`, else
`~/.claude`). A status line the user had before is saved next to it and
`vbw statusline off` restores it. `vbw statusline status` says which is set.

The setting also asks Claude Code to re-run the status line every 5 seconds
(`statusLine.refreshInterval: 5`), on top of its event-driven redraws, so a
run's time and its working agents stay current while nothing else happens.
A run is budgeted at 60 ms (no network, no git process).

The setting changed with this version. `vbw statusline on`, and a session that
starts in a VBW project, update a setting made by an older VBW (or by VBW 1) in
place, keeping the refresh interval and the saved status line. `vbw statusline
status` says when the setting is an older one, and `vbw doctor` flags it with
`vbw statusline on` as the fix.

The setting runs the newest installed VBW's `scripts/vbw-statusline.sh` from
the plugin cache, because the plugin's directory changes with every update and
settings cannot use `${CLAUDE_PLUGIN_ROOT}`.

A session started with `claude --plugin-dir ./plugin` (a working tree of VBW)
is the exception: its status line is drawn by the working tree's script and
shows the working tree's version. Any other session shows the version of the
newest installed copy. If the working tree is moved or deleted, or is no longer
a VBW plugin, the session falls back to the installed copy.

## Projects where VBW is turned off

When a project's settings turn the plugin off, the status line does not show
VBW there. It shows the status line you had before `vbw statusline on` (the
earlier status line), or nothing shows if you had none. Nothing is written in
that project.

```json
{ "enabledPlugins": { "vbw@vbw-marketplace": false } }
```

Claude Code reads these files in this order, and the first one that sets the
plugin decides: `.claude/settings.local.json`, then `.claude/settings.json`
(both in the project), then your own `settings.json` (in the folder named
above).

VBW's script only says "off" (it exits with code 3). The setting itself then
runs the earlier status line with the same input; VBW never runs it.

Only a setting made by this version can hand back. If `vbw doctor` says the
status line was set by an older VBW, run `vbw statusline on` to update it.

## The cost side file

On each render in a VBW project, the status line writes the session's figures
from Claude Code to `.vbw/runtime/cost.SESSION.json`:

```json
{ "session": "s1", "usd": 1.4234, "in": 62000, "out": 1200, "at": "2026-10-11T21:52:15Z" }
```

`usd` is the session's total cost, `in` and `out` its total input and output
tokens, `at` the time of the render. The file goes to a temporary name and is
renamed, so a reader never sees half of it. A render with no cost figures leaves
the file as it was, and a folder that cannot be written is skipped quietly: the
status line still renders. It never writes `.vbw/record.json`.

`vbw run start` and `vbw run end` read it to work out what a run cost, and
`vbw show costs` reads it for the milestone totals (docs/costs.md).

## Engineering

- One jq program renders all the lines from Claude Code's JSON, the record,
  and VBW's runtime state (`next.json`, and the session's own `auto.SESSION.json`).
- `next.json` is the last answer of `vbw next`. It now also holds the `qa` key: each
  phase QA checks again with its reasons, and the phases that keep their pass
  (docs/next.md). The status line reads only its `action` and `gate`, so it does not
  show the reasons; `vbw show qa` does.
- It reads `.vbw/runtime/glance.json` when that is newer than the record, and
  the record otherwise (docs/record.md). The glance holds only what the status
  line shows, so the 60 ms limit holds on a record over 2 MB. Any `vbw` command
  refreshes a missing or stale glance.
- No network, no git process (the branch is read from
  `.git/HEAD`, also in linked worktrees). The one thing it writes is the cost side
  file below, never the record.
- It reads stdin with a timeout (Claude Code may send nothing on the first
  render) and never fails: a bad render prints `[VBW] status line unavailable`.
- Exit 3 is the hand-back signal: the script prints nothing and exits 3 where
  VBW is turned off. `tools/bench-hooks.sh` measures it as `status line (VBW
  off)`, within the same 60 ms.
- `NO_COLOR` turns the colors off.
