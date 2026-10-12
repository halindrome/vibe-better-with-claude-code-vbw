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
| A loop is already on and not ended | `vbw loop stop` first. |
| The current milestone has requirements and is not shipped | Finish or ship it first: each item gets its own milestone. |
| `--ceiling` and no session has a cost figure | `vbw statusline on`, or use `--no-ceiling`. |

A missing ceiling choice, `--finish-item` without `--ceiling`, both ceiling
forms together, or a `USD` that is not a positive number is a usage error
(exit 2) that names the three forms.

## `vbw loop stop`

Run it from any session of the project, not only the one that started the
loop. It records the time and the session that asked, and the loop stops
before its next step (a run in progress ends first).

- With no loop on, or an ended loop, it prints `no loop is on` and exits 0.
- A second stop changes nothing.

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

A second loop step approves nothing again and records no second decision.

**What still waits for you.** When any condition fails, `vbw next` answers as
docs/next.md rows 3a, 4 and 4a describe: a requirement whose text differs by
one character, an extra requirement, a requirement for an item not on the
loop's list, a loop that is stopping or not on, a contract that is not ready
(row 3a), or a contract needing the approval of changed test files (row 4a).

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

An escalated fix is retried once (`vbw fix retry`). A second escalation of the
same item, a plan blocked again, or a scope violation parks the item
(`vbw loop park`): its commits since its milestone began are reverted with new
revert commits (history is kept), its work leaves the record and the spec, the
backlog entry stays open, and the loop moves to the next item.

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
| Parked | Each parked item, the reason, its revert commits and how to bring the work back. |
| Waiting for you | Skipped `[human]` requirements, and why the loop stopped (for example `end of the list` or `stopped by the user` with the session). |
| Cost | The loop's total and each item's cost, in dollars and tokens (parked items included). |

A cost VBW did not see is written `unknown`, never `0` and never an estimate.
The record stores the same facts. After the end, `vbw loop status` says the loop
ended, why, and names the report.
