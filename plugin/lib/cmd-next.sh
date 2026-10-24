#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record,
# the approval state of its contract, and whether the code changed since proof.

# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"
# shellcheck source=qa-inputs.sh
. "$VBW_LIB/qa-inputs.sh"
# shellcheck source=effort.sh
. "$VBW_LIB/effort.sh"
# shellcheck source=cmd-approve.sh
. "$VBW_LIB/cmd-approve.sh"
# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"
# shellcheck source=sessions.sh
. "$VBW_LIB/sessions.sh"

# next_holder RECORD: the display name of the lease's session, empty without a lease session.
next_holder() {
  local sid
  sid=$(printf '%s' "$1" | jq -r '.lease.session // empty')
  [ -z "$sid" ] || holder_display "$sid"
}

# qa_state RECORD [DIGESTS]: lib/qa.jq's answer (closure, recheck, standing, interleaved, problems).
# The one judgment of whether a pass stands; a pass of another fingerprint
# version is first fingerprinted again at its own commit (qa_settle).
qa_state() {
  local d="${2:-}"
  [ -n "$d" ] || d=$(qa_digests "$1")
  qa_settle "$1" "$d"
  printf '%s' "$1" | jq -c --slurpfile in <(printf '%s' "$d") --slurpfile ch <(qa_cache_read) --argjson fpv "$QA_FP_VERSION" '$in[0] as $inputs | $ch[0] as $cache | '"$(cat "$VBW_LIB/qa.jq")"
}

# qa_deviations RECORD: lib/qa.jq's deviations alone ({Pn: [{file, plan, change, commit, by,
# decision}]}): the proof's evidence and the decisions decide them, so no digest is computed.
qa_deviations() {
  printf '%s' "$1" | jq -c --argjson inputs null --argjson cache null -f "$VBW_LIB/qa.jq" | jq -c '.deviations'
}

# qa_combined RECORD [DIGESTS]: {Pn: the phase's current fingerprint}: what a
# standing pass holds in qa.tree (D91). A pass that stands across a fingerprint
# version is held by the qa.tree it has.
qa_combined() {
  local d="${2:-}"
  [ -n "$d" ] || d=$(qa_digests "$1")
  qa_state "$1" "$d" | jq -c --slurpfile dg <(printf '%s' "$d") --slurpfile rc <(printf '%s' "$1") '$dg[0] as $d | $rc[0] as $r | . as $s | $d | map_values(.combined)
    + ([$r.phases[] | select(.id as $i | $s.standing | index($i)) | select(.qa.tree != null) | {(.id): .qa.tree}] | add // {})'
}

# next_answer: vbw next's answer without the step and the road (lib/next.jq), on
# stdout; it writes nothing. The one place the answer is judged, so the command,
# vbw status and the road (lib/road.sh) read the same one.
next_answer() {
  vbw_require_project
  local effort record hash counts approved=false changed=false legacy=false next qa waiting profile problems="" holder prev=/dev/null adoc=/dev/null
  record=$(record_read) || return $?
  hash=$(contract_hash "$record")
  # Check files edited since the approval wait: the build goes on, the one approval comes before proof.
  waiting=$(contract_waiting "$record") && commands_approved "$record" && approved=true
  # An unapproved contract that approval would refuse is not offered for approval (R171).
  [ "$approved" = true ] || problems=$(approve_problems "$record")
  next_code_changed "$record" && changed=true
  # A VBW 1 plan not yet converted (docs/convert.md).
  [ -d "$VBW_ROOT/.vbw-planning" ] && ! printf '%s' "$record" | jq -e 'has("converted") or .project.legacy.choice == "fresh"' > /dev/null && legacy=true
  # Tracked files, and of those the code: outside .vbw/ and not documentation (is_doc).
  counts=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | jq -Rs "$VBW_JQ_DEFS"'[split("\u0000")[] | select(length > 0)]
    | {tracked: length, code: ([.[] | select((startswith(".vbw/") or is_doc) | not)] | length)}')
  qa=$(qa_state "$record")
  # A plan that names a plan or phase that is not there cannot be judged.
  printf '%s' "$qa" | jq -e '.problems | any(.[]; contains("does not exist")) | not' > /dev/null || vbw_die "$(printf '%s' "$qa" | jq -r '.problems | join("; ")')"
  # The profile's effort table; a wrong table stops here, before any answer.
  effort=$(effort_table "$(printf '%s' "$record" | jq -r '.settings.profile')") || exit 1
  profile=$(interview_effective "$record")
  holder=$(next_holder "$record")
  # The last answer (a gate's since) and, while not approved, the last approved contract (a re-approval).
  [ -f "$VBW_RUNTIME/next.json" ] && prev="$VBW_RUNTIME/next.json"
  [ "$approved" = true ] || [ ! -f "$VBW_RUNTIME/approved-contract.json" ] || adoc="$VBW_RUNTIME/approved-contract.json"
  next=$(printf '%s' "$record" | jq -c --rawfile prev "$prev" --slurpfile approved_doc "$adoc" --argjson effort "$effort" --argjson tracked "$counts" --argjson approved "$approved" --arg waiting "$waiting" --arg problems "$problems" --arg contract "$hash" \
    --argjson code_changed "$changed" --argjson legacy "$legacy" --slurpfile qa <(printf '%s' "$qa") --argjson profile "$profile" --arg session "$(vbw_session)" --arg holder "$holder" --slurpfile tiers "$VBW_LIB/tiers.json" "$VBW_JQ_DEFS$(cat "$VBW_LIB/next.jq")")
  printf '%s\n' "$next"
}

cmd_next() {
  vbw_require_project
  local next record step road hint
  next=$(next_answer) || exit $?
  # The step to run, with its end time and the sentence to say (R190, D425), and the
  # road, the end of the milestone (R191, D438). Only the command asks for them: a
  # caller inside the kernel (the Stop hook's gate, ship, the loop) never pays for
  # the proof's reuse plan and keeps the road of the previous answer, so the
  # status line and Mission Control keep the last vbw next's road.
  if [ "${FUNCNAME[1]:-main}" = main ]; then
    record=$(record_read)
    step=$(step_next "$record" "$next")
    road=$(step_road "$record" "$next" "$(step_live_note "$(printf '%s' "$record" | jq -r '.lease.run // ""')")")
    next=$(printf '%s' "$next" | jq -c --argjson step "$step" --argjson road "${road:-null}" '. + {step: $step, road: $road}')
    # The /rename hint (D444): once per clone, only for the command.
    hint=$(sessions_rename_hint "$(vbw_session)" "$VBW_ROOT" "$(basename "$VBW_ROOT")")
    next=$(printf '%s' "$next" | jq -c --arg hint "$hint" '. + {rename_hint: (if $hint == "" then null else $hint end)}')
  else
    road=$(jq -c '.road // empty' "$VBW_RUNTIME/next.json" 2> /dev/null) || road=
    [ -z "$road" ] || next=$(printf '%s' "$next" | jq -c --argjson road "$road" '. + {road: $road}')
  fi
  # The status line shows the last answer (docs/statusline.md).
  printf '%s\n' "$next" > "$VBW_RUNTIME/next.json.$$" && mv "$VBW_RUNTIME/next.json.$$" "$VBW_RUNTIME/next.json"
  if [ "${1:-}" = "--json" ]; then
    # The project folder (vbw root), for the workflows' args: agents of a session started in a
    # subfolder work there. Only in the command's answer: the kept one, and what a caller inside
    # the kernel builds from it (the loop's step note), hold no path, so a copy of the project
    # never points back at it.
    if [ "${FUNCNAME[1]:-main}" = main ]; then
      printf '%s\n' "$next" | jq -c --arg root "$VBW_ROOT" '. + {root: $root}'
    else
      printf '%s\n' "$next"
    fi
  else
    printf '%s\n' "$next" | jq -r '"\(.action)\(if .gate then " (needs you)" else "" end): \(.instruction)"'
  fi
}

# True when the project's files differ from the ones the last proof saw: the
# working folder (vbw_code_tree: content, so committing VBW's record never
# makes evidence stale) or the committed code the checks ran on (head: an edit
# proved while uncommitted and committed later was never proved). No evidence
# counts as no change: the evidence is already stale for lack of a proof.
next_code_changed() {
  local proved head now
  proved=$(printf '%s' "$1" | jq -r '.evidence.tree // empty')
  [ -n "$proved" ] || return 1
  now=$(vbw_code_tree) || return 0
  [ "$now" = "$proved" ] || return 0
  head=$(printf '%s' "$1" | jq -r '.evidence.head // empty')
  [ -n "$head" ] || return 1
  now=$(vbw_head_tree) || return 0
  [ "$now" != "$head" ]
}
