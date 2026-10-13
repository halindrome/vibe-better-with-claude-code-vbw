#!/usr/bin/env bats
# R184: docs/statusline.md says, in plain words, what the status line shows in
# a project where VBW is turned off (the user's earlier status line, or
# nothing), which settings files decide it and in what order, that the
# setting itself runs the earlier status line (VBW never does), and that
# vbw statusline on updates a setting made by an older VBW. The old claim
# that the setting never changes is gone. L1.

load helper

DOC="$REPO_ROOT/docs/statusline.md"

# section: the doc's section about a project where VBW is turned off.
section() { sed -n '/^## .*[Tt]urned off/,/^## /p' "$DOC"; }

@test "R184: docs/statusline.md has a section on projects where VBW is turned off" {
  [ -n "$(section)" ] || {
    echo "no '## ... turned off' section in docs/statusline.md"
    false
  }
}

@test "R184: it names the setting and the three settings files in Claude Code's order" {
  local s
  s=$(section)
  printf '%s\n' "$s" | grep -qF 'enabledPlugins'
  printf '%s\n' "$s" | grep -qF '"vbw@vbw-marketplace": false'
  printf '%s\n' "$s" | grep -qF '.claude/settings.local.json'
  printf '%s\n' "$s" | grep -qF '.claude/settings.json'
  printf '%s\n' "$s" | grep -qF 'settings.json'
  # The local file is named before the project file: it wins.
  local a b
  a=$(printf '%s\n' "$s" | grep -nF '.claude/settings.local.json' | head -1 | cut -d: -f1)
  b=$(printf '%s\n' "$s" | grep -nF '.claude/settings.json' | head -1 | cut -d: -f1)
  [ "$a" -le "$b" ]
}

@test "R184: it says the earlier status line comes back there, or nothing shows, and VBW itself never runs it" {
  local s
  s=$(section)
  printf '%s\n' "$s" | grep -qi 'earlier status line'
  printf '%s\n' "$s" | grep -qiE 'nothing (shows|is shown)|shows nothing'
  printf '%s\n' "$s" | grep -qiE 'never runs'
}

@test "R184: it says vbw statusline on updates a setting made by an older VBW, and the old 'same setting' claim is gone" {
  section | grep -qF 'vbw statusline on'
  section | grep -qF 'vbw doctor'
  ! grep -qF 'It is the same setting VBW 1 used' "$DOC" || {
    echo "docs/statusline.md still says the setting never changes"
    false
  }
}
