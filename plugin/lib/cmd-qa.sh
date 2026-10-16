#!/usr/bin/env bash
# vbw qa finding [PHASE] REQ TEXT | record PHASE pass|fail TIER [NOTE]: the QA agent's
# goal-backward verification of a built phase (VBW 1's QA mandate; docs/proof.md).
# A finding opens a fix item marked source "qa": only QA closes it, because the
# checks may pass while the work still deviates from the plan. A finding belongs
# to the phase whose QA found it (D332): named at the finding, or adopted by the
# phase's fail verdict when left out; a verdict changes only its own phase's
# findings, so phases sharing a requirement never close each other's. The verdict is
# recorded against the digest of the phase's inputs and those of the phases it
# builds on (lib/qa-inputs.sh): a change to them needs QA again, others do not. Three failed rounds in a row escalate.

VBW_QA_ROUNDS=3

cmd_qa() {
  local sub="${1:-}"
  case "$sub" in
    finding) { [ $# -eq 3 ] && [ -n "$3" ]; } || { [ $# -eq 4 ] && [ -n "$4" ]; } || vbw_usage_error "usage: vbw qa finding [PHASE] REQ TEXT" ;;
    record)
      [ $# -ge 4 ] && [ $# -le 5 ] && { [ "$3" = pass ] || [ "$3" = fail ]; } \
        && { [ "$4" = quick ] || [ "$4" = standard ] || [ "$4" = deep ]; } \
        || vbw_usage_error "usage: vbw qa record PHASE pass|fail quick|standard|deep [NOTE]"
      ;;
    *) vbw_usage_error "usage: vbw qa finding [PHASE] REQ TEXT | qa record PHASE pass|fail TIER [NOTE]" ;;
  esac
  vbw_require_project
  local record
  record=$(record_read)
  if [ "$sub" = finding ]; then
    local fphase="" freq ftext
    if [ $# -eq 4 ]; then fphase=$2; freq=$3; ftext=$4; else freq=$2; ftext=$3; fi
    printf '%s' "$record" | jq -e --arg q "$freq" 'any(.requirements[]; .id == $q)' > /dev/null || vbw_die "unknown requirement $freq"
    [ -z "$fphase" ] || printf '%s' "$record" | jq -e --arg p "$fphase" --arg q "$freq" 'any(.phases[]; .id == $p and any(.reqs[]; . == $q))' > /dev/null \
      || vbw_die "$fphase is not a phase with requirement $freq: name the phase whose QA found the problem"
    record_update "$VBW_JQ_DEFS"'.fixes += [{id: next_fix_id, req: $q, source: "qa", attempts: 0, status: "open", note: $t} + (if $p == "" then {} else {phase: $p} end)]
      | escalate_phases([.phases[] | select((.tier // "express") == "express" and (.reqs | index($q)) and ($p == "" or .id == $p)) | .id]; null; "QA found a problem in \($q): \($t)"; $at)' \
      --arg q "$freq" --arg t "$ftext" --arg p "$fphase" --arg at "$(vbw_now)"
    jq -r '.fixes[-1] | "\(.id) opened for \(.req)\(if .phase then " in \(.phase)" else "" end) (qa): \(.note)"' "$VBW_RECORD"
    return 0
  fi
  local phase="$2" result="$3" tier="$4" note="${5:-}" tree digests curf
  printf '%s' "$record" | jq -e --arg p "$phase" 'any(.phases[]; .id == $p)' > /dev/null || vbw_die "unknown phase $phase"
  printf '%s' "$record" | jq -e '.evidence.tree' > /dev/null || vbw_die "no proof yet: QA verifies proven work (vbw prove first)"
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  ! next_code_changed "$record" || vbw_die "the code changed since the last proof: run vbw prove --full, then record the verdict again"
  printf '%s' "$record" | jq -e "$VBW_JQ_DEFS"'proof_complete' > /dev/null || vbw_die "the last proof was partial: run vbw prove --full, then record the verdict again"
  # The pass covers this phase's inputs and those of the phases it builds on (D91).
  digests=$(qa_digests "$record")
  tree=$(printf '%s' "$digests" | jq -r --arg p "$phase" '.[$p].combined // empty')
  [ -n "$tree" ] || vbw_die "$phase is not a phase of the active milestone"
  if [ "$result" = fail ]; then
    printf '%s' "$record" | jq -e --arg p "$phase" '. as $r | ([.phases[] | select(.id == $p)][0].reqs) as $q
      | any(.fixes[]; .source == "qa" and .status == "open" and (.req as $x | any($q[]; . == $x)) and ((has("phase") | not) or .phase == $p))' > /dev/null \
      || vbw_die "a failed verdict needs its findings first (vbw qa finding $phase REQ TEXT for each)"
  fi
  vbw_scratch_json curf "$(qa_combined "$record" "$digests" | jq -c --arg p "$phase" --arg t "$tree" '. + {($p): $t}')"
  record_update "$VBW_JQ_DEFS"'$cf[0] as $cur | ([.phases[] | select(.id == $p)][0]) as $ph
    | ($ph.reqs) as $q
    | (if $res == "fail" and ($ph.qa.result // "") == "fail" then ($ph.qa.rounds // 1) + 1 elif $res == "fail" then 1 else 0 end) as $rounds
    | (.phases[] | select(.id == $p)).qa = ({result: $res, tier: $tier, tree: $tree, at: $at}
        + (if $note != "" then {note: $note} else {} end) + (if $rounds > 0 then {rounds: $rounds} else {} end))
    # The findings left without a phase belong to this failed verdict; a verdict changes only the findings of its own phase (D332).
    | .fixes |= map(if $res == "fail" and .source == "qa" and .status == "open" and (has("phase") | not) and (.req as $x | any($q[]; . == $x)) then .phase = $p else . end)
    | .fixes |= map(if .source == "qa" and (.req as $x | any($q[]; . == $x)) and ((has("phase") | not) or .phase == $p) then
        (if $res == "pass" and (.status | IN("open", "fixed")) then .status = "closed"
         elif $res == "fail" and .status == "fixed" then .status = "closed"
         elif $res == "fail" and .status == "open" and $rounds >= $cap then .status = "escalated"
         else . end)
      else . end)
    | escalate_phases(if $rounds >= 2 then [$p] else [] end; null; "QA needs a second round"; $at)
    | finish_phases($cur)' \
    --arg p "$phase" --arg res "$result" --arg tier "$tier" --arg tree "$tree" --arg note "$note" \
    --arg at "$(vbw_now)" --argjson cap "$VBW_QA_ROUNDS" --slurpfile cf "$curf"
  vbw_guard_drop "$curf"
  qa_cache_put "$phase" "$digests"
  record_commit "chore(vbw): qa $phase $result"
  jq -r --arg p "$phase" '.phases[] | select(.id == $p) | "\(.id) qa \(.qa.result) (\(.qa.tier))\(if .qa.rounds then ", round \(.qa.rounds)" else "" end)"' "$VBW_RECORD"
}
