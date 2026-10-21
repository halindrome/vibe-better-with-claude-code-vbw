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
# (runs.json) is read. Events are ordered by their line in the one shared log
# ($LOG, one small append each), never by a clock: a sample's line follows its
# snapshot, a store read's line comes before the read. The projects tests
# share are built once per file (setup_file) and copied for each test.

load helper
load machine-helper
load fixture-helper

# book_setup: the test folder, its samples folder and the stand-in jq. For fixture_build.
book_setup() {
  machine_setup
  SNAPS="$TEST_ROOT/snaps"
  STORE="$CLAUDE_CONFIG_DIR/vbw/slots.json"
  mkdir -p "$SNAPS" "$TEST_ROOT/standin"
  REAL_JQ=$(command -v jq)
  cat > "$TEST_ROOT/standin/jq" << SH
#!/bin/sh
case " \$* " in *runs.json*) printf 'read runs.json\\n' >> "\$LOG" ;; esac
exec "$REAL_JQ" "\$@"
SH
  chmod +x "$TEST_ROOT/standin/jq"
}

# book_one: book_setup, then on 2 cores a project of one check. For fixture_build.
book_one() {
  book_setup
  cores 2
  machine_project "$PROJECT" A 1 0
}

setup_file() {
  fixture_build base book_setup
  fixture_build one book_one
}
setup() { fixture_copy base; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

# sample SECONDS: in the background, every 50 ms for SECONDS, copy the store to
# $SNAPS/N.json (nothing when there is none), note whether a proof copy exists in
# $PROJECT, then log "sample N"; SAMPLER is its pid.
sample() {
  (
    local i n=$(($1 * 20))
    for ((i = 0; i < n; i++)); do
      cp "$STORE" "$SNAPS/$i.json" 2> /dev/null || true
      ls -d "$PROJECT"/.vbw/runtime/proof.* 2> /dev/null | wc -l | tr -d ' ' > "$SNAPS/$i.copies"
      printf 'sample %s\n' "$i" >> "$LOG"
      sleep 0.05
    done
  ) &
  SAMPLER=$!
}

# sample_line N: the log line of sample N (empty: it was never logged).
sample_line() { awk -v n="$1" '$1 == "sample" && $2 == n { print NR; exit }' "$LOG"; }

# samples_before LINE: the samples logged before log line LINE, one number per line.
samples_before() { awk -v l="$1" 'NR < l && $1 == "sample" { print $2 }' "$LOG"; }

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
  fixture_copy one
  hold 4
  sample 12
  (cd "$PROJECT" && PATH="$TEST_ROOT/standin:$PATH" exec perl -e '$SIG{ALRM} = "DEFAULT"; alarm 120; exec { $ARGV[0] } @ARGV' "$VBW" prove) > "$TEST_ROOT/a.out" 2>&1 < /dev/null 3>&- &
  local pa=$!
  wait_ok "$HOLDER" "$pa" || { show; false; }
  wait "$SAMPLER" 2> /dev/null || true
  local release i l first
  # B's unit logs its end before B gives the slot back: a line before it happened during the hold.
  release=$(end_line B-C1)
  [ -n "$release" ] || { show; false; }
  # While B held the slot: A waited as vbw:plan, made no copy, read no run store.
  local waiting='' during=0
  for i in $(snaps_where 'any(.waiting[]; .id == "vbw:plan")'); do
    l=$(sample_line "$i")
    [ -z "$l" ] || [ "$l" -gt "$release" ] || waiting=1
  done
  [ -n "$waiting" ] || { echo "no sample during the hold showed vbw:plan waiting"; show; cat "$SNAPS"/*.json; false; }
  for i in $(samples_before "$release"); do
    during=$((during + 1))
    [ "$(cat "$SNAPS/$i.copies")" = 0 ] || { echo "a proof copy existed while the slot was held elsewhere (sample $i)"; show; false; }
  done
  [ "$during" -gt 0 ] || { echo "no sample fell inside the hold"; show; false; }
  first=$(awk '$1 == "read" && $2 == "runs.json" { print NR; exit }' "$LOG")
  [ -n "$first" ] || { echo "the stand-in jq never saw the run store read"; show; false; }
  [ "$first" -gt "$release" ] || { echo "the run store was read (log line $first) before the holder let go (line $release)"; show; false; }
  # Once it ran: the store listed a bookkeeping step as held.
  [ -n "$(snaps_where 'any(.held[]; .id == "vbw:plan" or .id == "vbw:copies" or .id == "vbw:save")')" ] \
    || { echo "no sample showed vbw:plan, vbw:copies or vbw:save held"; cat "$SNAPS"/*.json; false; }
  grep -q '^proved$' "$TEST_ROOT/a.out" || { cat "$TEST_ROOT/a.out"; false; }
}

@test "R202: vbw next --json never waits for a slot: it answers at once while every slot is held" {
  fixture_copy one
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
  fixture_copy one
  # A file where the store's folder should be: the folder cannot be made.
  rm -rf "$CLAUDE_CONFIG_DIR/vbw"
  : > "$CLAUDE_CONFIG_DIR/vbw"
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"the computer-wide limit was not in force"* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = proved ] || { echo "$output"; false; }
}

@test "R202: a nested run takes no slot for its bookkeeping either" {
  fixture_copy one
  sample 6
  run within 120 env VBW_SLOT_STORE="$STORE" "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  kill "$SAMPLER" 2> /dev/null || true
  wait "$SAMPLER" 2> /dev/null || true
  [ -z "$(ls "$SNAPS" | grep '\.json$')" ] || { echo "a nested run used the store:"; cat "$SNAPS"/*.json; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = proved ] || { echo "$output"; false; }
}
