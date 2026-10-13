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
  approve_record "$record" "$hash" "$text" "$(printf '%s' "$record" | jq -r '"by the loop on the user'"'"'s behalf (loop started \(.loop.started_at), items \([.loop.items[].id] | join(", ")))"')" > /dev/null
}

# loop_ended_answer RECORD: what an ended loop answers: done at the end of its list, else stopped.
loop_ended_answer() {
  printf '%s' "$1" | jq -c '.loop.ended.reason as $r
    | {action: (if ($r | startswith("end of the list")) then "done" else "stopped" end), reason: $r}'
}

# loop_commit_report MESSAGE: the report written from the record and committed with it (and the spec).
loop_commit_report() {
  # shellcheck source=loop-report.sh
  . "$VBW_LIB/loop-report.sh"
  record_update '.loop.report = ".vbw/loop-report.md"'
  loop_report_write "$VBW_RECORD"
  record_commit "$1" .vbw/record.json .vbw/spec.md .vbw/loop-report.md
}

# loop_end REASON: the loop ends here: written once, committed with the report, and answered.
loop_end() {
  record_update '.loop.ended = {at: $at, reason: $r}' --arg at "$(vbw_now)" --arg r "$1"
  loop_commit_report "chore(vbw): loop ended"
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

# loop_kernel CMD...: runs a kernel step the loop takes itself (milestone start, spec add, ship) in a
# subshell, so a refusal (vbw_die exits) cannot end the step in silence: the refusal's words come
# back on stdout with status 1, for the loop to end with that reason (F179).
loop_kernel() {
  local err out
  err=$(mktemp "$VBW_RUNTIME/loop-kernel.XXXXXX") || { printf 'cannot create a temporary file in %s\n' "$VBW_RUNTIME"; return 1; }
  if ( "$@" ) > /dev/null 2> "$err"; then rm -f "$err"; return 0; fi
  out=$(sed 's/^vbw: //' "$err" | tr '\n' ' ' | cut -c1-300)
  rm -f "$err"
  printf '%s\n' "${out:-refused without a reason}"
  return 1
}

# loop_open_item RECORD ITEM: opens the item's milestone (started when the current one is shipped or
# parked, renamed when it is active with no requirements of its own), adds its requirement (unless
# the milestone already holds it), and marks it and its backlog entry in progress. Status 1 and the reason on stdout when the milestone
# cannot be opened.
loop_open_item() {
  local rec=$1 id=$2 text proof title m head base q
  text=$(printf '%s' "$rec" | jq -r --arg i "$id" '.loop.items[] | select(.id == $i) | .text')
  proof=$(loop_item_proof "$text")
  title=$(loop_item_text "$text")
  if printf '%s' "$rec" | jq -e '.milestone.status != "active"' > /dev/null; then
    loop_kernel cmd_milestone start "$title" || return 1
    loop_kernel cmd_spec add "$proof" "$title" || return 1
  elif printf '%s' "$rec" | jq -e '. as $r | .milestone.id as $m | any($r.requirements[]; .milestone == $m
      and ((.proof == "human" and (.id as $i | any($r.phases[]; .milestone != $m and any(.reqs[]; . == $i)))) | not)) | not' > /dev/null; then
    loop_kernel cmd_milestone rename "$title" || return 1
    loop_kernel cmd_spec add "$proof" "$title" || return 1
  elif ! printf '%s' "$rec" | jq -e --arg t "$(loop_norm "$title")" '.milestone.id as $m | any(.requirements[]; .milestone == $m and .text == $t)' > /dev/null; then
    printf '%s has requirements of its own and is not shipped: finish or ship it first (vbw next)\n' "$(printf '%s' "$rec" | jq -r .milestone.id)"
    return 1
  fi
  # Otherwise the milestone already holds the item's requirement (asked for before the loop took it up).
  m=$(jq -r .milestone.id "$VBW_RECORD")
  # The requirement's id is kept on the item: a later milestone start carries a skipped [human]
  # requirement away from this milestone, and the report still has to name it (F191).
  q=$(jq -r --arg m "$m" --arg t "$(loop_norm "$title")" '[.requirements[] | select(.milestone == $m and .text == $t)][0].id // empty' "$VBW_RECORD")
  head=$(git -C "$VBW_ROOT" rev-parse HEAD)
  base=$(loop_figures_now)
  record_update '(.loop.items[] | select(.id == $i)) |= (.status = "in_progress" | .milestone = $m | .head = $h | .baseline = $b
      | if $q == "" then . else .req = $q end)
    | (.todos[] | select(.id == $i)).status = "in_progress"' --arg i "$id" --arg m "$m" --arg h "$head" --argjson b "$base" --arg q "$q"
  loop_commit "$id" open
}

# loop_ship_item ITEM: vbw ship, then the item shipped with its own cost and its backlog entry done.
loop_ship_item() {
  local id=$1 cost why
  if ! why=$(loop_kernel cmd_ship); then loop_end "the ship was refused: $why (item $id, step ship)"; return 1; fi
  cost=$(loop_spend "$VBW_RECORD" "$id" | jq -c 'if . == null then null else del(.sessions) end')
  record_update '(.loop.items[] | select(.id == $i)) |= (.status = "shipped" | .cost = $c | .at = $at)
    | (.todos[] | select(.id == $i)).status = "done"' --arg i "$id" --argjson c "$cost" --arg at "$(vbw_now)"
  loop_commit_report "chore(vbw): loop $id ship"
}

# loop_park_item ITEM REASON: the item in progress is parked (loop-park.sh), the report refreshed.
loop_park_item() {
  # shellcheck source=loop-park.sh
  . "$VBW_LIB/loop-park.sh"
  loop_park "$2" > /dev/null
  loop_commit_report "chore(vbw): loop $1 park"
}

# loop_retry ITEM NEXT_JSON: at escalate (fixes) or unblock (plans), each one the item has not retried
# yet is retried once (vbw fix retry, vbw plan reset) and recorded; one already retried parks the item.
loop_retry() {
  local cur=$1 next=$2 key id ids why
  case "$(printf '%s' "$next" | jq -r .action)" in escalate) key=fixes ;; *) key=plans ;; esac
  ids=$(printf '%s' "$next" | jq -r --arg k "$key" '.detail[$k][]')
  for id in $ids; do
    if record_read | jq -e --arg i "$cur" --arg k "$key" --arg x "$id" '.loop.items[] | select(.id == $i) | ((.retried[$k] // []) | index($x)) != null' > /dev/null; then
      if [ "$key" = fixes ]; then why="fix $id escalated again after one retry"
      else why="plan $id blocked again after one reset: $(record_read | jq -r --arg x "$id" '.plans[] | select(.id == $x) | .note // "no note"')"; fi
      loop_park_item "$cur" "$why"; return 0
    fi
  done
  for id in $ids; do
    if [ "$key" = fixes ]; then cmd_fix retry "$id" > /dev/null; else cmd_plan reset "$id" > /dev/null; fi
    record_update '(.loop.items[] | select(.id == $i)).retried |= ((. // {fixes: [], plans: []}) | .[$k] += [$x])' --arg i "$cur" --arg k "$key" --arg x "$id"
  done
  loop_commit "$cur" retry
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
  # shellcheck source=cmd-fix.sh
  . "$VBW_LIB/cmd-fix.sh"
  # shellcheck source=cmd-plan.sh
  . "$VBW_LIB/cmd-plan.sh"
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
        loop_ship_item "$cur" || return 0 ;;
      escalate | unblock)
        loop_retry "$cur" "$next" ;;
      scope)
        loop_park_item "$cur" "scope violation: $(printf '%s' "$next" | jq -r '.detail.violations[0]')" ;;
      plan | build | fix | qa | prove | run)
        loop_emit "$next"; return 0 ;;
      *)
        loop_end "$(printf '%s' "$next" | jq -r --arg t "$cur" '"\(.action) needs you: \(.instruction) (item \($t), step \(.action))"')"; return 0 ;;
    esac
  done
}
