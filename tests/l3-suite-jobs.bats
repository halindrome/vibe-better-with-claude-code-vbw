#!/usr/bin/env bats
# T27: tools/l3-suite.sh runs several scenarios L3_JOBS at a time and starts the
# next one as soon as any running scenario ends, never waiting on the oldest
# (a slow scenario must not leave slots idle). Each scenario's exit counts, and
# its lines print in the order asked. L1: a copy of the suite whose l3_child
# runs a stand-in scenario instead of Claude Code.

load helper

setup() {
  vbw_setup
  SUITE="$REPO_ROOT/tools/l3-suite.sh"
  mkdir -p "$TEST_ROOT/copy/tools"
  # The seam: the one line that starts a scenario's own process.
  grep -qx 'l3_child() { L3_CHILD=1 bash "$0" "$1"; }' "$SUITE"
  sed 's|^l3_child() { L3_CHILD=1 bash "$0" "$1"; }$|l3_child() { bash "$STUB" "$1"; }|' "$SUITE" > "$TEST_ROOT/copy/tools/l3-suite.sh"
  ! grep -q 'L3_CHILD=1 bash' "$TEST_ROOT/copy/tools/l3-suite.sh" || false
  STUB="$TEST_ROOT/stub.sh"
  MARK="$TEST_ROOT/marks"
  mkdir -p "$MARK"
  # A scenario named in BLOCK (default greenfield) ends only once convert, the
  # last one asked, has started (up to TICKS tenths of a second, default 200);
  # a scenario named in FAIL exits 1.
  cat > "$STUB" << 'SH'
#!/usr/bin/env bash
: > "$MARK/$1.started"
if case " ${BLOCK:-greenfield} " in *" $1 "*) true ;; *) false ;; esac; then
  n=0
  while [ ! -f "$MARK/convert.started" ]; do
    n=$((n + 1)); [ "$n" -le "${TICKS:-200}" ] || { echo "[$1] convert never started"; exit 1; }
    sleep 0.1
  done
fi
echo "[$1] done"
case " ${FAIL:-} " in *" $1 "*) exit 1 ;; esac
exit 0
SH
  export STUB MARK
}
teardown() { vbw_teardown; }

suite() { run env TMPDIR="$TEST_ROOT" L3_JOBS=2 L3_STAGGER=0 bash "$TEST_ROOT/copy/tools/l3-suite.sh" "$@" < /dev/null; }

@test "T27: a slow scenario does not hold its slot's successors: the others run through the free slot" {
  suite greenfield reject resume change convert
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"never started"* ]] || { echo "$output"; false; }
  [[ "$output" == *"L3 suite: all checks passed"* ]]
}

@test "T27: no more than L3_JOBS scenarios run at once" {
  # Two slots, both held by scenarios waiting for convert: convert cannot start
  # until they give up, so both fail.
  BLOCK="greenfield reject" TICKS=20 suite greenfield reject convert
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"[greenfield] convert never started"* ]] || { echo "$output"; false; }
  [[ "$output" == *"[reject] convert never started"* ]] || { echo "$output"; false; }
}

@test "T27: each scenario's exit counts, and the lines print in the order asked" {
  FAIL=resume suite greenfield reject resume change convert
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"L3 suite: FAILED"* ]]
  order=$(printf '%s\n' "$output" | sed -n 's/^\[\([a-z]*\)\] done$/\1/p' | tr '\n' ' ')
  [ "$order" = "greenfield reject resume change convert " ] || { echo "$output"; false; }
}
