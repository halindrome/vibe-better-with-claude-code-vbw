#!/usr/bin/env bash
# What a run reads in its own clean copy (docs/proof.md, R166). Before a run
# the access time (atime, the time the system notes when a file is read) of
# every tracked file and folder of the copy, and of the copy's own git HEAD
# and index files, is set back with touch -a to an old date. After it, what
# moved forward was read: a file was opened, a folder was listed, git was used.
# A file a run writes remembers that run's read list; a later run in the same
# copy that reads it adds that list to its own.
#
# Per slot a state folder (outside the copy) holds: gitdir, files and dirs (the
# tracked paths, "./"-prefixed, NUL-separated), ref (modification and access
# time set to the old date plus a day: the yardstick "read since" compares
# with), mark (just before the run started: "written since"), wlist (written
# files the reset set back) and written.json (path -> read list).

# The old date, for touch -t (local time), and its epoch bound: a set-back time
# is before 1 January 2001 whatever the time zone.
READS_OLD=200001010000
READS_OLD_DAY=200001020000
READS_OLD_BOUND=978307200

# reads_atime PATH: access time in epoch seconds (GNU stat first; BSD's
# `stat -f` means file system status on Linux). Only a number, 0 when unreadable.
reads_atime() {
  local t
  t=$(stat -c %X "$1" 2> /dev/null) || t=$(stat -f %a "$1" 2> /dev/null) || t=0
  case "$t" in "" | *[!0-9]*) t=0 ;; esac
  printf '%s\n' "$t"
}

# reads_probe DIR: the start-of-proof test of the file system DIR is on. A
# file's access time is set back and must stay there; reading the file and
# listing a folder must then move it forward.
reads_probe() {
  local p ok=0 a
  p=$(mktemp -d "$1/probe.XXXXXX" 2> /dev/null) || ok=1
  if [ "$ok" -eq 0 ]; then
    printf 'x\n' > "$p/f" 2> /dev/null || ok=1
    touch -a -t "$READS_OLD" "$p/f" "$p" 2> /dev/null || ok=1
    a=$(reads_atime "$p/f")
    [ "$ok" -ne 0 ] || [ "$a" -lt "$READS_OLD_BOUND" ] || ok=1
    [ "$(reads_atime "$p")" -lt "$READS_OLD_BOUND" ] || ok=1
    if [ "$ok" -eq 0 ]; then
      cat "$p/f" > /dev/null 2>&1
      [ "$(reads_atime "$p/f")" -ge "$READS_OLD_BOUND" ] || ok=1
      ls "$p" > /dev/null 2>&1
      [ "$(reads_atime "$p")" -ge "$READS_OLD_BOUND" ] || ok=1
    fi
  fi
  [ -z "${p:-}" ] || { chmod -R u+rwx "$p" 2> /dev/null; rm -rf "$p"; }
  [ "$ok" -eq 0 ] || { printf 'this file system does not record which files are read\n' >&2; return 1; }
}
