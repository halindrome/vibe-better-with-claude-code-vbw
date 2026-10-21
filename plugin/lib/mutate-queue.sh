#!/usr/bin/env bash
# Rule breaks side by side (T174, docs/workflows.md). Sourced by cmd-mutate.sh.
#   vbw mutate PLAN Rn.k --queue WHAT FILE...   set one break aside, files back at once, nothing runs
#   vbw mutate PLAN --run                       run every queued break of PLAN, side by side
# A queued break waits in .vbw/runtime/mutate-queue/PLAN/NNNN/: files/ holds its
# broken bytes (a file it deleted is absent), meta.json what it is {target, req,
# rk, check, what, files, broke, head}. The run judges each break as the single
# form does: the rule's check once on the unbroken code at HEAD (unless a recorded
# break at HEAD already ran it), then each break in its own proof copy, as many at
# a time as there are copies (check_jobs, under the computer-wide slots), and each
# result recorded in queue order (mutate_record). A break queued at another commit
# is dropped and named: its bytes belong to older files.

# mutate_queue_dir PLAN: the plan's queue folder.
mutate_queue_dir() {
  printf '%s/mutate-queue/%s\n' "$VBW_RUNTIME" "$1"
}

# mutate_queue_entries PLAN: the queued breaks' folders, in queue order, one per line.
mutate_queue_entries() {
  local d
  for d in "$(mutate_queue_dir "$1")"/[0-9]*; do
    [ -f "$d/meta.json" ] && printf '%s\n' "$d"
  done
  return 0
}

# mutate_queue_add PLAN DIR META_JSON: the set-aside folder DIR joins the plan's queue.
mutate_queue_add() {
  local q n=0 d k
  q=$(mutate_queue_dir "$1")
  mkdir -p "$q" || vbw_die "cannot create $q"
  for d in "$q"/[0-9]*; do
    [ -d "$d" ] || continue
    k=${d##*/}
    k=$((10#$k))
    [ "$k" -le "$n" ] || n=$k
  done
  printf '%s\n' "$3" > "$2/meta.json" || vbw_die "cannot write the queued break"
  mv "$2" "$q/$(printf '%04d' $((n + 1)))" || vbw_die "cannot queue the break in $q"
  printf '%s queued (%s waiting): run them all with vbw mutate %s --run\n' \
    "$(printf '%s' "$3" | jq -r .target)" "$(mutate_queue_entries "$1" | wc -l | tr -d ' ')" "$1"
}

# mutate_queue_run PLAN: vbw mutate PLAN --run.
mutate_queue_run() {
  local plan="$1" record head e entries=() keep=() stale=0 surv=0 bad='' checks ids=() cfiles=() f base unb=() n i k
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg p "$plan" 'any(.plans[]; .id == $p)' > /dev/null || vbw_die "unknown plan $plan: vbw show roadmap lists the plans"
  while IFS= read -r e; do [ -n "$e" ] && entries+=("$e"); done < <(mutate_queue_entries "$plan")
  [ ${#entries[@]} -gt 0 ] || vbw_die "no break waits for $plan: make each break and queue it with vbw mutate $plan Rn.k --queue \"what you broke\" FILE..., then run vbw mutate $plan --run"
  head=$(git rev-parse HEAD) || vbw_die "the project has no commit yet"
  for e in "${entries[@]}"; do
    if [ "$(jq -r .head "$e/meta.json")" = "$head" ]; then keep+=("$e"); continue; fi
    printf '%s was queued at another commit, so its break is of older files: break it again\n' "$(jq -r .target "$e/meta.json")" >&2
    rm -rf "$e"
    stale=1
  done
  [ ${#keep[@]} -gt 0 ] || { rmdir "$(mutate_queue_dir "$plan")" 2> /dev/null || true; return 1; }
  # The checks the breaks need, each once, and their files: those must be the committed ones.
  checks=$(for e in "${keep[@]}"; do jq -r .check "$e/meta.json"; done | jq -R . | jq -sc 'unique')
  while IFS= read -r f; do [ -n "$f" ] && ids+=("$f"); done < <(printf '%s' "$checks" | jq -r '.[]')
  while IFS= read -r -d '' f; do cfiles+=("$f"); done < <(printf '%s' "$record" | jq -j --argjson ids "$checks" '[.checks[] | select(.id as $c | $ids | index($c) != null) | .files // [] | .[]] | unique[] | . + "\u0000"')
  if [ ${#cfiles[@]} -gt 0 ] && [ -n "$(vbw_dirty_files "${cfiles[@]}")" ]; then
    vbw_die "check files differ from the last commit: $(vbw_dirty_files "${cfiles[@]}"): commit them first, so the breaks are run against the approved tests"
  fi
  checks_begin "$record"
  base=$(printf '%s' "$record" | jq -c --arg p "$plan" --arg h "$head" \
    '[.plans[] | select(.id == $p) | (.mutations // [])[] | select(.head == $h) | (.checks // {}) | keys[]] | unique')
  for f in "${ids[@]}"; do
    printf '%s' "$base" | jq -e --arg c "$f" 'index($c) != null' > /dev/null || unb+=("$f")
  done
  n=${#keep[@]}
  [ "$n" -ge ${#unb[@]} ] || n=${#unb[@]}
  n=$(proofcopy_slots "$n")
  printf 'running %s breaks of %s, %s at a time\n' "${#keep[@]}" "$plan" "$n"
  proofcopy_create_slots "$n"
  # Each check once on the unbroken code: a check red there makes every break of it prove nothing.
  if [ ${#unb[@]} -gt 0 ]; then
    bad=$(checks_run_all "$record" "${unb[@]}" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')
    if [ -n "$bad" ]; then
      proofcopy_remove
      checks_end
      rm -rf "$(mutate_queue_dir "$plan")"
      vbw_die "checks do not pass on the unbroken code, so a break proves nothing: $bad; make them pass and commit, then break again (the queued breaks are dropped)"
    fi
  fi
  # The breaks, one per copy, a wave at a time: each copy gets its break, runs its
  # rule's check pinned to it (.slot), and goes back to HEAD before the next wave.
  local units unit res broke=() m
  for ((i = 0; i < ${#keep[@]}; i += n)); do
    units='[]'
    for ((k = 0; k < n && i + k < ${#keep[@]}; k++)); do
      e=${keep[$((i + k))]}
      broke=()
      while IFS= read -r -d '' f; do broke+=("$f"); done < <(jq -j '.broke[] + "\u0000"' "$e/meta.json")
      mutate_put "$e" "${PROOF_COPIES[$k]}" "${broke[@]}"
      unit=$(checks_unit "$record" "$(jq -r .check "$e/meta.json")")
      units=$(printf '%s' "$units" | jq -c --argjson u "$unit" --argjson k "$k" \
        '. + [$u + {name: "break\($k)", out: "break\($k).out", slot: $k}]')
    done
    res=$(checks_run_units "$units")
    for ((k = 0; k < n && i + k < ${#keep[@]}; k++)); do
      e=${keep[$((i + k))]}
      broke=()
      while IFS= read -r -d '' f; do broke+=("$f"); done < <(jq -j '.broke[] + "\u0000"' "$e/meta.json")
      mutate_clean "${PROOF_COPIES[$k]}" "${broke[@]}"
      printf '%s' "$res" | jq -c --arg b "break$k" --arg c "$(jq -r .check "$e/meta.json")" '{($c): .[$b]}' > "$e/result.json"
    done
  done
  proofcopy_remove
  checks_end
  # The results, recorded in queue order as the single form records one; the
  # computer-wide wait is said once, at the end.
  local waited=$SLOTS_WAITED lost=$SLOTS_LOST ruledoc
  SLOTS_WAITED=0 SLOTS_LOST=
  for e in "${keep[@]}"; do
    m=$(jq -c . "$e/meta.json")
    ruledoc=$(printf '%s' "$record" | jq -c --argjson m "$m" '.requirements[] | select(.id == $m.req) | (.rules // [])[$m.rk - 1] | {req: $m.req, text, check}')
    cfiles=()
    while IFS= read -r -d '' f; do cfiles+=("$f"); done < <(printf '%s' "$record" | jq -j --arg c "$(printf '%s' "$m" | jq -r .check)" '[.checks[] | select(.id == $c) | .files // [] | .[]] | unique[] | . + "\u0000"')
    mutate_record "$plan" "$(printf '%s' "$m" | jq -r .target)" "$(printf '%s' "$m" | jq -r .what)" "$head" "$(cat "$e/result.json")" \
      "$(record_read)" "$ruledoc" "" "$(printf '%s' "$m" | jq -c .files)" ${cfiles[@]+"${cfiles[@]}"} || surv=1
    rm -rf "$e"
  done
  rmdir "$(mutate_queue_dir "$plan")" 2> /dev/null || true
  SLOTS_WAITED=$waited SLOTS_LOST=$lost
  slots_say
  [ "$surv" = 0 ] && [ "$stale" = 0 ]
}
