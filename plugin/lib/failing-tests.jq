# failing-tests.jq: the failing test names in a kept output, each once, in order
# of appearance (R195.6). Input: the whole output as one string (jq -Rs).
# Recognised: TAP/bats, cargo test, pytest, go test, jest, vitest, mocha.
# Read only by vbw show fix, never on a hook or status-line path (R195.9).
def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
def first_match($re): capture($re) | .n | trim;
split("\n") as $lines
# mocha's own summary repeats each failure after "N passing"; only the inline lines count.
| ([$lines | to_entries[] | select(.value | test("^\\s*\\d+ (passing|failing)")) | .key] | (min // ($lines | length))) as $summary
| [ $lines | to_entries[] | .key as $i | .value as $l
    | (  ($l | select(test("^not ok \\d+"))        | first_match("^not ok \\d+\\s*(- )?(?<n>.*?)(\\s+#\\s*(TODO|SKIP).*)?$"))
      // ($l | select(test("^test .+ \\.\\.\\. FAILED$")) | first_match("^test (?<n>.+) \\.\\.\\. FAILED$"))
      // ($l | select(test("^FAILED \\S"))          | first_match("^FAILED (?<n>.*?)( - .*)?$"))
      // ($l | select(test("^\\s*--- FAIL: \\S"))   | first_match("^\\s*--- FAIL: (?<n>\\S+)"))
      // ($l | select(test("^\\s*✕ "))              | first_match("^\\s*✕ (?<n>.*?)( \\(\\d+(\\.\\d+)? ?m?s\\))?$"))
      // ($l | select(test("^\\s*× "))              | first_match("^\\s*× (?<n>.*?)( \\d+(\\.\\d+)? ?m?s)?$"))
      // ($l | select($i < $summary and test("^\\s+\\d+\\) \\S")) | first_match("^\\s+\\d+\\) (?<n>.*)$"))
      ),
      # cargo's closing "failures:" list: indented bare names right after the heading
      ( select($l == "failures:" and ($lines[$i + 1] // "" | test("^    \\S+$")))
        | label $stop | $lines[$i + 1:][] | if test("^    \\S+$") then trim else break $stop end )
  ]
| reduce .[] as $n ([]; if index([$n]) then . else . + [$n] end)
