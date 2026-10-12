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
    | [.loop.items[].text | norm] as $have
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
