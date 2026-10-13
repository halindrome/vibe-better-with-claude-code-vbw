#!/usr/bin/env bash
# The loop's report (R179; docs/loop.md, The report). Sourced by the loop step.

# loop_report_write RECORD_FILE: renders .vbw/loop-report.md from the record alone (plus the commits
# whose VBW-Plan trailer names a plan of an item's milestone). Reads; the step commits the file.
loop_report_write() {
  local rec=$1 spend log cur='null' id
  spend=$(loop_spend "$rec")
  # An item still in progress when the loop ended: its spend so far, as the park would freeze it (F184).
  id=$(jq -r '[.loop.items[] | select(.status == "in_progress")][0].id // empty' "$rec")
  if [ -n "$id" ] && jq -e '.loop.ended != null' "$rec" > /dev/null; then
    cur=$(loop_spend "$rec" "$id" | jq -c 'if . == null then null else del(.sessions) end')
  fi
  log=$(mktemp "$VBW_RUNTIME/report.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$log"
  git -C "$VBW_ROOT" log --format='%h%x1f%s%x1f%(trailers:key=VBW-Plan,valueonly,separator=%x20)' > "$log" 2> /dev/null || : > "$log"
  jq -r --argjson spend "$spend" --argjson cur "$cur" --rawfile log "$log" "$LOOP_USD_JQ"'
    def cost: if . == null then "unknown" else "\(.usd | usd) (\(.in) in, \(.out) out)" end;
    . as $r | .loop as $l
    | ([$log | split("\n")[] | select(length > 0) | split("\u001f") | {hash: .[0], subject: .[1], plans: ((.[2] // "") | split(" "))}]) as $commits
    | def plans_of($m): [$r.plans[] | select(.phase as $p | any($r.phases[]; .id == $p and .milestone == $m)) | .id];
      def commits_of($m): plans_of($m) as $p | [$commits[] | select(any(.plans[]; . as $x | $p | index($x) != null))];
      # The requirement of an item: by the id kept at its open; else the one of its milestone with its text (F191).
      def req_of($i): (if $i.req then [$r.requirements[] | select(.id == $i.req)][0] else null end)
        // ([$r.requirements[] | select(.milestone == $i.milestone and .text == ($i.text | sub("^\\[(human|auto)\\] "; "")))][0]);
    "# Loop report",
    "",
    "Started \($l.started_at). \(if $l.ended == null then "State: running (an item still in progress shows as in progress)."
      else "State: ended \($l.ended.at): \($l.ended.reason)." end)",
    "",
    "## Shipped",
    ( [$l.items[] | select(.status == "shipped")] as $s
      | if ($s | length) == 0 then "none yet" else
        $s[] | . as $i
        | (req_of($i) | .id // "none") as $q
        | "- \($i.id) \($i.text) (\($i.milestone), \($q)): \(commits_of($i.milestone) | map("\(.hash) \(.subject)") | join("; "))" end ),
    "",
    "## Parked",
    ( [$l.items[] | select(.status == "parked")] as $p
      | if ($p | length) == 0 then "none" else
        $p[] | "- \(.id) \(.text) (\(.milestone // "no milestone")): \(.reason // "no reason recorded")\(if .left then "; left unreverted: \(.left)" else "" end); revert commits: \((.reverts // []) | map(if type == "object" then (.hash // .sha // tostring) else tostring end | .[0:7]) | join(", ")); to bring the work back, revert the reverts (git revert, newest first) or run the item again with /vbw:loop \(.id)" end ),
    "",
    "## Waiting for you",
    ( ([$l.items[] | select(.status == "shipped" and .proof == "human") | req_of(.) | select(. != null and .status != "accepted" and .status != "rejected")]
        + [$r.requirements[] | select(.proof == "human" and .skipped == true and .status == "open")] | unique_by(.id)) as $w
      | if ($w | length) == 0 then "no skipped [human] requirement" else $w[] | "- \(.id) \(.text) (skipped for you to judge)" end ),
    ( if $l.ended == null then "the loop is still running" else "the loop stopped: \($l.ended.reason)" end ),
    "",
    "## Cost",
    "Loop total: \($spend | cost)",
    ( $l.items[] | select(.status == "shipped" or .status == "parked" or .status == "in_progress")
      | "- \(.id) (\(.status)): \(if .status == "in_progress" then (if $l.ended == null then "in progress, not counted yet" else "\($cur | cost) so far (cut off when the loop ended)" end) else (.cost | cost) end)" )' "$rec" > "$VBW_ROOT/.vbw/loop-report.md"
  vbw_guard_drop "$log"
  rm -f "$log"
}
