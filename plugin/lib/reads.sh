#!/usr/bin/env bash
# What a run reads in its own clean copy (docs/proof.md, R166). Before a run
# the access time (atime, the time the system notes when a file is read) of
# every tracked file and folder of the copy, and of the copy's own git HEAD
# and index files, is set back with touch -a to an old date. After it, what
# moved forward was read: a file was opened, a folder was listed, git was used.
# #
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

# reads_stamp SECONDS: the local time SECONDS ago, as touch -t wants it.
reads_stamp() {
  local e=$(( $(date +%s) - $1 ))
  date -r "$e" +%Y%m%d%H%M.%S 2> /dev/null || date -d "@$e" +%Y%m%d%H%M.%S
}

# reads_touch LIST COPY: set back the access time of each path in LIST (NUL-
# separated, relative to COPY). Links themselves, never what they point to;
# a path that is gone is skipped.
reads_touch() {
  (cd "$2" && xargs -0 -r touch -h -a -t "$READS_OLD" -- < "$1") 2> /dev/null || true
}

# reads_moved LIST COPY REF: the paths of LIST (NUL-separated, relative to COPY)
# read since the reset (REF, absolute, is the yardstick), NUL-separated.
reads_moved() {
  (cd "$2" && xargs -0 -r sh -c 'ref=$1; shift; find "$@" -maxdepth 0 -anewer "$ref" -print0' sh "$3" < "$1") 2> /dev/null || true
}

# reads_reset COPY STATE: before a run (STATE absolute). The first call also
# records the copy's tracked files and folders (they never change: the copy is
# a detached checkout) and where its git HEAD and index files are. "Written by
# the run" means newer than the mark: 2 seconds back (whole-second file
# systems), but never before the copy's first reset. A file the previous run
# wrote just before may be taken for this run's, and then carries both lists.
reads_reset() {
  local copy=$1 st=$2 gd slack=2 sec
  mkdir -p "$st" || return 1
  if [ ! -f "$st/gitdir" ]; then
    # The copy was just made: wait for the next whole second, so that no file of
    # it can look written by the first run on a file system with whole-second times.
    sec=$(date +%s)
    while [ "$(date +%s)" = "$sec" ]; do sleep 0.05; done
    slack=0
    : > "$st/mark0" && touch -t "$(reads_stamp 0)" "$st/mark0" || return 1
    gd=$(git -C "$copy" rev-parse --absolute-git-dir) || return 1
    git -C "$copy" ls-files -z | jq -Rs -j '
      (split("\u0000") | map(select(length > 0))) as $f
      | ($f[] | "./" + . + "\u0000")' > "$st/files" || return 1
    git -C "$copy" ls-files -z | jq -Rs -j '
      (split("\u0000") | map(select(length > 0))) as $f
      | ([$f[] | split("/") | . as $p | range(1; length) | $p[:.] | join("/")] | unique | map("./" + .)) as $d
      | ("." , $d[]) + "\u0000"' > "$st/dirs" || return 1
    printf '%s\n' "$gd" > "$st/gitdir"
  fi
  gd=$(cat "$st/gitdir")
  : > "$st/ref" && touch -t "$READS_OLD_DAY" "$st/ref" || return 1
  : > "$st/mark" && touch -t "$(reads_stamp "$slack")" "$st/mark" || return 1
  # Never earlier than the first mark: nothing made with the copy is a write.
  [ ! "$st/mark0" -nt "$st/mark" ] || touch -r "$st/mark0" "$st/mark" || return 1
  reads_touch "$st/files" "$copy"
  reads_touch "$st/dirs" "$copy"
  [ ! -e "$gd/HEAD" ] || touch -a -t "$READS_OLD" "$gd/HEAD" 2> /dev/null || true
  [ ! -e "$gd/index" ] || touch -a -t "$READS_OLD" "$gd/index" 2> /dev/null || true
}

# reads_collect COPY STATE: after a run; prints its read list as one JSON
# object {files, dirs: [{path, fp}], git}. fp fingerprints the names of the
# tracked files and folders directly in the listed folder. 
reads_collect() {
  local copy=$1 st=$2 gd git=false line fp
  gd=$(cat "$st/gitdir")
  [ -z "$(find "$gd/HEAD" "$gd/index" -maxdepth 0 -anewer "$st/ref" -print 2> /dev/null)" ] || git=true
  reads_moved "$st/files" "$copy" "$st/ref" > "$st/opened"
  reads_moved "$st/dirs" "$copy" "$st/ref" > "$st/listed"
  : > "$st/dirs.json"
  while IFS= read -r line; do
    fp=$(printf '%s' "$line" | vbw_sha256)
    printf '%s' "$line" | jq -c --arg fp "$fp" '{path: .[0], fp: $fp}' >> "$st/dirs.json"
  done < <(jq -Rs -c --rawfile listed "$st/listed" '
    def strip: if . == "." then "" else sub("^\\./"; "") end;
    (split("\u0000") | map(select(length > 0) | strip)) as $f
    | ($listed | split("\u0000") | map(select(length > 0)))[] as $raw | ($raw | strip) as $d
    | [($raw | strip | if . == "" then "." else . end),
       ([$f[] | select($d == "" or startswith($d + "/")) | ltrimstr($d + "/") | split("/")[0]] | unique)]' "$st/files")
  jq -nc --rawfile o "$st/opened" --slurpfile d "$st/dirs.json" --argjson g "$git" '
    def strip: sub("^\\./"; "");
    def paths: split("\u0000") | map(select(length > 0) | strip);
    {files: ($o | paths), dirs: $d, git: $g} as $own
    | $own
    | {files: (.files | unique), dirs: (.dirs | unique_by(.path)), git}' > "$st/last.json" || return 1
  cat "$st/last.json"
}
