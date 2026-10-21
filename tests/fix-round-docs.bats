#!/usr/bin/env bats
# R182 (docs/workflows.md, docs/proof.md): the user docs say which agent runs
# vbw fix done in a fix round: the fixing workflow (its closing Lead), not a Dev.
# The order itself is behaviour of the workflow, pinned by its own tests. L1.

load helper

DOC="$REPO_ROOT/docs/workflows.md"
PROOF="$REPO_ROOT/docs/proof.md"

# flat TEXT: TEXT on one line, so a sentence wrapped across lines matches.
flat() { tr '\n' ' ' | tr -s ' '; }

@test "R182: the vbw:fixing row names vbw fix done" {
  local row
  row=$(grep -E '^\| `vbw:fixing`' "$DOC")
  [ -n "$row" ] || { echo "no vbw:fixing row"; false; }
  printf '%s' "$row" | grep -q 'vbw fix done' || { echo "$row"; false; }
}

@test "R182: the vbw fix done row names the fix round's workflow, not the Dev, as who runs it" {
  local row who
  row=$(grep -E '^\| `vbw fix done F1`' "$DOC")
  [ -n "$row" ] || { echo "no vbw fix done row"; false; }
  who=$(printf '%s' "$row" | awk -F'|' '{print $3}')
  printf '%s' "$who" | grep -qE 'Lead|workflow' || { echo "who: $who"; false; }
  printf '%s' "$who" | grep -qvE '^[[:space:]]*Dev[[:space:]]*$' || { echo "who: $who"; false; }
}

@test "R182: the docs no longer say a Dev runs vbw fix done" {
  ! flat < "$DOC" | grep -qE 'Dev or Docs agent runs `vbw plan done`, `vbw fix done`' || false
  ! flat < "$PROOF" | grep -qE 'Devs each running `vbw check`, `vbw fix done`'
}
