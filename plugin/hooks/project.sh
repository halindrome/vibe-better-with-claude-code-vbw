# shellcheck shell=bash
# Sourced by the hook scripts and the status line (docs/guards.md): the one
# definition, for them, of the project a session belongs to. The guard commands
# in hooks.json repeat the same loop inline, so a missing file can never stop
# a guard. Every part of VBW finds the project the way the kernel does
# (vbw_git_root: git rev-parse --show-toplevel), so a session started in a
# subfolder of a VBW project is a VBW session.

# vbw_project_of DIR: sets root to the project of a session started in DIR: the
# nearest folder at or above DIR that holds .git (a folder, or the file of a
# linked worktree or a submodule), never above /; DIR itself when none does.
# No process: [ -e ] tests and parameter expansion, for the hot paths. It is a
# VBW project when $root/.vbw/record.json exists.
# shellcheck disable=SC2034 # root is the function's answer, read by the caller
vbw_project_of() {
  root=$1
  local d=$1
  while [ "$d" != / ] && [ -n "$d" ] && [ ! -e "$d/.git" ]; do
    case "$d" in */*) d=${d%/*}; d=${d:-/} ;; *) d=/ ;; esac
  done
  [ ! -e "$d/.git" ] || root=$d
}

# vbw_vbw_above DIR: sets vbwdir to the nearest folder at or above DIR that holds
# a .vbw folder, never above /; empty when none does. Walked like vbw_project_of,
# no process, so the hand-back outside a VBW project stays cheap.
# shellcheck disable=SC2034 # vbwdir is the function's answer, read by the caller
vbw_vbw_above() {
  vbwdir=""
  local d=$1
  while [ -n "$d" ]; do
    if [ -d "$d/.vbw" ]; then vbwdir=$d; return 0; fi
    [ "$d" != / ] || return 0
    case "$d" in */*) d=${d%/*}; d=${d:-/} ;; *) return 0 ;; esac
  done
}
