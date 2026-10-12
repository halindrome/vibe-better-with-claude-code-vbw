#!/usr/bin/env bats
# R180 (P129; docs/loop.md): vbw ship run by the loop makes no tag, no push and
# no call to a remote: with a remote configured, the remote's refs and the
# tags are unchanged after a loop's ship. L1.

load helper
load loop-helper

setup() {
  loop_project
  git init -q --bare "$TEST_ROOT/remote.git"
  git remote add origin "$TEST_ROOT/remote.git"
  git push -q -u origin main
}
teardown() { vbw_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }
remote_refs() { git ls-remote "$TEST_ROOT/remote.git" | sort; }

@test "R180: a loop's ship leaves the remote and the tags unchanged" {
  local refs tags
  refs=$(remote_refs)
  tags=$(git tag -l)
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  loop_build P2
  [ "$(step)" = prove ]
  loop_prove
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.milestone.status == "shipped" and .loop.items[0].status == "shipped"' .vbw/record.json
  [ "$(remote_refs)" = "$refs" ]
  [ "$(git tag -l)" = "$tags" ]
  [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]
}
