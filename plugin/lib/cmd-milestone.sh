#!/usr/bin/env bash
# vbw milestone start TITLE | rename TITLE.
# start opens the next milestone once the current one has shipped. Shipped
# requirements, plans and checks stay in the record: their checks keep running
# in every vbw prove, so later work cannot silently break shipped work. The new
# milestone starts with no requirements (vbw next: spec), except the [human]
# ones the user skipped at ship (later): they move in, open, with their history.
# rename names the current milestone (vbw init calls M1 "First milestone");
# a shipped milestone keeps the name it shipped with.

cmd_milestone() {
  [ $# -eq 2 ] && { [ "$1" = start ] || [ "$1" = rename ]; } && [ -n "$2" ] \
    || vbw_usage_error "usage: vbw milestone start TITLE | milestone rename TITLE"
  vbw_require_project
  if [ "$1" = rename ]; then
    record_read | jq -e '.milestone.status != "shipped"' > /dev/null \
      || vbw_die "$(record_read | jq -r '"\(.milestone.id) has shipped: start the next one (vbw milestone start TITLE)"')"
    record_update '.milestone.title = $t' --arg t "$2"
    jq -r '"\(.milestone.id) is now \(.milestone.title)"' "$VBW_RECORD"
    return 0
  fi
  record_read | jq -e '.milestone.status == "shipped"' > /dev/null \
    || vbw_die "$(record_read | jq -r '"\(.milestone.id) is not shipped yet: finish it first (vbw next)"')"
  # Every known session's current figures become the new milestone's baseline.
  local base="{}" sid figs
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    figs=$(costs_figures "$sid")
    [ "$figs" = null ] || base=$(printf '%s' "$base" | jq -c --arg s "$sid" --arg at "$(vbw_now)" --argjson f "$figs" '.[$s] = $f + {at: $at}')
  done < <(costs_sessions)
  record_update '"M\((.milestone.id | ltrimstr("M") | tonumber) + 1)" as $n
    | .milestone = {id: $n, title: $t, status: "active"}
    | .costs.runs = (.costs.runs // []) | .costs.milestones = ((.costs.milestones // {}) + {($n): {baseline: $base}})
    | (.requirements[] | select(.later == true)) |= (.milestone = $n | .status = "open" | del(.skipped, .later))' \
    --arg t "$2" --argjson base "$base"
  record_commit "chore(vbw): start $(jq -r .milestone.id "$VBW_RECORD")"
  jq -r '"started \(.milestone.id) \(.milestone.title): add its requirements to .vbw/spec.md (vbw spec add)"' "$VBW_RECORD"
}
