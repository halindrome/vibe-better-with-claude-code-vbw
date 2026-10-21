# shellcheck shell=bash
# Claude Code's list of running chats (R192): <claude-config-dir>/sessions/<pid>.json,
# one file per running session with sessionId, cwd, name, nameSource (auto or
# derived for a name Claude Code made, anything else for the user's own /rename),
# status (busy, idle) and updatedAt (milliseconds). VBW only reads it. Load after
# helper; vbw_setup gives the hermetic CLAUDE_CONFIG_DIR the list lives under.

registry_dir() { printf '%s/sessions' "$CLAUDE_CONFIG_DIR"; }

# registry_entry PID SESSION NAME [UPDATED_MS] [CWD] [NAMESOURCE] [STATUS]: one
# entry of the list, as Claude Code 2.1.301 writes it (cwd defaults to the project).
registry_entry() {
  mkdir -p "$(registry_dir)"
  jq -nc --arg s "$2" --arg n "$3" --argjson u "${4:-1792300000000}" --arg c "${5:-$PROJECT}" --arg ns "${6:-auto}" --arg st "${7:-idle}" \
    '{sessionId: $s, cwd: $c, startedAt: ($u - 60000), version: "2.1.301", kind: "interactive", entrypoint: "cli",
      name: $n, nameSource: $ns, nameSince: ($u - 60000), updatedAt: $u, status: $st, statusUpdatedAt: $u}' \
    > "$(registry_dir)/$1.json"
}

# A session id long enough to be cut to 8 characters, and a second one.
SESSION_A=0123456789abcdef-aaaa
SESSION_B=fedcba9876543210-bbbb
