# The loop

The loop works through a list of backlog items while you are away. You name the
items and choose how much it may spend. For each item it plans, builds, proves
and ships on its own, and it asks you nothing about a contract that is exactly
the item you named. Anything else still waits for you.

```
vbw loop start T4 T7 --ceiling 20
vbw loop status
vbw loop stop
```

The items are backlog ids from `vbw todo list`. The loop records its state in
the record (`loop`, docs/record.md), so any session of the project can read it
or stop it.

## `vbw loop start`

```
vbw loop start [--session ID] ITEM... --ceiling USD
vbw loop start [--session ID] ITEM... --ceiling USD --finish-item
vbw loop start [--session ID] ITEM... --no-ceiling
```

You must choose one of the three ceiling forms (D317). VBW never picks one for
you.

| Form | What it does |
|---|---|
| `--ceiling USD` | Stops before the next step once the loop has spent `USD`. |
| `--ceiling USD --finish-item` | When `USD` is reached, lets the current item finish, then stops. |
| `--no-ceiling` | No spend limit. An explicit choice, not a default. |

`start` records the items in the order you gave them, each with a snapshot of
its backlog text (a later edit of the backlog changes nothing in the loop), the
ceiling, the session (`--session`, else the current one), the start time, and
every known session's cost figures as the baseline. It commits the record
(`chore(vbw): loop start`). Only you start a loop: the guard denies
`vbw loop start` to any tool call (docs/guards.md), and `/vbw:loop` runs it
with your own arguments.

### Refusals

Each refusal exits 1, changes nothing and ends with `Next:` and what to do.

| Why | What to do |
|---|---|
| No item | Name items from `vbw todo list`. |
| Unknown item (`stop` as an item says to run `vbw loop stop`) | Use an id from `vbw todo list`. |
| Item already done or dropped | Pick an open item. |
| Same item twice | Name each item once. |
| A loop is already on and not ended | `vbw loop stop` first (twice when it is already stopping and its session is gone). |
| The current milestone has requirements and is not shipped | Finish or ship it first: each item gets its own milestone. A `[human]` requirement carried over from an earlier ship (skipped, waiting for you) does not count. |
| `--ceiling` and no session has a cost figure | `vbw statusline on`, or use `--no-ceiling`. |

A missing ceiling choice, `--finish-item` without `--ceiling`, both ceiling
forms together, or a `USD` that is not a positive number is a usage error
(exit 2) that names the three forms.

## `vbw loop stop`

Run it from any session of the project, not only the one that started the
loop. It records the time and the session that asked, and the loop stops
before its next step (a run in progress ends first).

- With no loop on, or an ended loop, it prints `no loop is on` and exits 0.
- A second stop, while the loop is still stopping, ends it at once and writes
  the report: the way to end a loop whose own session is gone (only that
  session's Stop hook ends a stopping loop otherwise).

## `vbw loop status`

```
vbw loop status
vbw loop status --json
```

Prints the items in order with their status and text, the ceiling
(`$5 (stop at the next step)`, `$5 (finish the item first)` or `none`), the
session, the start time, the baseline per session, and the spend. It also
shows `stopping since AT (asked by session S)` after a stop, and
`ended AT: REASON (report: PATH)` once the loop has ended. With no loop it
prints `no loop is on`; `--json` returns `{ "on": false }`.

The spend is computed as a milestone's total is (docs/costs.md): for each
session with figures, the current figures minus the loop's baseline, summed. It
comes with one word:

| Word | Meaning |
|---|---|
| `under` | spend is below the ceiling |
| `reached` | spend is at or above the ceiling |
| `cannot tell` | no session has a figure |

`cannot tell` counts as reached, so the loop stops, except with
`--no-ceiling`, where there is nothing to compare and the loop goes on. With a
ceiling, the status then names `vbw statusline on`.

`--json` carries `on`, `items`, `ceiling`, `session`, `started_at`,
`baseline`, `spend` (null when unknown), `word` (null with no ceiling),
`stopping`, `ended` and `report`.

## Approval by delegation

A contract normally waits for your approval (`vbw approve`). Starting a loop
delegates that approval for the items you named, and only for them.

**The rule.** While a loop is on and not stopping, the kernel approves the
contract with no question when all of this holds:

- every requirement of the current milestone has text equal to the recorded
  text of one loop item (spacing normalised);
- each item is matched at most once;
- the milestone holds nothing else, except a `[human]` requirement an earlier
  ship carried over;
- the contract is ready to approve (no missing check file, spec and record in
  line).

A backlog text starting with `[human] ` becomes a `[human]` requirement with
the rest as its text; `[auto] ` likewise; any other text is an `[auto]`
requirement as written.

**What is written.** The same as `vbw approve` (docs/proof.md), plus the
loop's own record:

- consent for the contract's fingerprint, the shape, and the approved-contract
  snapshot;
- consent for the project commands and the test-file form (D315);
- a decision: `Contract approved by the loop on the user's behalf (loop started AT, items ...): ... (FP)`,
  with `AT` the loop's start time, the item ids, and `FP` the contract's
  fingerprint;
- the approval commit, `chore(vbw): approve contract FP`.

When the contract is already approved and only a project command or the
test-file form changed, the loop approves that alone the same way: a decision
`Project commands approved by the loop on the user's behalf (loop started AT,
items ...): name (argv); ...` and its commit `chore(vbw): approve commands`
come first, then the consent; `vbw approve` records the same decision without
the loop's words. A consent is never granted without its decision.

When `vbw next` asks for the approval of changed check files (docs/next.md row
4a) and every listed file is one a mutation check strengthened (it appears in the
`strengthened` list of a red mutation entry of a current-milestone plan, docs/proof.md)
and is still exactly what that entry's commit held, the loop approves them the
same way (consent, shape, snapshot, approval commit) with a decision
`Strengthened check files approved by the loop on the user's behalf (loop started
AT, items ...): FILES`. `vbw next` then moves on to the proof.

A second loop step approves nothing again and records no second decision.

**What still waits for you.** When any condition fails, `vbw next` answers as
docs/next.md rows 3a, 4 and 4a describe: a requirement whose text differs by
one character, an extra requirement, a requirement for an item not on the
loop's list, a loop that is stopping or not on, a contract that is not ready
(row 3a), or a contract needing the approval of changed test files (row 4a) when any of
them was not strengthened by a mutation check, or was edited again after its red
break.

**Who can approve.** Only the kernel's own loop step approves. The guard
denies `vbw loop start`, `vbw loop next` and `vbw loop park` to any tool call,
so neither Claude nor an agent can approve on your behalf.

## The cycle

```
/vbw:loop T4 T7 --ceiling 20
/vbw:loop T4 --ceiling 20 --finish-item
/vbw:loop T4 T7 --no-ceiling
/vbw:loop stop
```

`/vbw:loop` takes the same arguments as `vbw loop start`, runs it with them and
shows one message: the items in order, the ceiling and its form, that approval
is delegated for these items only, what never happens (no push, release or
publish, no work beyond the items, a `[human]` requirement waits for you), and
how to stop. `/vbw:loop stop` runs `vbw loop stop` and says what the loop was
doing. Only you can run `/vbw:loop`; Claude cannot start it.

After that message the **Stop hook** drives the session. Each time Claude would
stop, the hook (`vbw auto gate`) blocks the stop and hands it the next loop
step, until the loop is done or stopped. Only the session that started the loop
is driven; any other session ignores it. The loop's steps are not counted
against `autonomy_cap` (the steps of an ordinary autonomous run); the loop's
own ceiling is its cap. While this session's proof runs in the background the
hook asks for nothing.

The hook is the plugin's own (`hooks/stop.sh` in `hooks/hooks.json`), not part
of `/vbw:loop` or `/vbw:vibe`, so it runs once per stop and still drives the
loop after you resume the session. It starts the kernel only for a session with
a loop on (`vbw loop start` leaves a mark in `.vbw/runtime/`, the loop's end
removes it) or an armed autonomous run; in every other session it does nothing.
A session resumed from before this change gets its mark back when you run
`/vbw:loop` again: it says the loop is already on and drives it from there.

### `vbw loop next`

Each step is one kernel call, `vbw loop next --json`. Only the loop's hook calls
it; the guard denies it to any tool call. It does every step that needs no
agent, then returns the first one that does.

For the next waiting item it:

1. opens a milestone titled with the item (`vbw milestone start`), or renames
   the current milestone when it has no requirements yet;
2. adds the item's recorded text as that milestone's one requirement (`[auto]`,
   or `[human]` when the backlog text starts with `[human] `) and marks the
   item in progress;
3. approves the contract by delegation when `vbw next` says `approve`
   (see below). It never calls `vbw approve` and never asks the approval menu;
4. runs `vbw ship` when `vbw next` says `ship`. `vbw ship` also ships with
   skipped `[human]` requirements: they move on to the next milestone (D256);
5. marks the shipped item's backlog entry done, then starts the next item.

When the list is finished it answers `done` and records the loop as ended.

A step that needs an agent or a proof comes back as `vbw next` would give it,
with the same `detail`, `rigor`, `effort` and `profile` fields: `plan`,
`build`, `fix`, `qa` (run the workflow) and `prove` (run `vbw prove`). A run the
loop opens carries the usual lease and ends through `vbw run end`.

Two cases the loop settles itself:

- **A decision.** When planning returns `needs_decisions`, the loop takes the
  recommended option for each and records the decision as chosen by the loop.
  The `guided` autonomy setting never makes the loop ask.
- **A `[human]` requirement** at the accept step. The loop runs `vbw req skip`
  for it. It never accepts or rejects for you, and accepts no suggestion for
  you. The requirement waits in the next milestone, and the report lists it.

An escalated fix is retried once, then the item is parked: see
"Retry once, then park" below.

## Retry once, then park

When the loop cannot get an item through, it tries once more, then gives the
item up and moves on. It never stops the whole loop for one bad item.

**The retry.** The first time an item escalates (`vbw next` answers
`escalate`), the loop runs `vbw fix retry` for each escalated fix, and the fix
is open again for one more attempt. A plan the Dev blocked is reset once with
`vbw plan reset`. Each retry is recorded on the item (`retried`, docs/record.md),
so the loop retries an item once, never twice.

**The park.** The loop parks the item (`vbw loop park`) when:

- a fix escalates again after its retry;
- a plan is blocked again after its reset;
- a scope violation shows up (a commit touched a file outside its plan).

`vbw loop park` does these steps, in order:

1. Reverts the item's commits made since its milestone began, newest first,
   each with `git revert`. History is kept: nothing is rewritten, and each
   revert is a new commit.
2. Leaves alone any file you staged or edited by hand, and any file git does
   not track. Three kinds of commit are left in place and named in the park's
   decision and the report (D326): one touching a file you staged or edited,
   one that changes code and a `.vbw/` file together (reverting it would
   rewrite the record), and one that does not revert cleanly.
3. Removes the item's requirement, phases, plans, checks, rules and fixes from
   the record, and its line from `.vbw/spec.md`. The project then proves as it
   did before the item started.
4. Marks the milestone `parked`, with the reason and the time, and freezes its
   cost the way a ship does (docs/costs.md). The milestone goes in the
   record's `parked` list (docs/record.md).
5. Records a decision: the item, the reason, the revert commits and how to
   bring the work back.
6. Leaves the item's backlog entry open, and sets the item to `parked` in the
   loop with its reverts, the commits it left in place and why, its reason and
   its cost.
7. Commits the record. The loop then starts the next item.

Run by hand with no item in progress, `vbw loop park` refuses, changes nothing
and ends with `Next: `. Only the loop's own step runs it; the guard denies it
to any tool call (docs/guards.md).

**Bringing the work back.** The report and the decision both list the revert
commits. Either:

- revert the reverts (`git revert REVERT_COMMIT`, newest first) to get the
  code back, or
- run the item again: its backlog entry is still open, so
  `/vbw:loop THE_ITEM --ceiling USD` starts it over from a clean milestone.

## Where the loop stops

Before each step the loop compares its spend with the ceiling (the spend and
its words are under `vbw loop status` above).

| Case | What happens |
|---|---|
| `--ceiling USD`, spend `reached` | Stops before the next step. |
| `--ceiling USD`, spend `cannot tell` | Counts as reached: stops before the step. |
| `--ceiling USD --finish-item`, `reached` | The current item runs on to its ship, then the loop stops. |
| `--no-ceiling` | No comparison, even with no cost figure. |
| End of the list | Stops after the last item's ship. |
| `/vbw:loop stop` or `vbw loop stop`, from any session | Stops before the next step. The reason names you and the session. |
| A run open in another session | Stops, with that reason. |
| A contract not ready yet (`vbw next` says `contract`: a check file not written, the spec not synced, a rule missing) | The session's unfinished plan step: handed back to the session once, recorded as `asked` in the loop state. The same unsatisfied instruction for the same item a second time stops the loop, with `asked once already` in the reason (D334). |
| An action the loop cannot do | Stops with the reason, the item and the step, recorded in the loop state. |

A workflow or proof already running is never killed: the loop stops once its
result is recorded. The stop reason is in `vbw loop status` and in the report.

## The report

`.vbw/loop-report.md` is written when the loop ends and refreshed each time an
item ends, so a machine that died overnight still leaves one. An item still
running shows as in progress. The sections:

| Section | Holds |
|---|---|
| Shipped | Each item, its milestone, its requirement and its commits. |
| Parked | Each parked item, the reason, the commits left in place and why, its revert commits and how to bring the work back. |
| Waiting for you | Every `[human]` requirement still owed to you: one the loop skipped, one of a shipped `[human]` item, and one carried into the loop's milestones from a ship before it, each listed until you judge it, wherever a later milestone carried it; and why the loop stopped (for example `end of the list` or `stopped by the user` with the session). |
| Cost | The loop's total and each item's cost, in dollars and tokens (parked items included). |

A cost VBW did not see is written `unknown`, never `0` and never an estimate.
The record stores the same facts. After the end, `vbw loop status` says the loop
ended, why, and names the report.

## The promise

Two sentences hold for every loop.

**Nothing is approved without a record of who approved it.** Either you
approved through `/vbw:approve`, or the loop approved by the delegation you
gave when you started it. A delegated approval writes the decision (`Contract
approved by the loop on the user's behalf ...`) and the consent entry for the
contract's fingerprint (see "Approval by delegation"). Claude and agents cannot
approve: the guard denies it.

**Nothing the loop does leaves the project: the loop never leaves the project.** While a loop is on, no push,
release, publish or deploy runs, from the loop's workflows or from anyone in
the session: the guard denies them (docs/guards.md, "While a loop is on").
Every ship is local, a commit for you to review; you push when you choose. The
guards that hold for any run (protected checks, the record, secrets, the
run's files) hold unchanged for the loop's runs.

To push or release, stop the loop with `/vbw:loop stop`, then do it yourself.
