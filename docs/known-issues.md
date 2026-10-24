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
| [The loop's time budget counts waiting](#the-loops-time-budget-counts-waiting) | Known issue | Loops | Re-run the item |
| [A unit that lost the slot store may leave a slot held](#a-unit-that-lost-the-slot-store-may-leave-a-slot-held) | Known issue | Many runs at once | None needed |
| [Real-user scenarios for four features](#real-user-scenarios-for-four-features) | Planned | Test coverage | Not applicable |
| [Cost per correct outcome](#cost-per-correct-outcome) | Idea | Everyone | Not applicable |

## Known issues

### The loop's time budget counts waiting

**What.** The loop gives each item a time budget ([loop.md](loop.md#the-time-budget)). Before the item is planned it is the label's guess or twice the median of shipped items of the same size; once the item is planned and the step history times its road, it is twice the time so far plus that road, at least 30 minutes. The time is wall-clock: time lost to dropped network connections or to waiting for you counts as time, so it can still stop a healthy item.

**Who and when.** Anyone running `/vbw:loop` over a backlog while the machine or the connection is unreliable.

**Workaround.** The stop keeps all the work and parks nothing. Run `/vbw:loop THE_ITEM` again, or finish the item with `/vbw:vibe`.

**Plan.** The stuck test counts progress (plans done, fixes closed) instead of elapsed time, so waiting is not grinding.

**Where.** `plugin/lib/loop-step.sh` (`loop_item_budget`, `loop_item_rebudget`).

### A unit that lost the slot store may leave a slot held

**What.** The computer-wide limit is kept in a small shared store (`slots.json` in the Claude config folder, [proof.md](proof.md#the-computer-wide-limit)). When a unit that was waiting for a slot loses the store (it fails or is damaged), the unit goes on without the limit, but its waiting entry stays in the store. If the store works again before that run ends, another run's step can hand that entry a slot nobody uses, and the slot stays held until the run exits.

**Who and when.** Rare: a store that fails and recovers within one proof, with other runs waiting. The effect is one slot fewer for other runs until the proof ends, never a wrong result.

**Workaround.** None needed. The slot comes back when the run ends.

**Plan.** Drop the entry of a unit that lost the store as soon as the store can be written again.

**Where.** `plugin/lib/slots.sh` (`slots_hold`, `slots_lose`).

## Planned improvements

### Real-user scenarios for four features

**What.** Four features have unit and contract tests but no real-user scenario, one that drives the real Claude Code interface the way a person does:

1. Session names and the Sessions tab: the holder named in the status line, Comms and `vbw next`, and the resume line.
2. A task break judged by the plan's own rules, on an early plan whose requirement a later plan completes.
3. A fix committing its own requirement's check files, with one approval.
4. Failing output kept and named by `vbw show fix`.

**Who and when.** Until these exist, treat the four as less proven than features that have one.

**Plan.** One scenario per feature, each checking the outcome in the record and in git, not on screen.

**Where.** `tools/l3-suite.sh` (add a `scenario_NAME` function and the name to the list); `tools/l3.sh` is the driver. Scenarios use model usage, so this needs Claude Code access.

## Under consideration

### Cost per correct outcome

**What.** VBW's benchmark so far compares cost per run on small practice cases ([benchmark.md](benchmark.md)), where VBW's up-front planning and proof cost more than a quick prompt. Cost per run is not the question a user has. Ten cheap turns that ship broken code waste more than five dearer turns that ship proven code. The idea is to measure and show VBW's cost per proven result, with the cost of rework counted on the plain side too.

**Who and when.** Everyone choosing whether VBW is worth its cost.

**Open questions.** What counts as a correct outcome on the plain side (the same checks decide)? How is rework counted? The current cases are small and have one requirement each, so they cannot answer this; it needs multi-requirement projects ([Not measured](benchmark.md#not-measured)).

**Where.** `vbw show costs` (`plugin/lib/cmd-show.sh`, `plugin/lib/costs.sh`); `tools/baseline/`.
