#!/usr/bin/env bats
# R161 (docs/next.md): the decision table that says what vbw next answers
# renders as a table: every row has the header's number of cells (pipes
# inside code spans do not count), so no explanation lands in the wrong
# column. L1.

load helper

DOC="$REPO_ROOT/docs/next.md"

# cells LINE: the number of column separators outside backtick spans.
cells() { printf '%s\n' "$1" | sed 's/`[^`]*`//g' | tr -cd '|' | wc -c | tr -d ' '; }

@test "R161: every row of the decision table in docs/next.md has the header's number of cells" {
  local header want bad="" line n=0
  header=$(grep -m1 '^| # | Condition | action | gate |' "$DOC")
  [ -n "$header" ] || { echo "no decision table header in docs/next.md"; false; }
  want=$(cells "$header")
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$(cells "$line")" = "$want" ] || bad="$bad"$'\n'"row $n: $(printf '%s' "$line" | cut -c1-120)"
  done < <(awk '/^\| # \| Condition \| action \| gate \|/{on=1; next} on && /^\|/{print} on && !/^\|/{exit}' "$DOC")
  [ "$n" -ge 10 ] || { echo "the table has only $n rows"; false; }
  [ -z "$bad" ] || { printf 'rows with the wrong number of cells (header has %s):%s\n' "$want" "$bad"; false; }
}

@test "R161: the ship row explains detail.later inside its action cell" {
  local row
  row=$(grep -m1 '^| 12 | otherwise |' "$DOC")
  [ -n "$row" ]
  [[ "$row" == *'`detail.later`'* ]] || { echo "$row"; false; }
  [ "$(cells "$row")" = 5 ] || { echo "$row"; false; }
}
