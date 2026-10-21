#!/usr/bin/env bats
# R150 (decision D238; docs/record.md): every vbw command that writes the record
# rewrites .vbw/runtime/glance.json in the same locked write. The glance holds
# the record's schema, lease and protected list exactly as the record does,
# besides what the status line reads, and stays current (strictly newer than
# the record) even when both are written within the same second. A failed
# glance write leaves the record written and the guards reading the record;
# after the record changes outside vbw, the next vbw command rewrites the
# glance from it. L1.

load helper
load protected-helper
load glance-helper

setup() {
  vbw_setup
  glance_project
}

teardown() { vbw_teardown; }

# after ARGS...: run vbw ARGS; the glance is then current and holds the record's
# schema, lease and protected list.
after() {
  "$VBW" "$@" > /dev/null || { echo "vbw $* failed"; return 1; }
  glance_current || { echo "the glance is not current after vbw $*"; return 1; }
  glance_same || { echo "after vbw $*"; return 1; }
}

@test "R150: vbw init writes a current glance with the record's schema, lease and protected list" {
  mkdir -p "$TEST_ROOT/fresh project"
  cd "$TEST_ROOT/fresh project"
  vbw_git_project
  after init
  jq -e '.protected == [] and .lease == null and .schema == 4' "$GLANCE"
}

@test "R150: every command that writes the record leaves a current glance with its schema, lease and protected list" {
  glance_current
  glance_same
  after decide "The glance follows the record"
  after todo add "Write the receipt"
  VBW_SESSION_ID=s1 after run start plan
  jq -e '.lease.kind == "plan"' "$GLANCE"
  VBW_SESSION_ID=s1 after run end
  VBW_SESSION_ID=s1 after run start build P1.1
  jq -e '.lease.kind == "build" and .lease.session == "s1"' "$GLANCE"
  VBW_SESSION_ID=s1 after run end
  after qa finding R1 "Payment fails"
  VBW_SESSION_ID=s1 after run start fix F1
  jq -e '.lease.kind == "fix"' "$GLANCE"
  VBW_SESSION_ID=s1 after run end
  jq -e '.lease == null' "$GLANCE"
  # A contract change that protects one more file: tests/c3.sh joins the list.
  protected_doc 4 | jq -c '.plans[0].files = ["src/", "tests/"]' > "$TEST_ROOT/doc.json"
  after apply < "$TEST_ROOT/doc.json"
  jq -e '.protected | index("tests/c3.sh") != null' "$GLANCE"
  after approve
}

@test "R150: the glance stays newer than the record when both are written within the same second" {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    "$VBW" decide "Decision $i" > /dev/null
    glance_current || { echo "write $i: the glance ($(secs "$GLANCE")) is not newer than the record ($(secs .vbw/record.json))"; false; }
  done
}

@test "R150: a failed glance write leaves the record written and the guards reading the record" {
  local real
  real=$(command -v mv)
  mkdir -p "$TEST_ROOT/shim"
  # An mv that refuses to put anything at .vbw/runtime/glance.json, and moves every other file.
  printf '#!/bin/sh\nfor a do last=$a; done\ncase "$last" in */glance.json) exit 1 ;; esac\nexec "%s" "$@"\n' "$real" > "$TEST_ROOT/shim/mv"
  chmod +x "$TEST_ROOT/shim/mv"
  glance_current
  jq -e '.lease == null' "$GLANCE"
  VBW_SESSION_ID=s1 PATH="$TEST_ROOT/shim:$PATH" "$VBW" run start build P1.1 > /dev/null
  jq -e '.lease.kind == "build"' .vbw/record.json
  ! glance_current || { echo "the glance written before the build run is still current"; false; }
  # The guards follow the record's build run, never the glance written before it.
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write README.md workflow-subagent)")
  denied_with "outside this run's files"
  local outside=$ANSWER
  ANSWER=$(hook_answer "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)")
  denied_with "is a protected check file"
  local protected=$ANSWER
  # The next write that succeeds makes the glance current again, with the same answers.
  "$VBW" decide "The glance is written again" > /dev/null
  glance_current
  glance_same
  [ "$(hook_answer "$PROJECT" "$(file_in Write README.md workflow-subagent)")" = "$outside" ]
  [ "$(hook_answer "$PROJECT" "$(file_in Write tests/c1.sh workflow-subagent)")" = "$protected" ]
}

@test "R150: after the record changes outside vbw, the next vbw command rewrites the glance from the record" {
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  jq -e '.lease.kind == "build"' "$GLANCE"
  git checkout -- .vbw/record.json
  jq -e '.lease == null' .vbw/record.json
  ! glance_current || { echo "the glance is current after git checkout of the record"; false; }
  "$VBW" status > /dev/null
  glance_same
}
