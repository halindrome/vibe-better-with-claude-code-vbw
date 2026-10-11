#!/usr/bin/env bash
# vbw apply < PLAN_JSON: the Lead's one write (docs/workflows.md). Replaces
# the current milestone's phases, plans and checks in a single validated update:
#   {"phases": [{id, title, reqs, goal?, criteria?, tier?}],   (the Architect's)
#    "plans":  [{id, phase, title, reqs, files, after, tasks?, role?}],   (the Lead's)
#    "checks": [{id, req, run, files?, exit?, output?, timeout?, alone?}],
#    "rules":  [{req, text, check}]}   (optional, the Lead's: R31)
# A check may carry "alone": true (a boolean): it never runs beside another VBW check (R45).
# "rules" are the conditions, edges and error cases an [auto] requirement
# states, each with the check that tests it. When present, apply refuses a rule
# whose check is not in the plan or belongs to another requirement, a rule for a
# [human] requirement, and any unproven [auto] requirement of the plan's phases
# that lists no rules (earlier rules count). Without the key nothing changes.
# The phases and plans are the current milestone's; "checks" are the checks of
# its requirements. Earlier milestones' phases, plans and checks are kept (their
# checks keep guarding shipped work). Re-planning mid-milestone is allowed: a
# plan that has started must come back unchanged and keeps its status; every
# other plan is "planned". Refused while a build or fix run is open.
# Every phase gets its rigor tier here: the floor comes from rigor.sh; the
# Architect's optional tier may only raise it (a lower one is refused) and is
# kept as the phase's proposed tier (config rigor auto restores it), and
# settings.rigor forced to a tier overrides both. A phase that already existed
# keeps escalations, outcome and its qa verdict. A phase that has started (a plan
# not planned, or an escalation) or finished keeps its tier, reasons and predicted
# tier on every re-plan, forced rigor included (R159): the floor, the forced tier and
# the one-plan rule for express judge only the phases that have not started. A new
# phase may cover a requirement a started phase covers (R157).
# vbw apply --patch < DOC: only plans, checks and rules, merged by id (R80).
# vbw apply --add < DOC: new phases with their plans, checks and rules (R116),
# appended to the milestone; a phase id it already has, a requirement any
# phase covers (in any milestone) or that belongs to another milestone, or a
# plan or check id in use is refused and nothing changes. The full apply refuses
# what --add refuses about other milestones (a requirement another milestone owns,
# or one a phase of another milestone covers), through the one shared rule
# (foreign_reqs), before every other rule; its own milestone's phases are replaced.
# Every existing item stays as it was and keeps the tier it was accepted at:
# the rigor floor and the one-plan-per-express rule judge only the phases the
# doc brings (their signals see the whole milestone); every other rule above
# holds for the merged whole.

# Every mode takes an optional "test_files": {run, files} (R167): the Lead's proposal of how the
# project's test runner runs one test file (run: an argv naming {file} exactly once; files: git
# pathspecs without spaces). A bad one is refused before anything changes. A good one is written as
# the spec's "## Test files" section, replacing an older one, and the spec is synced; the user
# approves the form with the contract, and VBW never runs one that is not approved.

# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"
# shellcheck source=cmd-spec.sh
. "$VBW_LIB/cmd-spec.sh"

# foreign_reqs: the refusals --add and the full apply share. Only phases of other
# milestones count as covering (a new phase may cover a requirement of this
# milestone again: R157). $scope is "add" (--add: a requirement of this milestone
# that another milestone's phase covers is refused too) or "others" (the full apply).
FOREIGN_REQS_JQ='def foreign_reqs($r; $m; $p; $scope; $mode):
    [$p.phases[] | (.reqs | arrays)[]] as $reqs
    | [($reqs[] | . as $q | ([$r.phases[] | select(.milestone != $m) | select(any(.reqs[]; . == $q))][0]) | select(. != null)
         | select($scope == "add" or ([$r.requirements[] | select(.id == $q and .milestone == $m)] | length) == 0)
         | "\($q) is already covered by \(.id) (milestone \(.milestone)): \($mode) takes requirements that have no phase yet"),
       ($reqs[] | . as $q | ([$r.requirements[] | select(.id == $q and .milestone != $m)][0]) | select(. != null)
         | "\($q) belongs to milestone \(.milestone): \($mode) takes requirements of this milestone")];
'

# apply_refuse MESSAGE: every refusal names the mode it came from (R156).
# apply_next MESSAGE: the one next step of the kind of refusal MESSAGE is. Messages of the
# record's own validation (an unknown requirement, a duplicate id, ...) take the last arm.
apply_next() {
  case "$1" in
    "a patch carries plans"*) echo "remove \"phases\" from the document, or send it to a full apply (vbw apply) to change phases" ;;
    "--add needs"*) echo "send --add a JSON object whose \"phases\" array holds the new phases, with their plans, checks and rules" ;;
    "test_files must be"*) echo "give test_files as {\"run\": [argv naming {file} once], \"files\": [git pathspecs]}, or leave it out" ;;
    "apply needs a JSON object"*) echo "pipe one JSON object into vbw apply: {\"phases\": [], \"plans\": [], \"checks\": []}" ;;
    "apply needs phases"*) echo "give phases, plans and checks as arrays, and rules as [{req, text, check}] if present" ;;
    *"is already a phase of this milestone"*) echo "give the new phase an unused id, or change the existing phase with a full apply" ;;
    *"is already a plan"* | *"is already a check"*) echo "give it an unused id, or change the existing one with vbw apply --patch" ;;
    *"is already covered by"* | *"belongs to milestone"*) echo "take that requirement out of the phases in the document; plan only requirements of this milestone that have no phase yet" ;;
    *"not a phase this --add brings"*) echo "set the plan's phase to one of the phases of this --add, or send the plan with vbw apply --patch" ;;
    *"not a requirement of the phases this --add brings"*) echo "set its req to a requirement of the new phases, or send it with vbw apply --patch" ;;
    *"has an unknown field"*) echo "remove that field from the document; the allowed fields are in docs/workflows.md" ;;
    *"the tier must be"*) echo "set the phase's tier to express, standard or deep, or leave it out" ;;
    *" run is open"*) echo "end the open run (vbw run end), then plan again" ;;
    *"a plan that has started must stay"*) echo "put the plan back as the record has it (vbw show plan ID), and add a new plan for any further work" ;;
    *"its goal and criteria stay"*) echo "keep the phase's goal and criteria as they are, and add a new phase for the further work (vbw apply --add)" ;;
    *"has work started: its title"* | *"has work started: its requirements"*) echo "keep the phase as it is; add a new phase for the further work (vbw apply --add)" ;;
    *"a [human] requirement"*) echo "remove that rule: only [auto] requirements list rules" ;;
    *"which is not a check of"*) echo "name a check of that requirement in the rule, or add the check to the plan's checks" ;;
    *"lists no rules"*) echo "add one rule per condition, edge and error case to \"rules\", each with the check that tests it" ;;
    *"the Architect may only raise a tier"*) echo "raise the phase's tier to its floor or higher, or leave the tier out" ;;
    *"is express: one plan"*) echo "merge the phase's plans into one, or raise the phase's tier to standard" ;;
    *) echo "fix what the message names in the document, then run vbw apply again (vbw doctor checks the record)" ;;
  esac
}

# apply_refuse MESSAGE: every refusal names the mode it came from (R156) and ends with its next step (R162).
apply_refuse() { vbw_die "$MODE_NAME refused: $1"$'\n'"Next: $(apply_next "$1")"; }

# apply_internal MESSAGE: an internal failure; its next step is the same for every kind.
apply_internal() { vbw_die "internal error: $1"$'\n'"Next: run vbw doctor, then send the document again; report it if it fails again"; }

# apply_write_test_files FORM: the spec's "## Test files" section becomes FORM (replacing an
# older one, wherever it stands), then the spec is synced. The run line is plain words when
# they parse back to the same argv, else a JSON array.
apply_write_test_files() {
  local spec="$VBW_DIR/spec.md" tmp
  [ -f "$spec" ] || vbw_die "no .vbw/spec.md (run /vbw:init)"
  tmp=$(mktemp "$VBW_RUNTIME/spec.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$tmp"
  awk 'BEGIN { skip = 0 }
    /^#{1,2}[ \t]/ { skip = (tolower($0) ~ /^##[ \t]+test files[ \t\r]*$/) }
    !skip { print }' "$spec" > "$tmp"
  [ ! -s "$tmp" ] || [ -z "$(tail -c 1 "$tmp")" ] || printf '\n' >> "$tmp"
  printf '%s' "$1" | jq -r '"\n## Test files\n\n- run: \(.run | if all(.[]; test("\\s") | not) and (.[0] | startswith("[") | not) then join(" ") else tojson end)\n- files: \(.files | join(" "))"' >> "$tmp"
  cat "$tmp" > "$spec"
  rm -f "$tmp"
  vbw_guard_drop "$tmp"
  spec_sync "$(spec_parse)"
}

cmd_apply() {
  local patch=false add=false
  MODE_NAME="full apply"
  case "${1:-}" in --patch) patch=true; MODE_NAME="--patch"; shift ;; --add) add=true; MODE_NAME="--add"; shift ;; esac
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw apply < plan.json (full apply) | vbw apply --add < doc.json | vbw apply --patch < doc.json"
  vbw_require_project
  local doc record problem merged filter hypo tiers judged one pdoc='{}' df tf pf ids p form=null
  doc=$(cat)
  if printf '%s' "$doc" | jq -e 'type == "object" and has("test_files")' > /dev/null 2>&1; then
    form=$(printf '%s' "$doc" | jq -c '.test_files')
    printf '%s' "$form" | jq -e 'type == "object" and (keys == ["files", "run"])
        and (.run | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)
             and ([.[] | [match("\\{file\\}"; "g")] | length] | add) == 1)
        and (.files | type == "array" and length > 0 and all(.[]; type == "string" and length > 0 and (test("\\s") | not)))' > /dev/null 2>&1 \
      || apply_refuse "test_files must be {run, files}: run an argv naming {file} exactly once, files a non-empty array of git pathspecs without spaces"
    doc=$(printf '%s' "$doc" | jq -c 'del(.test_files)')
  fi
  if [ "$add" = true ]; then
    # --add: new phases with their plans, checks and rules, appended to the milestone;
    # every existing item stays as it is, its tier included; the rigor floor and the
    # one-plan-per-express rule judge the new phases only, every other rule the merged whole.
    printf '%s' "$doc" | jq -e 'type == "object" and (.phases | type == "array" and length > 0)
        and all(.phases[]; type == "object" and (.id | type == "string") and (.reqs | type == "array"))
        and all(.plans, .checks, .rules; . == null or (type == "array" and all(.[]; type == "object")))' > /dev/null 2>&1 \
      || apply_refuse "--add needs a JSON object with the new phases ({id, title, reqs}) and their plans, checks and rules"
    pdoc=$(printf '%s' "$doc" | jq -c '{phases, plans: (.plans // []), checks: (.checks // []), rules: (.rules // [])}')
    problem=$(record_read | jq -r --slurpfile f_p <(printf '%s' "$pdoc") "$FOREIGN_REQS_JQ"'$f_p[0] as $p | . as $r | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph | [$p.phases[].id] as $new | [$p.phases[].reqs[]] as $newreqs
      | [($p.phases[] | select(.id as $i | any($ph[]; .id == $i)) | "\(.id) is already a phase of this milestone: --add takes new phases only"),
         foreign_reqs($r; $m; $p; "add"; "--add")[],
         ($p.plans[] | select(.phase as $x | $new | index($x) | not) | "\(.id // "a plan") is for \(.phase // "no phase"), not a phase this --add brings"),
         ($p.plans[] | select(.id as $i | any(($r.plans // [])[]; .id == $i)) | "\(.id) is already a plan: --add takes new plans only"),
         ($p.checks[] | select(.id as $i | any(($r.checks // [])[]; .id == $i)) | "\(.id) is already a check: --add takes new checks only"),
         ($p.checks[], $p.rules[] | select(.req as $q | $newreqs | index($q) | not)
           | "\(.id // "the rule \"\(.text)\"") is for \(.req), not a requirement of the phases this --add brings")]
      | .[0] // empty') || apply_internal "cannot read the added phases"
    [ -z "$problem" ] || apply_refuse "$problem"
    doc=$(record_read | jq -c --slurpfile f_p <(printf '%s' "$pdoc") '$f_p[0] as $p | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph
      | ([.requirements[] | select(.milestone == $m)]) as $rq
      | {phases: [($ph[] | {id, title, reqs} + with_entries(select(.key | IN("goal", "criteria")))
            + (if (.proposed // .tier) != null then {tier: (.proposed // .tier)} else {} end)), $p.phases[]],
         plans: ([.plans[] | select(.phase as $x | any($ph[]; .id == $x)) | with_entries(select(.key | IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role")))] + $p.plans),
         checks: ([.checks[] | select(.req as $x | any($rq[]; .id == $x))] + $p.checks),
         rules: ([$rq[] | .id as $q | (.rules // [])[] | {req: $q, text, check}] + $p.rules)}') \
      || apply_internal "cannot merge the added phases"
  elif [ "$patch" = true ]; then
    # --patch: plans, checks and rules to change, merged by id (rules by requirement and text)
    # into the milestone; the merged whole then meets every rule a full apply does.
    printf '%s' "$doc" | jq -e 'type == "object" and (has("phases") | not)' > /dev/null 2>&1 \
      || apply_refuse "a patch carries plans, checks and rules, never phases: change phases with a full apply"
    pdoc=$(printf '%s' "$doc" | jq -c '{plans: (.plans // []), checks: (.checks // []), rules: (.rules // [])}')
    doc=$(record_read | jq -c --slurpfile f_p <(printf '%s' "$pdoc") '$f_p[0] as $p | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph
      | ([.requirements[] | select(.milestone == $m)]) as $rq
      | def merge($old; $new; $keys): [$old[] | . as $o | ([$new[] | select(. as $n | $keys | all(. as $k | $n[$k] == $o[$k]))][0]) // $o]
          + [$new[] | . as $n | select(any($old[]; . as $o | $keys | all(. as $k | $n[$k] == $o[$k])) | not)];
      {phases: [$ph[] | {id, title, reqs} + with_entries(select(.key | IN("goal", "criteria")))
          + (if (.proposed // .tier) != null then {tier: (.proposed // .tier)} else {} end)],
       plans: merge([.plans[] | select(.phase as $x | any($ph[]; .id == $x)) | with_entries(select(.key | IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role")))]; $p.plans; ["id"]),
       checks: merge([.checks[] | select(.req as $x | any($rq[]; .id == $x))]; $p.checks; ["id"]),
       rules: merge([$rq[] | .id as $q | (.rules // [])[] | {req: $q, text, check}]; $p.rules; ["req", "text"])}') \
      || apply_internal "cannot merge the patch"
  fi
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || apply_refuse "apply needs a JSON object on stdin"
  printf '%s' "$doc" | jq -e '(keys - ["phases", "plans", "checks", "rules"]) == [] and all(.phases, .plans, .checks; type == "array")
      and ((has("rules") | not) or (.rules | type == "array" and all(.[]; type == "object" and (keys - ["req", "text", "check"]) == [] and (.text | type == "string" and length > 0))))' \
    > /dev/null || apply_refuse "apply needs phases, plans and checks, each an array, and optionally rules: [{req, text, check}]"
  if [ "$add" = false ] && [ "$patch" = false ]; then
    problem=$(record_read | jq -r --slurpfile f_p <(printf '%s' "$doc") "$FOREIGN_REQS_JQ"'$f_p[0] as $p | . as $r | foreign_reqs($r; .milestone.id; $p; "others"; "full apply")[0] // empty') \
      || apply_internal "cannot read the phases' requirements"
    [ -z "$problem" ] || apply_refuse "$problem"
  fi
  problem=$(printf '%s' "$doc" | jq -r '[
      (.phases[] | . as $o | keys[] | select(IN("id", "title", "reqs", "goal", "criteria", "tier") | not) | "\($o.id // "a phase") has an unknown field: \(.)"),
      (.plans[] | . as $o | keys[] | select(IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role") | not) | "\($o.id // "a plan") has an unknown field: \(.)")
    ] | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  problem=$(printf '%s' "$doc" | jq -r '.phases[] | select(has("tier") and (.tier | IN("express", "standard", "deep") | not))
    | "\(.id // "a phase") has the tier \(.tier | tojson): the tier must be express, standard or deep"' | head -n 1)
  [ -z "$problem" ] || apply_refuse "$problem"
  record=$(record_read)
  printf '%s' "$record" | jq -e '.lease == null or .lease.kind == "plan"' > /dev/null \
    || apply_refuse "a $(printf '%s' "$record" | jq -r .lease.kind) run is open: plan again after it ends (vbw run end)"
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | [.plans[] | select(.status != "planned" and (.phase as $p | any($mine[]; . == $p))) | . as $old
        | ([$d.plans[] | select(.id == $old.id)][0]) as $new
        | select($new == null or ($new | {phase, reqs, files, after: (.after // [])}) != ($old | {phase, reqs, files, after}))
        | "\($old.id) is \($old.status): a plan that has started must stay as it is (same phase, requirements, files and order)"]
    | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  # A phase has started when one of its plans is no longer planned or it has an escalation:
  # its goal and criteria then stay (R158); a phase that has not started may change both.
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m | [.phases[] | select(.milestone == $m)] as $old
    | [.plans[] | select(.status != "planned") | .phase] as $began
    | [$d.phases[] | . as $n | ([$old[] | select(.id == $n.id)][0]) as $o | select($o != null)
        | select(($o.escalations // []) != [] or any($began[]; . == $o.id))
        | select(($o.goal // null) != ($n.goal // null) or ($o.criteria // null) != ($n.criteria // null))
        | "\($n.id) has work started: its goal and criteria stay as they are; add a new phase for the further work"]
    | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m | [.phases[] | select(.milestone == $m)] as $old
    | select(any(.plans[]; .status != "planned" and (.phase as $p | any($old[]; .id == $p))))
    | [($d.phases[] | . as $n | ([$old[] | select(.id == $n.id)][0]) as $o | select($o != null)
        | if $o.title != $n.title then "\($n.id) has work started: its title stays \"\($o.title)\" (a phase is not renamed once planned work has started)"
          elif ($o.reqs | sort) != ($n.reqs | sort) then "\($n.id) has work started: its requirements stay \($o.reqs | join(", "))" else empty end)
      ] | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") --slurpfile f_p <(printf '%s' "$pdoc") --argjson add "$add" "$VBW_JQ_DEFS"'$f_d[0] as $d | select($d | has("rules"))
    | . as $r | $d.rules as $rules | ([$f_p[0].phases[]?.reqs[]] | unique) as $newreqs
    | [($rules[] | . as $x | select(any($r.requirements[]; .id == $x.req and .proof == "human"))
        | "the rule \"\($x.text)\" is for \($x.req), a [human] requirement: only [auto] requirements list rules"),
       ($rules[] | . as $x | select(any($d.checks[]; .id == $x.check and .req == $x.req) | not)
        | "the rule \"\($x.text)\" names \($x.check), which is not a check of \($x.req) in this plan"),
       ($r.requirements[] | . as $q | select(.proof == "auto" and .status != "proven" and ($q | doc_only($d.plans; $d.checks) | not)
          and any($d.phases[].reqs[]; . == $q.id) and (($add | not) or ($newreqs | index($q.id) != null))
          and ($r.phases | any(.milestone == $r.milestone.id and any(.reqs[]; . == $q.id)
                and (((.escalations // []) != []) or (.id as $i | $r.plans | any(.phase == $i and .status != "planned")))) | not)
          and ((($rules | any(.req == $q.id)) or ((.rules // []) | length > 0)) | not))
        | "\(.id) lists no rules: list each condition, edge and error case its text states, with the check that tests it (rules)")]
    | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  hypo=$(printf '%s' "$record" | jq -c --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m
    | .phases = [(.phases[] | select(.milestone != $m)), ($d.phases[] | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "tier")))))]
    | .plans = [.plans[] | select(.phase as $p | $d.phases | any(.id == $p) | not)] + [$d.plans[] | {id, phase, title, reqs, files, after: (.after // [])}]')
  # The phases judged: with --add only the ones it brings, else every phase of the doc.
  judged=$doc
  [ "$add" = false ] || judged=$pdoc
  # A phase that has started (a plan no longer planned, or an escalation) or finished keeps
  # its tier, reasons and predicted tier: only the phases that have not started are judged (R159).
  ids=()
  while IFS= read -r p; do
    ids+=("$p")
  done < <(printf '%s' "$record" | jq -r --slurpfile f_j <(printf '%s' "$judged") '.milestone.id as $m
    | [.plans[] | select(.status != "planned") | .phase] as $began
    | [.phases[] | select(.milestone == $m and ((.escalations // []) != [])) | .id] as $esc
    | $f_j[0].phases[].id | select(. as $i | (($began + $esc) | index($i)) | not)')
  tiers='[]'
  if [ ${#ids[@]} -gt 0 ]; then
    tiers=$(printf '%s' "$hypo" | rigor_assess "${ids[@]}" 2> /dev/null) \
      || apply_internal "cannot compute the rigor tiers"
  fi
  problem=$(printf '%s' "$tiers" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | [.[] | . as $a | ([$d.phases[] | select(.id == $a.id)][0].tier) as $s
      | select($s != null and ($s | IN("express", "standard", "deep")) and (["express", "standard", "deep"] | index($s)) < (["express", "standard", "deep"] | index($a.floor)))
      | "\($a.id) is planned at \($s) but its signals set the floor at \($a.floor) (\($a.reasons | map(select(test("^(requirements|files|risk|breaks|tests): ") and (test(": none$") | not))) | join("; "))): the Architect may only raise a tier"]
    | .[0] // empty')
  if [ -n "$problem" ] && [ "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" = auto ]; then
    apply_refuse "$problem"
  fi
  one=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") --slurpfile f_tiers <(printf '%s' "$tiers") --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" '$f_d[0] as $d | $f_tiers[0] as $tiers |
      [$tiers[] | . as $a | (if $mode | IN("express", "standard", "deep") then $mode else $a.tier end) as $t
        | select($t == "express" and ([$d.plans[] | select(.phase == $a.id)] | length) > 1)
        | "\($a.id) is express: one plan, merge its plans or raise its tier"] | .[0] // empty')
  [ -z "$one" ] || apply_refuse "$one"
  vbw_scratch df "$doc"
  vbw_scratch tf "$tiers"
  vbw_scratch pf "$pdoc"
  filter='$f_d[0] as $d | $f_tiers[0] as $tiers | $f_pd[0] as $pd | .milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | ([.requirements[] | select(.milestone == $m) | .id]) as $myreqs
    | (.plans | map({key: .id, value: .status}) | from_entries) as $status
    | [.phases[] | select(.milestone == $m)] as $old
    | [.plans[] | select(.status != "planned") | .phase] as $started
    | .checks as $c0
    | .phases = (if $patch then .phases else [(.phases[] | select($add or .milestone != $m)), ((if $add then $pd.phases else $d.phases end)[] | . as $np | ([$old[] | select(.id == $np.id)][0]) as $o
                  | ([$tiers[] | select(.id == $np.id)][0]) as $a
                  | (.tier // null) as $sub
                  | ($mode | IN("express", "standard", "deep")) as $forced
                  | (($o != null) and (($o.escalations // []) != [] or any($started[]; . == $np.id))) as $locked
                  | (if $forced then $mode else $a.tier end) as $want
                  | ($locked and ($o.tier != null)) as $keep
                  | (if $keep then $o.tier else $want end) as $tier
                  | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "criteria"))))
                    + (if $keep then ($o | with_entries(select(.key == "proposed")))
                       elif $sub != null then {proposed: $sub} else {} end)
                    + {tier: $tier,
                       reasons: (if $keep then ($o.reasons // [])
                         else ($a.reasons | map(select(startswith("Architect raised") | not))
                           + (if $forced then ["forced: vbw config rigor \($mode)"]
                              elif ($sub != null and $tier == $sub and $tier != $a.floor) then ["raised by the Architect"]
                              else [] end)) end),
                       predicted: (if $locked then ($o.predicted // $tier) else $tier end)}
                    + ($o // {} | with_entries(select(.key | IN("escalations", "outcome", "qa")))))] end)
    | ([($pd.plans // $d.plans)[] | {id, phase, title, reqs, files, after: (.after // []), status: ($status[.id] // "planned")}
          + (with_entries(select(.key | IN("tasks", "role"))))]) as $np
    | .plans = (if $patch or $add then [.plans[] | . as $o | ([$np[] | select(.id == $o.id)][0]) // $o] + [$np[] | select($status[.id] == null)]
        else [(.plans[] | select(.phase as $p | any($mine[]; . == $p) | not)), $np[]] end)
    | .checks = (if $patch or $add then [$c0[] | . as $o | ([$pd.checks[] | select(.id == $o.id)][0]) // $o] + [$pd.checks[] | select(.id as $i | $c0 | any(.id == $i) | not)]
        else [($c0[] | select(.req as $q | any($myreqs[]; . == $q) | not)), $d.checks[]] end)
    | if $d | has("rules") then .requirements |= map(. as $q
        | if any($d.rules[]; .req == $q.id) then .rules = [$d.rules[] | select(.req == $q.id) | {text, check}] else . end)
      else . end'
  # The merged record is checked here, so a violation names the mode too; record_update checks it again.
  merged=$(mktemp "$VBW_RUNTIME/apply.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"$'\n'"Next: check that $VBW_RUNTIME exists and can be written to, then run vbw apply again"
  vbw_guard_add file "$merged"
  jq "$filter | .protected = ([(.checks // [])[]? | objects | .files? | arrays | .[] | strings] | unique)" --slurpfile f_d "$df" --slurpfile f_tiers "$tf" --slurpfile f_pd "$pf" --argjson patch "$patch" --argjson add "$add" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" "$VBW_RECORD" > "$merged" 2> /dev/null \
    || apply_internal "cannot merge the plan into the record"
  problem=$(record_violation "$merged") || true
  rm -f "$merged"
  vbw_guard_drop "$merged"
  [ -z "$problem" ] || apply_refuse "$problem"
  record_update "$filter" --slurpfile f_d "$df" --slurpfile f_tiers "$tf" --slurpfile f_pd "$pf" --argjson patch "$patch" --argjson add "$add" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')"
  vbw_guard_drop "$df"
  vbw_guard_drop "$tf"
  vbw_guard_drop "$pf"
  jq -r '.milestone.id as $m | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | "applied \($mine | length) phases, \([.plans[] | select(.phase as $p | any($mine[]; . == $p))] | length) plans, \(.checks | length) checks in all"' "$VBW_RECORD"
  [ "$form" = null ] || apply_write_test_files "$form"
}
