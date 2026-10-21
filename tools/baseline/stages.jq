# Tokens and dollars per stage of one session's requests (predict-run.sh stages).
# Input: an array of {id, model, ts, u, stage}, one per billed request (u is the
# API usage block). $p[0] is prices.json; $split, when not empty, is an ISO UTC
# time after which every request counts as the followup stage; $bymodel[0] is
# {model: usd} from the per-model lines of Claude Code's /cost ({} when unread).
#
# usd prices each request's recorded tokens at list price. A transcript does not
# record every output token (a thinking request shows a few), so usd falls short
# of /cost, most for thinking-heavy agents. Each model's shortfall (its /cost
# figure minus its priced requests) is spread over that model's requests evenly:
# adjusted_usd is a stage's share of its models' /cost figures. A request whose
# model is not in the price table counts under unpriced.

def order: ["main", "map", "plan", "build", "mutation", "qa", "fix", "close", "recommend", "research", "subagent", "followup"];

def price($model):
  $p[0].models as $m
  | ([$m | keys[] | select(. as $k | $model | startswith($k))] | first) as $k
  | if $k == null then null else $m[$k] end;

def counts:
  (.u.cache_creation // null) as $c
  | {input: (.u.input_tokens // 0),
     cache_write_5m: (if $c == null then (.u.cache_creation_input_tokens // 0) else ($c.ephemeral_5m_input_tokens // 0) end),
     cache_write_1h: (if $c == null then 0 else ($c.ephemeral_1h_input_tokens // 0) end),
     cache_read: (.u.cache_read_input_tokens // 0),
     output: (.u.output_tokens // 0)};

def usd($t; $r):
  (if ($r.long_prompt // null) != null and ($t.input + $t.cache_write_5m + $t.cache_write_1h + $t.cache_read) > $r.long_prompt
   then $r.long else $r end) as $q
  | ($t.input * $q.input + $t.cache_write_5m * $q.cache_write_5m + $t.cache_write_1h * $q.cache_write_1h
     + $t.cache_read * $q.cache_read + $t.output * $q.output) / 1000000;

def r4: (. * 10000 | round) / 10000;

def sum: reduce .[] as $x ({requests: 0, input: 0, cache_write_5m: 0, cache_write_1h: 0, cache_read: 0, output: 0, usd: 0, adjusted_usd: 0};
  .requests += 1 | .input += $x.t.input | .cache_write_5m += $x.t.cache_write_5m | .cache_write_1h += $x.t.cache_write_1h
  | .cache_read += $x.t.cache_read | .output += $x.t.output | .usd += $x.usd | .adjusted_usd += $x.adj)
  | .tokens = (.input + .cache_write_5m + .cache_write_1h + .cache_read + .output)
  | .usd |= r4 | .adjusted_usd |= r4;

($bymodel[0] // {}) as $cost
| [ .[] | (if $split != "" and .ts > $split then .stage = "followup" else . end)
    | . as $q | counts as $t | price($q.model) as $r
    | {stage: $q.stage, model: $q.model, t: $t, usd: (if $r == null then null else usd($t; $r) end)} ] as $all
| ($all | map(select(.usd != null))) as $priced0
# Per model: its priced sum and request count, and the share of its /cost shortfall each request carries.
| ($priced0 | group_by(.model) | map({key: .[0].model, value: {n: length, usd: (map(.usd) | add)}}) | from_entries) as $pm
| ($priced0 | map(. + {adj: (.usd + (if $cost[.model] == null then 0
                                       else ($cost[.model] - $pm[.model].usd) / $pm[.model].n end))})) as $priced
| {
    stages: [ (order + ($priced | map(.stage) | unique | map(select(IN(order[]) | not))))[] as $s
              | ($priced | map(select(.stage == $s))) | select(length > 0) | {stage: $s} + sum ],
    total: ($priced | sum),
    models: ($priced | group_by(.model) | map({model: .[0].model} + sum + {cost_usd: $cost[.[0].model]})),
    cost_models_not_in_transcripts: ([$cost | keys[] | select($pm[.] == null)] | map({model: ., usd: $cost[.]})),
    unpriced: ($all | map(select(.usd == null)) | {requests: length, models: (map(.model) | unique)})
  }
