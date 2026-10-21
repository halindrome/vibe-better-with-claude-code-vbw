#!/usr/bin/env bats
# R184: whether Claude Code loads VBW's panel (the hooks.json module) in a
# project that turns the VBW plugin off is found out in the real app, not
# assumed. The pluginoff scenario in tools/l3-suite.sh opens Claude Code in a
# VBW project whose .claude/settings.json sets enabledPlugins
# "vbw@vbw-marketplace" to false, confirms Claude Code itself reports VBW
# turned off there, and records whether the panel module was loaded and
# whether anything of VBW showed. Passing means nothing of VBW shows: if Claude
# Code loads the panel there, the panel shows nothing in that project, and the
# result names the panel test that proves it. As in tests/l3-results.bats,
# these tests do not run Claude Code (L1): they hold the scenario's structure
# and its committed result, written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/pluginoff.json"

body() { sed -n '/^scenario_pluginoff()/,/^}/p' "$SUITE"; }

@test "R184: the pluginoff scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_pluginoff()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw pluginoff
  sed -n '1,26p' "$SUITE" | grep -qw pluginoff
}

@test "R184: it turns VBW off in the project's own settings and writes its result with its fixture and what it did not test" {
  [ -n "$(body)" ]
  body | grep -q 'enabledPlugins'
  body | grep -q 'vbw@vbw-marketplace'
  body | grep -q '\.claude/settings\.json'
  body | grep -q 'result_write pluginoff '
  body | grep -qi 'fixture='
}

@test "R184: a committed result is honest: L3, passed, VBW confirmed off by Claude Code, and nothing of VBW shown" {
  [ -f "$RESULT" ] || {
    echo "the pluginoff scenario has not been run: no result is committed"
    false
  }
  jq -e '.scenario == "pluginoff" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string")
    and .facts.plugin_disabled_confirmed == true
    and (.facts.panel_module_loaded | type == "boolean")
    and .facts.panel_shown == false
    and .facts.vbw_statusline_shown == false
    and (.not_tested | type == "array" and length > 0)' "$RESULT"
}

@test "R184: if Claude Code loads the panel where VBW is off, the result names the panel test that proves it shows nothing there" {
  [ -f "$RESULT" ] || {
    echo "the pluginoff scenario has not been run: no result is committed"
    false
  }
  if jq -e '.facts.panel_module_loaded == true' "$RESULT" > /dev/null; then
    local t
    t=$(jq -r '.facts.panel_test // ""' "$RESULT")
    [[ "$t" == tests/panel/*.test.mjs ]] && [ -f "$REPO_ROOT/$t" ] || {
      echo "the panel loads where VBW is off, but no panel test is named: '$t'"
      false
    }
    grep -q 'enabledPlugins' "$REPO_ROOT/$t"
  fi
}
