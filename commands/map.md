---
name: vbw:map
category: advanced
disable-model-invocation: true
description: Analyze existing codebase with adaptive Scout teammates to produce structured mapping documents.
argument-hint: [--incremental] [--package=name] [--tier=solo|duo|quad]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, TeamCreate, TaskCreate, SendMessage, TeamDelete, Skill, LSP
---

# VBW Map: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then R="${SESSION_LINK}"; fi; if [ -z "$R" ]; then ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true); [ -n "$ANY_LINK" ] && R="$ANY_LINK"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; LINK="${SESSION_LINK}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

Existing mapping:
```text
!`ls .vbw-planning/codebase/ 2>/dev/null || echo "No codebase mapping found"`
```
META.md:
```
!`cat .vbw-planning/codebase/META.md 2>/dev/null || echo "No META.md found"`
```
Project files:
```text
!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile build.gradle pom.xml 2>/dev/null || echo "No standard project files found"`
```
Git HEAD:
```text
!`git rev-parse HEAD 2>/dev/null || echo "no-git"`
```
Agent Teams:
```text
!`echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}"`
```

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **No git:** WARN "Not a git repo -- incremental mapping disabled." Continue in full mode.
3. **Empty project:** No source files → STOP: "No source code found to map."

## Steps

### Step 1: Parse arguments and detect mode

- **--incremental**: force incremental refresh
- **--package=name**: scope to single monorepo package
- **--tier=solo|duo|quad**: force specific tier (overrides auto-detection)

**Mode detection:** If META.md exists + git repo: compare `git_hash` to HEAD. <20% files changed = incremental, else full. No META.md or no git = full. Store MAPPING_MODE and CHANGED_FILES.

### Step 1.5: Size codebase and select tier

Count source files (Glob), excluding: .vbw-planning/, node_modules/, .git/, vendor/, dist/, build/, target/, .next/, __pycache__/, .venv/, coverage/. If --package, scope to that dir. Store SOURCE_FILE_COUNT.

| Tier | Files | Strategy | Scouts |
|------|-------|----------|--------|
| solo | <200 | Orchestrator maps inline | 0 |
| duo | 200-1000 | 2 scouts, combined domains | 2 |
| quad | 1000+ | Full 4-scout team | 4 |

Overrides: --tier flag forces tier. Agent Teams not enabled → force solo (`⚠ Agent Teams not enabled — using solo mode`). `prefer_teams='never'` in config → force solo (`⚠ prefer_teams=never — using solo mode`).
Display: `◆ Sizing: {SOURCE_FILE_COUNT} source files → {tier} mode`

Read `prefer_teams` before applying tier:
```bash
PREFER_TEAMS=$(bash "{plugin-root}/scripts/normalize-prefer-teams.sh" .vbw-planning/config.json 2>/dev/null || echo "auto")
```
If `PREFER_TEAMS` is `never`, force solo regardless of file count or --tier flag.

After selecting the tier, evaluate the optional Dynamic Workflows executor (see `{plugin-root}/references/workflow-executor.md`):
```bash
WF_MODE=$(bash "{plugin-root}/scripts/normalize-workflows-mode.sh" .vbw-planning/config.json 2>/dev/null || echo "auto")
WF_SUPPORTED=$(bash "{plugin-root}/scripts/detect-workflows-support.sh" --status 2>/dev/null || echo "unsupported")
WF_EXECUTOR=$(bash "{plugin-root}/scripts/resolve-executor.sh" --mode --fanout "${SOURCE_FILE_COUNT:-0}" --workflows-mode "$WF_MODE" --supported "$WF_SUPPORTED" 2>/dev/null || echo "fallback")
WF_MAX_WORKERS=$(bash "{plugin-root}/scripts/normalize-workflow-max-workers.sh" .vbw-planning/config.json 2>/dev/null || echo 4)
```
This applies to the `duo` and `quad` tiers (both fan out to a Scout team a workflow can replace; `solo` runs in the orchestrator and is never a workflow). The duo/quad scan runs as a workflow whenever `WF_EXECUTOR` is `workflow` — i.e. `prefer_workflows≠never` (default `auto`) AND the runtime supports workflows (the user's Claude config must enable them) AND the scan is wide enough (fan-out ≥ 2; `SOURCE_FILE_COUNT` clears this at both tiers). `WF_EXECUTOR=fallback` (`prefer_workflows=never`, unsupported runtime, or low fan-out) always uses the Scout team (2 scouts for duo, 4 for quad).

### Step 2: Detect monorepo

**JS/Node patterns:** Check lerna.json, pnpm-workspace.yaml, packages/ or apps/ with sub-package.json, root workspaces field.

**Multi-component detection:** Count distinct build system roots at different paths. Build system markers: package.json, Cargo.toml, go.mod, pyproject.toml, build.gradle, pom.xml, *.xcodeproj, Podfile, pubspec.yaml. If 2+ markers found at different directory levels (not just root), treat as monorepo.

If monorepo + --package: scope to that package.

### Step 3: Execute mapping (tier-branched)

**Step 3-solo:** Orchestrator analyzes each domain sequentially, writes to `.vbw-planning/codebase/`:

- Domain 1 (Tech Stack): STACK.md + DEPENDENCIES.md
- Domain 2 (Architecture): ARCHITECTURE.md + STRUCTURE.md
- Domain 3 (Quality): CONVENTIONS.md + TESTING.md
- Domain 4 (Concerns): CONCERNS.md

Display ✓ per domain. After all 7 docs written, skip Step 3.5, go to Step 4.

---

**Step 3-duo executor selection:** If the duo scan is workflow-eligible — `WF_EXECUTOR` is `workflow` (i.e. `prefer_workflows≠never` + a supported runtime + fan-out ≥ 2; see Step 1.5 and `{plugin-root}/references/workflow-executor.md`) — run **Step 3-duo-workflow** and skip the scout-team path. Otherwise run **Step 3-duo** (the scout-team path) as written.

**Step 3-duo-workflow (opt-in — Dynamic Workflows executor):** Offload the two-domain scan to a Claude Dynamic Workflow instead of a Scout team. Prefer the first-class `Workflow` tool when the runtime exposes it, falling back to the per-request `ultracode` keyword, then to the Step 3-duo scout team (see `{plugin-root}/references/workflow-executor.md` "Invoking a workflow"):
- Dispatch `Workflow({ script })` with an inline script that scans the codebase across the same two combined domains (Tech + Architecture; Quality + Concerns), spawning each domain worker via `agent(prompt, { agentType: 'vbw:vbw-scout' })`. It runs in the background; monitor via `/workflows`.
- **Direct doc writes (deliberate design decision — see `{plugin-root}/references/workflow-executor.md` "Carve-out: read-only map codebase docs"):** the codebase map docs are read-only and ungated, so the workflow's `vbw:vbw-scout` workers write their domain docs **directly via `<output_paths>`** — identical to the Step 3-duo scout-team path — and return only `cross_cutting` summaries. The orchestrator does **not** round-trip the seven docs' full content back through session context. Assign `<output_paths>` per worker exactly as Step 3-duo:
  - Tech + Architecture worker → `.vbw-planning/codebase/STACK.md`, `.vbw-planning/codebase/DEPENDENCIES.md`, `.vbw-planning/codebase/ARCHITECTURE.md`, `.vbw-planning/codebase/STRUCTURE.md`
  - Quality + Concerns worker → `.vbw-planning/codebase/CONVENTIONS.md`, `.vbw-planning/codebase/TESTING.md`, `.vbw-planning/codebase/CONCERNS.md`
- **Gated-artifact bridging unchanged:** this direct-write carve-out applies ONLY to the read-only `codebase/*.md` docs. Any gated artifact (plans, SUMMARY.md, VERIFICATION.md) must still be orchestrator-bridged and must never be written by a workflow.
- **Worker model (governed, not inherited):** resolve the worker model exactly as the Scout team does — `bash "{plugin-root}/scripts/resolve-agent-settings.sh" scout .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "{effort}"` — and pass it explicitly to each worker via `agent(prompt, { agentType: 'vbw:vbw-scout', model: '${RESOLVED_MODEL}' })`. Workers MUST NOT inherit the session or any `ultracode` model. The default `quality` profile resolves `scout` to Sonnet (`budget` → Haiku); only a user `model_overrides`/custom profile escalates to a frontier model. See "Model and effort governance" in `{plugin-root}/references/workflow-executor.md`.
- **Worker concurrency cap:** fan out to at most `${WF_MAX_WORKERS}` workers concurrently (resolved in Step 1.5 via `normalize-workflow-max-workers.sh`; `0` = no VBW cap). The two domains are independent, so they run together; the runtime still caps at 16 concurrent / 1000 total. See `workflow_max_workers` in `{plugin-root}/references/workflow-executor.md`.
- **Enforcement parity:** workflow workers are normal subagents under the same SubagentStart/PreToolUse hooks and file/spawn guards as Task-spawned scouts — no special handling needed.
- **Fallback (mandatory):** if no workflow surface is available at dispatch, the run errors, or it returns no usable result, run the standard **Step 3-duo** scout-team path below instead.
- Display `◆ Executor: Dynamic Workflow (duo scan)`. The workers write the seven docs directly; verify them in Step 3.5 exactly as the team path, then proceed to Step 3.5.

**Step 3-duo:** **Pre-TeamCreate cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Create team via TeamCreate: `team_name="vbw-map-duo"`, `description="Codebase Map (duo)"` with 2 Scouts via TaskCreate. **Set `subagent_type: "vbw:vbw-scout"` on each Scout TaskCreate.** Do not pass `isolation`, `cwd`, `working_dir`, `workingDirectory`, or `workdir` on any TaskCreate.

Scout A (Tech + Architecture): analyze tech stack, deps, architecture, structure. Write findings directly to the output paths. Include in prompt:
```
<output_paths>
.vbw-planning/codebase/STACK.md
.vbw-planning/codebase/DEPENDENCIES.md
.vbw-planning/codebase/ARCHITECTURE.md
.vbw-planning/codebase/STRUCTURE.md
</output_paths>
```
Mode: {MAPPING_MODE}. After writing all 4 files, send a `scout_findings` message (domain: "tech-and-architecture") with `cross_cutting` findings only (file contents already written). Schema ref: `{plugin-root}/references/handoff-schemas.md`

Scout B (Quality + Concerns): analyze quality, conventions, testing, debt, risks. Write findings directly to the output paths. Include in prompt:
```
<output_paths>
.vbw-planning/codebase/CONVENTIONS.md
.vbw-planning/codebase/TESTING.md
.vbw-planning/codebase/CONCERNS.md
</output_paths>
```
Mode: {MAPPING_MODE}. After writing all 3 files, send a `scout_findings` message (domain: "quality-and-concerns") with `cross_cutting` findings only. Schema ref: `{plugin-root}/references/handoff-schemas.md`

**Scout model (effort-gated):** Fast/Turbo: `Model: haiku`. Thorough/Balanced: inherit session model.
**Scout turn budget (effort-gated):** Resolve with `bash "{plugin-root}/scripts/resolve-agent-max-turns.sh" scout .vbw-planning/config.json "{effort}"`. If `SCOUT_MAX_TURNS` is non-empty, pass `maxTurns: ${SCOUT_MAX_TURNS}` to each Scout TaskCreate. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
**Skill pre-evaluation:** Before composing Scout task descriptions, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for codebase mapping, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.

If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning each duo-mode Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

**Payload prefix (duo mode):** Use this as the FIRST lines of each Scout task body:
```text
<skill_activation>
Call Skill('{relevant-skill-1}').
Call Skill('{relevant-skill-2}').
</skill_activation>
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
<skill_follow_up_files>
{If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
</skill_follow_up_files>
```
When no installed skills apply, use this prefix instead:
```text
<skill_no_activation>
Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
</skill_no_activation>
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
```

**MCP tools:** If code-analysis MCP tools are available (architecture extraction, dependency graphs, call hierarchy, symbol search), note the specific tools in each Scout's task prompt so Scouts can leverage them alongside Glob/Read/Grep.

Wait for all findings. Proceed to Step 3.5.

---

**Step 3-quad executor selection:** If the quad scan is workflow-eligible — `WF_EXECUTOR` is `workflow` (i.e. `prefer_workflows≠never` + a supported runtime + fan-out ≥ 2; see Step 1.5 and `{plugin-root}/references/workflow-executor.md`) — run **Step 3-quad-workflow** and skip the scout-team path. Otherwise run **Step 3-quad** (the scout-team path) as written.

**Step 3-quad-workflow (opt-in — Dynamic Workflows executor):** Offload the four-domain scan to a Claude Dynamic Workflow instead of a Scout team. Prefer the first-class `Workflow` tool when the runtime exposes it, falling back to the per-request `ultracode` keyword, then to the Step 3-quad scout team (see `{plugin-root}/references/workflow-executor.md` "Invoking a workflow"):
- Dispatch `Workflow({ script })` with an inline script that scans the codebase across the same four domains (Tech Stack, Architecture, Quality, Concerns), spawning each domain worker via `agent(prompt, { agentType: 'vbw:vbw-scout' })`. It runs in the background; monitor via `/workflows`.
- **Direct doc writes (deliberate design decision — see `{plugin-root}/references/workflow-executor.md` "Carve-out: read-only map codebase docs"):** the codebase map docs are read-only and ungated, so the workflow's `vbw:vbw-scout` workers write their domain docs **directly via `<output_paths>`** — identical to the Step 3-quad scout-team path — and return only `cross_cutting` summaries. The orchestrator does **not** round-trip the seven docs' full content (~900 lines) back through session context. Assign `<output_paths>` per worker exactly as Step 3-quad:
  - Tech Stack worker → `.vbw-planning/codebase/STACK.md`, `.vbw-planning/codebase/DEPENDENCIES.md`
  - Architecture worker → `.vbw-planning/codebase/ARCHITECTURE.md`, `.vbw-planning/codebase/STRUCTURE.md`
  - Quality worker → `.vbw-planning/codebase/CONVENTIONS.md`, `.vbw-planning/codebase/TESTING.md`
  - Concerns worker → `.vbw-planning/codebase/CONCERNS.md`
- **Gated-artifact bridging unchanged:** this direct-write carve-out applies ONLY to the read-only `codebase/*.md` docs. Any gated artifact (plans, SUMMARY.md, VERIFICATION.md) must still be orchestrator-bridged and must never be written by a workflow.
- **Worker model (governed, not inherited):** resolve the worker model exactly as the Scout team does — `bash "{plugin-root}/scripts/resolve-agent-settings.sh" scout .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "{effort}"` — and pass it explicitly to each worker via `agent(prompt, { agentType: 'vbw:vbw-scout', model: '${RESOLVED_MODEL}' })`. Workers MUST NOT inherit the session or any `ultracode` model. The default `quality` profile resolves `scout` to Sonnet (`budget` → Haiku); only a user `model_overrides`/custom profile escalates to a frontier model. See "Model and effort governance" in `{plugin-root}/references/workflow-executor.md`.
- **Worker concurrency cap:** fan out to at most `${WF_MAX_WORKERS}` workers concurrently (resolved in Step 1.5 via `normalize-workflow-max-workers.sh`; `0` = no VBW cap). The four domains are independent, so with the default `4` they run together; a lower cap batches them. The runtime still caps at 16 concurrent / 1000 total. See `workflow_max_workers` in `{plugin-root}/references/workflow-executor.md`.
- **Enforcement parity:** workflow workers are normal subagents under the same SubagentStart/PreToolUse hooks and file/spawn guards as Task-spawned scouts — no special handling needed.
- **Fallback (mandatory):** if no workflow surface is available at dispatch, the run errors, or it returns no usable result, run the standard **Step 3-quad** scout-team path below instead.
- Display `◆ Executor: Dynamic Workflow (quad scan)`. The workers write the seven docs directly; verify them in Step 3.5 exactly as the team path, then proceed to Step 3.5.

**Step 3-quad:** **Pre-TeamCreate cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Create team via TeamCreate: `team_name="vbw-map-quad"`, `description="Codebase Map (quad)"` with 4 Scouts via TaskCreate. **Set `subagent_type: "vbw:vbw-scout"` on each Scout TaskCreate.** Do not pass `isolation`, `cwd`, `working_dir`, `workingDirectory`, or `workdir` on any TaskCreate. Each Scout writes its domain files directly via `<output_paths>`, then sends a `scout_findings` message with `cross_cutting` findings only (file contents already written). Schema ref: `{plugin-root}/references/handoff-schemas.md`
- Scout 1 (Tech Stack): `<output_paths>` = `.vbw-planning/codebase/STACK.md`, `.vbw-planning/codebase/DEPENDENCIES.md`
- Scout 2 (Architecture): `<output_paths>` = `.vbw-planning/codebase/ARCHITECTURE.md`, `.vbw-planning/codebase/STRUCTURE.md`
- Scout 3 (Quality): `<output_paths>` = `.vbw-planning/codebase/CONVENTIONS.md`, `.vbw-planning/codebase/TESTING.md`
- Scout 4 (Concerns): `<output_paths>` = `.vbw-planning/codebase/CONCERNS.md`

Security: PreToolUse hook handles enforcement. **Scout model:** same as duo. **Scout turn budget:** same as duo (pass `maxTurns: ${SCOUT_MAX_TURNS}` when non-empty, omit when empty). **Skill pre-evaluation:** Before composing Scout task descriptions, evaluate installed skills visible in your system context — read each skill's description and select all materially helpful installed skills for codebase mapping, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context — not just the single most direct skill. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected — {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references. If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning each quad-mode Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block. **MCP tools:** If code-analysis MCP tools are available (architecture extraction, dependency graphs, call hierarchy, symbol search), note the specific tools in each Scout's task prompt so Scouts can leverage them alongside Glob/Read/Grep.

**Payload prefix (quad mode):** Use this as the FIRST lines of each Scout task body:
```text
<skill_activation>
Call Skill('{relevant-skill-1}').
Call Skill('{relevant-skill-2}').
</skill_activation>
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
<skill_follow_up_files>
{If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
</skill_follow_up_files>
```
When no installed skills apply, use this prefix instead:
```text
<skill_no_activation>
Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
</skill_no_activation>
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
```

**Scout communication (effort-gated):**

| Effort | Messages |
|--------|----------|
| Thorough | Cross-cutting findings + contradiction flags for INDEX.md Validation Notes |
| Balanced | Cross-cutting findings only |
| Fast | Blockers only |

Use targeted `message` not `broadcast`. Wait for all findings. Display ✓ per scout.

### Step 3.5: Verify mapping documents written by Scouts

**Skip if solo** (docs already written). Scouts wrote files directly via `<output_paths>`. Verify all 7 docs exist in `.vbw-planning/codebase/`: STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md. If any are missing, log `⚠ Missing: {filename}` and write a placeholder from the `scout_findings` message content (fall back to cross_cutting text). Use `cross_cutting` findings from scout_findings messages for INDEX.md Validation Notes in Step 4.

### Step 4: Synthesize INDEX.md and PATTERNS.md

Read all 7 docs. Produce:
- **INDEX.md:** Cross-referenced index with key findings + "Validation Notes" for contradictions
- **PATTERNS.md:** Recurring patterns: architectural, naming, quality, concern, dependency

### Step 5: Create META.md and present summary

**HARD GATE — Shutdown before presenting results:** Solo: no team, skip. **Duo or Quad via the Dynamic Workflows executor (Step 3-duo-workflow / Step 3-quad-workflow, no TeamCreate): no team exists — skip the shutdown handshake; the workflow runtime manages and tears down its own workers.** Duo/Quad scout-team path: send `shutdown_request` to each teammate, wait for `shutdown_response` (approved=true) delivered via SendMessage tool call (NOT plain text). If a teammate responds in plain text instead of calling SendMessage, re-send the `shutdown_request`. If rejected, re-request (max 3 attempts per teammate — then proceed). Call TeamDelete. **Post-TeamDelete residual cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Verify: after TeamDelete, there must be ZERO active teammates. If teardown stalls, advise the user to run `/vbw:doctor --cleanup`. Only THEN proceed to META.md and user output. Failure to shut down leaves agents running and consuming API credits.

Write META.md: mapped_at, git_hash, file_count, document list, mode, monorepo flag, mapping_tier, mcp_tools_used (tool names or "none").

Display per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: Phase Banner (Codebase Mapped, Mode, Tier), ✓ per document, Key Findings (◆), Next Up block.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — Phase Banner (double-line box), File Checklist (✓), ◆ for findings, ⚠ for warnings, Next Up Block, no ANSI.
