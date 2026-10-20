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
# files the reset set back), written.json ({lists: run id -> read list, files:
# path -> [run id]}) and runid (the last run id given).

# The old date, for touch -t (local time): a set-back time is a day before the
# yardstick file (READS_OLD_DAY) that "read since" is compared with.
READS_OLD=200001010000
READS_OLD_DAY=200001020000

# reads_probe DIR: the start-of-proof test of the file system DIR is on. A
# file's access time is set back and must stay behind the yardstick; reading
# the file and listing a folder must then move it past it. The same comparison
# (find -anewer) the collector uses, so the probe proves what the proof relies on.
reads_probe() {
  local p ok=0
  p=$(mktemp -d "$1/probe.XXXXXX" 2> /dev/null) || ok=1
  if [ "$ok" -eq 0 ]; then
    mkdir "$p/d" 2> /dev/null && printf 'x\n' > "$p/d/f" 2> /dev/null || ok=1
    : > "$p/ref" && touch -t "$READS_OLD_DAY" "$p/ref" 2> /dev/null || ok=1
    touch -a -t "$READS_OLD" "$p/d/f" "$p/d" 2> /dev/null || ok=1
    # Each set-back must have taken: the yardstick and both access times are years old. Asked by age,
    # never by comparing with a file made a moment before, whose time can be equal on a fast machine
    # (2.0.37 CI, Linux).
    [ "$ok" -ne 0 ] || [ -n "$(find "$p/ref" -maxdepth 0 -mtime +1000 2> /dev/null)" ] || ok=1
    [ "$ok" -ne 0 ] || [ "$(find "$p/d/f" "$p/d" -maxdepth 0 -atime +1000 2> /dev/null | wc -l | tr -d ' ')" = 2 ] || ok=1
    if [ "$ok" -eq 0 ]; then
      cat "$p/d/f" > /dev/null 2>&1
      [ -n "$(find "$p/d/f" -maxdepth 0 -anewer "$p/ref" 2> /dev/null)" ] || ok=1
      ls "$p/d" > /dev/null 2>&1
      [ -n "$(find "$p/d" -maxdepth 0 -anewer "$p/ref" 2> /dev/null)" ] || ok=1
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
  [ -f "$st/written.json" ] || printf '{"lists":{},"files":{}}\n' > "$st/written.json"
  jq -j '.files | keys[] | "./" + . + "\u0000"' "$st/written.json" > "$st/wlist" || return 1
  : > "$st/ref" && touch -t "$READS_OLD_DAY" "$st/ref" || return 1
  : > "$st/mark" && touch -t "$(reads_stamp "$slack")" "$st/mark" || return 1
  # Never earlier than the first mark: nothing made with the copy is a write.
  [ ! "$st/mark0" -nt "$st/mark" ] || touch -r "$st/mark0" "$st/mark" || return 1
  reads_touch "$st/files" "$copy"
  reads_touch "$st/dirs" "$copy"
  reads_touch "$st/wlist" "$copy"
  [ ! -e "$gd/HEAD" ] || touch -a -t "$READS_OLD" "$gd/HEAD" 2> /dev/null || true
  [ ! -e "$gd/index" ] || touch -a -t "$READS_OLD" "$gd/index" 2> /dev/null || true
}

# reads_collect COPY STATE: after a run; prints its read list as one JSON
# object {files, dirs: [{path, fp}], git}. fp fingerprints the names of the
# tracked files and folders directly in the listed folder: the SHA-256 of the
# compact JSON text [path, names]. A fixed number of processes whatever the
# number of listed folders: one jq builds every listing text from one parent-
# to-names map, bash writes one scratch file per text, one sha256 call hashes
# them all, one jq assembles the list. Reads the written files this run opened
# (set back by the reset) for their lists, and records the files it wrote with
# a single copy of this list (written.json: lists by run id, files by path).
reads_collect() {
  local copy=$1 st=$2 gd git=false line n=0 id
  local -a names
  gd=$(cat "$st/gitdir")
  [ -z "$(find "$gd/HEAD" "$gd/index" -maxdepth 0 -anewer "$st/ref" -print 2> /dev/null)" ] || git=true
  reads_moved "$st/files" "$copy" "$st/ref" > "$st/opened"
  reads_moved "$st/dirs" "$copy" "$st/ref" > "$st/listed"
  reads_moved "$st/wlist" "$copy" "$st/ref" > "$st/inherited"
  jq -Rs -c --rawfile listed "$st/listed" '
    def strip: if . == "." then "" else sub("^\\./"; "") end;
    (reduce (split("\u0000") | map(select(length > 0) | strip))[] as $f ({};
      ($f | split("/")) as $p
      | reduce range(0; $p | length) as $i (.; .[$p[:$i] | join("/")] += [$p[$i]]))) as $kids
    | ($listed | split("\u0000") | map(select(length > 0)))[]
    | strip as $d
    | [(if $d == "" then "." else $d end), ($kids[$d] // [] | unique)]' "$st/files" > "$st/listings"
  rm -rf "$st/fp"; mkdir -p "$st/fp"
  while IFS= read -r line; do
    printf '%s' "$line" > "$st/fp/$n"
    names[n]=$n
    n=$((n + 1))
  done < "$st/listings"
  : > "$st/hashes"
  if [ "$n" -gt 0 ]; then
    # One call; each line is "<hash>  <file>" with either sha256sum or shasum.
    (cd "$st/fp" && { if command -v sha256sum > /dev/null 2>&1; then sha256sum "${names[@]}"; else shasum -a 256 "${names[@]}"; fi; }) > "$st/hashes" || return 1
  fi
  jq -nc --rawfile o "$st/opened" --rawfile i "$st/inherited" --rawfile l "$st/listings" --rawfile h "$st/hashes" --slurpfile w "$st/written.json" --argjson g "$git" '
    def strip: sub("^\\./"; "");
    def paths: split("\u0000") | map(select(length > 0) | strip);
    ($h | split("\n") | map(select(length > 0) | split("  ")[0])) as $fps
    | ($l | split("\n") | map(select(length > 0) | fromjson)) as $ls
    | {files: ($o | paths), dirs: [range(0; $ls | length) as $k | {path: $ls[$k][0], fp: $fps[$k]}], git: $g} as $own
    | ([($i | paths)[] as $p | ($w[0].files[$p] // [])[]] | unique) as $ids
    | reduce $ids[] as $id ($own; ($w[0].lists[$id]) as $l
        | {files: (.files + $l.files), dirs: (.dirs + $l.dirs), git: (.git or $l.git)})
    | {files: (.files | unique), dirs: (.dirs | unique_by(.path)), git}' > "$st/last.json" || return 1
  # What the run wrote (not in .git) now carries its read list, stored once.
  (cd "$copy" && find . -path ./.git -prune -o -type f -newer "$st/mark" -print0) > "$st/new" 2> /dev/null || true
  if [ -s "$st/new" ]; then
    id=$(( $(cat "$st/runid" 2> /dev/null || echo 0) + 1 ))
    printf '%s\n' "$id" > "$st/runid"
    jq -c --rawfile n "$st/new" --slurpfile r "$st/last.json" --arg id "$id" '
      def strip: sub("^\\./"; "");
      .lists[$id] = $r[0]
      | reduce ($n | split("\u0000") | map(select(length > 0) | strip))[] as $p (.; .files[$p] += [$id])' \
      "$st/written.json" > "$st/written.tmp" && mv "$st/written.tmp" "$st/written.json" || return 1
  fi
  cat "$st/last.json"
}
