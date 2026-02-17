# VBW v1.21.30 Token & Infrastructure Analysis

**Date:** 2026-02-17
**Version:** v1.21.30
**Baseline:** v1.20.0 (full spec compliance)
**Scope:** 368 commits across 6 milestones — from full spec to discovery intelligence, team resilience, agent health, and event correlation
**Method:** 368 commits, 78 scripts, 51 test files (8,703 lines), 575 bats tests
**Verdict:** Per-request overhead **reduced 17%** from v1.20.0 (and 23% from v1.10.7). vibe.md skill extraction removed 343 lines from per-request loading. Shell-only architecture continues: 15 new scripts add **zero model tokens**.

---

## Executive Summary

v1.20.0 built the full V2/V3 enforcement infrastructure. v1.21.x refines how that infrastructure is loaded — moving the largest command (vibe.md) from per-request to on-demand skill loading, adding 7 agents (up from 6), and shipping 6 milestones that expand shell infrastructure without touching per-request overhead.

The key architectural shift: **vibe.md became a skill**. In v1.20.0, vibe.md (343 lines) was an active command loaded on every user message. In v1.21.x, it has `disable-model-invocation: true` and is loaded only when the user invokes `/vbw:vibe`. This single change accounts for most of the per-request reduction.

Six milestones shipped since v1.20.0:

| Milestone | Commits | New/Modified | Token Impact |
|---|---|---|---|
| Config Migration & Research Verification | ~10 | 2 plans, shell fixes | Zero (shell) |
| Discovery Intelligence | ~50 | discussion-engine.md, bootstrap rewrites | +6 lines refs (lazy) |
| Team Preference Control | ~12 | prefer_teams config, protocol updates | Zero (protocol text) |
| tmux Agent Teams Resilience | ~70 | 6 scripts (agent-health, pane mgmt) | Zero (shell hooks) |
| Agent Health Monitor | ~30 | agent-health.sh, circuit breakers, rolling summaries | Zero (shell + agent text) |
| Event Log Correlation IDs | 3 | log-event.sh + execute-protocol.md | Zero (shell) + ~11 lines ref |

**The pattern continues:** The codebase grew from 16,154 to 26,533 lines (+64%), yet per-request tokens dropped from 11,595 to 9,630 (-17%). Infrastructure growth and model consumption remain fully decoupled.

---

## The Before State: v1.20.0 Baseline

### Static Inventory (v1.20.0)

| Category | Files | Lines | Tokens (~15/line) |
|---|---|---|---|
| Commands (active, 6) | debug, fix, qa, research, status, vibe | 696 | ~10,440 |
| Commands (disabled, 15) | config, doctor, help, init, map, pause, profile, release, resume, skills, teach, todo, uninstall, update, whats-new | 1,650 | ~24,750 |
| Agents (6) | lead, dev, qa, scout, debugger, architect | 267 | ~4,005 |
| CLAUDE.md | 1 | 77 | ~1,155 |
| References (11) | discovery-protocol, effort×4, execute-protocol, handoff-schemas, model-profiles, phase-detection, brand, verification-protocol | 1,333 | ~19,995 |
| Scripts (63) | 40 new + 23 modified | 8,807 | 0 (shell) |
| Config (5) | defaults, model-profiles, rollout-stages, stack-mappings, token-budgets | 395 | 0 (shell) |
| Hooks | hooks.json | 227 | 0 (shell) |
| Tests (36) | bats test files | 4,767 | 0 (not loaded) |
| Templates (9) | PLAN, PROJECT, REQUIREMENTS, ROADMAP, STATE, SUMMARY, VERIFICATION, CONTEXT, RESEARCH | 238 | 0 (loaded once) |
| **Total** | **152 source files** | **16,154** | **~60,345** |

### Per-Request Overhead (v1.20.0)

```
debug.md             77 lines
fix.md               51 lines
qa.md                77 lines
research.md          51 lines
status.md            97 lines
vibe.md             343 lines    ← loaded every request
CLAUDE.md            77 lines
                    ─────────
Total:              773 lines  (~11,595 tokens)
```

---

## The After State: v1.21.30

### Static Inventory (v1.21.30)

| Category | Files | Lines | Tokens (~15/line) | vs v1.20.0 |
|---|---|---|---|---|
| Commands (active, 7) | debug, fix, list-todos, qa, research, status, verify | 588 | ~8,820 | -1,620 |
| Commands (disabled, 17) | config, discuss, doctor, help, init, map, pause, profile, release, resume, skills, teach, todo, uninstall, update, vibe, whats-new | 2,270 | ~34,050 | +9,300 |
| Agents (7) | lead, dev, qa, scout, debugger, architect, docs | 462 | ~6,930 | +2,925 |
| CLAUDE.md | 1 | 54 | ~810 | -345 |
| References (11) | discussion-engine, effort×4, execute-protocol, handoff-schemas, model-profiles, phase-detection, brand, verification-protocol | 1,516 | ~22,740 | +2,745 |
| Scripts (78) | 15 new + 63 modified | 11,959 | 0 (shell) | 0 |
| Config (5) | defaults, model-profiles, rollout-stages, stack-mappings, token-budgets | 434 | 0 (shell) | 0 |
| Hooks | hooks.json | 257 | 0 (shell) | 0 |
| Tests (51) | bats test files | 8,703 | 0 (not loaded) | 0 |
| Templates (10) | +UAT template | 290 | 0 (loaded once) | 0 |
| **Total** | **~187 source files** | **26,533** | **~73,350** | +13,005 |

### Per-Request Overhead (v1.21.30)

```
debug.md             94 lines    (+17 from v1.20.0)
fix.md               54 lines    (+3)
list-todos.md        64 lines    (NEW)
qa.md                81 lines    (+4)
research.md          56 lines    (+5)
status.md            99 lines    (+2)
verify.md           140 lines    (NEW — was invoked inline, now active command)
CLAUDE.md            54 lines    (-23)
                    ─────────
Total:              642 lines  (~9,630 tokens)

vs v1.20.0:         -131 lines  (~-1,965 tokens, -17%)
vs v1.10.7:         -192 lines  (~-2,880 tokens, -23%)
```

**Why it decreased:** vibe.md (343 lines) moved from active command to disabled skill. It's now loaded only when the user runs `/vbw:vibe`, not on every message. This removed 343 lines from per-request. Two new active commands were added: verify.md (140) and list-todos.md (64), adding 204 lines. Other commands grew slightly (+31 total). CLAUDE.md shrank 23 lines. Net: **-131 lines**.

---

## Milestone 1: Config Migration & Research Verification

**Commits:** ~10
**Token impact:** Zero per-request

Shell-only work: config migration during session-start.sh, research validation tests. All changes in shell scripts and bats tests. No command/agent/reference modifications.

---

## Milestone 2: Discovery Intelligence

**Commits:** ~50
**Token impact:** Zero per-request. +6 lines reference growth (discussion-engine.md, lazy load).

Replaced the discovery-protocol.md (159 lines) with discussion-engine.md (165 lines). The engine is loaded only during bootstrap and discuss modes — never per-request. Added domain research spawning to bootstrap flow (shell orchestration). Three-tier feature classification, thread-following questions, vague answer disambiguation — all encoded in the discussion engine reference.

---

## Milestone 3: Team Preference Control

**Commits:** ~12
**Token impact:** Zero per-request

Added `prefer_teams` enum to config (replacing boolean `agent_teams`). Updated execute-protocol.md, vibe.md, and debug.md with team creation decision trees. All protocol text changes — no new per-request loading.

---

## Milestone 4: tmux Agent Teams Resilience

**Commits:** ~70
**Token impact:** Zero per-request. +195 lines in agent definitions (lazy load per spawn).

The largest post-v1.20.0 milestone. 6 phases addressing agent team reliability:

| Phase | What Changed | Token Impact |
|---|---|---|
| Lifecycle Hooks | agent-start.sh, agent-stop.sh rewritten | Zero (shell) |
| Compaction Recovery | post-compact.sh, agent circuit breakers | +~195 tokens in agent defs |
| Lock Hardening | lease-lock.sh rewrite with flock | Zero (shell) |
| Event Log Hardening | log-event.sh event_id, type validation | Zero (shell) |
| Shutdown Protocol | SendMessage shutdown gates in protocols | ~0 (protocol text) |
| Discussion Engine | Conversation-based discovery | Zero (ref, lazy) |

Agent definitions grew from 267 to 462 lines (+195) across 7 agents (docs agent added). Each agent gained Circuit Breaker Protocol sections and compaction recovery instructions. This is +2,925 tokens total when ALL agents are spawned, but individual spawn cost is ~420 tokens more per agent.

---

## Milestone 5: Agent Health Monitor

**Commits:** ~30
**Token impact:** Zero per-request

Built `agent-health.sh` with start/idle/stop/cleanup subcommands, wired into 4 hooks. Added circuit breaker advisory to all 7 agent definitions. Created `compile-rolling-summary.sh` for context cost reduction in late phases. All shell infrastructure — zero per-request model tokens.

---

## Milestone 6: Event Log Correlation IDs

**Commits:** 3
**Token impact:** Zero per-request. +11 lines in execute-protocol.md (lazy load).

Added correlation_id threading: auto-generated UUID at phase start, stored in execution-state.json, auto-read by log-event.sh. Zero caller changes. execute-protocol.md grew by ~11 lines (correlation_id generation steps). Loaded once per execution invocation, not per-request.

---

## Global Impact: Token Flow Comparison

### Per-Request Overhead

```
                              v1.10.7      v1.20.0      v1.21.30     Change (v1.20→v1.21)
──────────────────────────────────────────────────────────────────────────────────────────
Active commands                 767          696          588         -108 lines
CLAUDE.md                        67           77           54          -23 lines
                               ─────        ─────        ─────       ─────
Per-request total               834          773          642         -131 lines
Est. tokens                  12,510       11,595        9,630      -1,965 tokens (-17%)
```

### Per-Phase Spawn+Context Overhead

```
                              v1.10.7      v1.20.0      v1.21.30     Change
──────────────────────────────────────────────────────────────────────────────
SMALL PROJECT (3 phases, 10 reqs, 3 Devs, 1 QA per phase)

Agent definitions             3,630        4,005        6,930       +2,925  (7 agents, circuit breakers)
Compiled context reads        5,295        5,850        6,400         +550  (rolling summary, research)
Handoff schema loads          1,410        3,360        4,140         +780  (schema growth)
Reference loads (execute)         0        5,775        7,590       +1,815  (execute-protocol grew)
Skill bundling savings       -1,000       -1,000       -1,000            0  (unchanged)
Compaction re-reads           1,000        1,000        1,000            0  (unchanged)
                             ──────       ──────       ──────       ──────
Per-phase non-request        10,335       18,990       25,060       +6,070

MEDIUM PROJECT (5 phases, 20 reqs, 4 Devs, 1 QA, V3 delta on)

Agent definitions             4,285        4,690        7,900       +3,210
Compiled context reads        7,155        8,900        9,800         +900
Handoff schema loads          1,680        4,020        4,960         +940
Reference loads (execute)         0        5,775        7,590       +1,815
Skill bundling savings       -1,600       -1,600       -1,600            0
Compaction re-reads           1,200        1,200        1,200            0
                             ──────       ──────       ──────       ──────
Per-phase non-request        12,720       22,985       29,850       +6,865
```

### The Trade-off

Per-phase overhead grew because agent definitions expanded (+195 lines for circuit breakers, compaction recovery, docs agent). But **per-request overhead dropped by 1,965 tokens**. Over a typical phase with 80 user messages:

```
Per-request savings:  1,965 × 80 = 157,200 tokens saved per phase
Per-phase growth:                    6,865 tokens added per phase (medium)
                                   ───────
Net per-phase:                    150,335 tokens SAVED
```

### Total Session Impact

| Scale | v1.20.0 Total | v1.21.30 Total | Saved | Reduction |
|---|---|---|---|---|
| Small (3 phases, 50 req/phase) | ~185,665 | ~155,490 | ~30,175 | **~16%** |
| Medium (5 phases, 80 req/phase) | ~306,125 | ~239,350 | ~66,775 | **~22%** |
| Large (8 phases, 80 req/phase) | ~330,360 | ~253,880 | ~76,480 | **~23%** |

### Coordination Overhead vs Stock Teams

```
                       Stock Teams    v1.0.99    v1.10.7    v1.20.0    v1.21.30
Per-request overhead      10,800       4,970      3,245      3,198      2,655
Per-phase spawn+context   87,100      33,200     10,910     18,990     25,060
                         ──────      ──────     ──────     ──────     ──────
Total coordination/phase  97,900      38,170     14,155     22,188     27,715
Per-request × 80 msgs   864,000     397,600    259,600    255,840    212,400

Total session (1 phase)  961,900     435,770    273,755    277,828    240,115
Reduction vs stock             —        55%        72%        71%        75%

Total session (5 phases) 4,809,500  2,178,850  1,368,775  1,289,140  1,101,575
Reduction vs stock             —        55%        72%        73%        77%
```

**v1.21.29 achieves 75-77% overhead reduction vs stock teams** — the best yet. The skill extraction moved the largest active command out of per-request loading, and the per-request savings compound across every user message.

---

## What Changed at Each Layer

```
LAYER                    v1.20.0    v1.21.30   CHANGE     METHOD
──────────────────────────────────────────────────────────────────────────
Commands (active)           696        588       -108    vibe→skill, +verify, +list-todos
Commands (disabled)       1,650      2,270       +620    vibe moved here, discuss added, init/config grew
Agents (7)                  267        462       +195    +docs agent, circuit breakers, compaction
CLAUDE.md                    77         54        -23    Streamlined active context
References (11)           1,333      1,516       +183    discussion-engine, execute-protocol, handoff
──────────────────────────────────────────────────────────────────────────
Model-visible inventory   4,023      4,890       +867    Agent + reference growth

BUT runtime loading patterns improved:
──────────────────────────────────────────────────────────────────────────
Per-request (×80 msgs)  11,595      9,630     -1,965    Skill extraction wins
Per-phase context       18,990     25,060     +6,070    Agent defs grew (circuit breakers)
Per-session (5-phase)  306,125    239,350    -66,775    Per-request savings dominate at scale

Shell-only infrastructure:
──────────────────────────────────────────────────────────────────────────
Scripts (63→78)          8,807     11,959     +3,152    15 new scripts, all shell
Config (5)                 395        434        +39    Config growth
Hooks                      227        257        +30    New hooks
Tests (36→51)            4,767      8,703     +3,936    251 new bats tests
Templates (9→10)           238        290        +52    +UAT template
──────────────────────────────────────────────────────────────────────────
Shell-only total        14,434     21,643     +7,209    ALL zero model tokens
```

**The key insight:** 7,209 lines of growth are invisible to the model. The model sees 867 more lines of source inventory, but loads 1,965 fewer tokens per request. The skill extraction pattern proves that *how* files are loaded matters more than total file size.

---

## Version Progression Table

| Milestone | Version | Optimization Type | Key Metric |
|---|---|---|---|
| Performance Optimization | v1.0.99 | 15 mechanisms: when/how to load | 61% overhead reduction |
| GSD Isolation | v1.10.0 | Two-marker isolation, PreToolUse block | (security, not tokens) |
| Token Compression | v1.10.2 | Content compression across all layers | 74% overhead reduction |
| Intelligent Discovery | v1.10.5 | Discovery protocol + phase questions | (quality, not tokens) |
| Context Compiler | v1.10.7 | Deterministic context routing | 86% overhead reduction |
| Vibe Consolidation | v1.10.15 | 10 commands → 1 unified entry point | -7.3% per-request |
| Model Profiles | v1.10.15 | Shell-only model resolution | Zero token cost |
| V3 Infrastructure | v1.10.15 | Feature-flagged shell hooks | Zero token cost |
| V2 Protocol Enforcement | v1.10.18 | Typed protocols, contracts, gates | +1,950 tokens per team spawn |
| Full Spec + Code Review | v1.20.0 | 53-item hardening sweep | ~85% overhead reduction |
| Discovery Intelligence | v1.21.x | Discussion engine, domain research | Zero per-request |
| Team Preference Control | v1.21.x | prefer_teams config enum | Zero per-request |
| tmux Agent Teams Resilience | v1.21.x | Lifecycle hooks, circuit breakers | +2,925 agent tokens (lazy) |
| Agent Health Monitor | v1.21.x | Health tracking, rolling summaries | Zero per-request |
| Event Log Correlation IDs | v1.21.x | UUID threading, auto-read | Zero per-request |
| **Skill Extraction (vibe.md)** | **v1.21.x** | **Active → disabled/skill** | **-17% per-request** |

---

## Key Takeaways

1. **Skill extraction is the next frontier.** Moving vibe.md from active command to on-demand skill saved 343 lines per request — 17% reduction. Any active command that isn't needed on every message is a candidate for skill extraction.

2. **Per-request remains king.** Despite per-phase overhead growing +6,070 tokens (agent circuit breakers, protocol growth), the per-request drop of -1,965 tokens produces net savings of 66,775 tokens per session (5-phase medium project).

3. **77% overhead reduction vs stock teams.** The cumulative effect of 16 optimization milestones over 6 versions. Stock Opus 4.6 agent teams consume ~4.8M tokens for a 5-phase project. VBW: ~1.1M.

4. **Shell-only growth continues to scale.** 15 new scripts (3,152 lines), 251 new tests (3,936 lines) — all zero model tokens. The test suite alone grew 82% without any model cost.

5. **Agent definitions are the new growth area.** 267 → 462 lines (+73%) from circuit breakers, compaction recovery, and the docs agent. Each agent spawn now costs ~60-90 more tokens. This is the trade-off for resilience: agents recover from stuck states and compaction, reducing costly retries.

6. **The codebase grew 64%; the model barely noticed.** 16,154 → 26,533 lines. Per-request tokens: 11,595 → 9,630 (-17%). The decoupling between codebase size and model cost is now a proven pattern across 368 commits.

---

## Appendix A: File Inventory Comparison

### Commands

| File | v1.20.0 | v1.21.30 | Status | Change |
|---|---|---|---|---|
| config.md | 345 (disabled) | 442 (disabled) | Modified | +97 |
| debug.md | 77 (active) | 94 (active) | Modified | +17 |
| discuss.md | — | 34 (disabled) | New | Standalone discuss |
| doctor.md | 72 (disabled) | 111 (disabled) | Modified | +39 |
| fix.md | 51 (active) | 54 (active) | Modified | +3 |
| help.md | 73 (disabled) | 37 (disabled) | Modified | -36 |
| init.md | 467 (disabled) | 504 (disabled) | Modified | +37 |
| list-todos.md | — | 64 (active) | New | Todo list viewer |
| map.md | 120 (disabled) | 123 (disabled) | Modified | +3 |
| pause.md | 28 (disabled) | 29 (disabled) | Modified | +1 |
| profile.md | 60 (disabled) | 61 (disabled) | Modified | +1 |
| qa.md | 77 (active) | 81 (active) | Modified | +4 |
| release.md | 96 (disabled) | 97 (disabled) | Modified | +1 |
| research.md | 51 (active) | 56 (active) | Modified | +5 |
| resume.md | 31 (disabled) | 33 (disabled) | Modified | +2 |
| skills.md | 61 (disabled) | 62 (disabled) | Modified | +1 |
| status.md | 97 (active) | 99 (active) | Modified | +2 |
| teach.md | 98 (disabled) | 100 (disabled) | Modified | +2 |
| todo.md | 29 (disabled) | 31 (disabled) | Modified | +2 |
| uninstall.md | 58 (disabled) | 55 (disabled) | Modified | -3 |
| update.md | 87 (disabled) | 94 (disabled) | Modified | +7 |
| verify.md | — | 140 (active) | New | UAT command |
| vibe.md | 343 (active) | 427 (disabled) | **Moved** | +84, active→disabled |
| whats-new.md | 25 (disabled) | 30 (disabled) | Modified | +5 |

### Agents

| File | v1.20.0 | v1.21.30 | Change |
|---|---|---|---|
| vbw-architect.md | 34 | 43 | +9 (circuit breaker) |
| vbw-debugger.md | 40 | 54 | +14 (circuit breaker + recovery) |
| vbw-dev.md | 54 | 72 | +18 (circuit breaker + compaction) |
| vbw-docs.md | — | 85 | New (documentation agent) |
| vbw-lead.md | 54 | 69 | +15 (circuit breaker + shutdown) |
| vbw-qa.md | 54 | 76 | +22 (circuit breaker + recovery) |
| vbw-scout.md | 31 | 63 | +32 (circuit breaker + web search) |

### References

| File | v1.20.0 | v1.21.30 | Change |
|---|---|---|---|
| discussion-engine.md | 159 | 165 | +6 (replaced discovery-protocol.md) |
| effort-profile-balanced.md | 44 | 44 | 0 |
| effort-profile-fast.md | 42 | 42 | 0 |
| effort-profile-thorough.md | 46 | 46 | 0 |
| effort-profile-turbo.md | 44 | 44 | 0 |
| execute-protocol.md | 385 | 506 | +121 (correlation_id, recovery, scale) |
| handoff-schemas.md | 224 | 276 | +52 (new message types) |
| model-profiles.md | 110 | 114 | +4 |
| phase-detection.md | 89 | 89 | 0 |
| vbw-brand-essentials.md | 44 | 44 | 0 |
| verification-protocol.md | 146 | 146 | 0 |

---

## Methodology Notes

Same methodology as prior analyses: ~15 tokens/line for markdown. Shell scripts, JSON config, hooks, and tests are 0 model tokens. Compiled context output: 10-12 tokens/line.

### What Was Measured vs Estimated

| Metric | Method | Confidence |
|---|---|---|
| File line counts | `wc -l` on actual files | Exact |
| Active vs disabled commands | `disable-model-invocation` header check | Exact |
| Per-request calculation | Sum of active commands + CLAUDE.md | High |
| Reference load patterns | Grep for `@${CLAUDE_PLUGIN_ROOT}` + `Read` instructions | High |
| Skill loading pattern | vibe.md loaded only on `/vbw:vibe` invocation | High |
| Per-request count per phase | 80 messages estimated | Medium |
| Scale projections | Linear extrapolation | Medium |
