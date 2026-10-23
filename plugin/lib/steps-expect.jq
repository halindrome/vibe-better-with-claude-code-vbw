# The expectation ladders (R191, docs/panel.md): one jq program turns the step
# history, the per-unit runs store and a step's units into its expected seconds.
#
# Interface: jq -n --slurpfile h HISTORY --slurpfile runs RUNS --arg kind K
#   --slurpfile size SIZE -f steps-expect.jq (a file: a proof's size names every unit)
#   $h[0]    the history {steps: [...]} or null (a missing or damaged file)
#   $runs[0] the runs store {runs: {name: {seconds, ...}}} or null
#   $kind    build | fix | plan | qa | proof
#   $size[0] build: [{id, tier, tasks, breaks}] (the wave's plans); fix: {tier};
#            plan: {reqs}; qa: [{id, tier}]; proof: {units: [name]}
# Output: one integer (seconds), or nothing when the history gives no basis.
# Every list is the latest 10 by the history's order; an even count takes the
# mean of the two middle values; fewer than 3 samples never make a basis.
#
# A build wave waits for its slowest plan (T174): each plan is timed at the
# quantile 0.75^(1/n) of its unit's seconds (n: the wave's plans), the time 3
# waves in 4 stay within when plans vary on their own: the upper quartile for a
# lone plan, 0.87 for two, 0.91 for three. A plan's unit of work is a task or a
# break (a rule it owes the mutation check), so its work is its tasks plus its
# breaks; the history from before breaks were recorded counts per task.
#
# A proof takes its units' costs times the learned ratio. The latest 10 proofs
# that recorded units give the ratio, their total wall time over their total
# unit time (one proof of two units cannot skew it), and each unit's fastest
# seconds among them; the store's last run joins that minimum, so a busy day's
# slow run never sets the promise (a proof that runs late moves its end, D424).
# A unit never run counts as the median of the known costs.

def median: sort | length as $n
  | if $n == 0 then empty
    elif $n % 2 == 1 then .[($n - 1) / 2 | floor]
    else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
# quantile($q): linear between the two nearest sorted values (0.5 is the median).
def quantile($q): sort | length as $n
  | if $n == 0 then empty
    else (($n - 1) * $q) as $p | ($p | floor) as $lo | ([$lo + 1, $n - 1] | min) as $hi
      | .[$lo] + (.[$hi] - .[$lo]) * ($p - $lo) end;
def latest: .[-10:];
def num: type == "number" and . >= 0;
def basis: if length >= 3 then median else empty end;

$size[0] as $size
| ($h[0] | if type == "object" and (.steps | type) == "array" then [.steps[] | select(type == "object")] else [] end) as $steps
| (if $kind == "build" and ($size | type) == "array" and ($size | length) > 0 then pow(0.75; 1 / ($size | length)) else 0.75 end) as $q
| def of($k): [$steps[] | select(.kind == $k and (.seconds | num))];
  def withparts: map(select((.parts | type) == "number" and .parts > 0));

  # A plan unit: one finished plan of a build, with its tier, tasks, breaks and seconds.
  # A list VBW never wrote (units or phases that are not arrays, an entry that is not an
  # object) is skipped, never an error: every shape the history has had stays readable.
  def items: if type == "array" then .[] | select(type == "object") else empty end;
  def plan_units: [of("build")[] | .units | items | select(.seconds | num)];
  def counted($f): ($f | type) == "number" and $f >= 0;
  # Per unit of size: the wave's quantile of seconds / size over the latest 10 that recorded it, times this size.
  def per($us; size; $n): $us | latest | if length >= 3 then (map(.seconds / size) | quantile($q)) * $n else empty end;
  def build_plan($p; $units):
    ($p.tier // "standard") as $t
    | ($p.tasks // 0) as $tk
    | (if counted($p.breaks) then $p.breaks else 0 end) as $bk
    | [$units[] | select(.tier == $t)] as $tu
    | ( ( if $tk + $bk > 0 then
            per([$tu[] | select(counted(.tasks) and counted(.breaks) and .tasks + .breaks > 0)]; .tasks + .breaks; $tk + $bk)
          else empty end )
        // ( if $tk > 0 then per([$tu[] | select(counted(.tasks) and .tasks > 0)]; .tasks; $tk) else empty end )
        // per($tu; 1; 1)
        // per($units; 1; 1) );
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
      | .seconds as $s | .phases as $ph | $ph | items | {tier: .tier, seconds: ($s / ($ph | length))} ] as $samples
    | if ($samples | length) >= 3 and ($size | length) > 0 then
        [ $size[] | .tier as $t
          | ( ( if ($t | type) == "string" then [$samples[] | select(.tier == $t)] | latest | map(.seconds) | basis else empty end )
              // ($samples | latest | map(.seconds) | basis) ) ] as $each
        | if ($each | length) == ($size | length) then $each | add else empty end
      else of("qa") | latest | map(.seconds) | basis end;

  def proof:
    ( [ of("proof")[] | select((.units | type) == "array" and (.units | length) > 0)
        | {seconds, units: [.units[] | select(type == "object" and (.name | type) == "string" and (.seconds | num))]}
        | select(([.units[].seconds] | add // 0) > 0) ] | latest ) as $hist
    | ( if ($hist | length) >= 3 then
          ($runs[0] | if type == "object" and (.runs | type) == "object" then .runs else {} end) as $store
          | (($hist | map(.seconds) | add) / ($hist | map([.units[].seconds] | add) | add)) as $ratio
          | (reduce ($hist[].units[]) as $u ({}; .[$u.name] = ([.[$u.name], $u.seconds] | map(select(. != null)) | min))) as $fast
          | def cost: . as $n | [$fast[$n], ($store[$n] | if type == "object" and (.seconds | num) then .seconds else null end)]
              | map(select(. != null)) | if length > 0 then min else null end;
          [ $size.units[]? | cost | select(. != null) ] as $known
          | if ($known | length) == 0 then empty
            else ($known | median) as $m
              | ([ $size.units[]? | cost // $m ] | add) * $ratio
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
