#!/usr/bin/env bash
# The record's own history (docs/proof.md, "Whose commits VBW judges"): the
# commits made since this record was born. VBW's trailers (VBW-Plan, VBW-Fix,
# VBW-Req) carry bare ids, and ids restart when a project starts a new record:
# a retired roadmap (VBW 1, or a record removed and made again) left commits
# whose trailers name ids the new record uses again. A commit older than the
# record cannot be one of its plans' commits: the record is born with its first
# commit, and `vbw approve` commits the record before any build can commit.
# So every reader of trailers walks only the commits after the newest commit
# that added .vbw/record.json; a project whose record was never committed walks
# its whole history, as before.

# history_base: the newest commit that added .vbw/record.json, or nothing.
history_base() {
  git -C "$VBW_ROOT" log --diff-filter=A --format=%H -1 -- .vbw/record.json 2> /dev/null || true
}

# history_args: sets HISTORY_ARGS, the revisions a `git log` of the record's own
# history takes: HEAD, then ^PARENT for each parent of the record's birth commit
# (the birth commit itself adds no plan work, so including it changes nothing).
# Use: git log [options] "${HISTORY_ARGS[@]}" (before any "--").
history_args() {
  local base p
  HISTORY_ARGS=(HEAD)
  base=$(history_base)
  [ -n "$base" ] || return 0
  while IFS= read -r p; do
    [ -z "$p" ] || HISTORY_ARGS+=("^$p")
  done < <(git -C "$VBW_ROOT" rev-parse "$base^@" 2> /dev/null)
}
