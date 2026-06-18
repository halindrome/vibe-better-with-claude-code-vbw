# Fork Readiness Ledger

**Purpose:** keep a hard fork of VBW a few hours away, not a few weeks — without taxing
ongoing upstream contribution. This branch (`integrated`) is
the **designated hard-fork base**: it carries upstream `main` plus all of our unmerged work.
Local-only — never pushed to upstream (`swt-labs`).

> Status as of 2026-06-18: option open, not exercised. We still PR to upstream.

## Remote topology

| Remote | Points to | Role |
| :--- | :--- | :--- |
| `origin` | `halindrome/vibe-better-with-claude-code-vbw` (our fork) | our branches push here |
| `upstream` | `swt-labs/vibe-better-with-claude-code-vbw` (MIT, root repo) | PR target |
| `yidakee` | `yidakee/vibe-better-with-claude-code-vbw` (original author) | `dev` + a few branches track |

(Note: the repo's `CLAUDE.md` "Git Workflow" section is stale — it describes a single
`origin` with direct push to swt-labs. Reality is the three remotes above.)

## Fork health (verify periodically)

- `origin/main` vs `upstream/main`: should stay **0 ahead / 0 behind** (live mirror).
- `integrated` vs `upstream/main`: **N ahead / 0 behind**
  (as of 2026-06-18: +89 / 0). The "0 behind" is the important invariant — it means this
  branch is a current base, not a stale snapshot. Rebase on upstream main regularly.

## Carried vs merged

This branch = everything. Individual carried items live as atomic `fix/*` and `feat/*`
branches on `origin` (one PR each). To see what is carried but not yet in upstream:
`git log --oneline upstream/main..HEAD`. Keep patches atomic and cherry-pickable so each can
upstream independently *or* be carried indefinitely.

## License

MIT. A hard fork is legally trivial — retain `LICENSE` and the existing copyright notice.
No permission required.

## The pivotal decision: drop-in replacement vs coexist

Claude Code namespaces slash commands, agents, and hooks by **plugin name only** (`/vbw:*`,
`vbw:vbw-scout`), NOT by marketplace. The plugin *cache* is keyed by both
(`plugins/cache/<marketplace>/<plugin>/<version>/`), so cache files never clobber — but two
plugins both named `vbw` **cannot be enabled simultaneously** without command/agent
namespace collision. (Verdict from inspecting `installed_plugins.json` + cache layout;
not yet doc-confirmed.)

Two fork modes follow from this:

### Mode A — Drop-in replacement (cheap, ~half day)
Users uninstall upstream `vbw` and install ours. **Keep `name: "vbw"`**; change only the
distribution identity (marketplace name/owner). Near-zero ripple — no command/agent/state
rename. This is the likely intent for "upstream won't merge our PRs, run our own VBW."

### Mode B — Coexist with upstream (expensive, ~2h+ rename + state migration)
Both installable at once. **Must rename the plugin** `name: "vbw"` → e.g. `vbwx`, which
ripples through everything below. Only choose this if users genuinely need both side by side.

## Rename checklist (Mode B only)

- `.claude-plugin/plugin.json` — `name`, `author`
- `.claude-plugin/marketplace.json` + root `marketplace.json` — `name`, `owner`, `plugins[]`
- `commands/*.md` frontmatter — `name: vbw:*` → `vbwx:*` (all slash command prefixes)
- `agents/vbw-*.md` — file names + any `Task(vbw-*)` / `agentType: 'vbw:vbw-*'` references
  (incl. workflow scripts in `commands/map.md`, `commands/debug.md`, `references/workflow-executor.md`)
- `hooks/hooks.json` + `scripts/*` — any literal `vbw` / `vbw-marketplace/vbw` cache-glob refs
  (plugin-root resolution cascade globs `plugins/cache/vbw-marketplace/vbw/*`)
- `.vbw-planning/` state directory — rename + update every reference. **Highest-risk item:**
  breaks existing consumer project state; needs a migration shim or a documented reset.
- Tests under `testing/` and `tests/` that assert `vbw` literals.

## Distribution (either mode)

- Publish a marketplace from the fork repo (`marketplace.json` at repo root already present).
- Users: `claude plugin marketplace add halindrome/vibe-better-with-claude-code-vbw`,
  then install the plugin. (Confirm exact CLI syntax against current Claude Code docs.)
- Pre-picked marketplace name: **TBD** (decide now to avoid a crunch-time blocker, e.g.
  `vbwx-marketplace` / `halindrome-vbw`).

## Version + CI on divergence

- Version: the 4-file sync (`VERSION`, `plugin.json`, both `marketplace.json`) + `bump-version.sh`
  + pre-push consistency hook still apply. Diverge with a fork suffix (e.g. `1.37.1-hal.1`).
- CI: review `.github/workflows` for upstream-specific context (release notify, required
  checks) and adapt.

## Maintenance posture NOW (keep the option cheap)

1. Keep this branch green and rebased on `upstream/main`. It is the instant fork base.
2. Keep every patch atomic / cherry-pickable.
3. Do **not** rename the plugin pre-emptively — it taxes every upstream PR with rename noise.
4. Decide the marketplace name and the Mode A/B intent before trigger time, not during.
