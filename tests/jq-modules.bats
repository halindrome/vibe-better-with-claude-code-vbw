#!/usr/bin/env bats
# The jq files VBW ships include their modules one level deep (L1). jq 1.8.2
# (Homebrew's jq on macOS) aborts, before its first output, a program that
# reaches a module only through another module ("Unknown function type",
# jqlang/jq#3636); for a guard that is a failure during a run, which blocks
# every call (R165). So a program includes every module it uses itself, and no
# module it includes includes or imports another.

load helper

# includes FILE: the module files FILE includes or imports, one per line.
includes() {
  local file="$1" name dir
  # One "NAME SEARCH" pair per line (module names and search folders hold no space).
  while read -r name dir; do
    [ -n "$name" ] || continue
    printf '%s/%s/%s.jq\n' "$(dirname "$file")" "${dir:-.}" "$name"
  done < <(sed -nE 's/^[[:space:]]*(include|import)[[:space:]]+"([^"]+)"[^{;]*(\{[[:space:]]*search:[[:space:]]*"([^"]*)"[[:space:]]*\})?.*$/\2 \4/p' "$file")
}

@test "every jq module a VBW program includes includes no other module (jq 1.8.2, jqlang/jq#3636)" {
  local file mod bad="" seen=0
  while IFS= read -r file; do
    while IFS= read -r mod; do
      seen=$((seen + 1))
      [ -f "$mod" ] || { bad="$bad$file includes $mod, which does not exist"$'\n'; continue; }
      if grep -qE '^[[:space:]]*(include|import)[[:space:]]+"' "$mod"; then
        bad="$bad$file includes $mod, which includes another module"$'\n'
      fi
    done < <(includes "$file")
  done < <(find "$PLUGIN_ROOT" -type f -name '*.jq' | LC_ALL=C sort)
  # The guards and the status line include modules: the rule has something to hold.
  [ "$seen" -ge 3 ]
  [ -z "$bad" ] || { printf '%s' "$bad"; false; }
}

@test "each guard includes lib/holder.jq itself, and the shared guard module includes nothing" {
  local g
  for g in guard-file guard-bash; do
    grep -qE '^include "holder" \{search: "\.\./lib"\};' "$PLUGIN_ROOT/hooks/$g.jq"
    grep -qE '^include "common" \{search: "\./"\};' "$PLUGIN_ROOT/hooks/$g.jq"
  done
  if grep -qE '^[[:space:]]*(include|import)[[:space:]]+"' "$PLUGIN_ROOT/hooks/common.jq"; then false; fi
}
