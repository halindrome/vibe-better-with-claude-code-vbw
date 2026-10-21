# Costs

VBW records what each run and each milestone cost, in dollars, from the figures
Claude Code gives the status line.

```
vbw show costs
vbw show costs --json
vbw show costs --ceiling 20
```

## What is measured

- **A run:** what its session spent between `vbw run start` and `vbw run end`
  (the end figures minus the start figures). Every `vbw run end` adds the run
  to the record and commits it, cost known or not.
- **A milestone:** everything spent in the project's sessions while the
  milestone was open. The runs' costs are the share of it that went through
  VBW's runs; the rest (your own conversation) counts in the milestone too.
  `vbw milestone start` notes where each session stood, and `vbw ship` freezes
  the total.

The data lives in the record (`costs`, docs/record.md). The figures come from
the status line's side file (docs/statusline.md), so the status line must be on.

Only dollars are measured. Claude Code gives the status line the session's
running cost, but no running token total: its token fields describe the last
request (the size of the context now, the last response's output), so they fall
when the context is compacted and are no spend. VBW does not store or show
them. Records written by a VBW that did store tokens stay valid, and are read by
their dollars.

## `vbw show costs`

Prints each milestone's total (dollars, sessions) and each run's share.

`--json` returns one object:

| Field | Meaning |
|---|---|
| `milestones[]` | `id`, `title`, `status` (`active` or `shipped`), `usd`, `sessions`; `usd` is null when no figure was seen, and stays null for a milestone shipped without figures |
| `runs[]` | `id` (the run's kind and start second, `qa-20260101T120000Z`; a second run started in that same second gets `-2`, a third `-3`, so no two runs share an id), `kind`, `milestone`, `session`, `started`, `ended`, `cost` (`{ usd }` or null) |
| `unknown` | `{ runs, milestones }`: the ids whose cost VBW did not see |
| `remedy` | what to do about unknown costs |

## `vbw show costs --ceiling USD`

Compares the active milestone's known spend with a ceiling. `USD` must be a
positive number; anything else is a usage error (exit 2).

| First word | Meaning | Exit |
|---|---|---|
| `under` | spend is below the ceiling | 0 |
| `reached` | spend is at or above the ceiling | 1 |
| `cannot tell` | no figure was seen, so there is nothing to compare | 1 |

`cannot tell` exits 1 on purpose: a check that cannot see the spend does not
pass.

## The loop's spend

`vbw loop status` shows what a running loop has spent (docs/loop.md). It uses
the same arithmetic as a milestone's total: each session's current figures
minus the figures at the loop's start, summed. It is unknown when no session
has a figure, and VBW then shows `cannot tell`, never 0.

## Unknown costs

`unknown` means VBW did not see the figures: the status line was off, the
run had no session, or the dollar figure went down during the run (a session
restarted or its file was replaced), so VBW cannot tell what was spent. VBW never shows 0 or an estimate in that case. Turn the
status line on and later runs are measured:

```
vbw statusline on
```
