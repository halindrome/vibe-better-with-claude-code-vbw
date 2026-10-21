#!/usr/bin/env bats
# R72, R116 (docs/rigor.md, docs/workflows.md): on the small path the router
# plans the change itself instead of the Lead, so it carries the Lead's role rule
# (plugin/agents/lead.md, "Role"): a plan that only writes documentation has
# role docs, and vbw next then hands it to the Docs agent (detail.docs); a plan
# with no role goes to the Dev. The 2.0.41 real-user run "docs" planned a
# documentation request through this path without the role, so the Dev built it.
# L1: the router's text, the Lead's text and the kernel on a fixture; the real
# app is tools/l3-suite.sh docs.

load helper

teardown() { vbw_teardown; }

# small_path: the router's section for the small path.
small_path() {
  sed -n '/^\*\*plan\*\* with `detail.tier` express or `detail.small`/,/^\*\*plan\*\*: /p' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}

@test "R72: the router's small path tells a documentation-only plan to take role docs, with the Lead's own list of documentation" {
  local small lead list
  small=$(small_path)
  [ -n "$small" ]
  printf '%s' "$small" | grep -qF '"role":"docs"'
  # One definition of documentation for both planners: the Lead's list, verbatim.
  list=$(sed -n 's/^4\. \*\*Role:\*\* plan only writing documentation (\(.*\)) gets .*/\1/p' "$PLUGIN_ROOT/agents/lead.md")
  [ -n "$list" ] || { echo "the Lead's role rule changed shape"; false; }
  printf '%s' "$small" | grep -qF "($list)" || { echo "the router does not carry the Lead's list: ($list)"; false; }
}

# docs_request: a git project with greet.sh and one [auto] documentation
# requirement, with a check and a plan for docs/USAGE.md, approved. ROLE is the
# plan's role as the planner wrote it ("" leaves the key out).
docs_request() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests docs
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh
  printf 'grep -q "Hello, Ada!" docs/USAGE.md\n' > tests/usage.sh
  git add greet.sh tests && git commit -q -m "feat: greet.sh"
  "$VBW" spec add auto "docs/USAGE.md shows ./greet.sh Ada and its output Hello, Ada!" > /dev/null
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "plan" and .detail.small == true' || { echo "$output"; false; }
  jq -n --arg role "$1" '{phases: [{id: "P1", title: "Write USAGE.md", reqs: ["R1"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Write docs/USAGE.md", reqs: ["R1"], files: ["docs/USAGE.md"], after: [], tasks: ["show the example"]}
      + (if $role == "" then {} else {role: $role} end)],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/usage.sh"], files: ["tests/usage.sh"]}],
    rules: [{req: "R1", text: "USAGE.md shows ./greet.sh Ada and Hello, Ada!", check: "C1"}]}' | "$VBW" apply --add > /dev/null
  "$VBW" approve > /dev/null
}

@test "R72: vbw next hands a documentation plan that carries role docs to the Docs agent" {
  docs_request docs
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "build" and .detail.plans == ["P1.1"] and .detail.docs == ["P1.1"]' || { echo "$output"; false; }
}

@test "R72: a documentation plan with no role is a Dev plan: the role is the planner's to write" {
  docs_request ""
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "build" and .detail.plans == ["P1.1"] and .detail.docs == []' || { echo "$output"; false; }
}
