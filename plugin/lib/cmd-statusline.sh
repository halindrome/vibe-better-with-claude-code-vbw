#!/usr/bin/env bash
# vbw statusline status | on | off (docs/statusline.md): the VBW status line,
# a core part of VBW. A plugin cannot set the main status line (only agent
# defaults), so /vbw:init turns it on in the user's settings.json. A status line
# the user had before is saved first, and `off` brings it back.
#
# The setting cannot name the plugin's directory: it changes with every update
# and ${CLAUDE_PLUGIN_ROOT} is not substituted in settings. So the command
# finds the newest installed VBW's scripts/vbw-statusline.sh in the plugin
# cache, except for a session that loaded a working tree (claude --plugin-dir):
# that copy's SessionStart hook recorded its folder under the session id in
# VBW's folder of the Claude config dir (R185), and a folder that still holds
# a VBW plugin renders the session instead. It runs on every render, so it
# spends processes only where needed: jq reads the session id only where that
# folder of records exists, and the installed versions are sorted only when
# there are more than one. A session that starts updates an older setting (R184).
# This is the one place VBW looks into the plugin cache (standards
# test exception, build plan K4).

VBW_STATUSLINE_CMD='sid=; _s=; for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; f=; p=; if [ -z "$_s" ] && [ -d "$_d/vbw/sessions" ]; then _s=1; sid=$(printf %s "$i" | jq -r '"'"'.session_id // empty'"'"' 2>/dev/null); case "$sid" in *[!A-Za-z0-9_-]*) sid= ;; esac; fi; [ -z "$sid" ] || { read -r p < "$_d/vbw/sessions/$sid"; } 2>/dev/null || p=; if [ -n "$p" ] && [ -f "$p/.claude-plugin/plugin.json" ] && [ -f "$p/scripts/vbw-statusline.sh" ]; then f=$p/scripts/vbw-statusline.sh; else set -- "$_d"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh; if [ $# -eq 1 ]; then f=$1; else f=$(ls -1 "$@" 2>/dev/null | sort -V | tail -1 || true); fi; fi; if [ -f "$f" ]; then printf %s "$i" | bash "$f"; rc=$?; [ "$rc" -eq 3 ] && break; exit "$rc"; fi; done'

# statusline_quote TEXT: TEXT as one single-quoted shell word.
statusline_quote() {
  local q="'" t="$1"
  printf "'%s'" "${t//$q/$q\\$q$q}"
}

# statusline_command: the command written into the setting. It reads Claude
# Code's input (with a timeout: Claude Code may send nothing and leave stdin
# open), gives it to the newest installed VBW's script, and where that script
# says "VBW is off here" (exit 3) hands the same input to the user's earlier
# status line. That line is written into the setting as quoted text, so Claude
# Code runs it, never VBW (D356). With none saved, it shows nothing.
statusline_command() {
  local prev="" body
  if [ -f "$(statusline_backup)" ]; then
    prev=$(jq -r '(if type == "object" then .command elif type == "string" then . else "" end) // ""' "$(statusline_backup)" 2> /dev/null || true)
  fi
  body='i=; while IFS= read -t 1 -r l; do i=$i$l$'"'\\n'"'; done; [ -z "$l" ] || i=$i$l; rc=0; '"$VBW_STATUSLINE_CMD"'; '
  if [ -n "$prev" ]; then
    body="${body}[ \"\$rc\" -eq 3 ] && printf %s \"\$i\" | sh -c $(statusline_quote "$prev"); "
  fi
  printf 'bash -c %s vbw\n' "$(statusline_quote "${body}exit 0")"
}

# The user's settings file, in the Claude config folder (vbw_claude_dir).
statusline_settings() {
  printf '%s/settings.json\n' "$(vbw_claude_dir)"
}

cmd_statusline() {
  local sub="${1:-status}" settings current want
  case "$sub" in
    status|on|off) [ $# -le 1 ] || vbw_usage_error "usage: vbw statusline status | on | off" ;;
    *) vbw_usage_error "usage: vbw statusline status | on | off" ;;
  esac
  settings=$(statusline_settings)
  current=""
  if [ -f "$settings" ]; then
    current=$(jq -r '.statusLine | if type == "object" then .command // "" elif type == "string" then . else "" end' "$settings" 2> /dev/null) \
      || vbw_die "cannot read $settings (not valid JSON)"
  fi
  want=$(statusline_command)
  case "$sub" in
    status)
      if [ -z "$current" ]; then printf 'off: no status line is set (vbw statusline on)\n'
      elif printf '%s' "$current" | grep 'vbw-statusline\.sh' > /dev/null; then
        if [ "$current" != "$want" ]; then printf 'on: an older VBW status line (vbw statusline on updates it)\n'
        elif statusline_refreshes "$settings"; then printf 'on: the VBW status line\n'
        else printf 'on: the VBW status line, refreshed on events only (vbw statusline on adds the 5-second refresh)\n'
        fi
      else printf 'another status line is set (vbw statusline on switches to VBW and keeps it)\n'
      fi
      ;;
    on)
      if printf '%s' "$current" | grep 'vbw-statusline\.sh' > /dev/null; then
        # Set by an older VBW: rewrite only its command, keep the interval
        # (5 when missing) and every other field; the current one stays as is.
        if [ "$current" != "$want" ] || ! statusline_refreshes "$settings"; then
          statusline_write "$settings" \
            '.statusLine |= if type == "object" then .command = $cmd | .refreshInterval = (if (.refreshInterval | type) == "number" then .refreshInterval else 5 end) else {type: "command", command: $cmd, refreshInterval: 5} end'
        fi
        printf 'on: the VBW status line\n'
        return 0
      fi
      if [ -n "$current" ]; then
        # Keep the user's own status line so that `off` can bring it back.
        jq '.statusLine' "$settings" > "$(statusline_backup)"
      fi
      # Claude Code redraws the status line on events only; the interval
      # (seconds) keeps run times and working agents current between them.
      statusline_write "$settings" '.statusLine = {type: "command", command: $cmd, refreshInterval: 5}'
      if [ -n "$current" ]; then
        printf 'on: the VBW status line replaced yours, which is saved (vbw statusline off brings it back)\n'
      else
        printf 'on: the VBW status line\n'
      fi
      ;;
    off)
      if printf '%s' "$current" | grep 'vbw-statusline\.sh' > /dev/null; then
        local backup
        backup=$(statusline_backup)
        if [ -f "$backup" ]; then
          statusline_write "$settings" '.statusLine = $prev[0]' --slurpfile prev "$backup"
          rm -f "$backup"
          printf 'off: your previous status line is back\n'
        else
          statusline_write "$settings" 'del(.statusLine)'
          printf 'off: the VBW status line was removed\n'
        fi
      else
        printf 'the VBW status line is not set; nothing changed\n'
      fi
      ;;
  esac
}

# statusline_refreshes SETTINGS: the status line has a refresh interval (VBW's
# 5 seconds, or one the user chose, which stays theirs).
statusline_refreshes() {
  jq -e '.statusLine | type == "object" and (.refreshInterval | type) == "number"' "$1" > /dev/null 2>&1
}

# Where the user's own status line is kept while VBW's is on.
statusline_backup() {
  printf '%s/vbw-statusline-previous.json\n' "$(dirname "$(statusline_settings)")"
}

# statusline_write SETTINGS FILTER [JQ OPTIONS...]: apply FILTER to the settings
# atomically, keeping every other setting.
statusline_write() {
  local file="$1" filter="$2" dir tmp
  shift 2
  dir=$(dirname "$file")
  mkdir -p "$dir"
  [ -f "$file" ] || printf '{}\n' > "$file"
  tmp=$(mktemp "$dir/settings.XXXXXX") || vbw_die "cannot write $dir"
  if ! jq --arg cmd "$(statusline_command)" ${1+"$@"} "$filter" "$file" > "$tmp"; then
    rm -f "$tmp"
    vbw_die "cannot update $file"
  fi
  mv "$tmp" "$file"
}
