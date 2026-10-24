# Known issues and roadmap

What is known to be wrong or unfinished in VBW 2 today, what is planned, and what is still only an idea. Larger open ideas that need design work are in [ideas.md](ideas.md).

Nothing here is a promise. An item is evidence of a problem; the fix named under it is the current plan and may change when someone works on it. Every item is judged against VBW's design for all its users, like any other request (see the first rule in [CONTRIBUTING.md](../CONTRIBUTING.md)).

## How to use this page

- **You hit one of these.** The workaround, if there is one, is under the item.
- **You found something that is not listed.** Open an issue with the [bug report template](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues/new?template=bug_report.md). Run `/vbw:doctor` first and paste its output.
- **You want to fix or build one.** Open a GitHub issue for it (or comment on the existing one) in [swt-labs/vibe-better-with-claude-code-vbw](https://github.com/swt-labs/vibe-better-with-claude-code-vbw/issues) before you start, so two people do not build the same thing. Then follow "Picking up an item" in [CONTRIBUTING.md](../CONTRIBUTING.md#picking-up-an-item-from-the-roadmap).
- **You disagree with a plan.** Say so in an issue, with the problem you see. A different solution to the same problem is welcome.

Status words:

- **Known issue:** VBW behaves worse than its documentation says.
- **Planned:** we intend to do it. No user-visible failure is behind it.
- **Idea:** we are weighing it. It may be adopted, reshaped or declined.

## At a glance

| Item | Status | Affects | Workaround |
|---|---|---|---|
| [The loop's time budget counts an interrupted turn or a sleeping computer](#the-loops-time-budget-counts-an-interrupted-turn-or-a-sleeping-computer) | Known issue | Loops | Stop the loop before you leave |
| [A unit that lost the slot store may leave a slot held](#a-unit-that-lost-the-slot-store-may-leave-a-slot-held) | Known issue | Many runs at once | None needed |
| [Cost per correct outcome](#cost-per-correct-outcome) | Idea | Everyone | Not applicable |

## Known issues

### The loop's time budget counts an interrupted turn or a sleeping computer

**What.** The loop gives each item a time budget ([loop.md](loop.md#the-time-budget)), and the item's time counts only while the loop works on it: a stopped loop, a session that was gone and a turn that ended on an API error are left out. Two pauses are not seen, because Claude Code reports neither: a turn you interrupted (Esc), and a computer asleep while a step runs. That time counts, so it can still stop a healthy item.

**Who and when.** Anyone who interrupts a loop's turn and walks away, or lets the computer sleep during a loop.

**Workaround.** Before you leave, stop the loop with `/vbw:loop stop`; `/vbw:loop THE_ITEM` resumes the item later without the time stopped. A stop by the budget keeps all the work: finish the item with `/vbw:vibe`.

**Plan.** Leave these pauses out too once Claude Code reports an interrupted turn or a resume from sleep to hooks.

**Where.** `plugin/lib/loop-step.sh` (`loop_item_seen`), `plugin/hooks/stop.sh`, `plugin/hooks/session-start.sh`.

### A unit that lost the slot store may leave a slot held

**What.** The computer-wide limit is kept in a small shared store (`slots.json` in the Claude config folder, [proof.md](proof.md#the-computer-wide-limit)). When a unit that was waiting for a slot loses the store (it fails or is damaged), the unit goes on without the limit, but its waiting entry stays in the store. If the store works again before that run ends, another run's step can hand that entry a slot nobody uses, and the slot stays held until the run exits.

**Who and when.** Rare: a store that fails and recovers within one proof, with other runs waiting. The effect is one slot fewer for other runs until the proof ends, never a wrong result.

**Workaround.** None needed. The slot comes back when the run ends.

**Plan.** Drop the entry of a unit that lost the store as soon as the store can be written again.

**Where.** `plugin/lib/slots.sh` (`slots_hold`, `slots_lose`).

## Under consideration

### Cost per correct outcome

**What.** VBW's benchmark so far compares cost per run on small practice cases ([benchmark.md](benchmark.md)), where VBW's up-front planning and proof cost more than a quick prompt. Cost per run is not the question a user has. Ten cheap turns that ship broken code waste more than five dearer turns that ship proven code. The idea is to measure and show VBW's cost per proven result, with the cost of rework counted on the plain side too.

**Who and when.** Everyone choosing whether VBW is worth its cost.

**Open questions.** What counts as a correct outcome on the plain side (the same checks decide)? How is rework counted? The current cases are small and have one requirement each, so they cannot answer this; it needs multi-requirement projects ([Not measured](benchmark.md#not-measured)).

**Where.** `vbw show costs` (`plugin/lib/cmd-show.sh`, `plugin/lib/costs.sh`); `tools/baseline/`.
