# Changelog

All notable changes to VBW will be documented in this file.

## [1.0.20] - 2026-02-07

### Added

- Real-time statusline dashboard: context window bar, API usage limits (session/weekly/sonnet/extra), cost tracking, clickable GitHub link, agent team status
- Manifesto section and Discord invite in README
- Statusline screenshot showcase in README Features section

### Changed

- Renamed `/vbw:build` to `/vbw:execute` to avoid security filter collision with `build/` pattern
- Moved directory scaffold into Step 0 of `/vbw:init` so all setup completes before user questions
- Versioned cache filenames in statusline -- auto-clears stale caches on plugin update
- Simplified `/vbw:whats-new` to read directly from plugin root instead of cache paths (fixes sandbox permission errors)
- Improved `/vbw:update` messaging to clarify "since" version in whats-new suggestion

### Fixed

- Security filter no longer blocks `skills/build/SKILL.md` (resolved by rename to `skills/execute/`)
- Usage limits API: added required `anthropic-beta: oauth-2025-04-20` header
- Extra usage credits display: correctly converts cents to dollars
- Statusline `utilization` field: removed erroneous x100 (API returns 0-100, not 0-1)
- Weekly countdown now shows days when >= 24 hours
- Removed hardcoded `/vbw:plan 1` references (auto-detection handles phase selection)

## [1.0.0] - 2026-02-07

### Added

- Complete agent system: Scout, Architect, Lead, Dev, QA, Debugger with tool permissions and effort profiles
- Full command suite: 25 commands covering lifecycle, monitoring, supporting, and advanced operations
- Codebase mapping with parallel mapper agents, synthesis (INDEX.md, PATTERNS.md), and incremental refresh
- Branded visual output: Unicode box-drawing, semantic symbols, progress bars, graceful degradation
- Skills integration: stack detection, skill discovery, auto-install suggestions, agent skill awareness
- Concurrent milestones with isolated state, switching, shipping, and phase management
- Persistent memory: CLAUDE.md generation, pattern learning, session pause/resume
- Resilience: three-tier verification pipeline, failure recovery, intra-plan resume, observability
- Version management: /vbw:whats-new changelog viewer, /vbw:update plugin updater
- Effort profiles: Thorough, Balanced, Fast, Turbo controlling agent behavior
- Deviation handling: auto-fix minor, auto-add critical, auto-resolve blocking, checkpoint architectural

### Changed

- Expanded from 3 foundational commands to 25 complete commands
- VERSION bumped from 0.1.0 to 1.0.0

## [0.1.0] - 2026-02-06

### Added

- Initial plugin structure with plugin.json and marketplace.json
- Directory layout (skills/, agents/, references/, templates/, config/)
- Foundational commands: /vbw:init, /vbw:config, /vbw:help
- Artifact templates for PLAN.md, SUMMARY.md, VERIFICATION.md, PROJECT.md, STATE.md, REQUIREMENTS.md, ROADMAP.md
- Agent definition stubs for 6 agents
