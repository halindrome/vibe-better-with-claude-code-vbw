#!/usr/bin/env bash
# The loop's park (R179; docs/loop.md, Retry once, then park): the item in progress is given up with
# its reason. Its commits are reverted (history kept, nothing rewritten), its work leaves the record
# and the spec, its milestone is parked and the backlog entry stays open. Sourced by the loop step and
# by vbw loop park.

# loop_park_reverts HEAD: reverts, newest first, the commits since HEAD that touch a file outside
# .vbw/ (VBW's own record commits are reconciled by the park's record update, never reverted). A
# commit touching a file the user staged or edited by hand, or one that does not revert cleanly, is
# left and named. A revert runs on a private index, so what the user staged stays staged. Sets
# LOOP_PARK_REVERTED (full hashes, newest first) and LOOP_PARK_LEFT (what was left and why).
loop_park_reverts() {
  local c f d hand code vbwfiles idx files=() dirty=() hash
  LOOP_PARK_REVERTED=""
  LOOP_PARK_LEFT=""
  idx="$VBW_RUNTIME/park.index"
  while IFS= read -r -d '' f; do dirty+=("$f"); done < <(git -C "$VBW_ROOT" diff --name-only -z HEAD)
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    files=()
    code=0 vbwfiles=0
    while IFS= read -r -d '' f; do
      files+=("$f")
      case "$f" in .vbw/*) vbwfiles=1 ;; *) code=1 ;; esac
    done < <(git -C "$VBW_ROOT" diff-tree --no-commit-id --name-only -r -z --root "$c")
    # A record-only commit (vbw's own) is not the item's work; one that changes code and the record
    # together cannot be reverted without touching the record, so it is left and named.
    [ "$code" = 1 ] || continue
    if [ "$vbwfiles" = 1 ]; then
      LOOP_PARK_LEFT="$LOOP_PARK_LEFT${LOOP_PARK_LEFT:+; }${c:0:7} (changes the record too)"
      continue
    fi
    hand=""
    for f in "${files[@]}"; do
      for d in ${dirty[@]+"${dirty[@]}"}; do [ "$f" = "$d" ] && hand=$f; done
    done
    if [ -n "$hand" ]; then
      LOOP_PARK_LEFT="$LOOP_PARK_LEFT${LOOP_PARK_LEFT:+; }${c:0:7} (you changed $hand)"
      continue
    fi
    vbw_guard_add file "$idx"
    if GIT_INDEX_FILE="$idx" git -C "$VBW_ROOT" read-tree HEAD > /dev/null 2>&1 \
      && GIT_INDEX_FILE="$idx" git -C "$VBW_ROOT" revert --no-edit "$c" > /dev/null 2>&1; then
      hash=$(git -C "$VBW_ROOT" rev-parse HEAD)
      git -C "$VBW_ROOT" reset -q HEAD -- "${files[@]}" > /dev/null 2>&1 || true
      LOOP_PARK_REVERTED="$LOOP_PARK_REVERTED${LOOP_PARK_REVERTED:+ }$hash"
    else
      GIT_INDEX_FILE="$idx" git -C "$VBW_ROOT" revert --abort > /dev/null 2>&1 || true
      LOOP_PARK_LEFT="$LOOP_PARK_LEFT${LOOP_PARK_LEFT:+; }${c:0:7} (does not revert cleanly)"
    fi
    rm -f "$idx"
    vbw_guard_drop "$idx"
  done < <(git -C "$VBW_ROOT" rev-list --no-merges "$1..HEAD")
}

# loop_park REASON: parks the item in progress (see the top of this file). The record changes in one
# update; the record, the spec and the removed check files are committed as chore(vbw): park ITEM.
loop_park() {
  local reason=$1 rec id text head m cost total reverts left leftrec said rmreq spec files=() f tmp keep=() drop=() stay=""
  rec=$(record_read)
  id=$(printf '%s' "$rec" | jq -r '[.loop.items[] | select(.status == "in_progress")][0].id')
  text=$(printf '%s' "$rec" | jq -r --arg i "$id" '.loop.items[] | select(.id == $i) | .text')
  head=$(printf '%s' "$rec" | jq -r --arg i "$id" '.loop.items[] | select(.id == $i) | .head // empty')
  m=$(printf '%s' "$rec" | jq -r .milestone.id)
  # The cost is read before anything changes: the item's own, and the milestone's frozen as a ship does.
  cost=$(loop_spend "$VBW_RECORD" "$id" | jq -c 'if . == null then null else del(.sessions) end')
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  total=$(costs_milestone_total "$VBW_RECORD" "$m")
  left=""
  # The requirements the park removes: the milestone's own, never a [human] one carried in from a shipped
  # milestone (it goes back to be judged by the user).
  rmreq=$(printf '%s' "$rec" | jq -c '. as $r | .milestone.id as $m
    | [.requirements[] | select(.milestone == $m)
        | select((.proof == "human" and (.id as $i | any($r.phases[]; .milestone != $m and any(.reqs[]; . == $i)))) | not) | .id]')
  # The check files that go: those of the removed checks that no remaining check names.
  while IFS= read -r -d '' f; do files+=("$f"); done < <(printf '%s' "$rec" | jq -j --argjson rm "$rmreq" '
    . as $r | [$r.fixes[] | select(has("req") and (.req as $q | any($rm[]; . == $q))) | .id] as $fx
    | [$r.checks[] | select((.req as $q | any($rm[]; . == $q)) or ((.fix // "") as $x | any($fx[]; . == $x)))] as $gone
    | ([$r.checks[] | select(. as $c | any($gone[]; .id == $c.id) | not) | .files // [] | .[]]) as $kept
    | [$gone[] | .files // [] | .[] | select(. as $p | any($kept[]; . == $p) | not)] | unique[] | . + "\u0000"')
  # A check file the user changed by hand stays where it is, named.
  for f in ${files[@]+"${files[@]}"}; do
    if [ -n "$(vbw_dirty_files "$f")" ]; then stay="$stay${stay:+, }$f"; else drop+=("$f"); fi
  done
  [ -z "$stay" ] || left="$left; left in place (you changed it): $stay"
  # The item's work leaves the record first, while the kernel that wrote it still reads it: its own commits
  # may have changed that kernel (VBW built with VBW), and the reverts below bring back the one before (T153).
  record_update "$VBW_JQ_DEFS"'. as $r | .milestone.id as $m
    | def has_it($l; $i): any($l[]; . == $i);
      ([.phases[] | select(.milestone == $m) | .id]) as $ph
    | ([.fixes[] | select(has("req") and has_it($rm; .req)) | .id]) as $fx
    | ([.checks[] | select(has_it($rm; .req) or ((.fix // "") as $x | has_it($fx; $x))) | .id]) as $ck
    | .requirements |= (map(select(.id as $i | has_it($rm; $i) | not))
        | map(if .milestone == $m then . + {skipped: true, later: true,
              milestone: ((.id as $i | [$r.phases[] | select(.milestone != $m and has_it(.reqs; $i))] | last | .milestone) // $m)} else . end))
    | .phases |= map(select(.milestone != $m))
    | .plans |= map(select(.phase as $p | has_it($ph; $p) | not))
    | .checks |= map(select(.id as $c | has_it($ck; $c) | not))
    | .fixes |= map(select(.id as $f | has_it($fx; $f) | not))
    | (if (.evidence | type) == "object"
       then .evidence.checks |= with_entries(select(.key as $k | has_it($ck; $k) | not)) | .evidence.scope = [] else . end)
    | (.loop.items[] | select(.id == $id)) |= (.status = "parked" | .reason = $reason | .reverts = [] | .cost = $cost | .at = $at)
    | (.todos[] | select(.id == $id)).status = "open"
    | .milestone.status = "parked"
    | .parked = ((.parked // []) + [{id: $m, title: .milestone.title, at: $at, reason: $reason, ids: ($ph + $rm + $fx)}])
    | (if $total == null then . else .costs.milestones[$m] = ((.costs.milestones[$m] // {baseline: {}}) + {total: $total}) end)' \
    --argjson rm "$rmreq" --arg id "$id" --arg reason "$reason" --argjson cost "$cost" \
    --argjson total "$total" --arg at "$(vbw_now)"
  if [ -n "$head" ]; then loop_park_reverts "$head"; else LOOP_PARK_REVERTED=""; LOOP_PARK_LEFT=""; fi
  reverts=$(for f in $LOOP_PARK_REVERTED; do printf '%s\n' "$f"; done | jq -Rsc 'split("\n") | map(select(length > 0))')
  [ -z "$LOOP_PARK_LEFT" ] || left="; left unreverted: $LOOP_PARK_LEFT$left"
  leftrec="${left#; }"
  said=""
  for f in $LOOP_PARK_REVERTED; do said="$said${said:+, }${f:0:7}"; done
  said="reverted ${said:-nothing}"
  record_update "$VBW_JQ_DEFS"'(.loop.items[] | select(.id == $id)) |= (.reverts = $reverts | if $leftrec == "" then . else .left = $leftrec end)
    | .decisions += [{id: (.decisions | next_id("D")), at: $at,
        text: ("Parked \($id) (\($text)): \($reason); \($said)\($left); milestone \($m) is parked, the backlog entry stays open; to bring the work back revert the reverts or run the item again")}]' \
    --arg id "$id" --arg reason "$reason" --argjson reverts "$reverts" --arg m "$m" \
    --arg at "$(vbw_now)" --arg text "$text" --arg said "$said" --arg left "$left" --arg leftrec "$leftrec"
  # The item's lines leave the spec; the removed check files leave the tree.
  spec="$VBW_ROOT/.vbw/spec.md"
  if [ -f "$spec" ]; then
    tmp=$(mktemp "$VBW_RUNTIME/spec.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
    vbw_guard_add file "$tmp"
    grep -Ev "^- ($(printf '%s' "$rmreq" | jq -r 'join("|")')) " "$spec" > "$tmp" || true
    cat "$tmp" > "$spec"
    rm -f "$tmp"
    vbw_guard_drop "$tmp"
  fi
  keep=(.vbw/record.json .vbw/spec.md)
  for f in ${drop[@]+"${drop[@]}"}; do
    rm -f "$VBW_ROOT/$f"
    git -C "$VBW_ROOT" cat-file -e "HEAD:$f" 2> /dev/null && keep+=("$f")
  done
  (
    vbw_guard_reset
    cd "$VBW_ROOT" || exit 1
    record_lock
    git commit --quiet --only -m "chore(vbw): park $id" -- "${keep[@]}" > /dev/null 2>&1 \
      || printf 'vbw: warning: could not commit the park of %s; commit .vbw yourself\n' "$id" >&2
    record_unlock
  )
  printf 'parked %s: %s; %s\n' "$id" "$reason" "$said"
}
