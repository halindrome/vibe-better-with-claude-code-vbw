#!/usr/bin/env bash
# VBW's read-only view of Claude Code's list of chats (R192):
# <claude-config-dir>/sessions/*.json, one file per running session. It is the
# only thing VBW reads outside the project. A name taken from it is kept on this
# computer only (.vbw/runtime/holder.json), never in the record (D442).

# sessions_registry: a JSON array of the list's entries (objects with a string
# sessionId). Malformed files are skipped; [] when the folder is missing or
# unreadable. Exit 0 always.
sessions_registry() {
  local dir f files=()
  dir="$(vbw_claude_dir)/sessions"
  for f in "$dir"/*.json; do
    [ -f "$f" ] && files+=("$f")
  done
  if [ ${#files[@]} -eq 0 ]; then
    printf '[]\n'
    return 0
  fi
  jq -Rn -c '[inputs | {f: input_filename, l: .}] | group_by(.f)
    | map(map(.l) | join("\n") | try fromjson catch empty)
    | map(select(type == "object" and (.sessionId | type) == "string"))' \
    "${files[@]}" 2> /dev/null || printf '[]\n'
  return 0
}

# sessions_name SID: the newest updatedAt entry's name, cleaned, or nothing.
sessions_name() {
  [ -n "${1:-}" ] || return 0
  sessions_registry | jq -r --arg s "$1" "$(cat "$VBW_LIB/holder.jq")"'
    [.[] | select(.sessionId == $s)] | sort_by(.updatedAt | if type == "number" then . else 0 end) | last
    | (.name // null) | clean_name | select(length > 0)' 2> /dev/null || true
  return 0
}

# sessions_project_entries ROOT: the entries whose cwd is ROOT or a folder under it.
sessions_project_entries() {
  sessions_registry | jq -c --arg r "${1%/}" '[.[] | select((.cwd | type) == "string"
    and (.cwd | rtrimstr("/")) as $c | $c == $r or ($c | startswith($r + "/")))]' 2> /dev/null || printf '[]\n'
  return 0
}

holder_file() { printf '%s/holder.json' "$VBW_RUNTIME"; }

# holder_write RUN SID: .vbw/runtime/holder.json {run, session, session_name}
# (session_name null when unknown), through a temporary name and a rename.
holder_write() {
  local name tmp
  name=$(sessions_name "$2")
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || return 0
  tmp=$(mktemp "$VBW_RUNTIME/holder.XXXXXX" 2> /dev/null) || return 0
  vbw_guard_add file "$tmp"
  if jq -nc --arg r "$1" --arg s "$2" --arg n "$name" \
    '{run: $r, session: $s, session_name: (if $n == "" then null else $n end)}' > "$tmp" 2> /dev/null; then
    mv "$tmp" "$(holder_file)" 2> /dev/null || true
  fi
  vbw_guard_drop "$tmp"
  rm -f "$tmp" 2> /dev/null || true
  return 0
}

holder_clear() { rm -f "$(holder_file)" 2> /dev/null || true; }

# holder_display SID: the display name of the holder: the list's live name, else
# holder.json's name (only when its session is SID), else 8 characters of the id.
holder_display() {
  local live
  live=$(sessions_name "${1:-}")
  jq -rn --arg s "${1:-}" --arg live "$live" --rawfile h <(cat "$(holder_file)" 2> /dev/null || true) \
    "$(cat "$VBW_LIB/holder.jq")"'
    ($h | try fromjson catch null) as $f
    | holder_name({session: $s}; (if ($f | type) == "object" and $f.session == $s then $f.session_name else null end); $live)'
}
