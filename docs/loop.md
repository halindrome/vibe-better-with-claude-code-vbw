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
