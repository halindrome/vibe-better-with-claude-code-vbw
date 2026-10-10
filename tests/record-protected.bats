#!/usr/bin/env bats
# R150 (decisions D226, D229; docs/record.md): when a write leaves the record
# with more than 50 checks, the single writer stores the protected field (every
# file a check protects, each once, sorted) right after lease and sets schema 4;
# with 50 checks or fewer there is no such field and the schema follows today's
# rules (R46). The field follows the checks on every write, a record of an
# older VBW moves to schema 4 on its next write, this VBW reads schemas 1 to 4,
# and the validator refuses a field or a schema 4 that does not match. L1.

load helper
load protected-helper

setup() {
  vbw_setup
  protected_base
}

teardown() { vbw_teardown; }

# corrupt: vbw status calls the record corrupt (exit 3).
corrupt() {
  vbw_run status
  [ "$status" -eq 3 ] || { echo "expected a corrupt record, got exit $status: $output"; return 1; }
  [[ "$output" == *corrupt* ]] || { echo "$output"; return 1; }
}

@test "R150: with 51 checks the writer stores every protected file once, sorted, right after lease, at schema 4" {
  protected_apply 51
  jq -e '.schema == 4' .vbw/record.json
  jq -e '(keys_unsorted | .[:4]) == ["schema", "lease", "protected", "checks"]' .vbw/record.json
  [ "$(jq -c '.protected' .vbw/record.json)" = "$(protected_union)" ]
  jq -e '.protected | length == 51 and . == unique and index("tests/shared.sh") != null' .vbw/record.json
}

@test "R150: exactly 50 checks gives no field and the schema today's rules choose" {
  protected_apply 50
  jq -e '(has("protected") | not) and .schema == 1' .vbw/record.json
  protected_apply 50 '.checks[0].alone = true'
  jq -e '(has("protected") | not) and .schema == 2' .vbw/record.json
  "$VBW" todo add --sort later --size small "Gift cards" > /dev/null
  jq -e '(has("protected") | not) and .schema == 3' .vbw/record.json
}

@test "R150: growing past 50 checks adds the field on that write; dropping to 50 removes it and returns to schema 1, 2 or 3" {
  protected_apply 50
  jq -e 'has("protected") | not' .vbw/record.json
  protected_apply 51
  jq -e 'has("protected") and .schema == 4' .vbw/record.json
  protected_apply 50
  jq -e '(has("protected") | not) and .schema == 1' .vbw/record.json
  protected_apply 51 '.checks[0].alone = true'
  jq -e 'has("protected") and .schema == 4' .vbw/record.json
  protected_apply 50 '.checks[0].alone = true'
  jq -e '(has("protected") | not) and .schema == 2' .vbw/record.json
}

@test "R150: adding, removing or changing a check's files updates the field in the same write" {
  protected_apply 54
  jq -e '.protected | index("tests/c3.sh") != null' .vbw/record.json
  # Change: C3 now protects another file.
  protected_doc 54 | jq -c '{checks: [.checks[] | select(.id == "C3") | .files = ["tests/other.sh"]]}' | "$VBW" apply --patch > /dev/null
  [ "$(jq -c '.protected' .vbw/record.json)" = "$(protected_union)" ]
  jq -e '.protected | index("tests/other.sh") != null and index("tests/c3.sh") == null' .vbw/record.json
  # Add: a new check with a new file.
  jq -nc '{checks: [{id: "C60", req: "R1", run: ["sh", "tests/new.sh"], files: ["tests/new.sh"]}]}' | "$VBW" apply --patch > /dev/null
  jq -e '.protected | index("tests/new.sh") != null' .vbw/record.json
  [ "$(jq -c '.protected' .vbw/record.json)" = "$(protected_union)" ]
  # Remove: a plan again without C5 and C7 (still more than 50 checks).
  protected_apply 54 '.checks |= map(select(.id != "C5" and .id != "C7"))'
  jq -e '(.checks | length) == 52 and .schema == 4' .vbw/record.json
  jq -e '.protected | index("tests/c5.sh") == null and index("tests/c7.sh") == null' .vbw/record.json
  [ "$(jq -c '.protected' .vbw/record.json)" = "$(protected_union)" ]
}

@test "R150: a schema-3 record with more than 50 checks and no field still works, and moves to schema 4 on its next write" {
  "$VBW" todo add --sort later --size small "Gift cards" > /dev/null
  protected_apply 51
  as_schema3
  jq -e '.schema == 3 and (has("protected") | not) and (.checks | length) == 51' .vbw/record.json
  local before cmd
  before=$(cksum < .vbw/record.json)
  for cmd in "status" "next" "show roadmap" "show contract" "show requirements" "todo list"; do
    # shellcheck disable=SC2086 # the command words split on purpose
    vbw_run $cmd
    [ "$status" -eq 0 ] || { echo "vbw $cmd: $output"; false; }
  done
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  vbw_run decide "Keep every check"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.schema == 4 and (keys_unsorted | .[:4]) == ["schema", "lease", "protected", "checks"]' .vbw/record.json
  [ "$(jq -c '.protected' .vbw/record.json)" = "$(protected_union)" ]
  jq -e '.decisions[-1].text == "Keep every check" and (.todos[0].sort == "later")' .vbw/record.json
}

@test "R150: this VBW reads schema 4 and asks for a newer VBW on schema 5, naming schema 4 as its highest" {
  protected_apply 51
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  record_edit '.schema = 5'
  vbw_run status
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"needs a newer VBW"* ]]
  [[ "$output" == *"reads up to schema 4"* ]] || { echo "$output"; false; }
}

@test "R150: a schema-4 record without the field is corrupt" {
  protected_apply 51
  jq -e '.schema == 4 and has("protected")' .vbw/record.json
  record_edit 'del(.protected) | .schema = 4'
  corrupt
}

@test "R150: a field that differs from the checks' files is corrupt: one missing, one extra, out of order or repeated" {
  protected_apply 51
  jq -e '.schema == 4 and has("protected")' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f
  cp .vbw/record.json "$TEST_ROOT/good.json"
  for f in '.protected |= .[1:]' '.protected += ["tests/zzz.sh"]' '.protected |= reverse' '.protected += [.protected[0]]' '.protected = "tests/c1.sh"'; do
    cp "$TEST_ROOT/good.json" .vbw/record.json
    record_edit "$f"
    corrupt || { echo "accepted: $f"; false; }
  done
}

@test "R150: on 50 checks or fewer a field, or schema 4, is corrupt" {
  protected_apply 50
  cp .vbw/record.json "$TEST_ROOT/good.json"
  record_edit '.protected = ([.checks[].files // [] | .[]] | unique) | .schema = 4'
  corrupt
  cp "$TEST_ROOT/good.json" .vbw/record.json
  record_edit '.schema = 4'
  corrupt
  cp "$TEST_ROOT/good.json" .vbw/record.json
  record_edit '.protected = ([.checks[].files // [] | .[]] | unique)'
  corrupt
  cp "$TEST_ROOT/good.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
