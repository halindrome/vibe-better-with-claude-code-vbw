#!/usr/bin/env bats
# R182 (docs/workflows.md, docs/proof.md): the user docs describe the fix
# round's new order: every Dev commits its fix and checks it with vbw check;
# after every Dev has returned, the workflow runs one vbw fix done for every
# fix whose Dev reported done (the closing Lead with a session, an agent of its
# own without one), then vbw run confirm and vbw run end. No text still says a
# Dev runs vbw fix done. L1.

load helper

DOC="$REPO_ROOT/docs/workflows.md"
PROOF="$REPO_ROOT/docs/proof.md"

# flat TEXT: TEXT on one line, so a sentence wrapped across lines matches.
flat() { tr '\n' ' ' | tr -s ' '; }

@test "R182: the vbw:fixing row says the workflow runs one vbw fix done after every Dev returns" {
  local row
  row=$(grep -E '^\| `vbw:fixing`' "$DOC")
  [ -n "$row" ] || { echo "no vbw:fixing row"; false; }
  printf '%s' "$row" | grep -q 'vbw fix done' || { echo "$row"; false; }
  printf '%s' "$row" | grep -qiE 'once|one `?vbw fix done' || { echo "$row"; false; }
  printf '%s' "$row" | grep -qiE 'after every Dev' || { echo "$row"; false; }
}

@test "R182: the vbw fix done row names the fix round's workflow, not the Dev, as who runs it" {
  local row who
  row=$(grep -E '^\| `vbw fix done F1`' "$DOC")
  [ -n "$row" ] || { echo "no vbw fix done row"; false; }
  who=$(printf '%s' "$row" | awk -F'|' '{print $3}')
  printf '%s' "$who" | grep -qE 'Lead|workflow' || { echo "who: $who"; false; }
  printf '%s' "$who" | grep -qvE '^[[:space:]]*Dev[[:space:]]*$' || { echo "who: $who"; false; }
}

@test "R182: the run-closing text says the fixing workflow's closing Lead runs vbw fix done before vbw run confirm, and that it still runs without a session" {
  local text
  text=$(sed -n '/^A workflow closes its own run/,/^### Who records/p' "$DOC" | flat)
  printf '%s' "$text" | grep -qE 'vbw fix done.{0,250}vbw run confirm|vbw run confirm.{0,250}after.{0,100}vbw fix done' || { echo "$text"; false; }
  printf '%s' "$text" | grep -qiE 'without (it|a session|`args.session`).{0,250}vbw fix done|vbw fix done.{0,250}without (it|a session|`args.session`)' || { echo "$text"; false; }
}

@test "R182: the docs no longer say a Dev runs vbw fix done; the Lead's closing step does" {
  ! flat < "$DOC" | grep -qE 'Dev or Docs agent runs `vbw plan done`, `vbw fix done`'
  local text
  text=$(sed -n '/^### Who records/,/^### The closing agent never refuses/p' "$DOC" | flat)
  # The Lead and vbw fix done in one clause (no full stop or semicolon between them).
  printf '%s' "$text" | grep -qE 'Lead[^.;]{0,200}vbw fix done' || { echo "$text"; false; }
}

@test "R182: when the closing agent stops, the docs give the vbw fix done to run by hand" {
  local text
  text=$(sed -n '/^### The closing agent never refuses/,/^### `vbw run confirm/p' "$DOC" | flat)
  printf '%s' "$text" | grep -q 'vbw fix done' || { echo "$text"; false; }
}

@test "R182: the one-test-run section says each Dev commits and runs vbw check, and the round's vbw fix done runs once after every Dev returns" {
  local text
  text=$(sed -n '/^## One test run per fix round/,/^## Rigor/p' "$DOC" | flat)
  printf '%s' "$text" | grep -qi 'commit' || { echo "$text"; false; }
  printf '%s' "$text" | grep -q 'vbw check' || { echo "$text"; false; }
  printf '%s' "$text" | grep -qiE 'vbw fix done.{0,200}once|once.{0,200}vbw fix done' || { echo "$text"; false; }
}

@test "R182: docs/proof.md no longer describes parallel Devs each running vbw fix done" {
  ! flat < "$PROOF" | grep -qE 'Devs each running `vbw check`, `vbw fix done`'
}
