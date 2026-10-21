# The prediction against the measured runs, stage by stage (predict-run.sh report).
# $pr[0] is the prediction (predictions/CASE.json); $p[0] and $v[0] are the
# plain and VBW 2 measures files predict-run.sh run writes. Dollars per stage
# are adjusted_usd (each stage's share of its models' /cost figures);
# unattributed is /cost minus the stages.

def money: if . == null then "none" else "$" + ((. * 100 | round) / 100 | tostring) end;
def span(f): "\(.point | f) (\(.low | f) to \(.high | f))";
def inside($a): if $a == null then "n/a" elif $a >= .low and $a <= .high then "yes" else "no" end;
def num: (. * 100 | round) / 100 | tostring;

def actuals($m):
  ($m.stages.stages | map({key: .stage, value: .adjusted_usd}) | from_entries)
  + {unattributed: ($m.record.cost_usd - $m.stages.total.adjusted_usd)};

def side($name; $label; $m):
  $pr[0].sides[$name] as $s
  | actuals($m) as $a
  | "### \($label)", "",
    "| Stage | Predicted, point (range) | Actual | In range |",
    "|---|---|---|---|",
    ($s.stages | to_entries[] | ($a[.key] // 0) as $x
      | "| \(.key) | \(.value | span(money)) | \($x | money) | \(.value | inside($x)) |"),
    ($a | to_entries[] | select($s.stages[.key] == null) | "| \(.key) | not predicted | \(.value | money) | n/a |"),
    "| total cost | \($s.total_usd | span(money)) | \($m.record.cost_usd | money) | \($s.total_usd | inside($m.record.cost_usd)) |",
    "| tokens | \($s.tokens | span(tostring)) | \($m.record.tokens) | \($s.tokens | inside($m.record.tokens)) |",
    "| wall minutes | \($s.wall_minutes | span(tostring)) | \($m.wall_seconds / 60 | num) | \($s.wall_minutes | inside($m.wall_seconds / 60)) |",
    "| user inputs | \($s.user_inputs | span(tostring)) | \($m.record.user_inputs) | \($s.user_inputs | inside($m.record.user_inputs)) |",
    "| hidden check at first finish | fails with probability \($s.first_fail_probability) | \(if $m.record.first_pass then "passed" else "failed" end) | n/a |",
    "| follow-ups | \($s.followups | span(tostring)) | \($m.record.followups) | \($s.followups | inside($m.record.followups)) |",
    "| correct at the end | with probability \($s.correct_probability) | \($m.record.pass) | n/a |",
    "| cost per correct result | \($s.usd_per_correct | span(money)) | \(if $m.record.pass then ($m.record.cost_usd | money) else "no correct result" end) | \($s.usd_per_correct | inside(if $m.record.pass then $m.record.cost_usd else null end)) |",
    "";

"## Predicted vs actual: \($pr[0].case), \($pr[0].model)", "",
"Prediction: estimate, committed before the runs. Runs: Claude Code \($v[0].claude_version) (plain: \($p[0].claude_version)); main conversation cache: plain \($p[0].main_cache_ttl // "unknown"), VBW 2 \($v[0].main_cache_ttl // "unknown"); leak check: plain \($p[0].leak), VBW 2 \($v[0].leak).", "",
side("vbw2"; "VBW 2"; $v[0]),
side("plain"; "Plain Claude Code"; $p[0]),
"### Ratios", "",
"| Measure | Predicted, point (range) | Actual | In range |",
"|---|---|---|---|",
(($v[0].record.cost_usd / $p[0].record.cost_usd) as $r
  | "| cost, VBW 2 over plain | \($pr[0].ratio | span(tostring)) | \($r | num) | \($pr[0].ratio | inside($r)) |"),
((if $v[0].record.pass and $p[0].record.pass
  then ($v[0].record.cost_usd / $p[0].record.cost_usd) else null end) as $c
  | "| cost per correct result, VBW 2 over plain | \($pr[0].ratio_per_correct | span(tostring)) | \(if $c == null then "n/a (a side has no correct result)" else ($c | num) end) | \($pr[0].ratio_per_correct | inside($c)) |")
