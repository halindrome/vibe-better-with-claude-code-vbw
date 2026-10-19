#!/usr/bin/env bats
# R192 (L1): docs/panel.md says how the Sessions tab shows another day.
load helper
@test "R192: docs/panel.md says another day is named like the rest of the panel" {
  tr '\n' ' ' < "$REPO_ROOT/docs/panel.md" | tr -s ' ' | grep -qE 'last active[^.]*another day[^.]*yesterday'
}
