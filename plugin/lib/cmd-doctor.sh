#!/usr/bin/env bash
# vbw doctor: everything VBW needs, one line each, with the fix for anything
# wrong. Exit 0 when nothing is wrong (warnings allowed), 1 otherwise. Changes
# nothing.

# shellcheck source=cmd-statusline.sh
. "$VBW_LIB/cmd-statusline.sh"
# shellcheck source=sessions.sh
. "$VBW_LIB/sessions.sh"

VBW_MIN_CLAUDE=2.1.286

cmd_doctor() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw doctor"
  DOCTOR_FAILED=0
  doctor_tools
  doctor_path
  doctor_claude
  doctor_sessions
  doctor_statusline
  if VBW_ROOT=$(git rev-parse --show-toplevel 2> /dev/null); then
    doctor_project
  else
    doctor_line info "not inside a git repository: project checks skipped"
  fi
  [ "$DOCTOR_FAILED" -eq 0 ]
}

# doctor_line ok|warn|fail|info MESSAGE [FIX]
doctor_line() {
  local mark
  case "$1" in ok) mark="✓" ;; warn) mark="!" ;; fail) mark="✗"; DOCTOR_FAILED=1 ;; *) mark="·" ;; esac
  printf '%s %s\n' "$mark" "$2"
  [ -z "${3:-}" ] || printf '    fix: %s\n' "$3"
}

# version_at_least HAVE NEED: dotted numeric comparison.
version_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$2" ]
}

doctor_tools() {
  local v
  v=$(jq --version 2> /dev/null | sed 's/^jq-//; s/-.*//')
  if [ -z "$v" ]; then doctor_line fail "jq is missing" "install jq (brew install jq / apt install jq)"
  elif version_at_least "$v" 1.6; then doctor_line ok "jq $v"
  else doctor_line fail "jq $v is too old (VBW needs 1.6 or later)" "update jq"
  fi
  v=$(git --version 2> /dev/null | awk '{print $3}')
  if [ -n "$v" ]; then doctor_line ok "git $v"; else doctor_line fail "git is missing" "install git"; fi
  # VBW commits as the user: without a name and email, git may refuse (or
  # guess one from the machine name).
  if [ -n "$v" ]; then
    if [ -n "$(git config user.name 2> /dev/null)" ] && [ -n "$(git config user.email 2> /dev/null)" ]; then
      doctor_line ok "git knows who you are ($(git config user.name))"
    else
      doctor_line warn "git has no name or email set: VBW's commits may fail" "git config --global user.name \"Your Name\" && git config --global user.email you@example.com"
    fi
  fi
}

# The loaded plugin: the folder the session start recorded for this session
# while it still holds a VBW plugin, else the plugin of this kernel. The vbw on
# PATH should be that plugin's.
doctor_path() {
  local loaded=$VBW_PLUGIN rec on_path pv lv
  rec=$(head -n 1 "$(vbw_claude_dir)/vbw/sessions/${CLAUDE_CODE_SESSION_ID:-none}" 2> /dev/null || true)
  [ -z "$rec" ] || [ ! -f "$rec/.claude-plugin/plugin.json" ] || loaded=$rec
  lv=$(jq -r '.version // "unknown"' "$loaded/.claude-plugin/plugin.json" 2> /dev/null || echo unknown)
  if ! on_path=$(command -v vbw 2> /dev/null) || [ -z "$on_path" ]; then
    doctor_line warn "no vbw on PATH (the loaded plugin is $loaded, version $lv)" "run $loaded/bin/vbw, or put $loaded/bin on PATH"
    return 0
  fi
  pv=$(jq -r '.version // "unknown"' "${on_path%/*}/../.claude-plugin/plugin.json" 2> /dev/null || echo unknown)
  if [ "$(cd "${on_path%/*}/.." 2> /dev/null && pwd -P)" = "$(cd "$loaded" 2> /dev/null && pwd -P)" ]; then
    doctor_line ok "vbw on PATH: $on_path (version $pv), the loaded plugin's"
  else
    doctor_line warn "vbw on PATH is $on_path (version $pv), not the loaded plugin's: $loaded (version $lv)" "run $loaded/bin/vbw, or put $loaded/bin first on PATH"
  fi
}

doctor_claude() {
  local v settings=() f wf=""
  v=$(claude --version 2> /dev/null | awk '{print $1}') || v=""
  if [ -z "$v" ]; then doctor_line warn "Claude Code version unknown (the claude command is not on PATH here)"
  elif version_at_least "$v" "$VBW_MIN_CLAUDE"; then doctor_line ok "Claude Code $v"
  else doctor_line fail "Claude Code $v is older than VBW needs ($VBW_MIN_CLAUDE)" "update Claude Code"
  fi
  # Workflows: off by default on the Pro plan; the setting wins when present.
  if [ -n "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" ]; then
    doctor_line fail "workflows are disabled (CLAUDE_CODE_DISABLE_WORKFLOWS)" "unset CLAUDE_CODE_DISABLE_WORKFLOWS"
    return 0
  fi
  settings=("$(statusline_settings)")
  [ -z "${VBW_ROOT:-}" ] || settings+=("$VBW_ROOT/.claude/settings.json" "$VBW_ROOT/.claude/settings.local.json")
  for f in "${settings[@]}"; do
    [ -f "$f" ] || continue
    jq -e '.disableWorkflows == true' "$f" > /dev/null 2>&1 && wf=off
    [ "$wf" = off ] || ! jq -e '.enableWorkflows == true' "$f" > /dev/null 2>&1 || wf=on
  done
  local mode=""
  for f in "${settings[@]}"; do
    [ -f "$f" ] || continue
    mode=$(jq -r '.permissions.defaultMode // empty' "$f" 2> /dev/null || true)
    [ -z "$mode" ] || break
  done
  case "$mode" in
    auto) doctor_line ok "Claude Code starts in auto permission mode" ;;
    bypassPermissions) doctor_line ok "Claude Code starts in bypassPermissions mode" ;;
    *) doctor_line warn "Claude Code starts in ${mode:-manual} permission mode (a session switched to auto mode with Shift+Tab is fine; in manual mode every agent step asks you first)" "to start in auto mode, set permissions.defaultMode to \"auto\" in $(statusline_settings)" ;;
  esac
  case "$wf" in
    on) doctor_line ok "workflows enabled" ;;
    off) doctor_line fail "workflows are disabled in your settings (disableWorkflows)" "remove disableWorkflows, then turn on Dynamic workflows in /config" ;;
    *) doctor_line warn "workflows: Claude Code's default (off on some plans)" "vbw workflows on" ;;
  esac
}

doctor_sessions() {
  local dir n
  dir="$(vbw_claude_dir)/sessions"
  if [ -d "$dir" ] && [ -r "$dir" ]; then
    n=$(sessions_registry | jq 'length' 2> /dev/null || echo 0)
    doctor_line ok "session names: Claude Code's list of chats ($dir) is readable, $n entries"
  else
    doctor_line info "session names: Claude Code's list of chats ($dir) not found: run holders are shown by their id"
  fi
}

doctor_statusline() {
  local state
  state=$(cmd_statusline status 2> /dev/null)
  case "$state" in
    *"an older VBW status line"*) doctor_line warn "the VBW status line was set by an older VBW (it cannot hand back to your earlier status line)" "vbw statusline on" ;;
    *"refreshed on events only"*) doctor_line warn "the VBW status line refreshes on events only, so it can look frozen while a workflow runs" "vbw statusline on" ;;
    on:*) doctor_line ok "VBW status line" ;;
    *) doctor_line warn "the VBW status line is not on" "vbw statusline on" ;;
  esac
}

doctor_project() {
  VBW_DIR="$VBW_ROOT/.vbw"
  VBW_RECORD="$VBW_DIR/record.json"
  [ ! -d "$VBW_ROOT/.vbw-planning" ] \
    || doctor_line info "VBW 1 project data (.vbw-planning/) is here; VBW 2 does not use it"
  if [ ! -f "$VBW_RECORD" ]; then
    doctor_line info "not a VBW project yet (/vbw:init)"
    return 0
  fi
  local v n
  if n=$(record_newer_schema "$VBW_RECORD"); then
    doctor_line fail "this project needs a newer VBW: its record was written with schema $n, this VBW reads up to schema $VBW_SCHEMA_MAX" "update VBW with /vbw:update"
    return 0
  elif v=$(record_violation "$VBW_RECORD"); then doctor_line ok "the plan of record is valid"
  else doctor_line fail "the plan of record is corrupt: $v" "restore .vbw/record.json from git (git checkout -- .vbw/record.json)"
  fi
  # shellcheck source=cmd-spec.sh
  . "$VBW_LIB/cmd-spec.sh"
  if spec_parse > /dev/null 2>&1; then doctor_line ok "the spec is valid"
  else doctor_line fail "the spec has errors" "vbw spec check shows them"
  fi
  [ -n "$v" ] && return 0
  if jq -e '.lease != null' "$VBW_RECORD" > /dev/null; then
    doctor_line warn "a run is open ($(jq -r .lease.run "$VBW_RECORD"))" "if no VBW workflow is running: vbw run end"
  fi
  if contract_approved "$(contract_hash "$(cat "$VBW_RECORD")")"; then doctor_line ok "the contract is approved"
  elif jq -e '(.checks | length) > 0' "$VBW_RECORD" > /dev/null; then
    doctor_line info "the contract is not approved (yet, or since it changed): VBW asks with the approval menu after you review it"
  fi
  doctor_guard
}

# The guard works with this jq: it must deny a destructive command here.
doctor_guard() {
  local out g=/dev/null d="${VBW_RECORD%/*}/runtime/glance.json"
  if [ -f "$VBW_RECORD" ] && [ -f "$d" ] && [ -r "$d" ] && [ "$d" -nt "$VBW_RECORD" ]; then g=$d; fi
  out=$(jq -nc --arg d "$VBW_ROOT" '{tool_name: "Bash", cwd: $d, tool_input: {command: "git reset --hard"}}' \
    | jq -nc --rawfile glance "$g" --arg root "$VBW_ROOT" -f "$VBW_PLUGIN/hooks/guard-bash.jq" - "$VBW_RECORD" "$VBW_PLUGIN/hooks/end.json" 2> /dev/null)
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1; then doctor_line ok "the guards work"
  else doctor_line fail "the guards do not work with this jq" "update jq, then run vbw doctor again"
  fi
}
