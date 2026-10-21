#!/usr/bin/env bash
# The single writer of .vbw/record.json. Every mutation goes through
# record_update: lock, apply one jq program, validate, rename into place.

VBW_LOCK_STALE_SECONDS=30
# A lock whose holder still runs is broken only past this age, for a holder id
# the system has since given to another process.
VBW_LOCK_HELD_SECONDS=600

# Print the first violation of FILE (empty output = valid). Status 1 if invalid.
record_violation() {
  local out
  if ! out=$(jq -c --slurpfile interview "$VBW_LIB/interview.json" -f "$VBW_LIB/record.jq" "$1" 2>/dev/null); then
    printf 'unparseable JSON\n'
    return 1
  fi
  [ "$out" = "[]" ] && return 0
  printf '%s\n' "$out" | jq -r '.[0]'
  return 1
}

# Schemas 1 to 4 are read. Every record this VBW writes is format 4 (D232): schema
# 4, with the protected field (the sorted list of every file a check protects) near
# its top, so the guards never read the checks (R150). Records of schemas 1 to 3
# written by an older VBW are read and become format 4 on their next write.
VBW_SCHEMA_MAX=4

# The schema of the record at FILE when it is a number above the highest this
# VBW reads (written by a newer VBW); empty and status 1 otherwise. A
# non-numeric or damaged schema is not "newer": it stays corrupt.
record_newer_schema() {
  local n
  n=$(jq -r --argjson max "$VBW_SCHEMA_MAX" 'if (.schema | type) == "number" and .schema > $max then .schema else empty end' "$1" 2> /dev/null) || return 1
  [ -n "$n" ] && printf '%s\n' "$n"
}

# Die (exit 4) when the record was written by a newer VBW.
record_refuse_newer() {
  local n
  n=$(record_newer_schema "$VBW_RECORD") || return 0
  vbw_die "this project needs a newer VBW: its record was written with schema $n, this VBW reads up to schema $VBW_SCHEMA_MAX; update VBW with /vbw:update" 4
}

# The glance: the record cut down to what the status line and the guards read
# (R149, R150): schema, lease and protected exactly as the record has them
# (protected left out only when the record has none, as an older VBW wrote it),
# besides the loop (session, started_at, ended; null without one), which the Bash
# guard reads, and the status line's fields. Both read it instead of the record, so
# neither parses a record of megabytes. It is never a source of truth (D238):
# the guards trust it only while it is strictly newer than the record, and
# otherwise read the record. Call with the record lock held. It is built in a
# temporary file and renamed into place, so it is never half-written.
record_glance_write() {
  local tmp
  tmp=$(mktemp "$VBW_RUNTIME/glance.XXXXXX" 2> /dev/null) || return 0
  vbw_guard_add file "$tmp"
  if jq -c --rawfile h <(cat "$VBW_RUNTIME/holder.json" 2> /dev/null || true) '.milestone.id as $m | {schema, lease}
      + (if has("protected") then {protected} else {} end)
      + {loop: (.loop | if type == "object" then {session, started_at, ended} else null end),
      project, milestone, settings,
      requirements: [.requirements[]? | select(.milestone == $m)],
      plans: [.plans[]? | select(.status == "building")],
      holder: (($h | try fromjson catch null) as $f
        | if ($f | type) == "object" and .lease != null and $f.run == .lease.run
          then {run: $f.run, session: ($f.session // null), session_name: ($f.session_name // null)} else null end)}' \
    "$VBW_RECORD" > "$tmp" 2> /dev/null; then
    record_open_marker "$tmp"
    mv "$tmp" "$VBW_RUNTIME/glance.json" 2> /dev/null || true
  fi
  vbw_guard_drop "$tmp"
  rm -f "$tmp" 2> /dev/null || true
}

# record_open_marker GLANCE: keep .vbw/runtime/run-open, an empty file that
# exists exactly while the record shows an open run lease, so a guard that
# cannot run jq (broken, missing, timed out) can still tell with a plain
# file test that a run is open (R165). Written only from a glance that was just
# built from a readable record: an unreadable record never reaches here, so the
# marker then stays as it was. Created by rename, so it is never half-written.
record_open_marker() {
  local m="$VBW_RUNTIME/run-open" t
  if [ "$(jq -r '.lease != null' "$1" 2> /dev/null)" = true ]; then
    [ -f "$m" ] && return 0
    t=$(mktemp "$VBW_RUNTIME/run-open.XXXXXX" 2> /dev/null) || return 0
    mv "$t" "$m" 2> /dev/null || rm -f "$t" 2> /dev/null || true
  else
    rm -f "$m" 2> /dev/null || true
  fi
}

# record_back FILE: set FILE's time one second back (touch -A on macOS and BSD,
# -r with -d on GNU; when neither works the time stays and the guards simply
# read the record). Done to a new record before it is renamed into place, so the
# glance written after it is strictly newer even when compared in whole seconds.
record_back() {
  touch -A -01 "$1" 2> /dev/null || touch -r "$1" -d '-1 second' "$1" 2> /dev/null || true
}

# record_glance_forward: a glance a read just rewrote is always set one second after
# the record (touch -r with -A on macOS and BSD, -d on GNU), so it is strictly
# newer even in whole seconds. The record and its time stay as they are; when
# neither touch works the guards read the record, as before.
record_glance_forward() {
  [ -f "$VBW_RUNTIME/glance.json" ] || return 0
  touch -r "$VBW_RECORD" -A 01 "$VBW_RUNTIME/glance.json" 2> /dev/null \
    || touch -r "$VBW_RECORD" -d '+1 second' "$VBW_RUNTIME/glance.json" 2> /dev/null || true
}

# True when the glance is a regular file strictly newer than the record.
record_glance_current() {
  [ -f "$VBW_RUNTIME/glance.json" ] && [ "$VBW_RUNTIME/glance.json" -nt "$VBW_RECORD" ]
}

# The validated record on stdout; exit 3 if it is corrupt, 4 if it is newer.
# A glance that is missing, not a regular file or not strictly newer than the
# record (after a checkout, a reset, a hand edit, or a record an older VBW wrote)
# is rewritten here under the lock, so the first vbw command brings it up to
# date. The record and its file time are never changed.
record_read() {
  local v
  record_refuse_newer
  v=$(record_violation "$VBW_RECORD") || vbw_die "record is corrupt: $v ($VBW_RECORD)" 3
  if ! record_glance_current; then
    (
      vbw_guard_reset
      mkdir -p "$VBW_RUNTIME" 2> /dev/null || exit 0
      record_lock
      record_glance_current || { record_glance_write; record_glance_forward; }
      record_unlock
    ) || true
  fi
  cat "$VBW_RECORD"
}

record_unlock() {
  vbw_guard_drop "$VBW_RUNTIME/lock"
}

# vbw_lock_alive PID: true while process PID runs (kill -0 is only a liveness
# probe; a process of another user answers "not permitted" and counts as running).
vbw_lock_alive() {
  local e
  e=$(kill -0 "$1" 2>&1) && return 0
  case "$e" in *ermitted*) return 0 ;; esac
  return 1
}

# vbw_lock_holder LOCK: the holder's process id, only when the whole line is
# there. A lock read while its holder is still writing the id shows part of it
# ("69" of "6980"): that once named a process that does not run and broke a
# live writer's lock. Without the line's newline the id is unknown (empty).
vbw_lock_holder() {
  local pid=""
  { IFS= read -r pid < "$1"; } 2> /dev/null || pid=""
  case "$pid" in "" | *[!0-9]*) pid="" ;; esac
  printf '%s' "$pid"
}

# True when the lock is abandoned. A lock names its holder's process id: it is
# abandoned once that process has ended, and while it runs only past
# VBW_LOCK_HELD_SECONDS. Age alone once broke the lock of a writer still at work
# on a busy machine (a write over 30 s), and two writes overlapped: updates were
# lost with no error (2026-10-19). A lock without a readable id (just created,
# or a directory an older VBW left) goes by age. An age that cannot be read (the
# lock vanished between the two looks, as happens under contention) is never
# "stale": treating it as age 0 once let a waiter delete a lock another writer
# had just taken (lost updates, CI 2.0.2).
vbw_is_stale() {
  local m pid
  [ -e "$1" ] || return 1
  pid=$(vbw_lock_holder "$1")
  m=$(vbw_mtime "$1")
  if [ -n "$pid" ]; then
    if ! vbw_lock_alive "$pid"; then
      # The holder may have ended normally after its id was read, and a new
      # writer taken the lock: only a lock that still names the ended holder is
      # abandoned (an ended process can no longer release it).
      [ "$(vbw_lock_holder "$1")" = "$pid" ]
      return
    fi
    [ "$m" -gt 0 ] && [ $(( $(date +%s) - m )) -gt "$VBW_LOCK_HELD_SECONDS" ]
    return
  fi
  [ "$m" -gt 0 ] && [ $(( $(date +%s) - m )) -gt "$VBW_LOCK_STALE_SECONDS" ]
}

# Take the project lock. An abandoned lock (vbw_is_stale) is broken, but only
# while holding the "break" mutex and after re-checking that it is still
# abandoned, so two processes can never both break it and one delete the
# other's fresh lock. No signals: kill -0 only asks whether the holder runs.
record_lock() {
  mkdir -p "$VBW_RUNTIME"
  vbw_lock_take "$VBW_RUNTIME/lock" "record"
}

# vbw_lock_create LOCK: create the lock file LOCK holding this process's id,
# failing when it exists. It
# uses bash's own noclobber open (O_CREAT|O_EXCL), never an outside tool: the
# Rust mkdir of Ubuntu 25.10 and 26.04 succeeds on an existing directory, so a
# mkdir lock let two writers in (lost writes, CI 2026-10-09). A lock directory
# left by an older VBW exists too, so it still excludes.
vbw_lock_create() {
  local r o="$-"
  set -C
  { printf '%s\n' "$$" > "$1"; } 2> /dev/null
  r=$?
  case "$o" in *C*) ;; *) set +C ;; esac
  return "$r"
}

# vbw_lock_dir DIR: take the lock folder DIR, whose owner file DIR/pid holds
# this process's id; fails when another process holds it. The folder is made
# with mkdir as before (an older VBW's lock of the same name still excludes),
# but only the owner file's exclusive create (vbw_lock_create) takes the lock:
# when several racing mkdir calls for one new folder all succeed (uutils mkdir,
# Ubuntu 26.04), only one of them creates DIR/pid.
vbw_lock_dir() {
  mkdir "$1" 2> /dev/null && vbw_lock_create "$1/pid"
}

# vbw_lock_remove LOCK: remove a lock file, or a lock directory an older VBW left.
vbw_lock_remove() {
  rm -f "$1" 2> /dev/null || rmdir "$1" 2> /dev/null || true
}

# vbw_lock_take LOCK WHAT: take the lock LOCK, as described above; it is
# released by vbw_guard_drop (and by the interrupt cleanup).
vbw_lock_take() {
  local lock="$1" brk="$1.break" deadline seen="" m
  # The wait counts from the last time the lock changed hands (its time moved):
  # a long queue of writers on a busy machine is progress, never a reason to
  # give up. One holder that keeps the lock twice the stale window (a deadlock,
  # or a write far slower than any seen) makes the waiter stop with an error;
  # it is never broken while it runs (vbw_is_stale), so no write is lost.
  deadline=$(( $(date +%s) + 2 * VBW_LOCK_STALE_SECONDS ))
  until vbw_lock_create "$lock"; do
    m=$(vbw_mtime "$lock")
    if [ "$m" != "$seen" ]; then
      seen=$m
      deadline=$(( $(date +%s) + 2 * VBW_LOCK_STALE_SECONDS ))
    fi
    if vbw_is_stale "$lock"; then
      vbw_is_stale "$brk" && vbw_lock_remove "$brk"
      if vbw_lock_create "$brk"; then
        vbw_is_stale "$lock" && vbw_lock_remove "$lock"
        vbw_lock_remove "$brk"
        continue
      fi
    fi
    [ "$(date +%s)" -le "$deadline" ] || vbw_die "$2 is locked by another vbw process ($lock)"
    sleep 0.05
  done
  vbw_guard_add lock "$lock"
}

# record_update FILTER [jq options...]: apply FILTER to the record atomically.
# The new record must validate, or nothing changes and the violation is shown.
record_update() {
  local filter="$1" tmp v
  shift
  record_refuse_newer
  record_lock
  record_refuse_newer
  v=$(record_violation "$VBW_RECORD") || vbw_die "record is corrupt: $v ($VBW_RECORD)" 3
  tmp=$(mktemp "$VBW_RUNTIME/record.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$tmp"
  # Every write produces format 4 (D232, R150): schema 4 and protected, the sorted
  # list of every string in the checks' files, each once ([] without checks or
  # files). Key order: schema, lease, protected, checks, then the rest, so the
  # guards read the beginning of the file alone (R149, R150). An older record
  # (schema 1 to 3) becomes format 4 here.
  jq "$@" "$filter
    | {schema: 4, lease: (.lease // null),
       protected: ([(.checks // [])[]? | objects | .files? | arrays | .[] | strings] | unique)}
      + (if has(\"checks\") then {checks} else {checks: []} end) + del(.schema, .lease, .protected, .checks)" "$VBW_RECORD" > "$tmp" 2>/dev/null || vbw_die "internal error: record update failed"
  v=$(record_violation "$tmp") || vbw_die "refused: $v"
  # The new record's time goes one second back, the old glance goes, and the
  # new glance is written after the record: it is strictly newer than the record
  # (even in whole seconds), a failed glance write leaves no glance that looks
  # current, and the record write never fails because of the glance.
  record_back "$tmp"
  rm -f "$VBW_RUNTIME/glance.json" 2> /dev/null || true
  mv "$tmp" "$VBW_RECORD"
  vbw_guard_drop "$tmp"
  record_glance_write
  record_unlock
}

# record_commit [--strict] MESSAGE [FILE...]: commit VBW's own files that changed (.vbw/spec.md,
# .vbw/record.json, .vbw/map.md, .vbw/.gitignore and the protected check
# files) with `git commit --only`, so the user's staged work stays staged.
# Called when a run ends, at approval and at ship. With FILE... (paths from the
# project root) only those of VBW's files are considered, so a command that
# writes the record alone never takes the user's edit of the spec with it
# (vbw todo). Nothing changed: no commit.
# A failing commit (no git identity, a hook) warns with git's own reason and
# never undoes the step; with --strict as first argument it prints the reason
# alone and returns 1, for a caller that must stop (vbw approve).
record_commit() {
  local strict=0
  [ "${1:-}" != "--strict" ] || { strict=1; shift; }
  local msg="$1" own=() changed=() untracked=() f why
  shift
  local only=("$@")
  (
    # A subshell starts without the parent's traps: it guards only its own lock.
    vbw_guard_reset
    cd "$VBW_ROOT" || exit 1
    if [ ${#only[@]} -gt 0 ]; then
      for f in "${only[@]}"; do [ -f "$f" ] && own+=("$f"); done
    else
      for f in .vbw/spec.md .vbw/record.json .vbw/map.md .vbw/.gitignore; do [ -f "$f" ] && own+=("$f"); done
      while IFS= read -r -d '' f; do [ -f "$f" ] && own+=("$f"); done \
        < <(jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"' "$VBW_RECORD")
    fi
    [ ${#own[@]} -gt 0 ] || exit 0
    while IFS= read -r -d '' f; do changed+=("$f"); done < <(git diff --name-only -z HEAD -- "${own[@]}" 2> /dev/null)
    while IFS= read -r -d '' f; do untracked+=("$f"); changed+=("$f"); done \
      < <(git ls-files -z --others --exclude-standard -- "${own[@]}")
    [ ${#changed[@]} -gt 0 ] || exit 0
    record_lock
    if why=$({ [ ${#untracked[@]} -eq 0 ] || git add -- "${untracked[@]}"; } 2>&1 &&
      git commit --quiet --only -m "$msg" -- "${changed[@]}" 2>&1); then
      record_unlock
      exit 0
    fi
    record_unlock
    if [ "$strict" = 1 ]; then
      printf '%s\n' "$why" >&2
    else
      printf 'vbw: warning: could not commit VBW files (%s): %s; commit them yourself\n' "$msg" "$why" >&2
    fi
    exit 1
  ) || [ "$strict" = 0 ]
}

# jq helper, prepended to update filters: the next free id with prefix P;
# next_fix_id: the next fix id, past those a parked milestone freed (T163).
# shellcheck disable=SC2016,SC2034 # jq text, not shell; used by the cmd-*.sh files
# covers($p): a plan file entry covers PATH: the same path, or a directory
# entry (ending in /) with PATH under it; two file lists overlap when either
# covers the other ("*" is any file). wave($done): of these plans, the next
# build wave: those whose after-plans are all in $done, no two sharing a file.
# vbw next and the approval's waves line both use it (D166).
VBW_JQ_DEFS='def next_id($p): (([.[]?.id | ltrimstr($p) | tonumber?] | max) // 0) + 1 | "\($p)\(.)";
def next_fix_id: (.fixes + [(.parked // [])[].ids[]? | select(startswith("F")) | {id: .}]) | next_id("F");
def covers($p): . as $e | $e == $p or (($e | endswith("/")) and ($p | startswith($e)));
def overlaps($a; $b): any($a[], $b[]; . == "*") or any($a[]; . as $x | any($b[]; . as $y | ($x | covers($y)) or ($y | covers($x))));
def proof_complete: (.evidence.commands // {}) as $m | .evidence.full != false
  or ((($m | has("quick")) and $m.quick.status != "skipped" and ($m | has("test") | not)) | not)
     and all($m | to_entries[] | select(.key != "quick"); .value.status != "skipped");
def wave($done): [.[] | select(all((.after // [])[]; . as $a | any($done[]; . == $a)))]
  | reduce .[] as $p ({ids: [], files: []}; if overlaps(.files; $p.files) then . else .ids += [$p.id] | .files += $p.files end) | .ids;
# waves($m): on the record, the milestone'"'"'s build waves as vbw next schedules them
# (blocked plans are skipped): the ids of the plans each wave runs, in wave order.
# The approval'"'"'s waves line (vbw show contract) and the road (lib/road.jq) both use it.
def waves($m): . as $r
  | {done: [.plans[] | select(.status == "done") | .id],
     left: [.plans[] | select(.status != "done" and .status != "blocked" and (.phase as $p | any($r.phases[]; .id == $p and .milestone == $m)))], w: []}
  | until(.left | length == 0; .done as $d
      | (.left | wave($d)) as $ids
      | if ($ids | length) == 0 then .left = [] else .w += [$ids] | .done += $ids | .left |= map(select(.id as $i | any($ids[]; . == $i) | not)) end)
  | .w;
'"$(cat "$VBW_LIB/rigor-defs.jq")"
