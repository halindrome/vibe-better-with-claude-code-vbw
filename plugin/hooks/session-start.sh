#!/usr/bin/env bash
# SessionStart: in a VBW project (the session's project directory holds
# .vbw/record.json, as for the guard), tell the model where the project stands
# and what comes next, in one line. Started in a subdirectory of a VBW project:
# say that the guards are off. Never a resume directive (ledger D289).
#
# Also, in every session: remove VBW 1's command copies (build plan K15).

# Without jq VBW can neither build its answer nor run its kernel (and the VBW 1
# reload notice below needs jq too): end quietly, like the per-tool-call hooks.
command -v jq > /dev/null 2>&1 || exit 0

root=${CLAUDE_PROJECT_DIR:-$PWD}
vbw="${0%/*}/../bin/vbw"

# VBW 1 copied its commands to <claude-dir>/commands/vbw/. User commands take
# precedence over plugin skills, so those copies would run VBW 1 instead of
# /vbw:init, /vbw:vibe and the rest (ledger D290). Only the config directory
# this session uses can shadow its commands, so only that one is cleaned
# ($CLAUDE_CONFIG_DIR, else ~/.config/claude-code if present, else ~/.claude).
# Remove only VBW's own copies (frontmatter "name: vbw:..."), and the directory
# once empty.
removed=0
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  claude_dir=$CLAUDE_CONFIG_DIR
elif [ -d "$HOME/.config/claude-code" ]; then
  claude_dir="$HOME/.config/claude-code"
else
  claude_dir="$HOME/.claude"
fi
if [ -d "$claude_dir/commands/vbw" ]; then
  for f in "$claude_dir/commands/vbw"/*.md; do
    [ -f "$f" ] || continue
    if awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && /^---$/ { exit 1 } /^name: vbw:/ { found = 1; exit } END { exit !found }' "$f"; then
      rm -f "$f" && removed=$((removed + 1))
    fi
  done
  rmdir "$claude_dir/commands/vbw" 2> /dev/null || true
fi

context="" notice=""

# Which copy of VBW is this? A copy loaded with claude --plugin-dir is named
# vbw@inline, so Claude Code gives its hooks a plugin data folder named
# vbw-inline; an installed copy gets vbw-vbw-marketplace (probe, R185).
plugin=${CLAUDE_PLUGIN_ROOT:-}
[ -n "$plugin" ] || plugin=$(cd "${0%/*}/.." 2> /dev/null && pwd) || plugin=${0%/*}/..
kernel=$plugin/bin/vbw
kversion=$(jq -r '.version // empty' "$plugin/.claude-plugin/plugin.json" 2> /dev/null || true)
loaded=0
[ "${CLAUDE_PLUGIN_DATA##*/}" != "vbw-inline" ] || loaded=1

# The hook's input arrives on stdin as one JSON line; Claude Code may leave
# the pipe open, so never wait for its end.
input="" line=""
while IFS= read -t 1 -r line; do input=$input$line; done
input=$input$line
sid=$(printf '%s' "$input" | jq -r '.session_id // "" | if test("^[A-Za-z0-9_-]+$") then . else "" end' 2> /dev/null || true)

# A loaded copy puts its own bin/ first on PATH for the session (the env file
# is read before each Bash tool command; one line, quoted for sh, bash and zsh)
# and records its folder for the session id (the status line and doctor read
# it). An installed copy writes no PATH line and drops its session's record
# (the same session resumed without the tree). Records older than 7 days go.
sessions=$claude_dir/vbw/sessions
if [ -d "$sessions" ]; then
  find "$sessions" -type f -mtime +7 -exec rm -f {} + 2> /dev/null || true
fi
if [ "$loaded" -eq 1 ]; then
  q="'"
  if [ -n "${CLAUDE_ENV_FILE:-}" ] && { printf 'export PATH=%s:"$PATH"\n' "'${plugin//$q/$q\\$q$q}/bin'" >> "$CLAUDE_ENV_FILE"; } 2> /dev/null; then
    :
  else
    notice="VBW could not put this loaded copy first on PATH (Claude Code gave no writable env file), so a plain vbw may run an installed release. Run ${kernel} instead."
    context="${context}VBW could not put the loaded copy first on PATH: run ${kernel} instead of vbw in this session. Tell the user once. "
  fi
  if [ -n "$sid" ]; then
    { mkdir -p "$sessions" && printf '%s\n' "$plugin" > "$sessions/$sid"; } 2> /dev/null || true
  fi
elif [ -n "$sid" ]; then
  rm -f "$sessions/$sid" 2> /dev/null || true
fi
[ "$removed" -eq 0 ] || context="VBW removed $removed outdated VBW 1 command copies that would have run instead of the VBW 2 commands. Tell the user once: run /reload-skills now (or restart Claude Code) before using any /vbw: command, because this session loaded the old copies. "

if [ -f "$root/.vbw/record.json" ]; then
  state=$(cd "$root" && "$vbw" status 2>&1 < /dev/null)
  newer=$?
  state=$(printf '%s\n' "$state" | head -n 1)
  if [ "$newer" -eq 4 ]; then
    # Written by a newer VBW: nothing works until VBW is updated (exit 4).
    context="${context}VBW project made by a newer VBW (${state#vbw: }). Tell the user once: update VBW with /vbw:update, then restart Claude Code; VBW cannot work on this project until then."
    notice="This project was made by a newer VBW. Update with /vbw:update, then restart Claude Code."
  else
    # VBW's status line set by an older VBW (an old command or no refresh interval): update it
    # (only VBW's own line; `on` keeps every other setting).
    case $("$vbw" statusline status 2> /dev/null) in
      *"refreshed on events only"* | *"an older VBW status line"*) "$vbw" statusline on > /dev/null 2>&1 || true ;;
    esac
    next=$(cd "$root" && "$vbw" next 2>&1 < /dev/null | head -n 1)
    context="${context}VBW project ($state). Next: $next. Continue with /vbw:vibe. The vbw command is on PATH (vbw help); this session's kernel is ${kernel}${kversion:+ (version $kversion)}."
  fi
elif [ -d "$root/.vbw-planning" ]; then
  context="${context}This project has a VBW 1 plan (.vbw-planning/). Tell the user once: VBW 2 leaves it untouched, and /vbw:vibe or /vbw:convert brings it into VBW 2 through a few questions."
else
  top=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null || true)
  if [ -n "$top" ] && [ -f "$top/.vbw/record.json" ]; then
    context="${context}This session started inside the VBW project at $top, not at its root, so the VBW guards are off. Tell the user to start Claude Code at $top."
  fi
fi

# The copies were loaded before this hook ran, so this session still has them:
# the user must reload before typing a /vbw: command. A systemMessage reaches
# the user at once; the context alone would wait for their first prompt.
[ "$removed" -eq 0 ] || notice="VBW 2 removed the old VBW 1 commands. Type /reload-skills (or restart Claude Code) before using any /vbw: command.${notice:+ $notice}"

[ -z "$context" ] || jq -n --arg c "$context" --arg n "$notice" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}} + (if $n == "" then {} else {systemMessage: $n} end)'
