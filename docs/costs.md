# Costs

VBW records what each run and each milestone cost, in dollars and tokens, from
the figures Claude Code gives the status line.

```
vbw show costs
vbw show costs --json
vbw show costs --ceiling 20
```

## What is measured

- **A run:** what its session spent between `vbw run start` and `vbw run end`
  (the end figures minus the start figures).
- **A milestone:** everything spent in the project's sessions while the
  milestone was open. The runs' costs are the share of it that went through
  VBW's runs; the rest (your own conversation) counts in the milestone too.
  `vbw milestone start` notes where each session stood, and `vbw ship` freezes
  the total.

The data lives in the record (`costs`, docs/record.md). The figures come from
the status line's side file (docs/statusline.md), so the status line must be on.

## `vbw show costs`

Prints each milestone's total (dollars, tokens, sessions) and each run's share.

`--json` returns one object:

| Field | Meaning |
|---|---|
| `milestones[]` | `id`, `status` (`active` or `shipped`), `usd`, `in`, `out`, `sessions`; `usd` is null when no figure was seen |
| `runs[]` | `id`, `kind`, `milestone`, `cost` (`{ usd, in, out }` or null) |
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

## Unknown costs

`unknown` means VBW did not see the figures: the status line was off, or the
run had no session. VBW never shows 0 or an estimate in that case. Turn the
status line on and later runs are measured:

```
vbw statusline on
```
