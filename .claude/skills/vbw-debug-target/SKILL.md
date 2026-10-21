---
name: vbw-debug-target
description: Use when the user reports VBW misbehavior (pasted Claude Code session output, a command behaving wrongly, unexpected .vbw state). Resolves the contributor's local debug target repo first, never a guessed path, and names where Claude Code keeps the session, subagent, hook and debug logs to replay what happened.
---

# Debugging VBW behavior

When the user reports VBW misbehavior — pasting Claude Code session output, describing incorrect command behavior, or showing unexpected file state — first resolve the contributor's **local debug target repo** instead of guessing a maintainer-specific path.

### Local debug target configuration (private, not committed)

Preferred setup in the VBW clone's shared Git common dir:

```text
$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt
```

In a standard non-worktree clone, this usually resolves to:

```text
.git/info/vbw-debug-target.txt
```

The first non-empty, non-comment line must be the absolute path to the contributor's primary VBW consumer/test repo.
Relative paths are rejected so the resolver produces the same result regardless of the caller's current working directory.

Example local file content:

```text
/absolute/path/to/your-test-repo
```

This file lives under the clone's shared Git metadata, so it stays private and all worktrees created from that clone can read it automatically.

Legacy fallback for a single checkout only:

```text
.claude/vbw-debug-target.txt
```

That legacy file remains supported and gitignored, but it is scoped to one checkout/worktree and will not be copied into new worktrees.

Resolution order:
1. `VBW_DEBUG_TARGET_REPO` env var (one-off override, absolute path only)
2. `$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt` in the current clone (preferred persistent local config, shared across worktrees)
3. `./.claude/vbw-debug-target.txt` in the current checkout/worktree (legacy fallback, absolute path only)
4. `<claude-config-dir>/vbw/debug-target.txt` (user-global fallback, absolute path only; `<claude-config-dir>` is resolved by `tools/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`)
5. If none are configured, **ask the user for the target repo path** — do not guess.

Use the shared resolver when debugging:

```bash
TARGET_REPO=$(bash tools/resolve-debug-target.sh repo)
TARGET_PLANNING=$(bash tools/resolve-debug-target.sh planning-dir)
ENCODED_PATH=$(bash tools/resolve-debug-target.sh encoded-path)
CLAUDE_PROJECT_DIR=$(bash tools/resolve-debug-target.sh claude-project-dir)
```

If the resolver exits non-zero, stop guessing and ask the user to configure a debug target.

### Claude Code Log Locations (canonical Claude config root)

In the paths below, `<claude-config-dir>` means the same Claude config root resolved by `tools/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`.

After resolving the target repo, derive the encoded Claude project path by replacing `/` with `-` in the absolute target-repo path. For an absolute path, the result begins with `-`.

Example rule:

```text
/absolute/path/to/project  ->  -absolute-path-to-project
```

When debugging, search these directories for evidence of what actually happened:

| Path | Contents | Use When |
| ------ | ---------- | ---------- |
| `<target-repo>/.vbw/` | Project state: `spec.md`, `record.json` (inspect with `vbw status` / `vbw show`) | Ground the investigation in actual workflow state |
| `<claude-config-dir>/projects/{encoded-path}/*.jsonl` | Session transcripts | Replaying what the LLM said/did in a session |
| `<claude-config-dir>/projects/{encoded-path}/{session-id}/subagents/agent-*.jsonl` | Subagent transcripts | Checking what VBW agent team members did |
| `<claude-config-dir>/projects/{encoded-path}/{session-id}/tool-results/` | Tool output snapshots | Seeing exact tool outputs from a session |
| `<claude-config-dir>/debug/{session-id}.txt` | Debug logs (`[DEBUG]`/`[WARN]`) | Startup issues, plugin loading, hook execution failures |
| `<claude-config-dir>/sessions/{pid}.json` | Active session metadata | Mapping a PID to a session ID |
| `<claude-config-dir>/session-env/{session-id}/` | Hook-exported env vars | Verifying `CLAUDE_SESSION_ID` and other env vars |
| `<claude-config-dir>/tasks/{session-id}/` | Task/subagent lock files | Checking for stuck or concurrent task issues |
| `<claude-config-dir>/settings.json` | User-level Claude Code settings and hooks | Verifying hook definitions, permissions, MCP config |

### Common search patterns

```bash
TARGET_REPO=$(bash tools/resolve-debug-target.sh repo)
CLAUDE_PROJECT_DIR=$(bash tools/resolve-debug-target.sh claude-project-dir)
CLAUDE_CONFIG_ROOT="$(dirname "$(dirname "$CLAUDE_PROJECT_DIR")")"

# Find sessions for the configured target repo
ls "$CLAUDE_PROJECT_DIR"/*.jsonl

# Search session transcripts for a VBW hook or command
grep -l 'vbw' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Find hook errors in debug logs
grep -El 'hook.*error|hook.*fail' "$CLAUDE_CONFIG_ROOT"/debug/*.txt

# Search for a specific tool invocation across sessions
grep -Erl 'vbw (next|apply|prove|run start)' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Check what a subagent did in a specific session
cat "$CLAUDE_PROJECT_DIR"/<session-id>/subagents/agent-*.jsonl
```
