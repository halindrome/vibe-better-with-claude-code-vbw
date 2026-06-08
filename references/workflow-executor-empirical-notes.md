# Workflow Executor — Empirical Notes (2026-06-05)

Findings from a **live** end-to-end run of the workflow-map idea on a real 4,614-file
monorepo (Corvex Connected Worker), using Claude Code **Opus 4.8** with the Dynamic
Workflows tool available. These map directly onto the open questions and
confirm-during-testing items in `workflow-executor.md`. Companion design lives in the
sibling stack repo `cmm-claude-code-setup/docs/TODO-workflow-team-replacement.md`.

> Caveat on generalization: this was one runtime (Opus 4.8, workflows enabled). The
> detection/opt-in scaffolding in this branch is still needed — these notes resolve
> *capability and shape* questions, not *availability* across plans/versions.

---

## TL;DR — the biggest input

`workflow-executor.md` assumes the only orchestrator-reachable trigger is the
**per-request `ultracode` keyword** (and flags, as an open question, whether even that can
be emitted programmatically). In this runtime there is a **first-class `Workflow` tool the
orchestrator can call directly** with an inline JS script. It is a strictly better fit for
VBW's stated goals ("deterministic, single-step, opt-in dispatch") than the `ultracode`
keyword, and it resolves both halves of the open question. Recommend treating the
`Workflow` tool as the primary invocation surface when present, with the `ultracode`
keyword (and team fallback) as alternates.

---

## Section-by-section notes (keyed to `workflow-executor.md`)

### "Invoking a workflow" (lines 82–96) + Open questions (155–162) — **RESOLVED**

- **A direct `Workflow` tool exists.** Signature observed:
  `Workflow({ script | scriptPath | name, args })` → returns immediately with a `runId`,
  runs in the background, and fires a task-notification on completion. The script body uses
  `agent(prompt, opts)`, `parallel(thunks)`, `pipeline(items, ...stages)`, `phase(title)`,
  `log(msg)`, and `return`s a structured object. This is deterministic and
  orchestrator-initiated — no reliance on Claude choosing to author a workflow from a typed
  keyword.
- **How a workflow script targets a specific `vbw-*` agent** (the second open question):
  `agent(prompt, { agentType: 'vbw:vbw-scout' })`. `agentType` resolves from the **same
  registry as the Agent tool**, so it spawns the exact plugin-namespaced agent
  (`vbw:vbw-scout`) — confirmed by the CMM call-counter and per-agent transcripts. Also
  supports `{ schema }` (forces StructuredOutput → validated object return), `{ label }`,
  `{ phase }`, `{ model }`, `{ isolation: 'worktree' }`.
- **`/effort ultracode` concern (lines 91–96) still valid and now moot for this path.** The
  direct `Workflow` tool avoids the "auto-spawn for every task" collision entirely — it is
  explicitly invoked per step. Keep the warning against `/effort ultracode`; the direct tool
  is the clean per-step trigger you wanted.
- **Opt-in alignment.** The `Workflow` tool itself **refuses unless the user has explicitly
  opted into multi-agent orchestration** for the turn. That dovetails with this branch's
  `map.md` gate (`prefer_workflows≠never` + a supported runtime). So "explicit opt-in" is enforced at
  *two* layers (VBW config + the tool), which is good.
- **Availability still needs detection.** Whether the orchestrator running a `/vbw:map`
  command can call the `Workflow` tool depends on the runtime exposing it — so
  `detect-workflows-support.sh` remains necessary; just have it also gate the
  direct-tool path, and keep graceful fallback to team/`ultracode` as the safety net.

### "Subagents are the worker primitive" (129–133) — **CONFIRMED**

Custom/named subagents work as workers via `agentType`. The four map domains ran as four
real `vbw:vbw-scout` agents. No need to limit this to the read-only map path on
*worker-targeting* grounds — that surface is confirmed. (Limiting to map for *now* on
caution grounds is still reasonable.)

### "Result-bridging rule (mandatory)" (98–110) — **WORKS, but may be stricter than needed for the map path**

- The rule (workflow must never write `.vbw-planning/`; orchestrator bridges) is sound for
  **gated** artifacts (plans, `SUMMARY.md`, `VERIFICATION.md`) — keep it there.
- **For the read-only map specifically**, the run showed the cleaner option also works: the
  workflow's `vbw:vbw-scout` workers wrote the seven `codebase/*.md` docs **directly** via
  `<output_paths>` — exactly as the existing team `Step 3-quad` does — and returned only
  `cross_cutting` summaries. The writes succeeded (these are the *same* agents the team path
  already trusts to write codebase docs; `.vbw-planning/codebase/` is not gated like
  plans/summaries).
- **Trade-off worth deciding explicitly:** the branch's `Step 3-quad-workflow` chooses
  orchestrator-bridging, which means the workflow must **return all seven docs' full content**
  for the orchestrator to write — a much heavier return payload than the team path (which
  writes directly and returns only cross-cutting findings). Letting the workflow workers
  write the codebase docs directly (and bridging *only* for gated artifacts) keeps the map
  path's payload as light as the team path and avoids re-serializing ~900 lines of docs
  through session context.
- Net: consider a **carve-out** — "result-bridging is mandatory for gated artifacts;
  read-only map codebase docs MAY be written directly by workflow workers via
  `<output_paths>`, identical to the team path." This preserves the guard rationale where it
  matters and removes a real efficiency regression where it doesn't.

### Project-policy enforcement on workflow workers — **NOT in the doc; should be (it's reassuring)**

All four workflow-spawned agents were governed by the project's `.claude/settings.json`
exactly like `Task`-spawned subagents: `SubagentStart [matcher:*]` hooks injected context,
and `PreToolUse` gates fired/blocked inside them. **Workflow workers are first-class
subagents subject to the same hook/enforcement surface as team/Task subagents.** Worth one
line in the doc — it means per-repo policy overlays (lint gates, CMM/ctx nudges, file
guards) keep working under the workflow executor with no special handling.

### "Run artifacts" (134–137) — minor enrichment

Beyond the script under the session dir, each run also writes **per-agent transcripts and a
run journal** under `<session>/subagents/workflows/<runId>/` (`agent-*.jsonl`,
`journal.jsonl`). Cleanly isolated from the main-session transcript — useful for
`/vbw:doctor`-style inspection and for verifying which executor actually ran. Still none of
it under `.vbw-planning/`, so the result-bridging rationale stands.

### Resume (86–88) — consistent, with a mechanism note

The tool exposes `Workflow({ scriptPath, resumeFromRunId })` for **within-session** resume
(cached completed agents return instantly). Matches the doc: cross-session resume is *not*
available, so VBW must still treat an unfinished workflow step as not-done and re-dispatch
on a new session. No change needed; just note the `resumeFromRunId` affordance exists.

---

## Concrete cost anchor (for `auto`/threshold tuning in `resolve-executor.sh`)

One real data point for the fan-out threshold decision:

| Metric | Value |
|---|---|
| Repo size | 4,614 source files (monorepo, 6 submodules) |
| Executor | 4× `vbw:vbw-scout` via `parallel()` |
| Wall-clock | ~194 s |
| Tool uses (all agents) | 72 |
| Subagent tokens | ~300k (agents inherited Opus) |
| Output | all 7 codebase docs written |

Implications for tuning: ~300k tokens for a 4-wide Opus scan is real spend — consider
defaulting workflow-map workers to **Sonnet** for routine maps (the CMM-vs-raw navigation
behavior is largely model-independent), reserving Opus for deep scans. The `auto` threshold
(currently fan-out ≥ N) is the right lever; this run suggests quad-tier repos comfortably
clear any sane threshold.

---

## Recommendations (suggested, not applied)

1. **Add the `Workflow` tool as the primary invocation surface** in `workflow-executor.md`
   "Invoking a workflow," with the `ultracode` keyword as an alternate and team as fallback.
   Move the two "open questions" to "resolved" (worker-targeting via `agentType`;
   programmatic dispatch via the tool).
2. **Carve out the map codebase docs** from the result-bridging rule (workers may write them
   directly via `<output_paths>`), keeping bridging mandatory for gated artifacts — removes
   the payload regression noted above.
3. **Add one line** that workflow workers are normal subagents under project hooks/guards
   (enforcement parity), and that `detect-workflows-support.sh` should also gate the
   direct-tool path.
4. **Record the cost anchor** near the threshold logic; consider a worker-model knob
   (Sonnet default for map).
5. Keep everything else as-is — the predicate/owner split, fail-closed detection,
   `delegation_mode=workflow` marker, and the `prefer_workflows` two-half opt-in (runtime support + `≠never`) are all
   correct and align with what the run demonstrated.
