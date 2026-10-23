#!/usr/bin/env bats
# R189 (kernel part, L1): when VBW stops for the user, vbw next --json carries
# since, the time VBW first reached that gate. It is kept while the same gate
# stands (same action and detail), whichever session or restart asks, so the
# needs-you line and Mission Control date the wait from the gate, not from when
# a panel first saw it. A new gate starts its own time; a step that needs
# nobody carries none.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
teardown() { vbw_teardown; }

# stamp_next JQ: edit the last answer as a gate reached long ago would have left it.
stamp_next() { jq "$1" .vbw/runtime/next.json > "$TEST_ROOT/n.json" && cp "$TEST_ROOT/n.json" .vbw/runtime/next.json; }

@test "R189: a gate carries since, the time VBW first reached it, kept while the same gate stands, in any session" {
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "spec" and .gate == true and (.since | test("^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' > /dev/null || { echo "$output"; false; }
  stamp_next '.since = "2026-01-02T03:04:05Z"'
  [ "$("$VBW" next --json | jq -r .since)" = "2026-01-02T03:04:05Z" ]
  [ "$(VBW_SESSION_ID=another "$VBW" next --json | jq -r .since)" = "2026-01-02T03:04:05Z" ]
  [ "$(jq -r .since .vbw/runtime/next.json)" = "2026-01-02T03:04:05Z" ]
}

@test "R189: a new gate starts its own time, a damaged last answer is ignored, and a step that needs nobody carries none" {
  "$VBW" next --json > /dev/null
  stamp_next '.since = "2026-01-02T03:04:05Z" | .action = "ship"'
  [ "$("$VBW" next --json | jq -r .since)" != "2026-01-02T03:04:05Z" ]
  printf '{"action": "spec", "gate": tru' > .vbw/runtime/next.json
  "$VBW" next --json | jq -e '.since | type == "string"' > /dev/null
  "$VBW" spec add auto "A customer can pay" > /dev/null
  "$VBW" next --json | jq -e '.gate == false and (has("since") | not)' > /dev/null || { "$VBW" next --json; false; }
}
