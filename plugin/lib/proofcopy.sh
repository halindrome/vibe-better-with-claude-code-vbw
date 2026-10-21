#!/usr/bin/env bash
# The clean copy vbw prove runs on (docs/proof.md): a detached git worktree of
# HEAD inside the project, so uncommitted changes and untracked files change no
# proof result. Git-ignored paths (dependencies, env files) are copied in, never
# linked (a copy-on-write clone where the file system offers one, a plain copy
# where it refuses), so the copy shares no writable folder with the working
# folder. Build output is not environment: the copy builds its own, so no
# artifact of a proof points into the working folder or another copy.
#
# A copy's folder is .vbw/runtime/proof.PID.XXXXXX: PID is the vbw process that
# made it. The next proof (proofcopy_create_slots) removes each copy whose owner
# has ended (kill -0 fails), never one whose owner runs. A copy without an owner
# part (proof.XXXXXX, an older VBW) goes only when over 24 hours old. A dead
# copy is first claimed by one atomic mv to proof.$$.swept-<its name>, so a
# second cleanup sees a live owner and leaves it, and a cleanup killed partway
# leaves a folder whose owner has ended. A copy that will not go prints one
# warning line and the proof goes on.

# Build-output folder names (Node, Python, Rust, Go and the like), at any depth.
PROOFCOPY_BUILD_DIRS='target dist build bin out __pycache__ .pytest_cache .mypy_cache .ruff_cache .tox .next .nuxt .gradle coverage'

# proofcopy_is_build_dir PATH: PATH's last segment names a build folder.
proofcopy_is_build_dir() {
  local b=${1##*/} n
  for n in $PROOFCOPY_BUILD_DIRS; do
    [ "$b" != "$n" ] || return 0
  done
  return 1
}

# proofcopy_slots WORK: how many copies to make for WORK pieces of work: one per
# parallel slot, as many as check_jobs allows and the work needs (at least 1).
proofcopy_slots() {
  local n
  n=$(vbw_check_jobs) || n=1
  [ "$1" -ge "$n" ] || n=$1
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n"
}

# proofcopy_create: make the copy; sets PROOF_COPY (absolute path). Called
# directly, never in $(...), so the guard that removes it on interrupt holds.
proofcopy_create() {
  proofcopy_create_slots 1
}

# proofcopy_create_slots N: make N copies, each made like the single one; sets
# PROOF_COPIES (all of them) and PROOF_COPY (the first). Called directly, never
# in $(...). proofcopy_remove removes every one, and so does an interrupt.
proofcopy_create_slots() {
  local i
  PROOF_COPIES=()
  proofcopy_sweep
  for ((i = 0; i < $1; i++)); do proofcopy_make; done
  PROOF_COPY=${PROOF_COPIES[0]}
}

# proofcopy_sweep: remove the proof copies whose owner has ended. Never fails.
proofcopy_sweep() {
  local d n rest pid claim
  for d in "$VBW_RUNTIME"/proof.*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    n=${d##*/}
    rest=${n#proof.}
    pid=${rest%%.*}
    if [ "$pid" != "$rest" ] && [ -n "${rest#*.}" ] && [ -n "$pid" ] && [ -z "${pid//[0-9]/}" ]; then
      ! kill -0 "$pid" 2> /dev/null || continue
    else
      [ -n "$(find "$d" -maxdepth 0 -mmin +1440 -print 2> /dev/null)" ] || continue
    fi
    claim="$VBW_RUNTIME/proof.$$.swept-$n"
    [ ! -e "$claim" ] || continue
    mv "$d" "$claim" 2> /dev/null || continue
    chmod -R u+rwx "$claim" > /dev/null 2>&1 || true
    rm -rf "$claim" > /dev/null 2>&1 || true
    git -C "$VBW_ROOT" worktree prune > /dev/null 2>&1 || true
    [ ! -e "$claim" ] || printf 'vbw: cannot remove the leftover proof copy %s; remove it by hand\n' ".vbw/runtime/${claim##*/}" >&2
  done
  return 0
}

# proofcopy_make: one more copy, added to PROOF_COPIES.
proofcopy_make() {
  local dir p l t real copy
  dir=$(mktemp -d "$VBW_RUNTIME/proof.$$.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  copy="$dir/tree"
  PROOF_COPIES+=("$copy")
  PROOF_COPY=$copy
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  git -C "$VBW_ROOT" -c core.hooksPath=/dev/null worktree add -q --detach "$copy" HEAD > /dev/null 2>&1 \
    || { proofcopy_remove; vbw_die "cannot make a clean copy of the committed code (does the project have a commit?)"; }
  real=$(cd -P "$VBW_ROOT" && pwd -P) || vbw_die "cannot resolve $VBW_ROOT"
  while IFS= read -r -d '' p; do
    p=${p%/}
    case "$p" in .git | .git/* | .vbw | .vbw/*) continue ;; esac
    ! proofcopy_is_build_dir "$p" || continue
    [ ! -e "$copy/$p" ] && [ ! -L "$copy/$p" ] || continue
    mkdir -p "$copy/$(dirname "$p")"
    proofcopy_copy "$VBW_ROOT/$p" "$copy/$p" || { proofcopy_remove; vbw_die "cannot copy the ignored path $p into the clean copy (is it readable?)"; }
    while IFS= read -r -d '' l; do
      t=$(readlink "$copy/$l")
      case "$t" in /*) t=$(cd -P "$(dirname "$t")" 2> /dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$t")") || t=$(readlink "$copy/$l") ;; esac
      # A link into .vbw (an old proof copy) is the stale-link scan's to report.
      case "$t" in "$real"/.vbw | "$real"/.vbw/*) ;; "$real" | "$real"/*)
        vbw_out 'vbw: %s links into the working folder (%s); it is copied as a link\n' "$l" "$(readlink "$copy/$l")" >&2 ;;
      esac
    done < <(cd "$copy" && find "$p" -type l -print0)
  done < <(git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard --directory)
}

# proofcopy_warn_stale: read-only scan of the working folder (git-ignored
# folders included, links never followed, .git and .vbw skipped) naming each
# link that points into this project's proof copies, with the repair. Says
# nothing when there is none. Never fails.
proofcopy_warn_stale() {
  local real l t n d r fix='re-run the project install command'
  real=$(cd -P "$VBW_ROOT" 2> /dev/null && pwd -P) || return 0
  [ ! -f "$VBW_ROOT/pnpm-lock.yaml" ] && [ ! -f "$VBW_ROOT/pnpm-workspace.yaml" ] || fix='delete node_modules and run pnpm install'
  while IFS= read -r -d '' l; do
    t=$(readlink "$l") || continue
    case "$t" in /*) ;; *) t="$(cd -P "$(dirname "$l")" 2> /dev/null && pwd -P)/$t" ;; esac
    # Fold . and .. away, then resolve the deepest folder that still exists.
    n=$(printf '%s' "$t" | awk -F/ '{for (i = 1; i <= NF; i++) if ($i == "..") { if (k) k-- } else if ($i != "" && $i != ".") p[++k] = $i; for (i = 1; i <= k; i++) printf "/%s", p[i]}')
    d=$n; while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
    r=$(cd -P "$d" 2> /dev/null && pwd -P)${n#"$d"}
    case "$n:$r" in "$VBW_ROOT/.vbw/runtime/proof."* | "$real/.vbw/runtime/proof."* | *":$real/.vbw/runtime/proof."*)
      vbw_out 'vbw: %s -> %s points into a proof copy of an earlier run; %s\n' "${l#./}" "$t" "$fix" >&2 ;;
    esac
  done < <(cd "$VBW_ROOT" && find . \( -name .git -o -path ./.vbw \) -prune -o -type l -print0 2> /dev/null)
}

# proofcopy_copy SRC DST: a copy-on-write clone first, a plain copy when the
# file system refuses; links inside stay links. A failed try leaves nothing.
proofcopy_copy() {
  local flag=--reflink
  [ "$(uname)" != Darwin ] || flag=-c
  cp -RP "$flag" "$1" "$2" 2> /dev/null && return 0
  rm -rf "$2" 2> /dev/null || true
  cp -RP "$1" "$2" 2> /dev/null && return 0
  chmod -R u+rwx "$2" 2> /dev/null || true
  rm -rf "$2"
  return 1
}

# proofcopy_remove: drop every copy's worktree and whatever is left of its
# directory, read-only folders included (rm never follows a link out of a copy).
proofcopy_remove() {
  local c
  for c in ${PROOF_COPIES[@]+"${PROOF_COPIES[@]}"}; do
    chmod -R u+rwx "$c" 2> /dev/null || true
    git -C "$VBW_ROOT" worktree remove --force "$c" > /dev/null 2>&1 || true
    vbw_guard_drop "$(dirname "$c")"
  done
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  PROOF_COPIES=()
  PROOF_COPY=
}

# proofcopy_verify HASH RECORD: die naming every check file whose committed
# bytes differ from the approved ones.
proofcopy_verify() {
  local f bad=""
  [ "$(VBW_ROOT="$PROOF_COPY" contract_hash "$2")" != "$1" ] || return 0
  while IFS= read -r -d '' f; do
    cmp -s "$VBW_ROOT/$f" "$PROOF_COPY/$f" 2> /dev/null || bad="$bad $f"
  done < <(printf '%s' "$2" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  proofcopy_remove
  vbw_die "check files not committed as approved:${bad:- (the committed contract differs)}: commit them, then ask the user with the approval menu (AskUserQuestion)"
}
