#!/usr/bin/env bash
# The loop's step (R178; docs/loop.md): approval by delegation. Sourced by vbw loop next.

# loop_matches RECORD: 0 when the current milestone's requirements, minus the [human] ones built in a
# phase of an earlier milestone (carried over by a ship), are at least one and each one's text equals
# the text of a distinct item on this loop's list (a text asked for twice needs two items).
loop_matches() {
  printf '%s' "$1" | jq -e '
    def norm: [splits("\\s+") | select(length > 0)] | join(" ");
    . as $r | .milestone.id as $m
    | [.requirements[] | select(.milestone == $m)
        | select((.proof == "human" and (.id as $i | any($r.phases[]; .milestone != $m and any(.reqs[]; . == $i)))) | not)
        | .text | norm] as $want
    | [.loop.items[].text | sub("^\\[(human|auto)\\] "; "") | norm] as $have
    | ($want | length) > 0
      and all($want | unique[]; . as $t | ($want | map(select(. == $t)) | length) <= ($have | map(select(. == $t)) | length))' > /dev/null
}

# loop_delegate RECORD NEXT_JSON: when the loop is on, not stopping and not ended, vbw next asks for the
# contract's approval (not the test files' one), the contract is ready and its requirements are the
# loop's items, the kernel approves it on the user's behalf. Otherwise nothing changes.
loop_delegate() {
  local record=$1 hash text
  printf '%s' "$record" | jq -e '.loop != null and .loop.stopping == null and .loop.ended == null' > /dev/null || return 0
  printf '%s' "$2" | jq -e '.action == "approve" and .gate == true and (.detail.files == null)' > /dev/null || return 0
  [ -z "$(approve_problems "$record")" ] || return 0
  loop_matches "$record" || return 0
  hash=$(contract_hash "$record")
  text=$(printf '%s' "$record" | jq -r --arg h "${hash:0:12}" '
    "Contract approved by the loop on the user'"'"'s behalf (loop started \(.loop.started_at), items \([.loop.items[].id] | join(", ")): \(.requirements | length) requirements, \(.checks | length) checks, \(.plans | length) plans (\($h)))"')
  approve_record "$record" "$hash" "$text" > /dev/null
}

# loop_ended_answer RECORD: what an ended loop answers: done at the end of its list, else stopped.
loop_ended_answer() {
  printf '%s' "$1" | jq -c '.loop.ended.reason as $r
    | {action: (if ($r | startswith("end of the list")) then "done" else "stopped" end), reason: $r}'
}

# loop_end REASON: the loop ends here: written once, committed, and answered.
loop_end() {
  record_update '.loop.ended = {at: $at, reason: $r}' --arg at "$(vbw_now)" --arg r "$1"
  record_commit "chore(vbw): loop ended" .vbw/record.json
  loop_ended_answer "$(record_read)"
}

# loop_commit ITEM ACTION: the step's record changes, committed with the record.
loop_commit() { record_commit "chore(vbw): loop $1 $2" .vbw/record.json .vbw/spec.md; }

# loop_emit NEXT_JSON: vbw next's answer with the loop object (item, spend, ceiling, word) added.
loop_emit() {
  local rec spend word
  rec=$(record_read)
  spend=$(loop_spend "$VBW_RECORD")
  word=$(loop_word "$VBW_RECORD" "$spend")
  printf '%s' "$1" | jq -c --slurpfile r <(printf '%s' "$rec") --argjson spend "$spend" --arg word "$word" '
    $r[0].loop as $l
    | ([$l.items | to_entries[] | select(.value.status == "in_progress")][0]) as $cur
    | . + {loop: {item: (if $cur == null then null else {id: $cur.value.id, text: $cur.value.text, n: ($cur.key + 1), of: ($l.items | length)} end),
        spend: $spend, ceiling: $l.ceiling, word: (if $word == "null" then null else $word end)}}'
}

# loop_ceiling_reason: the reason to stop on the ceiling (printed, status 0), or status 1 when the
# spend is under it.
loop_ceiling_reason() {
  local spend word
  spend=$(loop_spend "$VBW_RECORD")
  word=$(loop_word "$VBW_RECORD" "$spend")
  case "$word" in
    reached) jq -r --argjson s "$spend" "$LOOP_USD_JQ"'"ceiling reached: \($s.usd | usd) spent of a \(.loop.ceiling.usd | usd) ceiling"' "$VBW_RECORD" ;;
    "cannot tell") printf 'cannot tell what was spent (no figure seen): vbw statusline on\n' ;;
    *) return 1 ;;
  esac
}

# loop_open_item RECORD ITEM: opens the item's milestone (started when the current one is shipped or
# parked, renamed when it is active with no requirements of its own), adds its requirement (unless
# the milestone already holds it), and marks it and its backlog entry in progress. Status 1 and the reason on stdout when the milestone
# cannot be opened.
loop_open_item() {
  local rec=$1 id=$2 text proof title m head base
  text=$(printf '%s' "$rec" | jq -r --arg i "$id" '.loop.items[] | select(.id == $i) | .text')
  proof=$(loop_item_proof "$text")
  title=$(loop_item_text "$text")
  if printf '%s' "$rec" | jq -e '.milestone.status != "active"' > /dev/null; then
    cmd_milestone start "$title" > /dev/null
    cmd_spec add "$proof" "$title" > /dev/null
  elif printf '%s' "$rec" | jq -e '. as $r | .milestone.id as $m | any($r.requirements[]; .milestone == $m
      and ((.proof == "human" and (.id as $i | any($r.phases[]; .milestone != $m and any(.reqs[]; . == $i)))) | not)) | not' > /dev/null; then
    cmd_milestone rename "$title" > /dev/null
    cmd_spec add "$proof" "$title" > /dev/null
  elif ! printf '%s' "$rec" | jq -e --arg t "$(loop_norm "$title")" '.milestone.id as $m | any(.requirements[]; .milestone == $m and .text == $t)' > /dev/null; then
    printf '%s has requirements of its own and is not shipped: finish or ship it first (vbw next)\n' "$(printf '%s' "$rec" | jq -r .milestone.id)"
    return 1
  fi
  # Otherwise the milestone already holds the item's requirement (asked for before the loop took it up).
  m=$(jq -r .milestone.id "$VBW_RECORD")
  head=$(git -C "$VBW_ROOT" rev-parse HEAD)
  base=$(loop_figures_now)
  record_update '(.loop.items[] | select(.id == $i)) |= (.status = "in_progress" | .milestone = $m | .head = $h | .baseline = $b)
    | (.todos[] | select(.id == $i)).status = "in_progress"' --arg i "$id" --arg m "$m" --arg h "$head" --argjson b "$base"
  loop_commit "$id" open
}

# loop_ship_item ITEM: vbw ship, then the item shipped with its own cost and its backlog entry done.
loop_ship_item() {
  local id=$1 cost
  cmd_ship > /dev/null
  cost=$(loop_spend "$VBW_RECORD" "$id" | jq -c 'if . == null then null else del(.sessions) end')
  record_update '(.loop.items[] | select(.id == $i)) |= (.status = "shipped" | .cost = $c | .at = $at)
    | (.todos[] | select(.id == $i)).status = "done"' --arg i "$id" --argjson c "$cost" --arg at "$(vbw_now)"
  loop_commit "$id" ship
}

# loop_step: one call of vbw loop next. Stops come first (a run of this session is vbw next's answer,
# never killed); then the kernel-only actions are done one after the other, the record read afresh each
# time, until an agent step or a proof is due (vbw next's answer with the loop object), the list is
# finished (done) or the loop must stop. vbw next itself is only read.
loop_step() {
  # shellcheck source=cmd-milestone.sh
  . "$VBW_LIB/cmd-milestone.sh"
  # shellcheck source=cmd-spec.sh
  . "$VBW_LIB/cmd-spec.sh"
  # shellcheck source=cmd-req.sh
  . "$VBW_LIB/cmd-req.sh"
  # shellcheck source=cmd-ship.sh
  . "$VBW_LIB/cmd-ship.sh"
  local rec next cur waiting action why n
  while :; do
    rec=$(record_read)
    if printf '%s' "$rec" | jq -e --arg s "$(vbw_session)" '.lease != null and (.lease.session == null or .lease.session == $s)' > /dev/null; then
      next=$(cmd_next --json) || exit $?
      loop_emit "$next"; return 0
    fi
    if printf '%s' "$rec" | jq -e '.lease != null' > /dev/null; then
      loop_end "$(printf '%s' "$rec" | jq -r '"a run of another session (\(.lease.session)) is open"')"; return 0
    fi
    if printf '%s' "$rec" | jq -e '.loop.stopping != null' > /dev/null; then
      loop_end "$(printf '%s' "$rec" | jq -r '.loop.stopping | "stopped by the user (\(if .session == null then "no session" else "session \(.session)" end))"')"; return 0
    fi
    cur=$(printf '%s' "$rec" | jq -r '[.loop.items[] | select(.status == "in_progress")][0].id // empty')
    waiting=$(printf '%s' "$rec" | jq -r '[.loop.items[] | select(.status == "waiting")][0].id // empty')
    # The ceiling: before every step, or with --finish-item only before an item is opened.
    if printf '%s' "$rec" | jq -e '.loop.ceiling != null' > /dev/null \
      && { printf '%s' "$rec" | jq -e '.loop.ceiling.finish_item | not' > /dev/null || { [ -z "$cur" ] && [ -n "$waiting" ]; }; }; then
      if why=$(loop_ceiling_reason); then loop_end "$why"; return 0; fi
    fi
    if [ -z "$cur" ]; then
      if [ -z "$waiting" ]; then
        loop_end "$(printf '%s' "$rec" | jq -r '"end of the list: \([.loop.items[] | select(.status == "shipped")] | length) shipped, \([.loop.items[] | select(.status == "parked")] | length) parked"')"; return 0
      fi
      if ! why=$(loop_open_item "$rec" "$waiting"); then
        loop_end "$why (item $waiting, step open)"; return 0
      fi
      continue
    fi
    next=$(cmd_next --json) || exit $?
    action=$(printf '%s' "$next" | jq -r .action)
    if [ "$action" = approve ]; then
      loop_delegate "$rec" "$next"
      next=$(cmd_next --json) || exit $?
      action=$(printf '%s' "$next" | jq -r .action)
    fi
    case "$action" in
      accept)
        # A [human] requirement is the user's to judge: skipped, never accepted or rejected.
        for n in $(printf '%s' "$next" | jq -r '.detail.requirements[]'); do cmd_req skip "$n" > /dev/null; done
        loop_commit "$cur" accept ;;
      ship)
        loop_ship_item "$cur" ;;
      plan | build | fix | qa | prove | run)
        loop_emit "$next"; return 0 ;;
      *)
        loop_end "$(printf '%s' "$next" | jq -r --arg t "$cur" '"\(.action) needs you: \(.instruction) (item \($t), step \(.action))"')"; return 0 ;;
    esac
  done
}
