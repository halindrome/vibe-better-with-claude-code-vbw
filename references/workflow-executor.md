# Workflow Executor Backend

VBW can optionally offload **wide, parallel, bounded** steps to a [Claude Dynamic
Workflow](https://code.claude.com/docs/en/workflows) instead of running its own
Agent-Team/subagent fan-out. This is an **optional capability**, gated by the
`workflows` config setting and detected at runtime — exactly like LSP, MCP, and
`prefer_teams`. When the runtime does not support workflows, or the user opts
out, VBW behaves **identically to today**.

A Claude Dynamic Workflow is a JavaScript script the Claude Code runtime writes
and executes in the background, orchestrating many subagents at scale; the script
holds the loop, branching, and intermediate results, and only the final answer
returns to the session. "The script holds the plan."

## Division of responsibility (composition, not replacement)

VBW remains the **lifecycle owner**. A workflow is only ever an *executor for one
step* — never the owner of phases, plans, gates, verification, or cross-session
resume.

| Concern | Owner |
| :--- | :--- |
| Phase/plan state, routing, gates, QA→remediation, resume | VBW (`phase-detect.sh`, `control-plane.sh`, disk artifacts) |
| Deciding a step is wide enough to offload | VBW (`resolve-executor.sh`) |
| Running the fan-out for that one step | Workflow runtime (when selected) |
| Persisting the step's result into durable state | VBW (result-bridging, below) |

This composition is deliberate: VBW's value is durable, inspectable, verifiable,
cross-session-resumable state as the source of truth, while workflows are
ephemeral (resumable only within a session) and keep their intermediate results
out of context. Folding the VBW lifecycle into a single workflow would forfeit
all of that, so we do not.

## When a step qualifies

A step is workflow-eligible when it is:

- **Wide** — fans out across many independent units (files, modules, endpoints,
  targets) beyond the configured threshold.
- **Parallel** — the units have no ordering dependency on each other.
- **Bounded** — the unit set is enumerable up front and each unit's work is
  self-contained.

Good fits: large codebase audits/scans, multi-target verification, mechanical
migrations applied across many files. Poor fits: ordered plan execution, anything
requiring VBW gates/QA between units, or single-unit work.

## Decision pipeline

1. **Config** — `scripts/normalize-workflows-mode.sh` canonicalizes the
   `workflows` setting to `always | auto | never`.
2. **Detection** — `scripts/detect-workflows-support.sh` reports whether the
   runtime supports workflows (honors `CLAUDE_CODE_DISABLE_WORKFLOWS` and
   `disableWorkflows` in merged settings). Fails **closed** (unsupported) when it
   cannot confirm support.
3. **Resolution** — `scripts/resolve-executor.sh --fanout <N> [--threshold <N>]`
   returns `workflow` or `fallback`:
   - `never` → `fallback`
   - runtime unsupported → `fallback`
   - fanout below minimum / non-integer → `fallback`
   - `always` and wide enough → `workflow`
   - `auto` and fanout ≥ threshold → `workflow`, otherwise `fallback`
4. **Dispatch** — on `workflow`, the orchestrator runs the step as a workflow and
   records `delegation_mode=workflow` in `.delegated-workflow.json`. On
   `fallback`, the orchestrator runs its **existing** team/subagent/direct
   resolution (e.g. `resolve-execute-delegation-mode.sh`) unchanged.

`resolve-executor.sh` is an orthogonal predicate — it answers only "workflow or
not." It never re-implements team/subagent/direct selection.

## Invoking a workflow

The orchestrator triggers a workflow for the qualifying step using the Claude
Code workflow entry point (the `ultracode` keyword in the dispatched request, or
a saved/bundled workflow command). Workflows run in the background; `/workflows`
lists running and completed runs. Resume is within-session only — if the session
exits mid-run, the next session starts the step fresh, so VBW must treat an
unfinished workflow step as not-yet-done and re-dispatch on resume.

## Result-bridging rule (mandatory)

A workflow's output is the **final answer in the session context**, not a durable
artifact. The orchestrator MUST bridge that result into the VBW artifact the step
stands for — for example codebase map docs, a plan `SUMMARY.md`, or a
`VERIFICATION.md`.

- The orchestrator is the **sole writer** of VBW lifecycle artifacts.
- A workflow **must never write `.vbw-planning/` directly**. Doing so would bypass
  `file-guard.sh`, the contracts, and the gate system.
- `delegation_mode=workflow` is a recognized marker value. Per `file-guard.sh` and
  `agent-spawn-guard.sh` (which special-case only `team`), it is treated as a
  non-team mode and receives **no** team-style write bypass.

## Backward compatibility (top invariant)

With `workflows=auto` (default) the behavior is identical to today's VBW wherever
the runtime lacks workflows or the step is not wide enough. `workflows=never`
guarantees the legacy path. No phase, plan, gate, or verification semantics change
when the feature is inactive.

## Open questions (tracked, resolved empirically)

These are not yet settled from the public docs and are being confirmed by local
testing before any deeper wiring:

- How a plugin ships a **saved/bundled** `.js` workflow (on-disk location and
  command registration).
- Whether a workflow script can invoke VBW's `vbw-*` agents or only generic
  subagents.
- The exact programmatic trigger for a workflow from within a command context.

Until these are resolved, wiring is limited to the opt-in `/vbw:map` path and the
detection/resolution scaffolding, all defaulting to the existing behavior.
