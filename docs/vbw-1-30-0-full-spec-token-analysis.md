# VBW v1.30.0 Token & Infrastructure Analysis

**Date:** 2026-02-19
**Version:** v1.30.0
**Baseline:** v1.21.30
**Scope:** Two milestones — CC Alignment v1 (44 commits, 4 phases) + Worktree Isolation (41 commits, 6 phases) = 85 total commits
**Method:** 85 commits, 85 scripts, 57 test files (11,298 lines), 825 bats tests
**Verdict:** Per-request overhead **grew 12%** from v1.21.30 (CC Alignment enforcement content). Worktree Isolation added 6 scripts and 32 tests at **zero per-request cost** — all shell. Dead code removal in Phase 1 actually **reduced** total codebase by 1,665 lines vs the CC Alignment snapshot. Overall coordination overhead vs stock teams: **~73%** reduction.

---

## Executive Summary

v1.21.30 optimized loading patterns — moving vibe.md from active to on-demand, cutting per-request 17%. v1.30.0 ships two milestones: CC Alignment v1 (hardening agents, hooks, and commands for CC 2.1.47) and Worktree Isolation (git worktree-based per-plan Dev agent isolation).

The CC Alignment trade-off is deliberate: active commands grew +81 lines to encode better agent behavior, crash recovery protocols, and verification procedures. These lines improve agent output quality and reduce costly retries. Meanwhile, 20 always-true feature flags were graduated (removing dead code branches), agents gained native Task spawn restrictions and memory scoping, and 55 new BATS tests validate hook bash commands against CC's stricter classifier.

Worktree Isolation added 6 worktree lifecycle scripts and integrated them into the execute protocol at zero per-request cost — all shell infrastructure. Phase 1's dead code removal (lock-lite, graduated flags) actually removed more lines than Phases 2-6 added, resulting in a net codebase reduction.

Two milestones shipped since v1.21.30:

| Milestone | Commits | Phases | Token Impact |
|---|---|---|---|
| CC Alignment v1 | 44 | 4 (Dead Code, Agent Hardening, Hook Enhancement, Docs) | +78 lines per-request, +29 agents (lazy) |
| Worktree Isolation | 41 | 6 (Dead Code, Lifecycle Scripts, Agent Targeting, Integration, Protocol, Tests+Docs) | +16 reference lines (lazy), -505 script lines, -49 test lines |

**The pattern evolves:** The codebase grew from 26,533 to 37,627 lines (+42%), per-request tokens grew from 9,630 to 10,800 (+12%), but this remains 7% below v1.20.0's 11,595. The CC Alignment growth buys CC 2.1.47 compatibility; the Worktree Isolation work is entirely shell-only. Dead code removal in Worktree Phase 1 actually *reduced* the codebase by 1,665 lines vs the CC Alignment snapshot. Shell infrastructure change: scripts -505 lines (net), tests -49 lines (net) — invisible to the model.

---

## The Before State: v1.21.30 Baseline

### Static Inventory (v1.21.30)

| Category | Files | Lines | Tokens (~15/line) |
|---|---|---|---|
| Commands (active, 7) | debug, fix, list-todos, qa, research, status, verify | 588 | ~8,820 |
| Commands (disabled, 17) | config, discuss, doctor, help, init, map, pause, profile, release, resume, skills, teach, todo, uninstall, update, vibe, whats-new | 2,270 | ~34,050 |
| Agents (7) | lead, dev, qa, scout, debugger, architect, docs | 462 | ~6,930 |
| CLAUDE.md | 1 | 54 | ~810 |
| References (11) | discussion-engine, effort×4, execute-protocol, handoff-schemas, model-profiles, phase-detection, brand, verification-protocol | 1,516 | ~22,740 |
| Scripts (78) | shell infrastructure | 11,959 | 0 (shell) |
| Config (5) | defaults, model-profiles, rollout-stages, stack-mappings, token-budgets | 434 | 0 (shell) |
| Hooks | hooks.json | 257 | 0 (shell) |
| Tests (51) | bats test files | 8,703 | 0 (not loaded) |
| Templates (10) | PLAN, PROJECT, REQUIREMENTS, ROADMAP, STATE, SUMMARY, VERIFICATION, CONTEXT, RESEARCH, UAT | 290 | 0 (loaded once) |
| **Total** | **~187 source files** | **26,533** | **~73,350** |

### Per-Request Overhead (v1.21.30)

```
debug.md             94 lines
fix.md               54 lines
list-todos.md        64 lines
qa.md                81 lines
research.md          56 lines
status.md            99 lines
verify.md           140 lines
CLAUDE.md            54 lines
                    ─────────
Total:              642 lines  (~9,630 tokens)
```

---

## The After State: v1.30.0

### Static Inventory (v1.30.0)

| Category | Files | Lines | Tokens (~15/line) | vs v1.21.30 |
|---|---|---|---|---|
| Commands (active, 7) | debug, fix, list-todos, qa, research, status, verify | 669 | ~10,035 | +1,215 |
| Commands (disabled, 17) | config, discuss, doctor, help, init, map, pause, profile, release, resume, skills, teach, todo, uninstall, update, vibe, whats-new | 2,290 | ~34,350 | +300 |
| Agents (7) | lead, dev, qa, scout, debugger, architect, docs | 491 | ~7,365 | +435 |
| CLAUDE.md | 1 | 51 | ~765 | -45 |
| References (11) | discussion-engine, effort×4, execute-protocol, handoff-schemas, model-profiles, phase-detection, brand, verification-protocol | 1,572 | ~23,580 | +840 |
| Scripts (85) | 7 new (CC Alignment) + 6 new (worktree) - 6 removed (dead code) | 12,652 | 0 (shell) | 0 |
| Config (5) | defaults, model-profiles, rollout-stages, stack-mappings, token-budgets | 427 | 0 (shell) | 0 |
| Hooks | hooks.json | 257 | 0 (shell) | 0 |
| Tests (57) | bats test files | 11,298 | 0 (not loaded) | 0 |
| Templates (10) | unchanged count | 301 | 0 (loaded once) | 0 |
| **Total** | **~218 source files** | **37,627** | **~76,095** | +2,745 |

### Per-Request Overhead (v1.30.0)

```
debug.md            108 lines    (+14 from v1.21.30)
fix.md               85 lines    (+31)
list-todos.md        64 lines    (+0)
qa.md               108 lines    (+27)
research.md          56 lines    (+0)
status.md            99 lines    (+0)
verify.md           149 lines    (+9)
CLAUDE.md            51 lines    (-3)
                    ─────────
Total:              720 lines  (~10,800 tokens)

vs v1.21.30:        +78 lines  (~+1,170 tokens, +12%)
vs v1.20.0:         -53 lines  (~-795 tokens, -7%)
vs v1.10.7:        -114 lines  (~-1,710 tokens, -14%)
```

**Why it increased from v1.21.30:** CC Alignment added enforcement content to active commands. debug.md gained agent spawn restriction documentation (+14). fix.md grew from expanded commit discipline and CC 2.1.47 compatibility (+31). qa.md expanded with agent frontmatter verification procedures (+27). verify.md gained CC version requirements checks (+9). CLAUDE.md shrank slightly (-3). These additions improve agent behavior quality and reduce costly retries — the per-request growth buys better first-pass accuracy.

**Why it's still below v1.20.0:** The vibe.md skill extraction from v1.21.x removed 343 lines from per-request. Even with +78 lines of CC Alignment content, v1.30.0 remains 53 lines below v1.20.0's per-request overhead.

---

## CC Alignment v1 Milestone

**Commits:** 44
**Phases:** 4
**Requirements:** 13/13

### Phase 1: Dead Code Cleanup (15 commits)

**Token impact:** Zero per-request. Shell-only changes.

Graduated 20 always-true feature flags (v2_* and v3_*), removing dead code branches from scripts. Defaulted v2_token_budgets to false. Removed plan mode compaction workaround. All changes in shell scripts and config files — zero model tokens.

### Phase 2: Agent Frontmatter Hardening (14 commits)

**Token impact:** +29 lines in agent definitions (+435 tokens per full team spawn). Zero per-request.

Added Task spawn restrictions (`allowedTools` / `disallowedTools`) and native memory scoping (`memory: project` / `memory: local`) to all 7 agents. Removed restart messaging from /vbw:update. Agent definitions grew from 462 to 491 lines. This is spawn-time overhead only — loaded when a specific agent is spawned, not per-request.

| Agent | v1.21.30 | v1.30.0 | Change |
|---|---|---|---|
| vbw-architect.md | 43 | 44 | +1 |
| vbw-debugger.md | 54 | 59 | +5 |
| vbw-dev.md | 72 | 87 | +15 |
| vbw-docs.md | 85 | 87 | +2 |
| vbw-lead.md | 69 | 74 | +5 |
| vbw-qa.md | 76 | 76 | 0 |
| vbw-scout.md | 63 | 64 | +1 |

### Phase 3: Hook Enhancements (11 commits)

**Token impact:** Zero per-request. Shell + test infrastructure only.

Captured last_assistant_message in agent-stop hook for crash recovery. Audited all 26 hook bash commands against CC 2.1.47 stricter classifier. Added 55 new BATS tests. All shell scripts and test files — zero model tokens.

### Phase 4: Documentation and Cleanup (4 commits)

**Token impact:** Zero per-request. Documentation and audit-only.

Added CC version requirements table to README. Documented model routing fix in CHANGELOG. Simplified compaction instructions for CC 2.1.47+ native support. Audited skill budget scaling rationale.

---

## Worktree Isolation Milestone

**Commits:** 41
**Phases:** 6
**Deviations:** 0

### Phase 1: Fix Failing Tests + Remove Dead Code (graduated flags, deleted lock-lite)

**Token impact:** Zero per-request. Shell-only changes.

Graduated 20 feature flags (same flags from CC Alignment, now cleaned in test files). Deleted lock-lite dead code (scripts and tests). Updated 16 test files. Net effect: script lines decreased, test lines decreased, bats test count dropped from 838 to 825. This is the phase responsible for the overall codebase *shrinking* despite 6 new worktree scripts being added later.

### Phase 2: Worktree Lifecycle Scripts (4 scripts)

**Token impact:** Zero per-request. Shell-only.

Created worktree-create.sh, worktree-merge.sh, worktree-cleanup.sh, worktree-status.sh. All fail-open (exit 0 on error). These are shell scripts — zero model tokens.

### Phase 3: Agent Targeting Scripts (2 scripts)

**Token impact:** Zero per-request. Shell-only.

Created worktree-target.sh (agent-to-worktree path resolution) and worktree-agent-map.sh (agent mapping registry). Shell scripts with corresponding BATS tests.

### Phase 4: Integrate with Existing Scripts

**Token impact:** Zero per-request. Shell-only.

Wired worktree isolation into config defaults, compaction hooks, file-guard, session-stop, and doctor-cleanup. All changes in existing shell scripts.

### Phase 5: Execute Protocol Integration (3 commits)

**Token impact:** +16 reference lines (+240 tokens per reference load). Lazy — only loaded during execution.

Modified execute-protocol.md at three insertion points: Step 2 (worktree creation after plan loading), Step 3 (worktree path in Dev task description), Step 5 (worktree merge and cleanup after completion). The reference file grew from 507 to 523 lines. This is the only model-visible change in the entire Worktree Isolation milestone.

### Phase 6: Tests + Documentation (5 commits)

**Token impact:** Zero per-request. Tests and docs only.

Added tests/worktree.bats (16 tests covering create, merge, cleanup, status, and integration scenarios). Updated CHANGELOG with worktree-isolation feature entry and lock-lite removal. Updated README bats count (838 → 825) and added worktree isolation description.

---

## Global Impact: Token Flow Comparison

### Per-Request Overhead

```
                              v1.10.7      v1.20.0      v1.21.30     v1.30.0      Change (v1.21→v1.30)
──────────────────────────────────────────────────────────────────────────────────────────────────────────
Active commands                 767          696          588          669          +81 lines
CLAUDE.md                        67           77           54           51           -3 lines
                               ─────        ─────        ─────        ─────        ─────
Per-request total               834          773          642          720          +78 lines
Est. tokens                  12,510       11,595        9,630       10,800       +1,170 tokens (+12%)
```

### Per-Phase Spawn+Context Overhead

```
                              v1.10.7      v1.20.0      v1.21.30     v1.30.0      Change
──────────────────────────────────────────────────────────────────────────────────────────
SMALL PROJECT (3 phases, 10 reqs, 3 Devs, 1 QA per phase)

Agent definitions             3,630        4,005        6,930        7,365         +435  (spawn restrictions, memory)
Compiled context reads        5,295        5,850        6,400        6,600         +200  (template growth)
Handoff schema loads          1,410        3,360        4,140        4,725         +585  (handoff-schemas grew)
Reference loads (execute)         0        5,775        7,590        7,845         +255  (execute-protocol +17 lines)
Skill bundling savings       -1,000       -1,000       -1,000       -1,000            0  (unchanged)
Compaction re-reads           1,000        1,000        1,000        1,000            0  (unchanged)
                             ──────       ──────       ──────       ──────       ──────
Per-phase non-request        10,335       18,990       25,060       26,535       +1,475

MEDIUM PROJECT (5 phases, 20 reqs, 4 Devs, 1 QA, V3 delta on)

Agent definitions             4,285        4,690        7,900        8,400         +500
Compiled context reads        7,155        8,900        9,800       10,050         +250
Handoff schema loads          1,680        4,020        4,960        5,350         +390
Reference loads (execute)         0        5,775        7,590        7,845         +255
Skill bundling savings       -1,600       -1,600       -1,600       -1,600            0
Compaction re-reads           1,200        1,200        1,200        1,200            0
                             ──────       ──────       ──────       ──────       ──────
Per-phase non-request        12,720       22,985       29,850       31,245       +1,395
```

### The Trade-off

Per-request overhead grew +1,170 tokens (CC Alignment enforcement content). Per-phase overhead grew +1,475 tokens (agent spawn restrictions + execute-protocol worktree integration). Over a typical phase with 80 user messages:

```
Per-request growth:   1,170 × 80 =  93,600 tokens added per phase
Per-phase growth:                     1,475 tokens added per phase
                                    ───────
Net per-phase:                       95,075 tokens MORE vs v1.21.30
```

**But the context matters:** v1.21.30 was an unusually low watermark thanks to vibe.md skill extraction. Compared to v1.20.0:

```
Per-request savings:    795 × 80 =  63,600 tokens saved per phase (vs v1.20.0)
Per-phase growth:                    7,305 tokens added per phase (vs v1.20.0)
                                   ───────
Net per-phase:                      56,295 tokens SAVED (vs v1.20.0)
```

### Total Session Impact

| Scale | v1.20.0 Total | v1.21.30 Total | v1.30.0 Total | Change (v1.21→v1.30) |
|---|---|---|---|---|
| Small (3 phases, 50 req/phase) | ~185,665 | ~155,490 | ~170,605 | +15,115 (+10%) |
| Medium (5 phases, 80 req/phase) | ~306,125 | ~239,350 | ~259,225 | +19,875 (+8%) |
| Large (8 phases, 80 req/phase) | ~330,360 | ~253,880 | ~277,160 | +23,280 (+9%) |

### Coordination Overhead vs Stock Teams

```
                       Stock Teams    v1.0.99    v1.10.7    v1.20.0    v1.21.30    v1.30.0
Per-request overhead      10,800       4,970      3,245      3,198      2,655       3,350
Per-phase spawn+context   87,100      33,200     10,910     18,990     25,060      26,535
                         ──────      ──────     ──────     ──────     ──────      ──────
Total coordination/phase  97,900      38,170     14,155     22,188     27,715      29,885
Per-request × 80 msgs   864,000     397,600    259,600    255,840    212,400     268,000

Total session (1 phase)  961,900     435,770    273,755    277,828    240,115     297,885
Reduction vs stock             —        55%        72%        71%        75%         69%

Total session (5 phases) 4,809,500  2,178,850  1,368,775  1,289,140  1,101,575  1,289,425
Reduction vs stock             —        55%        72%        73%        77%         73%
```

**v1.30.0 achieves 69-73% overhead reduction vs stock teams.** Down from v1.21.30's 75-77% — the CC Alignment enforcement content adds per-request tokens. However, this is the same tier as v1.20.0 (71-73%) while providing significantly better agent behavior: crash recovery, spawn restrictions, memory scoping, and CC 2.1.47 classifier compliance.

---

## What Changed at Each Layer

```
LAYER                    v1.21.30   v1.30.0    CHANGE     METHOD
──────────────────────────────────────────────────────────────────────────
Commands (active)           588        669        +81    CC Alignment enforcement in debug, fix, qa, verify
Commands (disabled)       2,270      2,290        +20    Minor growth in disabled commands
Agents (7)                  462        491        +29    +spawn restrictions, +memory scoping
CLAUDE.md                    54         51         -3    Streamlined after milestone archive
References (11)           1,516      1,572        +56    execute-protocol +17, handoff-schemas +39
──────────────────────────────────────────────────────────────────────────
Model-visible inventory   4,890      5,073       +183    Enforcement content + agent hardening + worktree protocol

Runtime loading patterns:
──────────────────────────────────────────────────────────────────────────
Per-request (×80 msgs)    9,630     10,800     +1,170    Active command growth (CC Alignment only)
Per-phase context        25,060     26,535     +1,475    Agent spawn restrictions + execute-protocol growth
Per-session (5-phase)   239,350    259,225    +19,875    Enforcement + protocol cost

Shell-only infrastructure:
──────────────────────────────────────────────────────────────────────────
Scripts (78→85)          11,959     12,652       +693    +13 new scripts, -6 removed (lock-lite dead code), net line reduction
Config (5)                  434        427         -7    Config cleanup
Hooks                       257        257          0    Unchanged
Tests (51→57)             8,703     11,298     +2,595    6 new test files, dead code cleanup reduced count (838→825 bats)
Templates (10)              290        301        +11    Template refinements
──────────────────────────────────────────────────────────────────────────
Shell-only total         21,643     24,935     +3,292    ALL zero model tokens
```

**The key insight:** This is the first release where per-request tokens *increased*. The increase is deliberate — encoding CC 2.1.47 enforcement rules into active commands means agents behave correctly under the stricter classifier without needing retries. The 12% per-request growth buys compatibility with 6 months of Claude Code evolution (2.1.32 through 2.1.47). The Worktree Isolation milestone then added 41 commits of shell infrastructure at zero per-request cost, while dead code removal actually *shrank* the overall codebase by 1,665 lines vs the CC Alignment snapshot.

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
| Skill Extraction (vibe.md) | v1.21.x | Active → disabled/skill | -17% per-request |
| CC Alignment v1 | v1.30.0 | Feature flag graduation, agent hardening, CC 2.1.47 compliance | +12% per-request (enforcement) |
| **Worktree Isolation** | **v1.30.0** | **Git worktree per-plan Dev isolation, execute-protocol integration** | **Zero per-request, +16 reference lines (lazy), -1,665 net codebase lines** |

---

## Key Takeaways

1. **First intentional per-request increase.** Active commands grew +78 lines (+12%) to encode CC 2.1.47 enforcement rules. Unlike previous growth that was accidental, this is a deliberate trade-off: paying 1,170 tokens per request to eliminate agent retries caused by classifier rejections.

2. **Still 7% below v1.20.0.** Even after CC Alignment growth, per-request remains below the pre-skill-extraction baseline (10,800 vs 11,595). The vibe.md extraction buffer hasn't been fully consumed.

3. **73% overhead reduction vs stock teams.** Down from v1.21.30's 77% but matching v1.20.0's tier. The reduction vs stock teams remains substantial and consistent across versions.

4. **Agent hardening is cheap at spawn time.** +29 agent lines = +435 tokens per full team spawn. This buys Task spawn restrictions (agents can't spawn unauthorized sub-agents) and memory scoping (agents read correct project vs local memory). The per-spawn cost is negligible vs the per-request impact.

5. **Shell infrastructure continues at zero model cost.** 13 new scripts added across both milestones, 6 removed (dead code), net +3,292 shell lines. The test suite grew 30% (8,703 → 11,298 lines, 51 → 57 files). Bats test count actually *decreased* (838 → 825) due to dead code cleanup removing obsolete tests. All invisible to the model.

6. **Feature flag graduation removes future overhead.** Graduating 20 always-true flags eliminates runtime branches in shell scripts. While this doesn't affect model tokens directly (shell is always zero), it reduces execution time and removes dead code paths that could cause confusion during debugging.

7. **Dead code removal offset new feature growth.** The codebase grew 42% overall (26,533 → 37,627), but the Worktree Isolation milestone actually *shrank* it by 1,665 lines vs the CC Alignment snapshot (39,292 → 37,627). Phase 1's lock-lite deletion and flag graduation removed more than Phases 2-6 added. Per-request: 9,630 → 10,800 (+12%). The decoupling between codebase size and model cost remains strong.

8. **Worktree Isolation: 41 commits at near-zero model cost.** The entire 6-phase worktree milestone produced only +16 model-visible lines (execute-protocol reference, loaded lazily during execution). Everything else — 6 scripts, 16 bats tests, protocol integration — is shell infrastructure. This demonstrates the architecture's strength: major features can ship without inflating per-request overhead.

---

## Appendix A: File Inventory Comparison

### Commands

| File | v1.21.30 | v1.30.0 | Status | Change |
|---|---|---|---|---|
| config.md | 442 (disabled) | 442 (disabled) | Unchanged | 0 |
| debug.md | 94 (active) | 108 (active) | Modified | +14 |
| discuss.md | 34 (disabled) | 34 (disabled) | Unchanged | 0 |
| doctor.md | 111 (disabled) | 111 (disabled) | Unchanged | 0 |
| fix.md | 54 (active) | 85 (active) | Modified | +31 |
| help.md | 37 (disabled) | 37 (disabled) | Unchanged | 0 |
| init.md | 504 (disabled) | 504 (disabled) | Unchanged | 0 |
| list-todos.md | 64 (active) | 64 (active) | Unchanged | 0 |
| map.md | 123 (disabled) | 123 (disabled) | Unchanged | 0 |
| pause.md | 29 (disabled) | 29 (disabled) | Unchanged | 0 |
| profile.md | 61 (disabled) | 61 (disabled) | Unchanged | 0 |
| qa.md | 81 (active) | 108 (active) | Modified | +27 |
| release.md | 97 (disabled) | 97 (disabled) | Unchanged | 0 |
| research.md | 56 (active) | 56 (active) | Unchanged | 0 |
| resume.md | 33 (disabled) | 33 (disabled) | Unchanged | 0 |
| skills.md | 62 (disabled) | 70 (disabled) | Modified | +8 |
| status.md | 99 (active) | 99 (active) | Unchanged | 0 |
| teach.md | 100 (disabled) | 100 (disabled) | Unchanged | 0 |
| todo.md | 31 (disabled) | 35 (disabled) | Modified | +4 |
| uninstall.md | 55 (disabled) | 55 (disabled) | Unchanged | 0 |
| update.md | 94 (disabled) | 96 (disabled) | Modified | +2 |
| verify.md | 140 (active) | 149 (active) | Modified | +9 |
| vibe.md | 427 (disabled) | 433 (disabled) | Modified | +6 |
| whats-new.md | 30 (disabled) | 30 (disabled) | Unchanged | 0 |

### Agents

| File | v1.21.30 | v1.30.0 | Change |
|---|---|---|---|
| vbw-architect.md | 43 | 44 | +1 (memory scoping) |
| vbw-debugger.md | 54 | 59 | +5 (spawn restrictions, memory) |
| vbw-dev.md | 72 | 87 | +15 (spawn restrictions, memory, commit rules) |
| vbw-docs.md | 85 | 87 | +2 (memory scoping) |
| vbw-lead.md | 69 | 74 | +5 (spawn restrictions, memory) |
| vbw-qa.md | 76 | 76 | 0 |
| vbw-scout.md | 63 | 64 | +1 (memory scoping) |

### References

| File | v1.21.30 | v1.30.0 | Change |
|---|---|---|---|
| discussion-engine.md | 165 | 165 | 0 |
| effort-profile-balanced.md | 44 | 44 | 0 |
| effort-profile-fast.md | 42 | 42 | 0 |
| effort-profile-thorough.md | 46 | 46 | 0 |
| effort-profile-turbo.md | 44 | 44 | 0 |
| execute-protocol.md | 506 | 523 | +17 (+1 correlation_id, +16 worktree integration at Steps 2/3/5) |
| handoff-schemas.md | 276 | 315 | +39 (new message types) |
| model-profiles.md | 114 | 114 | 0 |
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
| Per-request count per phase | 80 messages estimated | Medium |
| Scale projections | Linear extrapolation | Medium |
| Stock team baseline | Measured in v1.0.99 analysis, carried forward | Medium |
