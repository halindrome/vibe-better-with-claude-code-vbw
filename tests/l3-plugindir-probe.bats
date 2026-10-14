#!/usr/bin/env bats
# R185: before the fix, a probe in the real app finds out what Claude Code does
# when VBW is installed from the marketplace and a session is started with
# claude --plugin-dir pointing at a working tree, instead of assuming it. The
# plugindir scenario in tools/l3-suite.sh, run before the fix with its result
# named plugindir-probe, opens Claude Code that way (the installed VBW turned
# on, a PATH inherited with the installed release's bin/ on it) and records:
# which copies of VBW load, every vbw on the Bash tool's PATH in order, the vbw
# the session and an agent it starts resolve, which copy's hooks ran, the
# plugin data folder name the loaded copy's hooks get, and whether its
# SessionStart hook got a CLAUDE_ENV_FILE. As in tests/l3-results.bats, these
# tests do not run Claude Code (L1): they hold the scenario's structure and its
# committed result, written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
PROBE="$REPO_ROOT/tools/l3-results/plugindir-probe.json"

body() { sed -n '/^scenario_plugindir()/,/^}/p' "$SUITE"; }

@test "R185: the plugindir scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_plugindir()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw plugindir
  sed -n '1,26p' "$SUITE" | grep -qw plugindir
}

@test "R185: it starts the session with the working tree and the installed VBW on, and can name its result plugindir-probe" {
  [ -n "$(body)" ]
  body | grep -q 'L3_MODE='
  body | grep -q 'result_write '
  body | grep -q 'plugindir-probe'
  body | grep -qi 'fixture='
  # tools/l3.sh has a mode that loads the working tree with the installed VBW left on.
  grep -qE '\[ "\$mode" = both \]|both\)' "$REPO_ROOT/tools/l3.sh"
}

@test "R185: the committed probe is an honest L3 run of two different versions" {
  [ -f "$PROBE" ] || {
    echo "the probe has not been run: no tools/l3-results/plugindir-probe.json is committed"
    false
  }
  jq -e '.scenario == "plugindir-probe" and .evidence_level == "L3"
    and (.passed | type == "boolean")
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string") and (.not_tested | type == "array" and length > 0)
    and (.facts.claude_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+"))
    and (.facts.tree_version | type == "string" and length > 0)
    and (.facts.installed_version | type == "string" and length > 0)
    and .facts.tree_version != .facts.installed_version' "$PROBE"
}

@test "R185: the probe names the copies loaded, the PATH order, the vbw resolved by the session and an agent, and whose hooks ran" {
  [ -f "$PROBE" ] || {
    echo "the probe has not been run"
    false
  }
  jq -e '(.facts.loaded_copies | type == "array" and length > 0 and all(.[]; type == "string"))
    and (.facts.plugin_bins_on_path | type == "array" and all(.[]; type == "string"))
    and (.facts.session_vbw_path | type == "string" and endswith("/vbw"))
    and (.facts.session_vbw_version | type == "string")
    and (.facts.agent_vbw_path | type == "string" and endswith("/vbw"))
    and (.facts.hooks_from | type == "array" and length > 0 and all(.[]; type == "string"))
    and (.facts.plugin_data_id | type == "string" and length > 0)
    and (.facts.env_file_given | type == "boolean")
    and (.facts.launch_path_had_installed | type == "boolean")' "$PROBE"
}
