#!/usr/bin/env bats
# R202 (docs/proof.md): VBW's own bookkeeping counts in the computer-wide
# limit. The proof-wide heavy steps each hold one slot while they run, under
# their own unit names (vbw:plan for the reuse planning, vbw:copies for making
# the clean copies, vbw:save for saving the run store) and give it back at
# once after; a nested run (VBW_SLOT_STORE set) takes none. vbw next never
# waits for a slot. The held count never exceeds the limit, VBW's own entries
# included. When the store cannot be used, the steps run under check_jobs
# alone with the existing message. L1 (tests/machine-helper.bash): the store is
# sampled every 50 ms while the runs go; a stand-in jq logs when the run store
# (runs.json) is read.

load helper
load machine-helper

setup() {
  machine_setup
  SNAPS="$TEST_ROOT/snaps"
  STORE="$CLAUDE_CONFIG_DIR/vbw/slots.json"
  mkdir -p "$SNAPS" "$TEST_ROOT/standin"
  REAL_JQ=$(command -v jq)
  cat > "$TEST_ROOT/standin/jq" << SH
#!/bin/sh
case " \$* " in *runs.json*) printf '%s\\n' "\$(date +%s)" >> "\$STORE_READS" ;; esac
exec "$REAL_JQ" "\$@"
SH
  chmod +x "$TEST_ROOT/standin/jq"
  export STORE_READS="$TEST_ROOT/store-reads"
  : > "$STORE_READS"
}

teardown() { machine_teardown; }

# sample SECONDS: in the background, every 50 ms for SECONDS, copy the store to
# $SNAPS/N.json (nothing when there is none) and note the time and whether a
# proof copy exists in $PROJECT; SAMPLER is its pid.
sample() {
  (
    local i n=$(($1 * 20))
    for ((i = 0; i < n; i++)); do
      cp "$STORE" "$SNAPS/$i.json" 2> /dev/null || true
      date +%s > "$SNAPS/$i.t"
      ls -d "$PROJECT"/.vbw/runtime/proof.* 2> /dev/null | wc -l | tr -d ' ' > "$SNAPS/$i.copies"
      sleep 0.05
    done
  ) &
  SAMPLER=$!
}

# snaps_where JQ: the sample numbers whose store satisfies JQ.
snaps_where() {
  local f
  for f in "$SNAPS"/*.json; do
    [ -f "$f" ] || continue
    jq -e "$1" "$f" > /dev/null 2>&1 && basename "$f" .json
  done
}

# max_held: the most entries held in any sample.
max_held() {
  local f m=0 n
  for f in "$SNAPS"/*.json; do
    [ -f "$f" ] || continue
    n=$(jq '.held | length' "$f" 2> /dev/null || echo 0)
    [ "$n" -le "$m" ] || m=$n
  done
  echo "$m"
}

# hold SECONDS: project B holds the only slot for SECONDS; HOLDER is its vbw.
hold() {
  machine_project "$OTHER" B 1 "$1"
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  HOLDER=$BG_PID
  wait_starts 1 B-
}

@test "R202: with the only slot held, vbw prove waits as vbw:plan before reading the run store or making a copy, and the store lists the step while it runs" {
  cores 2
  machine_project "$PROJECT" A 1 0
  hold 4
  sample 12
  (cd "$PROJECT" && PATH="$TEST_ROOT/standin:$PATH" exec perl -e '$SIG{ALRM} = "DEFAULT"; alarm 120; exec { $ARGV[0] } @ARGV' "$VBW" prove) > "$TEST_ROOT/a.out" 2>&1 < /dev/null 3>&- &
  local pa=$!
  wait_ok "$HOLDER" "$pa" || { show; false; }
  wait "$SAMPLER" 2> /dev/null || true
  local release i t
  release=$(awk '$1 == "end" && $3 == "B-C1" { print $2; exit }' "$LOG")
  [ -n "$release" ] || { show; false; }
  # While B held the slot: A waited as vbw:plan, made no copy, read no run store.
  local waiting='' during=0
  for i in $(snaps_where 'any(.waiting[]; .id == "vbw:plan")'); do
    t=$(cat "$SNAPS/$i.t")
    [ "$t" -ge "$release" ] || waiting=1
  done
  [ -n "$waiting" ] || { echo "no sample during the hold showed vbw:plan waiting"; cat "$SNAPS"/*.json; false; }
  for i in "$SNAPS"/*.t; do
    t=$(cat "$i")
    [ "$t" -ge "$release" ] && continue
    during=$((during + 1))
    [ "$(cat "${i%.t}.copies")" = 0 ] || { echo "a proof copy existed while the slot was held elsewhere"; false; }
  done
  [ "$during" -gt 0 ] || { echo "no sample fell inside the hold"; false; }
  while IFS= read -r t; do
    [ -z "$t" ] || [ "$t" -ge "$release" ] || { echo "the run store was read at $t, before the holder let go at $release"; false; }
  done < "$STORE_READS"
  [ -s "$STORE_READS" ] || { echo "the stand-in jq never saw the run store read"; false; }
  # Once it ran: the store listed a bookkeeping step as held.
  [ -n "$(snaps_where 'any(.held[]; .id == "vbw:plan" or .id == "vbw:copies" or .id == "vbw:save")')" ] \
    || { echo "no sample showed vbw:plan, vbw:copies or vbw:save held"; cat "$SNAPS"/*.json; false; }
  grep -q '^proved$' "$TEST_ROOT/a.out" || { cat "$TEST_ROOT/a.out"; false; }
}

@test "R202: vbw next --json never waits for a slot: it answers at once while every slot is held" {
  cores 2
  machine_project "$PROJECT" A 1 0
  hold 6
  run within 20 "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  jq -e '.action | type == "string"' <<< "$output" > /dev/null || { echo "$output"; false; }
  kill -0 "$HOLDER" 2> /dev/null || { echo "the holder had already let go: the answer proves nothing"; show; false; }
  wait_ok "$HOLDER"
}

@test "R202: two proofs at once, limit 2, three units each: the held count never exceeds 2, VBW's own entries included" {
  cores 3
  machine_project "$PROJECT" A 3 1
  machine_project "$OTHER" B 3 1
  (cd "$PROJECT" && "$VBW" config set check_jobs 3 > /dev/null)
  (cd "$OTHER" && "$VBW" config set check_jobs 3 > /dev/null)
  sample 20
  local pa pb
  bg "$PROJECT" "$TEST_ROOT/a.out" prove
  pa=$BG_PID
  bg "$OTHER" "$TEST_ROOT/b.out" prove
  pb=$BG_PID
  wait_ok "$pa" "$pb" || { show; false; }
  kill "$SAMPLER" 2> /dev/null || true
  wait "$SAMPLER" 2> /dev/null || true
  [ "$(max_held)" -le 2 ] || { echo "held $(max_held) with limit 2"; cat "$SNAPS"/*.json; false; }
  [ "$(peak)" -le 2 ] || { echo "peak $(peak) units with limit 2"; show; false; }
  [ -n "$(snaps_where 'any(.held[]; .id | startswith("vbw:"))')" ] || { echo "no sample showed a bookkeeping entry held"; false; }
}

@test "R202: when the store cannot be used, the bookkeeping steps run under check_jobs alone with the existing message" {
  cores 2
  machine_project "$PROJECT" A 1 0
  # A file where the store's folder should be: the folder cannot be made.
  rm -rf "$CLAUDE_CONFIG_DIR/vbw"
  : > "$CLAUDE_CONFIG_DIR/vbw"
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"the computer-wide limit was not in force"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = proved ] || { echo "$output"; false; }
}

@test "R202: a nested run takes no slot for its bookkeeping either" {
  cores 2
  machine_project "$PROJECT" A 1 0
  sample 6
  run within 120 env VBW_SLOT_STORE="$STORE" "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  kill "$SAMPLER" 2> /dev/null || true
  wait "$SAMPLER" 2> /dev/null || true
  [ -z "$(ls "$SNAPS" | grep '\.json$')" ] || { echo "a nested run used the store:"; cat "$SNAPS"/*.json; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = proved ] || { echo "$output"; false; }
}
