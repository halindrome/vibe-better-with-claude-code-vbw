#!/usr/bin/env bash
# Shared helpers for the vbw kernel. Sourced by bin/vbw; never executed alone.
# Exit codes: 0 ok, 1 error, 2 usage, 3 corrupt record, 4 record written by a newer VBW.

vbw_die() {
  printf 'vbw: %s\n' "$1" >&2
  vbw_guard_run
  if [ -n "${VBW_DIE_HOOK:-}" ]; then local h=$VBW_DIE_HOOK; VBW_DIE_HOOK=; "$h" || true; fi
  exit "${2:-1}"
}

# Interrupt-safe cleanup. Temporary files and held lock directories are
# registered here; INT, TERM and HUP remove them and exit (so the caller's own
# EXIT trap still runs), and so does vbw_die. An EXIT trap is installed only
# when the process has none (the vbw entry point), so a caller's EXIT trap is
# never replaced or cleared, and no trap text is ever evaluated.
VBW_GUARD_FILES=()
VBW_GUARD_LOCKS=()
VBW_GUARD_DIRS=()
VBW_GUARD_EXIT=0

# vbw_guard_add KIND PATH: remove PATH on interrupt, die or vbw_guard_drop.
# KIND is file, lock (a lock file, or the lock directory of an older VBW) or dir (a directory tree, rm -rf;
# rm never follows a symlink inside it).
vbw_guard_add() {
  local kind="$1" path="$2"
  case "$kind" in
    lock) VBW_GUARD_LOCKS+=("$path") ;;
    dir) VBW_GUARD_DIRS+=("$path") ;;
    *) VBW_GUARD_FILES+=("$path") ;;
  esac
  trap 'vbw_guard_run; exit 130' INT
  trap 'vbw_guard_run; exit 143' TERM
  trap 'vbw_guard_run; exit 129' HUP
  if [ "$VBW_GUARD_EXIT" -eq 0 ] && [ -z "$(trap -p EXIT)" ]; then
    trap vbw_guard_run EXIT
    VBW_GUARD_EXIT=1
  fi
}

# Forget everything registered (a subshell calls this: it owns none of it).
vbw_guard_reset() {
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
  VBW_GUARD_DIRS=()
  VBW_GUARD_EXIT=0
}

# Remove everything registered (files and locks with rm, an old lock directory with rmdir).
vbw_guard_run() {
  local p
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do rm -f "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do rm -f "$p" 2>/dev/null || rmdir "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do chmod -R u+rwx "$p" 2>/dev/null || true; rm -rf "$p" 2>/dev/null || true; done
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
  VBW_GUARD_DIRS=()
}

# vbw_guard_drop PATH: clean up one registered path now (file or lock dir);
# when nothing is left, the traps are removed again.
vbw_guard_drop() {
  local p keep=()
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do [ "$p" != "$1" ] || { chmod -R u+rwx "$1" 2>/dev/null; rm -rf "$1" 2>/dev/null; } || true; done
  rm -f "$1" 2>/dev/null || true
  rmdir "$1" 2>/dev/null || true
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_FILES=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_LOCKS=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_DIRS=(${keep[@]+"${keep[@]}"})
  [ $(( ${#VBW_GUARD_FILES[@]} + ${#VBW_GUARD_LOCKS[@]} + ${#VBW_GUARD_DIRS[@]} )) -eq 0 ] || return 0
  trap - INT TERM HUP
  if [ "$VBW_GUARD_EXIT" -eq 1 ]; then trap - EXIT; VBW_GUARD_EXIT=0; fi
}

vbw_usage_error() {
  printf 'vbw: %s\n' "$1" >&2
  printf 'usage: vbw <command> [args]   (vbw help for the list)\n' >&2
  exit 2
}

# The calling Claude Code session: VBW_SESSION_ID (skills pass ${CLAUDE_SESSION_ID}),
# else CLAUDE_CODE_SESSION_ID, else empty (unknown).
vbw_session() {
  printf '%s' "${VBW_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
}

vbw_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# This clone's own settings: $(git-common-dir)/vbw/settings.json (shared by the
# clone's worktrees, never in the shared record). Today: check_jobs, how many
# checks run at the same time (1 to 64; 1 is sequential). Without a setting
# the machine decides: three quarters of its processor cores.
vbw_clone_settings_file() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/settings.json\n' "$common"
}

# vbw_cores_ok N: N is a whole number of at least 1: digits only, no leading
# zero (it would read as octal), no sign, dot or trailing text.
vbw_cores_ok() {
  case "$1" in '' | *[!0-9]* | 0*) return 1 ;; esac
}

# vbw_cores: the processor core count, from the first of getconf, nproc and
# sysctl (found on PATH) that gives a whole number of at least 1; none gives
# "cannot be read" (status 1, no output).
vbw_cores() {
  local n
  n=$(getconf _NPROCESSORS_ONLN 2> /dev/null) || n=""
  vbw_cores_ok "$n" && { printf '%s\n' "$n"; return 0; }
  n=$(nproc 2> /dev/null) || n=""
  vbw_cores_ok "$n" && { printf '%s\n' "$n"; return 0; }
  n=$(sysctl -n hw.ncpu 2> /dev/null) || n=""
  vbw_cores_ok "$n" && { printf '%s\n' "$n"; return 0; }
  return 1
}

# vbw_claude_dir: the user's Claude config folder: CLAUDE_CONFIG_DIR when set,
# else ~/.config/claude-code when that folder exists, else ~/.claude.
vbw_claude_dir() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_CONFIG_DIR"
  elif [ -d "$HOME/.config/claude-code" ]; then
    printf '%s\n' "$HOME/.config/claude-code"
  else
    printf '%s\n' "$HOME/.claude"
  fi
}

# vbw_machine_limit: three quarters of the cores, rounded down, 1 to 64; 1 when
# the count cannot be read. No setting, no environment override.
vbw_machine_limit() {
  local n cores
  cores=$(vbw_cores) || cores=""
  if [ -z "$cores" ]; then printf '1\n'; return 0; fi
  n=$((cores * 3 / 4))
  [ "$n" -ge 1 ] || n=1
  [ "$n" -le 64 ] || n=64
  printf '%s\n' "$n"
}

# vbw_check_jobs_set_value: the check_jobs value set in this clone's settings,
# or nothing when missing, damaged or out of range.
vbw_check_jobs_set_value() {
  local file n
  file=$(vbw_clone_settings_file) || return 1
  n=$(jq -r '.check_jobs // empty' "$file" 2> /dev/null) || n=""
  case "$n" in
    [1-9] | [1-5][0-9] | 6[0-4]) printf '%s\n' "$n" ;;
  esac
  return 0
}

# vbw_check_jobs: the one reader of check_jobs: a valid set value, else three
# quarters of the cores (rounded down, 1 to 64), 1 when the count cannot be read.
vbw_check_jobs() {
  local n
  n=$(vbw_check_jobs_set_value) || return 1
  if [ -n "$n" ]; then printf '%s\n' "$n"; return 0; fi
  vbw_machine_limit
}

# vbw_check_jobs_source: "set" or "machine default".
vbw_check_jobs_source() {
  local n
  n=$(vbw_check_jobs_set_value) || return 1
  if [ -n "$n" ]; then printf 'set\n'; else printf 'machine default\n'; fi
}

# vbw_check_jobs_set N|default: atomic, locked change of check_jobs.
vbw_check_jobs_set() {
  local file tmp lock
  file=$(vbw_clone_settings_file)
  mkdir -p "${file%/*}"
  lock="${file%/*}/settings.lock"
  vbw_lock_take "$lock" "this clone's settings"
  [ -f "$file" ] || printf '{}\n' > "$file"
  tmp=$(mktemp "${file%/*}/settings.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  if [ "$1" = default ]; then
    jq 'del(.check_jobs)' "$file" > "$tmp" 2> /dev/null
  else
    jq --argjson n "$1" '.check_jobs = $n' "$file" > "$tmp" 2> /dev/null
  fi || vbw_die "this clone's settings file is damaged ($file); delete it and set again"
  mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
}

# Absolute path of the enclosing git repository, or die.
vbw_git_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || vbw_die "not a git repository (VBW needs git: it commits with provenance)"
  printf '%s\n' "$root"
}

# Sets VBW_ROOT, VBW_DIR, VBW_RECORD and VBW_RUNTIME for the current project.
vbw_project() {
  VBW_ROOT=$(vbw_git_root)
  VBW_DIR="$VBW_ROOT/.vbw"
  VBW_RECORD="$VBW_DIR/record.json"
  VBW_RUNTIME="$VBW_DIR/runtime"
}

vbw_require_project() {
  vbw_project
  [ -f "$VBW_RECORD" ] || vbw_die "not a VBW project (run /vbw:init)"
  mkdir -p "$VBW_RUNTIME"
}

# SHA-256 hex digest of stdin (GNU coreutils or BSD/macOS shasum).
vbw_sha256() {
  local out
  if command -v sha256sum > /dev/null 2>&1; then
    out=$(sha256sum)
  else
    out=$(shasum -a 256)
  fi
  printf '%s\n' "${out%% *}"
}

# The git tree id of the project's files as they are now (tracked and new,
# committed or not; ignored files, .vbw/ and a kept VBW 1 .vbw-planning/
# excluded): a content fingerprint that no commit changes. Built in a temporary
# index seeded from the real one, so only changed files are rehashed; the
# user's index and files are untouched.
# vbw_head_tree: the tree of the committed code (HEAD, without .vbw and
# .vbw-planning), which is what vbw prove runs on: the fingerprint of what a
# proof proved. Prints nothing when there is no commit yet.
vbw_head_tree() {
  local idx status
  git -C "$VBW_ROOT" rev-parse -q --verify HEAD > /dev/null 2>&1 || return 0
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  vbw_guard_add file "$idx"
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    git read-tree HEAD &&
      git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning > /dev/null 2>&1 &&
      git write-tree
  )
  status=$?
  vbw_guard_drop "$idx"
  return $status
}

vbw_code_tree() {
  local idx real
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  vbw_guard_add file "$idx"
  real=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-path index)
  if [ -f "$real" ]; then cp "$real" "$idx"; else rm -f "$idx"; fi
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    git add -A -- . ':(exclude).vbw' ':(exclude).vbw-planning' > /dev/null 2>&1 &&
      git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning > /dev/null 2>&1 &&
      git write-tree
  )
  local status=$?
  vbw_guard_drop "$idx"
  return $status
}

# Modification time in epoch seconds. GNU stat first: on Linux, BSD's `stat -f`
# means "file system status" and succeeds with other output, while macOS rejects
# GNU's `-c`. Only a number is ever returned (0 when it cannot be read).
vbw_mtime() {
  local t
  t=$(stat -c %Y "$1" 2>/dev/null) || t=$(stat -f %m "$1" 2>/dev/null) || t=0
  case "$t" in "" | *[!0-9]*) t=0 ;; esac
  printf '%s\n' "$t"
}

# vbw_stamp_newer DIR FILE...: gives each FILE (a path under DIR) a modification
# time one second later than the newest file under DIR, build output included. The
# time comes from the files' times, never from the clock, so it holds when a file is
# stamped ahead of now. A missing FILE is left missing.
vbw_stamp_newer() {
  local dir="$1" newest t f stamp
  shift
  newest=0
  while IFS= read -r -d '' f; do
    t=$(vbw_mtime "$f")
    if [ "$t" -gt "$newest" ]; then newest=$t; fi
  done < <(find "$dir" ! -type d -print0 2> /dev/null)
  t=$((newest + 1))
  stamp=$(date -d "@$t" +%Y%m%d%H%M.%S 2> /dev/null) || stamp=$(date -r "$t" +%Y%m%d%H%M.%S 2> /dev/null) || return 0
  for f in "$@"; do
    if [ -e "$dir/$f" ] || [ -L "$dir/$f" ]; then touch -h -t "$stamp" "$dir/$f" 2> /dev/null || touch -t "$stamp" "$dir/$f" 2> /dev/null || true; fi
  done
}

# vbw_dirty_files FILE...: those of the project-relative FILEs that differ from
# HEAD or are new, comma-separated.
vbw_dirty_files() {
  [ $# -gt 0 ] || return 0
  local f out=""
  while IFS= read -r -d '' f; do out="$out${out:+, }$f"; done \
    < <(cd "$VBW_ROOT" && { git diff --name-only -z HEAD -- "$@"; git ls-files -z --others --exclude-standard -- "$@"; })
  printf '%s' "$out"
}
