#!/usr/bin/env bash
# vbw loop start [--session ID] ITEM... (--ceiling USD [--finish-item] | --no-ceiling)
#   | stop | status [--json]: the loop through the backlog (R178; docs/loop.md). The loop's state
# lives in the record (loop), so any session can read it or stop it.

LOOP_USAGE="usage: vbw loop start [--session ID] ITEM... --ceiling USD [--finish-item] | --no-ceiling   |   vbw loop stop   |   vbw loop status [--json]"
LOOP_FORMS="choose one: --ceiling USD (stop at the next step), --ceiling USD --finish-item, or --no-ceiling"

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
    *) vbw_usage_error "$LOOP_USAGE" ;;
  esac
}

# loop_start ARGS...: validates the usage first (exit 2), then the state (exit 1), then writes.
loop_start() {
  local session="" ceiling="" finish=0 none=0 item items=() id
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
    text=$(loop_norm "$(loop_item_text "$text")")
    built=$(printf '%s' "$built" | jq -c --arg i "$id" --arg t "$text" --arg p "$proof" '. += [{id: $i, text: $t, proof: $p, status: "waiting"}]')
    list="$list${list:+, }$id"
  done
  printf '%s' "$rec" | jq -e '.loop != null and .loop.ended == null' > /dev/null \
    && vbw_die "a loop is already on. Next: run vbw loop status to see it, or vbw loop stop to end it"
  printf '%s' "$rec" | jq -e '.milestone.status != "shipped" and (.milestone.id as $m | any(.requirements[]; .milestone == $m))' > /dev/null \
    && vbw_die "$(printf '%s' "$rec" | jq -r .milestone.id) has requirements and is not shipped. Next: finish or ship it first (vbw next): each item gets its own milestone"
  # Every known session's current figures are the loop's baseline.
  local base="{}" sid figs
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    figs=$(costs_figures "$sid")
    [ "$figs" = null ] || base=$(printf '%s' "$base" | jq -c --arg s "$sid" --arg at "$(vbw_now)" --argjson f "$figs" '.[$s] = $f + {at: $at}')
  done < <(costs_sessions)
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
  printf 'loop on: %s; %s; session %s\n' "$list" "$desc" "${session:-unknown}"
}

loop_stop() {
  vbw_require_project
  local rec; rec=$(record_read)
  if ! printf '%s' "$rec" | jq -e '.loop != null and .loop.ended == null' > /dev/null; then
    printf 'no loop is on\n'; return 0
  fi
  if printf '%s' "$rec" | jq -e '.loop.stopping != null' > /dev/null; then
    printf '%s' "$rec" | jq -r '.loop.stopping | "the loop is already stopping since \(.at) (asked by \(if .session == null then "no session" else "session \(.session)" end))"'
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
    jq --argjson spend "$spend" --arg word "$word" '.loop as $l
      | {on: ($l.ended == null), items: $l.items, ceiling: $l.ceiling, session: $l.session, started_at: $l.started_at,
         baseline: $l.baseline, spend: $spend, word: (if $word == "null" then null else $word end),
         stopping: ($l.stopping // null), ended: ($l.ended // null), report: ($l.report // null)}' "$VBW_RECORD"
    return 0
  fi
  jq -r --argjson spend "$spend" --arg word "$word" '
    def usd: "$" + (. * 100 | round | tostring | if length < 3 then ("000" + .)[-3:] else . end | .[:-2] + "." + .[-2:]);
    .loop as $l
    | "loop \(if $l.ended != null then "ended" elif $l.stopping != null then "stopping" else "on" end)",
      ($l.items[] | "  \(.id) [\(.status)\(if .proof == "human" then ", human" else "" end)] \(.text)"),
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
