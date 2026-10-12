#!/usr/bin/env bash
# The loop's report (R179; docs/loop.md, The report). Sourced by the loop step.

# loop_report_write RECORD_FILE: renders .vbw/loop-report.md from the record alone (plus the commits
# whose VBW-Plan trailer names a plan of an item's milestone). Reads; the step commits the file.
loop_report_write() {
  local rec=$1 spend log
  spend=$(loop_spend "$rec")
  log=$(mktemp "$VBW_RUNTIME/report.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$log"
  git -C "$VBW_ROOT" log --format='%h%x1f%s%x1f%(trailers:key=VBW-Plan,valueonly,separator=%x20)' > "$log" 2> /dev/null || : > "$log"
  jq -r --argjson spend "$spend" --rawfile log "$log" "$LOOP_USD_JQ"'
    def cost: if . == null then "unknown" else "\(.usd | usd) (\(.in) in, \(.out) out)" end;
    . as $r | .loop as $l
    | ([$log | split("\n")[] | select(length > 0) | split("\u001f") | {hash: .[0], subject: .[1], plans: ((.[2] // "") | split(" "))}]) as $commits
    | def plans_of($m): [$r.plans[] | select(.reqs as $q | any($r.requirements[]; .milestone == $m and (.id as $i | $q | index($i) != null))) | .id];
      def commits_of($m): plans_of($m) as $p | [$commits[] | select(any(.plans[]; . as $x | $p | index($x) != null))];
    "# Loop report",
    "",
    "Started \($l.started_at). \(if $l.ended == null then "State: running (an item still in progress shows as in progress)."
      else "State: ended \($l.ended.at): \($l.ended.reason)." end)",
    "",
    "## Shipped",
    ( [$l.items[] | select(.status == "shipped")] as $s
      | if ($s | length) == 0 then "none yet" else
        $s[] | . as $i
        | ([$r.requirements[] | select(.milestone == $i.milestone and .text == ($i.text | sub("^\\[(human|auto)\\] "; "")))][0].id // "none") as $q
        | "- \($i.id) \($i.text) (\($i.milestone), \($q)): \(commits_of($i.milestone) | map("\(.hash) \(.subject)") | join("; "))" end ),
    "",
    "## Parked",
    ( [$l.items[] | select(.status == "parked")] as $p
      | if ($p | length) == 0 then "none" else
        $p[] | "- \(.id) \(.text) (\(.milestone // "no milestone")): \(.reason // "no reason recorded"); revert commits: \((.reverts // []) | map(if type == "object" then (.hash // .sha // tostring) else tostring end | .[0:7]) | join(", ")); to bring the work back, revert the reverts (git revert, newest first) or run the item again with /vbw:loop \(.id)" end ),
    "",
    "## Waiting for you",
    ( [$r.requirements[] | select(.proof == "human" and .skipped == true and .status == "open")] as $w
      | if ($w | length) == 0 then "no skipped [human] requirement" else $w[] | "- \(.id) \(.text) (skipped for you to judge)" end ),
    ( if $l.ended == null then "the loop is still running" else "the loop stopped: \($l.ended.reason)" end ),
    "",
    "## Cost",
    "Loop total: \($spend | cost)",
    ( $l.items[] | select(.status == "shipped" or .status == "parked" or .status == "in_progress")
      | "- \(.id) (\(.status)): \(if .status == "in_progress" then "in progress, not counted yet" else (.cost | cost) end)" )' "$rec" > "$VBW_ROOT/.vbw/loop-report.md"
  vbw_guard_drop "$log"
  rm -f "$log"
}
