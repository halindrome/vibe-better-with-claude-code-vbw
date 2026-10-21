# shellcheck shell=bash
# The glance (decision D238): .vbw/runtime/glance.json, the small side file the
# kernel rewrites with every record write. The Bash and file guards read it
# instead of .vbw/record.json while it is current, and read the record
# otherwise. Load after helper and protected-helper:
#   load helper
#   load protected-helper
#   load glance-helper
#
# Current: a regular, readable file strictly newer than the record, as sh's
# [ -nt ] compares them (whole seconds under macOS /bin/sh). The kernel keeps the
# glance it writes newer than the record, even within the same second; any later
# change to the record (git checkout, git reset, a hand edit) leaves the glance
# not newer, so the guards read the record.

GLANCE=.vbw/runtime/glance.json

# secs FILE: the file's modification time in whole seconds.
secs() { date -r "$1" +%s; }

# glance_current [DIR]: the glance of the project at DIR (default .) is current,
# by sh's test and by whole seconds.
glance_current() {
  local d="${1:-.}"
  sh -c '[ -f "$1" ] && [ -r "$1" ] && [ "$1" -nt "$2" ]' _ "$d/$GLANCE" "$d/.vbw/record.json" || return 1
  [ "$(secs "$d/$GLANCE")" -gt "$(secs "$d/.vbw/record.json")" ]
}

# glance_same [DIR]: the glance holds the record's schema, lease and protected
# list exactly as the record does, besides the fields the status line reads.
glance_same() {
  local d="${1:-.}"
  jq -n -e --slurpfile g "$d/$GLANCE" --slurpfile r "$d/.vbw/record.json" '
    ($g[0] | has("schema") and has("lease") and has("protected"))
    and ($g[0] | {schema, lease, protected}) == ($r[0] | {schema, lease, protected})
    and ($g[0] | has("project") and has("milestone") and has("settings") and has("requirements") and has("plans"))' > /dev/null \
    || {
      echo "the glance does not hold the record's schema, lease and protected list:"
      jq -c '{schema, lease, protected, keys: keys}' "$d/$GLANCE"
      jq -c '{schema, lease, protected}' "$d/.vbw/record.json"
      return 1
    }
}

# glance_project: in the current folder, a project with three checks (C1 to C3,
# protecting tests/c1.sh, tests/c2.sh and tests/shared.sh), plan P1.1 writing
# src/ and tests/, its contract approved and everything committed.
glance_project() {
  protected_base
  protected_apply 3 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  git add -A
  git commit -q -m "chore(test): planned"
}

bash_in() {
  jq -nc --arg c "$1" --arg a "${2:-}" --arg s "${3:-s1}" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: "Bash", tool_input: {command: $c}}
    + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'
}
file_in() {
  jq -nc --arg t "$1" --arg p "$2" --arg a "${3:-}" --arg s "${4:-s1}" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: $t,
    tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}} + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'
}

# hook_answer DIR INPUT_JSON: the PreToolUse guard's answer in the project at DIR
# (the input's cwd set to DIR). The guard must print no error.
hook_answer() {
  local tool
  tool=$(printf '%s' "$2" | jq -r .tool_name)
  printf '%s' "$2" | jq -c --arg d "$1" '.cwd = $d' \
    | HOOK_PROJECT_DIR="$1" vbw_hook PreToolUse "$tool" 2> "$TEST_ROOT/err"
  [ ! -s "$TEST_ROOT/err" ] || { echo "the guard printed an error:"; cat "$TEST_ROOT/err"; return 1; }
}

# from_record DIR INPUT_JSON: the answer with the glance moved aside, so the
# guard can only read the record; the glance is put back unchanged (mv keeps
# its time).
from_record() {
  local a s=0
  [ ! -e "$1/$GLANCE" ] || mv "$1/$GLANCE" "$TEST_ROOT/glance.aside"
  a=$(hook_answer "$1" "$2") || s=1
  [ ! -e "$TEST_ROOT/glance.aside" ] || mv "$TEST_ROOT/glance.aside" "$1/$GLANCE"
  [ "$s" = 0 ] || { printf '%s\n' "$a"; return 1; }
  printf '%s' "$a"
}

# like_record DIR INPUT_JSON: the answer (left in ANSWER) is the one the record
# gives, whatever the glance holds.
like_record() {
  local r
  ANSWER=$(hook_answer "$1" "$2")
  r=$(from_record "$1" "$2")
  [ "$ANSWER" = "$r" ] || { printf 'answer differs from the record'"'"'s for %s\ngiven: %s\nrecord: %s\n' "$2" "$ANSWER" "$r"; return 1; }
}

# both DIR INPUT_JSON: with a current glance, the answer equals the one the
# record gives (left in ANSWER).
both() {
  glance_current "$1" || { echo "the glance is not current"; return 1; }
  like_record "$1" "$2"
}

denied_with() {
  [[ "$ANSWER" == *'"deny"'* && "$ANSWER" == *"$1"* ]] || { echo "not denied with '$1': $ANSWER"; return 1; }
}
allowed() { [ -z "$ANSWER" ] || { echo "not allowed: $ANSWER"; return 1; }; }
