#!/usr/bin/env bats
# R202 (docs/proof.md): a unit's slot in the computer-wide limit covers its
# read tracking. The slot is taken before the unit's access times are reset
# and given back only after its read list is collected, so VBW's own tracking
# work counts in the limit. The command's time limit still counts from the
# command's start, never from the tracking or the wait, and the "waited" line
# counts a wait for the slot. L1 (tests/machine-helper.bash): stand-in find and
# touch commands on PATH copy the slot store each time the reset (touch -h -a
# -t <the old date>) and the collection (find ... -anewer) run, so the store as
# it stood at each tracking step can be read afterwards.

load helper
load machine-helper

setup() {
  machine_setup
  SNAP_DIR="$TEST_ROOT/snaps"
  SNAP_STORE="$CLAUDE_CONFIG_DIR/vbw/slots.json"
  mkdir -p "$SNAP_DIR" "$TEST_ROOT/standin"
  export SNAP_DIR SNAP_STORE
  # A snapshot is the store's text, or an empty file when no store exists.
  cat > "$TEST_ROOT/standin/find" << 'SH'
#!/bin/sh
case " $* " in
  *" -anewer "*) case " $* " in *probe.*) ;; *) f=$(mktemp "$SNAP_DIR/collect.XXXXXX"); cp "$SNAP_STORE" "$f" 2> /dev/null || : > "$f" ;; esac ;;
esac
exec /usr/bin/find "$@"
SH
  cat > "$TEST_ROOT/standin/touch" << 'SH'
#!/bin/sh
case " $* " in
  *" -h -a -t 200001010000 "*) f=$(mktemp "$SNAP_DIR/reset.XXXXXX"); cp "$SNAP_STORE" "$f" 2> /dev/null || : > "$f" ;;
esac
exec /usr/bin/touch "$@"
SH
  chmod +x "$TEST_ROOT/standin/find" "$TEST_ROOT/standin/touch"
  PATH="$TEST_ROOT/standin:$PATH"
  export PATH
}

teardown() { machine_teardown; }

# held_at_every_step UNIT: every reset and every collection snapshot shows UNIT holding a slot.
held_at_every_step() {
  local f n=0
  [ -n "$(ls "$SNAP_DIR" | grep '^reset\.')" ] || { echo "no reset snapshot: the stand-in touch never saw the reset"; return 1; }
  [ -n "$(ls "$SNAP_DIR" | grep '^collect\.')" ] || { echo "no collection snapshot: the stand-in find never saw the collection"; return 1; }
  for f in "$SNAP_DIR"/*; do
    n=$((n + 1))
    jq -e --arg id "$1" 'any(.held[]; .id == $id)' "$f" > /dev/null 2>&1 \
      || { echo "at ${f##*/} the store did not show $1 holding a slot:"; cat "$f"; echo; return 1; }
  done
  [ "$n" -gt 0 ]
}

# hold SECONDS: project B holds the only slot for SECONDS; HOLDER is its vbw.
hold() {
  machine_project "$OTHER" B 1 "$1"
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  HOLDER=$BG_PID
  wait_starts 1 B-
}

@test "R202: the unit holds its slot while its access times are reset and while its read list is collected" {
  cores 2
  machine_project "$PROJECT" A 1 0
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  held_at_every_step C1 || { echo "$output"; false; }
}

@test "R202: with the only slot held elsewhere, no reset and no collection happens before the holder lets go, and the waited line counts the wait" {
  cores 2
  machine_project "$PROJECT" A 1 0
  hold 4
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  held_at_every_step C1 || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | tail -n 1)" =~ ^waited\ ([0-9]+)\ s\ for\ other\ VBW\ runs ]] || { echo "$output"; false; }
  [ "${BASH_REMATCH[1]}" -ge 1 ] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}

@test "R202: the command's time limit counts from the command's start, not from the tracking or the wait" {
  cores 2
  machine_project "$PROJECT" A 1 0 '[{"id": "C2", "req": "R1", "run": ["sh", "tests/unit.sh", "A-C2", "2", "0"], "files": ["tests/unit.sh"], "timeout": 3}]'
  hold 5
  run within 120 "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [[ "$output" == *"C2 pass"* ]] || { echo "$output"; false; }
  wait_ok "$HOLDER"
}
