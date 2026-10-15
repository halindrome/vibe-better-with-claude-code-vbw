#!/usr/bin/env bash
# vbw loop start [--session ID] ITEM... (--ceiling USD [--finish-item] | --no-ceiling)
#   | stop | status [--json] | park [REASON]: the loop through the backlog (R178; docs/loop.md). The loop's state
# lives in the record (loop), so any session can read it or stop it.

LOOP_USAGE="usage: vbw loop start [--session ID] ITEM... --ceiling USD [--finish-item] | --no-ceiling   |   vbw loop stop   |   vbw loop status [--json]"
LOOP_FORMS="choose one: --ceiling USD (stop at the next step), --ceiling USD --finish-item, or --no-ceiling"
# LOOP_TIME_JQ (T156): hm, seconds as "4h05m"; took($l), an item's seconds from its open to its ship or
# park, else to the loop's end, else to now.
# shellcheck disable=SC2034 # used by the loop step and the report, which this file sources
LOOP_TIME_JQ='def hm: floor | "\(. / 3600 | floor)h\(. % 3600 / 60 | floor | tostring | if length < 2 then "0" + . else . end)m";
  def took($l): ((.at // $l.ended.at) | if . then fromdateiso8601 else now end) - (.opened_at | fromdateiso8601) | floor;'

cmd_loop() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  # shellcheck source=loop.sh
  . "$VBW_LIB/loop.sh"
  case "$sub" in
    start) loop_start "$@" ;;
    stop)
      [ $# -eq 0 ] || vbw_usage_error "usage: vbw loop stop"
      loop_stop ;;
    status)
      [ $# -eq 0 ] || { [ $# -eq 1 ] && [ "$1" = --json ]; } || vbw_usage_error "usage: vbw loop status [--json]"
      loop_status "${1:-}" ;;
    next)
      [ $# -eq 1 ] && [ "$1" = --json ] || vbw_usage_error "usage: vbw loop next --json"
      loop_next ;;
    park)
      [ $# -le 1 ] || vbw_usage_error "usage: vbw loop park [REASON]"
      loop_park_cmd "${1:-parked by hand (vbw loop park)}" ;;
    *) vbw_usage_error "$LOOP_USAGE" ;;
  esac
}

# loop_park_cmd REASON: parks the item in progress (the kernel's own step, like vbw loop next).
loop_park_cmd() {
  vbw_require_project
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  # shellcheck source=loop-step.sh
  . "$VBW_LIB/loop-step.sh"
  local rec cur
  rec=$(record_read)
  printf '%s' "$rec" | jq -e '.loop != null and .loop.ended == null' > /dev/null \
    || vbw_die "no loop is on. Next: start one with /vbw:loop"
  printf '%s' "$rec" | jq -e '.lease == null' > /dev/null \
    || vbw_die "a run is open. Next: wait for it to end (vbw status), then run vbw loop park again"
  cur=$(printf '%s' "$rec" | jq -r '[.loop.items[] | select(.status == "in_progress")][0].id // empty')
  [ -n "$cur" ] || vbw_die "no item is in progress. Next: see the loop with vbw loop status"
  loop_park_item "$cur" "$1"
  printf 'parked %s: %s\n' "$cur" "$1"
}

# loop_next: the kernel's loop step (loop-step.sh): off, the end's answer again, or the step.
loop_next() {
  vbw_require_project
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  # shellcheck source=loop-step.sh
  . "$VBW_LIB/loop-step.sh"
  local rec
  rec=$(record_read)
  if ! printf '%s' "$rec" | jq -e '.loop != null' > /dev/null; then
    printf '{"action":"off","reason":"no loop is on"}\n'; return 0
  fi
  if printf '%s' "$rec" | jq -e '.loop.ended != null' > /dev/null; then
    loop_ended_answer "$rec"; return 0
  fi
  loop_step
}

# loop_start ARGS...: validates the usage first (exit 2), then the state (exit 1), then writes.
loop_start() {
  local session="" ceiling="" finish=0 none=0 items=() id
  session=$(vbw_session)
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) [ $# -ge 2 ] || vbw_usage_error "--session needs an id"
        session=$2; shift 2 ;;
      --ceiling) [ $# -ge 2 ] || vbw_usage_error "--ceiling USD needs an amount: $LOOP_FORMS"
        ceiling=$2; shift 2 ;;
      --finish-item) finish=1; shift ;;
      --no-ceiling) none=1; shift ;;
      -*) vbw_usage_error "unknown option $1: $LOOP_USAGE" ;;
      *) items+=("$1"); shift ;;
    esac
  done
  if [ "$none" = 1 ] && [ -n "$ceiling" ]; then vbw_usage_error "--ceiling USD and --no-ceiling are two forms, not both: $LOOP_FORMS"; fi
  if [ "$none" = 0 ] && [ -z "$ceiling" ]; then vbw_usage_error "a loop needs a ceiling choice: $LOOP_FORMS"; fi
  if [ "$none" = 1 ] && [ "$finish" = 1 ]; then vbw_usage_error "--finish-item goes with --ceiling USD: $LOOP_FORMS"; fi
  if [ -n "$ceiling" ]; then
    printf '%s' "$ceiling" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && jq -ne --argjson c "$ceiling" '$c > 0' > /dev/null \
      || vbw_usage_error "--ceiling needs a positive number of dollars, not '$ceiling': $LOOP_FORMS"
  fi
  vbw_require_project
  local rec; rec=$(record_read)
  [ ${#items[@]} -gt 0 ] || vbw_die "no item named. Next: pick items from vbw todo list and run vbw loop start T1 ... again"
  local list="" built="[]" text proof state seen=" "
  for id in ${items[@]+"${items[@]}"}; do
    state=$(printf '%s' "$rec" | jq -r --arg t "$id" '[.todos[] | select(.id == $t)][0] | if . == null then "unknown" else .status end')
    if [ "$state" = unknown ]; then
      if [ "$id" = stop ]; then vbw_die "stop is not an item. Next: run vbw loop stop to stop a loop"; fi
      vbw_die "$id is not in the backlog. Next: see the items with vbw todo list"
    fi
    case "$state" in done | dropped) vbw_die "$id is $state. Next: pick an open item from vbw todo list" ;; esac
    case "$seen" in *" $id "*) vbw_die "$id is named twice. Next: name each item once" ;; esac
    seen="$seen$id "
    text=$(printf '%s' "$rec" | jq -r --arg t "$id" '.todos[] | select(.id == $t) | .text')
    proof=$(loop_item_proof "$text")
    text=$(loop_norm "$text")
    built=$(printf '%s' "$built" | jq -c --arg i "$id" --arg t "$text" --arg p "$proof" '. += [{id: $i, text: $t, proof: $p, status: "waiting"}]')
    list="$list${list:+, }$id"
  done
  if printf '%s' "$rec" | jq -e '.loop != null and .loop.ended == null' > /dev/null; then
    # The loop's own session starting it again (after a resume) gets its Stop hook's mark back (T150).
    [ -z "$session" ] || ! printf '%s' "$rec" | jq -e --arg s "$session" '.loop.session == $s' > /dev/null || loop_mark "$session"
    vbw_die "a loop is already on. Next: run vbw loop status to see it, or vbw loop stop to end it (twice when it is already stopping and its session is gone)"
  fi
  printf '%s' "$rec" | jq -e '.milestone.status != "shipped" and (. as $r | .milestone.id as $m
      | any($r.requirements[]; .milestone == $m and ((.proof == "human" and (.id as $i | any($r.phases[]; .milestone != $m and any(.reqs[]; . == $i)))) | not)))' > /dev/null \
    && vbw_die "$(printf '%s' "$rec" | jq -r .milestone.id) has requirements and is not shipped. Next: finish or ship it first (vbw next): each item gets its own milestone"
  # Every known session's current figures are the loop's baseline.
  local base
  base=$(loop_figures_now)
  if [ -n "$ceiling" ] && [ "$base" = "{}" ]; then
    vbw_die "no session has a cost figure, so a ceiling cannot be measured. Next: run vbw statusline on, or start with --no-ceiling"
  fi
  local ceil=null desc="no ceiling"
  if [ -n "$ceiling" ]; then
    ceil=$(jq -nc --argjson u "$ceiling" --argjson f "$finish" '{usd: $u, finish_item: ($f == 1)}')
    desc="ceiling \$$ceiling ($([ "$finish" = 1 ] && echo 'finish the item first' || echo 'stop at the next step'))"
  fi
  record_update '.loop = {items: $items, ceiling: $ceil, session: (if $s == "" then null else $s end), started_at: $at, baseline: $base}' \
    --argjson items "$built" --argjson ceil "$ceil" --arg s "$session" --arg at "$(vbw_now)" --argjson base "$base"
  record_commit "chore(vbw): loop start" .vbw/record.json
  [ -z "$session" ] || loop_mark "$session"
  printf 'loop on: %s; %s; session %s\n' "$list" "$desc" "${session:-unknown}"
}

# loop_mark SESSION: the mark the plugin's Stop hook (hooks/stop.sh) looks for before it starts the kernel.
loop_mark() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
  mkdir -p "$VBW_RUNTIME" && : > "$VBW_RUNTIME/loop.$1"
}

loop_stop() {
  vbw_require_project
  local rec; rec=$(record_read)
  if ! printf '%s' "$rec" | jq -e '.loop != null and .loop.ended == null' > /dev/null; then
    printf 'no loop is on\n'; return 0
  fi
  if printf '%s' "$rec" | jq -e '.loop.stopping != null' > /dev/null; then
    # A stopping loop ends at its session's next Stop hook; when that session is gone, nothing would
    # end it, so a second stop ends it here, with the report (F170).
    # shellcheck source=cmd-next.sh
    . "$VBW_LIB/cmd-next.sh"
    # shellcheck source=loop-step.sh
    . "$VBW_LIB/loop-step.sh"
    loop_end "stopped by the user (a second vbw loop stop while it was stopping)" > /dev/null
    printf '%s' "$rec" | jq -r '.loop.stopping | "the loop was stopping since \(.at) (asked by \(if .session == null then "no session" else "session \(.session)" end)); it is ended now. Report: .vbw/loop-report.md"'
    return 0
  fi
  record_update '.loop.stopping = {at: $at, session: (if $s == "" then null else $s end)}' --arg at "$(vbw_now)" --arg s "$(vbw_session)"
  record_commit "chore(vbw): loop stop" .vbw/record.json
  printf 'the loop is stopping: it ends before its next step (a run in progress ends first)\n'
}

loop_status() {
  vbw_require_project
  local rec spend word
  rec=$(record_read)
  if ! printf '%s' "$rec" | jq -e '.loop != null' > /dev/null; then
    if [ "$1" = --json ]; then printf '{"on":false}\n'; else printf 'no loop is on\n'; fi
    return 0
  fi
  [ -f "$VBW_RECORD" ] || vbw_die "no record"
  spend=$(loop_spend "$VBW_RECORD")
  word=$(loop_word "$VBW_RECORD" "$spend")
  if [ "$1" = --json ]; then
    jq --argjson spend "$spend" --arg word "$word" "$LOOP_TIME_JQ"'.loop as $l
      | {on: ($l.ended == null), items: $l.items, ceiling: $l.ceiling, session: $l.session, started_at: $l.started_at,
         baseline: $l.baseline, spend: $spend, word: (if $word == "null" then null else $word end),
         stopping: ($l.stopping // null), ended: ($l.ended // null), report: ($l.report // null),
         time: ([$l.items[] | select(.status == "in_progress" and .budget != null and .opened_at != null)][0]
           | if . == null then null else {item: .id, elapsed: took($l), budget: .budget.seconds, basis: .budget.basis} end)}' "$VBW_RECORD"
    return 0
  fi
  jq -r --argjson spend "$spend" --arg word "$word" "$LOOP_USD_JQ$LOOP_TIME_JQ"'
    .loop as $l
    | "loop \(if $l.ended != null then "ended" elif $l.stopping != null then "stopping" else "on" end)",
      ($l.items[] | "  \(.id) [\(.status)\(if .proof == "human" then ", human" else "" end)] \(.text)\(if .budget != null and .opened_at != null
        then " (time: \(took($l) | hm) of a \(.budget.seconds | hm) budget, \(.budget.basis))" else "" end)"),
      "ceiling: \(if $l.ceiling == null then "none"
                  else "$\($l.ceiling.usd) (\(if $l.ceiling.finish_item then "finish the item first" else "stop at the next step" end))" end)",
      "session: \($l.session // "none")",
      "started: \($l.started_at)",
      "baseline: \(if ($l.baseline | length) == 0 then "none" else ($l.baseline | to_entries | map("\(.key) \(.value.usd | usd) (\(.value.in) in, \(.value.out) out)") | join("; ")) end)",
      ( if $spend != null
        then "spend: \($spend.usd | usd) (\($spend.in) in, \($spend.out) out, \($spend.sessions) session\(if $spend.sessions == 1 then "" else "s" end))\(if $word == "null" then "" else ": \($word)" end)"
        elif $l.ceiling == null then "spend: cannot tell (no session has a cost figure; vbw statusline on)"
        else "spend: cannot tell (no session has a cost figure; it counts as reached; vbw statusline on)" end ),
      ( $l.stopping // empty | "stopping since \(.at) (asked by \(if .session == null then "no session" else "session \(.session)" end))" ),
      ( $l.ended // empty | "ended \(.at): \(.reason)\(if $l.report != null then " (report: \($l.report))" else "" end)" )' "$VBW_RECORD"
}
