#!/usr/bin/env bats
# R192 (L1): the user docs state the facts of naming the run's holder: the
# read-only access to Claude Code's list of chats (docs/guards.md), where the name
# lives and the lease shape (docs/workflows.md, docs/record.md), the status line's
# `leading` and `held by` cells (docs/statusline.md), Comms, the Now box,
# /vbw-why and the Sessions tab (docs/panel.md), and the rename hint (docs/next.md).
# Facts a reader needs, not exact sentences (D400).

load helper

GUARDS="$REPO_ROOT/docs/guards.md"
WORKFLOWS="$REPO_ROOT/docs/workflows.md"
RECORD="$REPO_ROOT/docs/record.md"
STATUSLINE="$REPO_ROOT/docs/statusline.md"
PANEL="$REPO_ROOT/docs/panel.md"
NEXT="$REPO_ROOT/docs/next.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$1 lacks: $2"; return 1; }; }

@test "R192: docs/guards.md names the list of chats as VBW's one read outside the project, read-only, beside the three writes" {
  local line
  line=$(grep -F 'writes nothing outside the project' "$GUARDS")
  [ -n "$line" ]
  grep -qF '<claude-config-dir>/sessions/' "$GUARDS"
  has "$GUARDS" '<claude-config-dir>/sessions/[^.]*(read|reads|read-only)'
  has "$GUARDS" 'sessions/[^.]*never writ'
}

@test "R192: docs/workflows.md says the record's lease keeps its shape and the name lives in holder.json and the glance" {
  grep -qF '{run, kind, started_at, session, files}' "$WORKFLOWS"
  has "$WORKFLOWS" 'session_name'
  has "$WORKFLOWS" '\.vbw/runtime/holder\.json'
  has "$WORKFLOWS" 'holder\.json[^.]*(never|not)[^.]*record'
}

@test "R192: docs/record.md names the glance's holder field and that the record never carries the name" {
  has "$RECORD" 'glance\.json[^|]*`holder`'
  has "$RECORD" 'session_name'
}

@test "R192: docs/statusline.md shows the run cell's leading and held by forms, with the 20-character cut" {
  grep -qF '· leading' "$STATUSLINE"
  grep -qF '· held by' "$STATUSLINE"
  has "$STATUSLINE" 'held by[^.]*20'
  has "$STATUSLINE" 'sessions/'
}

@test "R192: docs/panel.md lists the Sessions tab with its short name and describes its rows" {
  grep -qE '^Now │ Plan │ Proof │ Timeline │ Decisions │ Team │ Sessions │ Costs' "$PANEL"
  has "$PANEL" 'Sess '
  grep -qiE '^#+ .*sessions' "$PANEL"
  has "$PANEL" 'holds the run'
  has "$PANEL" 'this chat'
  has "$PANEL" 'closed or not seen'
  has "$PANEL" 'claude --resume'
  has "$PANEL" 'No other chats are open on this project'
}

@test "R192: docs/panel.md describes Comms' run-started line, the Now box's held by, and /vbw-why by name" {
  has "$PANEL" 'run started by'
  has "$PANEL" 'held by'
  has "$PANEL" 'vbw-why[^|]*\|[^|]*(name|by)'
}

@test "R192: docs/next.md describes rename_hint: when it comes, once per project, never applied" {
  has "$NEXT" 'rename_hint'
  has "$NEXT" '/rename vbw'
  has "$NEXT" 'rename_hint[^.]*(once|second chat|another chat)|(once|second chat|another chat)[^.]*rename_hint'
  has "$NEXT" 'never (runs|applies)'
}

@test "R192: docs/panel.md's /vbw-why row names the holder by name and keeps the file count and wait for it" {
  local row
  row=$(grep -F '| `/vbw-why`' "$PANEL")
  [ -n "$row" ]
  echo "$row" | grep -qF 'held by this chat'
  echo "$row" | grep -qF 'wait for it'
  echo "$row" | grep -qi 'file count'
}
