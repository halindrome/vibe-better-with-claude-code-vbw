# The expectation ladders (R191, docs/panel.md): one jq program turns the step
# history, the per-unit runs store and a step's units into its expected seconds.
#
# Interface: jq -n --slurpfile h HISTORY --slurpfile runs RUNS --arg kind K
#   --argjson size SIZE -f steps-expect.jq
#   $h[0]    the history {steps: [...]} or null (a missing or damaged file)
#   $runs[0] the runs store {runs: {name: {seconds, ...}}} or null
#   $kind    build | fix | plan | qa | proof
#   $size    build: [{id, tier, tasks}] (the wave's plans); fix: {tier};
#            plan: {reqs}; qa: [{id, tier}]; proof: {units: [name]}
# Output: one integer (seconds), or nothing when the history gives no basis.
# Every list is the latest 10 by the history's order; an even count takes the
# mean of the two middle values; fewer than 3 samples never make a basis.

def median: sort | length as $n
  | if $n == 0 then empty
    elif $n % 2 == 1 then .[($n - 1) / 2 | floor]
    else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
def latest: .[-10:];
def num: type == "number" and . >= 0;
def basis: if length >= 3 then median else empty end;

($h[0] | if type == "object" and (.steps | type) == "array" then [.steps[] | select(type == "object")] else [] end) as $steps
| def of($k): [$steps[] | select(.kind == $k and (.seconds | num))];
  def withparts: map(select((.parts | type) == "number" and .parts > 0));

  # A plan unit: one finished plan of a build, with its tier, tasks and seconds.
  def plan_units: [of("build")[] | (.units // [])[] | select(type == "object" and (.seconds | num))];
  def per_plan($us): $us | latest | map(.seconds) | basis;
  def build_plan($p; $units):
    ($p.tier // "standard") as $t
    | ($p.tasks // 0) as $n
    | ( ( if $n > 0 then
            [$units[] | select(.tier == $t and (.tasks | type) == "number" and .tasks > 0)] | latest
            | if length >= 3 then (map(.seconds / .tasks) | median) * $n else empty end
          else empty end )
        // per_plan([$units[] | select(.tier == $t)])
        // per_plan($units) );
  def build:
    plan_units as $u
    | if ($u | length) >= 3 then
        [ $size[] | build_plan(.; $u) ] as $each
        | if ($each | length) == ($size | length) and ($each | length) > 0 then $each | max else empty end
      else
        (of("build") | withparts | latest) as $b
        | if ($b | length) >= 3 and ($size | length) > 0
          then ($b | map(.seconds / .parts) | median) * ($size | length) else empty end
      end;

  def fix:
    ( ( if ($size.tier | type) == "string" then of("fix") | map(select(.tier == $size.tier)) | latest | map(.seconds) | basis else empty end )
      // (of("fix") | latest | map(.seconds) | basis) );

  def planning:
    ( ( if ($size.reqs | type) == "number" and $size.reqs > 0 then
          of("plan") | map(select((.reqs | type) == "number" and .reqs > 0)) | latest
          | if length >= 3 then (map(.seconds / .reqs) | median) * $size.reqs else empty end
        else empty end )
      // (of("plan") | latest | map(.seconds) | basis) );

  def qa:
    [ of("qa")[] | select((.phases | type) == "array" and (.phases | length) > 0)
      | .seconds as $s | .phases as $ph | $ph[] | {tier: .tier, seconds: ($s / ($ph | length))} ] as $samples
    | if ($samples | length) >= 3 and ($size | length) > 0 then
        [ $size[] | .tier as $t
          | ( ( if ($t | type) == "string" then [$samples[] | select(.tier == $t)] | latest | map(.seconds) | basis else empty end )
              // ($samples | latest | map(.seconds) | basis) ) ] as $each
        | if ($each | length) == ($size | length) then $each | add else empty end
      else of("qa") | latest | map(.seconds) | basis end;

  def proof:
    ( [ of("proof")[] | select((.units | type) == "array" and (.units | length) > 0) ] | latest
      | map(([.units[] | select(type == "object" and (.seconds | num)) | .seconds] | add) as $sum
            | if $sum != null and $sum > 0 then .seconds / $sum else empty end) ) as $ratios
    | ( if ($ratios | length) >= 3 then
          ($runs[0] | if type == "object" and (.runs | type) == "object" then .runs else {} end) as $store
          | [ $size.units[]? | $store[.] | select(type == "object" and (.seconds | num)) | .seconds ] as $known
          | if ($known | length) == 0 then empty
            else ($known | median) as $m
              | ([ $size.units[]? | ($store[.] | if type == "object" and (.seconds | num) then .seconds else $m end) ] | add) * ($ratios | median)
            end
        else empty end )
      // ( of("proof") | withparts | latest
           | if length >= 3 and ($size.units | length) > 0
             then (map(.seconds / .parts) | median) * ($size.units | length) else empty end );

  ( if $kind == "build" then build
    elif $kind == "fix" then fix
    elif $kind == "plan" then planning
    elif $kind == "qa" then qa
    elif $kind == "proof" then proof
    else empty end )
  | round
