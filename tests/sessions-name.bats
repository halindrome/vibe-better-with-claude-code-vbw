#!/usr/bin/env bats
# R192, phase P152 (L1): the run remembers who holds it, by name. vbw run start
# reads the holder's name from Claude Code's list of running chats
# (<claude-config-dir>/sessions/*.json; the newest updatedAt wins) and keeps it
# on this computer only (D442): .vbw/runtime/holder.json {run, session,
# session_name} and the glance's `holder`, never the record. vbw run start and
# vbw run end refusals name the holder by its display name: the list's current
# name, else the stored one, else the first 8 characters of the id. Names are
# untrusted text: cleaned of control characters and escape sequences, cut to 40
# characters with an ellipsis. vbw doctor says whether the list can be read.

load helper
load sessions-helper

HOLDER=.vbw/runtime/holder.json
GLANCE=.vbw/runtime/glance.json

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

as() { local s="$1"; shift; VBW_SESSION_ID="$s" run "$VBW" "$@" < /dev/null; }
start() { VBW_SESSION_ID="$1" "$VBW" run start qa > /dev/null; }
end() { VBW_SESSION_ID="$1" "$VBW" run end > /dev/null; }

@test "R192: run start stores the holder's name from Claude Code's list in holder.json and the glance, never in the record" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  jq -e --arg s "$SESSION_A" '.session == $s and .session_name == "Payments work" and (.run | type) == "string"' "$HOLDER"
  jq -e --arg r "$(jq -r .lease.run .vbw/record.json)" '.run == $r' "$HOLDER"
  jq -e '.holder.session_name == "Payments work" and .holder.run == .lease.run and (.lease | has("session_name") | not)' "$GLANCE"
  jq -e '[.. | objects | has("session_name")] | any | not' .vbw/record.json
  ! grep -q "Payments work" .vbw/record.json
}

@test "R192: with several entries for one id the newest updatedAt wins" {
  registry_entry 101 "$SESSION_A" "Old name" 1792300000000
  registry_entry 102 "$SESSION_A" "Newest name" 1792300050000
  registry_entry 103 "$SESSION_A" "Middle name" 1792300020000
  start "$SESSION_A"
  jq -e '.session_name == "Newest name"' "$HOLDER"
}

@test "R192: no list, or no entry for this session: session_name is null and the run still starts" {
  as "$SESSION_A" run start qa
  [ "$status" -eq 0 ]
  jq -e '.session_name == null' "$HOLDER"
  jq -e '.holder.session_name == null and (.lease.run | type) == "string"' "$GLANCE"
  end "$SESSION_A"
  registry_entry 101 "$SESSION_B" "Someone else"
  as "$SESSION_A" run start qa
  [ "$status" -eq 0 ]
  jq -e '.session_name == null' "$HOLDER"
}

@test "R192: a malformed file in the list never fails a kernel command, and the good entries still count" {
  mkdir -p "$(registry_dir)"
  printf '{"sessionId": "%s", "name": ' "$SESSION_A" > "$(registry_dir)/100.json"
  printf 'not json at all\n' > "$(registry_dir)/99.json"
  as "$SESSION_A" run start qa
  [ "$status" -eq 0 ]
  jq -e '.session_name == null' "$HOLDER"
  end "$SESSION_A"
  registry_entry 101 "$SESSION_A" "Payments work"
  as "$SESSION_A" run start qa
  [ "$status" -eq 0 ]
  jq -e '.session_name == "Payments work"' "$HOLDER"
  as "$SESSION_B" next --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"Payments work"* ]]
  as "$SESSION_B" run end
  [ "$status" -ne 0 ]
  [[ "$output" == *"Payments work"* ]]
}

@test "R192: a name with escape sequences and control characters is stored and shown clean" {
  registry_entry 101 "$SESSION_A" "$(printf 'Pay\033[31mments\007 work\033]0;title\007 now\r\n')"
  start "$SESSION_A"
  jq -e '.session_name == "Payments work now"' "$HOLDER"
  as "$SESSION_B" run start qa
  [ "$status" -ne 0 ]
  [[ "$output" == *"Payments work now"* ]]
  [[ "$output" != *$'\033'* && "$output" != *$'\007'* ]]
}

@test "R192: refusals name the holder by its current name: a /rename made during the run shows at once; a closed chat keeps its stored name" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  registry_entry 101 "$SESSION_A" "Checkout fix" 1792300090000
  as "$SESSION_B" run start qa
  [ "$status" -ne 0 ]
  [[ "$output" == *"another session"* && "$output" == *"Checkout fix"* ]]
  [[ "$output" != *"Payments work"* ]]
  as "$SESSION_B" run end
  [ "$status" -ne 0 ]
  [[ "$output" == *"another session"* && "$output" == *"Checkout fix"* ]]
  jq -e --arg s "$SESSION_A" '.lease.session == $s' .vbw/record.json
  rm "$(registry_dir)/101.json"
  as "$SESSION_B" run end
  [ "$status" -ne 0 ]
  [[ "$output" == *"Payments work"* ]]
  jq -e --arg s "$SESSION_A" '.lease.session == $s' .vbw/record.json
}

@test "R192: with no name anywhere the first 8 characters of the id name the holder; a long name is cut to 40 with an ellipsis" {
  start "$SESSION_A"
  as "$SESSION_B" run end
  [ "$status" -ne 0 ]
  [[ "$output" == *"01234567"* && "$output" != *"$SESSION_A"* ]]
  end "$SESSION_A"
  local long="A very long chat name that keeps going on and on past forty"
  registry_entry 101 "$SESSION_A" "$long"
  start "$SESSION_A"
  as "$SESSION_B" run end
  [ "$status" -ne 0 ]
  [[ "$output" == *"${long:0:39}…"* && "$output" != *"${long:0:41}"* ]]
}

@test "R192: run end removes the stored name and the glance's holder" {
  registry_entry 101 "$SESSION_A" "Payments work"
  start "$SESSION_A"
  end "$SESSION_A"
  [ ! -e "$HOLDER" ]
  jq -e '.holder == null and .lease == null' "$GLANCE"
  jq -e '[.. | objects | has("session_name")] | any | not' .vbw/record.json
  ! grep -q "Payments work" .vbw/record.json
}

@test "R192: the record validator refuses a lease that carries session_name, so a name never reaches git history (D442)" {
  start "$SESSION_A"
  jq '.lease.session_name = "Payments work"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  as "$SESSION_A" status
  [ "$status" -eq 3 ]
  [[ "$output" == *"corrupt"* ]]
}

@test "R192: vbw doctor says in one line whether session names can be read from Claude Code's list" {
  as "$SESSION_A" doctor
  [ "$(printf '%s\n' "$output" | grep -c 'session names')" -eq 1 ]
  printf '%s\n' "$output" | grep 'session names' | grep -q 'not found'
  registry_entry 101 "$SESSION_A" "Payments work"
  as "$SESSION_A" doctor
  [ "$(printf '%s\n' "$output" | grep -c 'session names')" -eq 1 ]
  printf '%s\n' "$output" | grep 'session names' | grep -q 'readable'
  ! printf '%s\n' "$output" | grep 'session names' | grep -q 'not found'
}
