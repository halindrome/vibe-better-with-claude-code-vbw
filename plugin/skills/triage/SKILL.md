---
name: triage
description: Sort every new idea the user brings as now, next or later, with a reason and a size, before any requirement, planning or file change. Used by the vibe router for each new request.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" *) Bash(vbw *) Read
effort: low
---

# Triage

```!
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" triage 2>&1 || true
"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview 2>&1 || true
```

Above: the active milestone, its requirements, the open backlog and the user's answers. Write to the user's level, explanation depth and involvement ("-": plain words).

Router calls this for each new idea, before any requirement, planning or file change. At every autonomy setting (guided, balanced, hands-off) the idea is sorted and the user confirms or overrules it.

## When it applies

New idea: a feature, change, fix or wish not yet in the spec. Not a new idea, so no triage: an answer to a question VBW asked, "continue" or "go on", an approval, a question about the project, an autonomy setting stated in words (guided, balanced, hands-off, or a phrase that means one): the router records it; the rest of the same message goes to triage as usual.

Idea already matches a requirement or open backlog item: name it, no new entry. For a backlog item, offer to move it to now (`vbw spec add`, then `vbw todo done`).

A fix (a bug, a ticket, "X is broken"): before sorting, check that it still happens in the current code. Read the code path it names and its tests, and look for an earlier fix (`git log --grep "<ticket or key words>"`). Evidence that it is fixed (a commit, a `file:line` that already handles it, a test that covers it): the menu says so with that evidence, and its options are **already fixed** (Recommended) and **it still happens**. Already fixed: `vbw decide "<idea>: already fixed by <evidence>" "<the user's reason, or: the user agreed>"`, no requirement, no backlog item. It still happens: ask how (the user's words become the idea), then sort it as usual. Anything else found on the way (an obsolete workaround, cleanup) is a separate idea, sorted on its own, never folded into the fix.

## The sorting menu

One line per idea, one line each, all inside one AskUserQuestion; the line is inside it, so the user decides from what the menu shows. Per idea, the question text holds the idea and its line: the sort, the reason in one sentence, the size (small, medium or large). Each option's description repeats its sort's effect. Print no line before the menu.

- **now**: joins the active milestone.
- **next**, **later**: go into the backlog; next is the following milestone, later is someday.

VBW's sort is the first option, marked (Recommended); the two other sorts are the other options. Never ask the user to type a command. Up to four ideas per menu; more than four are sorted four at a time. During a run, sort without interrupting it; a "now" idea waits for the run to end.

## Outcomes

- **now**: `vbw spec add auto|human "<idea>"` for every now idea of the menu; then follow `vbw:suggest` once, before the first planning run (a yes costs nothing yet); then the normal flow (planning again, the approval menu). A now idea sorted during a run waits for the run to end; the suggestions come then, still before planning. No active milestone: `vbw milestone start "<title>"` with the idea as its first requirement.
- **next** or **later**: `vbw todo add --sort <sort> --size <size> "<idea>"`.

## Overrule

The user picked a sort other than VBW's: exactly one follow-up question (AskUserQuestion) that says plainly what the choice displaces and its risk.

- **now** displaces planned work: it grows the milestone, sends the plan back for a new approval and delays planned work.
- **later** instead of **now** displaces nothing, but a problem VBW judged urgent stays unfixed.

Options: one or two ready reasons, the user's own words, keep VBW's sort.

A reason chosen: follow the user's sort, then `vbw decide "Triage overrule: <idea>: VBW sorted <VBW's sort>, the user chose <user's sort>" "<the user's reason>"`. Keep VBW's sort: apply VBW's sort, record no overrule.

Say the warning once per idea. Never repeat or argue it; never ask again.
