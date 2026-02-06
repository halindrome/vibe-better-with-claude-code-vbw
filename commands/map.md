---
description: Analyze existing codebase with parallel mapper agents to produce structured mapping documents.
argument-hint: [--incremental] [--package=name]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Map: $ARGUMENTS

## Context

Working directory: `!`pwd``

Existing codebase mapping:
```
!`ls .planning/codebase/ 2>/dev/null || echo "No codebase mapping found"`
```

Current META.md:
```
!`cat .planning/codebase/META.md 2>/dev/null || echo "No META.md found"`
```

Git status:
```
!`git rev-parse --is-inside-work-tree 2>/dev/null && echo "Git repo: yes" || echo "Git repo: no"`
```

Current HEAD:
```
!`git rev-parse HEAD 2>/dev/null || echo "no-git"`
```

Project files detected:
```
!`ls package.json pyproject.toml Cargo.toml go.mod *.sln Gemfile build.gradle pom.xml 2>/dev/null || echo "No standard project files found"`
```

Tracked files (sample):
```
!`git ls-files 2>/dev/null || echo "Not a git repo"`
```

Current effort setting:
```
!`cat .planning/config.json 2>/dev/null || echo "No config found"`
```

## Guard

1. **Not initialized:** If .planning/ directory doesn't exist, STOP: "Run /vbw:init first."
2. **No git repo:** If not inside a git repository, WARN: "Not a git repo -- git hash tracking and incremental mapping disabled." Continue with full mapping mode.
3. **Empty project:** If no source files detected (no recognized project files and `git ls-files` returns 0 or git is unavailable and no common source directories exist), STOP: "No source code found to map."

## Steps

### Step 1: Detect incremental vs full mapping (CMAP-05)

Determine whether to perform a full mapping or an incremental refresh.

**Decision logic:**

1. Check if `.planning/codebase/META.md` exists
2. If META.md exists AND (`--incremental` flag is present OR no flag was provided):
   - Read the `git_hash` field from META.md frontmatter
   - Get the list of changed files since that hash:
     ```
     git diff --name-only {stored_hash}..HEAD
     ```
   - Count changed files relative to total tracked files
   - If changed files < 20% of total tracked files: **incremental mode**
     - Store the changed file list for mapper agents
     - Mappers will update only sections affected by changed files
   - If changed files >= 20% of total tracked files: **full mode**
     - Too many changes for incremental -- full rescan is more reliable
3. If META.md does not exist: **full mode** (first mapping)
4. If not a git repo: **full mode** (no diff capability)

Store the result:
- `MAPPING_MODE`: "full" or "incremental"
- `CHANGED_FILES`: list of changed file paths (empty if full mode)

### Step 2: Security enforcement (CMAP-10)

Define the security exclusion list. This list is mandatory for ALL mapper agents -- it is NOT optional and cannot be overridden.

```
SECURITY_EXCLUSIONS:
- .env, .env.*, .env.local, .env.production, .env.development
- *.pem, *.key, *.cert, *.p12, *.pfx
- credentials.json, secrets.json, service-account*.json
- **/node_modules/**, **/.git/**, **/dist/**, **/build/**
- Any file matching patterns in .gitignore
```

Every mapper agent prompt MUST include the following instruction verbatim:

> "NEVER read files matching these patterns: .env, .env.*, .env.local, .env.production, .env.development, *.pem, *.key, *.cert, *.p12, *.pfx, credentials.json, secrets.json, service-account*.json, node_modules/, .git/, dist/, build/. If a file path matches any exclusion pattern, skip it entirely. Do not report its contents. Additionally, respect all patterns listed in the project's .gitignore file."

### Step 3: Detect monorepo structure (CMAP-06)

Check for monorepo indicators:

1. `lerna.json` exists
2. `pnpm-workspace.yaml` exists
3. `packages/` directory exists with subdirectories containing their own package.json
4. `apps/` directory exists with subdirectories containing their own package.json
5. Root `package.json` contains a `workspaces` field

**If monorepo detected:**
- Set `MONOREPO=true`
- Enumerate all packages (name, path, has own package.json)
- If `--package=name` flag provided: scope mapping to that single package only
- Otherwise: map each package individually, then produce a cross-package INDEX.md section

**If not monorepo:**
- Set `MONOREPO=false`
- Proceed with standard single-project mapping

### Step 4: Spawn 4 parallel mapper agents (CMAP-01)

Spawn 4 mapper agents IN PARALLEL using the Task tool. Each mapper uses the Scout agent as its base definition with a specialized prompt prefix.

**Spawning protocol (for each mapper):**

1. Read `${CLAUDE_PLUGIN_ROOT}/agents/vbw-scout.md` using the Read tool
2. Extract the body content (everything after the closing `---` of the YAML frontmatter)
3. Use the **Task tool** to spawn the mapper:
   - `prompt`: The extracted body content of vbw-scout.md (Scout system prompt)
   - `description`: The mapper-specific prompt below, which includes:
     - The mapper's focus area and output documents
     - The security exclusion list from Step 2 (verbatim)
     - The mapping mode from Step 1 (full or incremental + changed file list)
     - The monorepo context from Step 3 (scope and package list)
     - The output directory: `.planning/codebase/`

All 4 Task tool calls are made in a single response so they execute in parallel.

---

**Mapper 1 -- Tech Stack Mapper**

Focus: Technology detection, dependency analysis, framework identification.

Produces:
- `STACK.md` -- Frameworks, languages, build tools, runtime versions, CI/CD pipeline
- `DEPENDENCIES.md` -- Dependency graph, version constraints, known vulnerability patterns, outdated packages

Prompt for mapper description:

> You are a Tech Stack Mapper. Your job is to analyze this codebase and produce two documents in the `.planning/codebase/` directory.
>
> SECURITY: NEVER read files matching these patterns: .env, .env.*, .env.local, .env.production, .env.development, *.pem, *.key, *.cert, *.p12, *.pfx, credentials.json, secrets.json, service-account*.json, node_modules/, .git/, dist/, build/. If a file path matches any exclusion pattern, skip it entirely. Do not report its contents. Additionally, respect all patterns listed in the project's .gitignore file.
>
> MODE: {MAPPING_MODE}. {If incremental: "Only analyze these changed files: {CHANGED_FILES}. Update existing documents rather than rewriting from scratch." If full: "Perform a complete scan of the entire codebase."}
>
> MONOREPO: {MONOREPO}. {If true and package-scoped: "Scope analysis to package: {package_name} at {package_path}." If true and not scoped: "Analyze each package separately and note cross-package dependencies."}
>
> **Scan targets:** package.json, pyproject.toml, Cargo.toml, go.mod, *.sln, Gemfile, build.gradle, pom.xml, Dockerfile, docker-compose.yml, CI configs (.github/workflows/, .gitlab-ci.yml, .circleci/), Makefile, tsconfig.json, webpack.config.*, vite.config.*, .babelrc, .eslintrc.*
>
> **STACK.md must contain:**
> - Primary language(s) and version requirements
> - Frameworks (frontend, backend, testing, utility)
> - Build tools and bundlers
> - Runtime requirements (Node version, Python version, etc.)
> - CI/CD pipeline description
> - Infrastructure (Docker, cloud configs if present)
>
> **DEPENDENCIES.md must contain:**
> - Production dependencies with version constraints
> - Development dependencies with version constraints
> - Dependency relationships (which deps depend on which)
> - Outdated or deprecated packages (if detectable)
> - Known vulnerability patterns (common CVE-prone packages)
>
> Write both documents to `.planning/codebase/` using the Write tool.

---

**Mapper 2 -- Architecture Mapper**

Focus: Code organization, architectural patterns, module boundaries, data flow.

Produces:
- `ARCHITECTURE.md` -- Layer structure, module graph, API surface, data flow patterns
- `STRUCTURE.md` -- Directory tree with annotations, file type distribution, naming patterns

Prompt for mapper description:

> You are an Architecture Mapper. Your job is to analyze this codebase and produce two documents in the `.planning/codebase/` directory.
>
> SECURITY: NEVER read files matching these patterns: .env, .env.*, .env.local, .env.production, .env.development, *.pem, *.key, *.cert, *.p12, *.pfx, credentials.json, secrets.json, service-account*.json, node_modules/, .git/, dist/, build/. If a file path matches any exclusion pattern, skip it entirely. Do not report its contents. Additionally, respect all patterns listed in the project's .gitignore file.
>
> MODE: {MAPPING_MODE}. {If incremental: "Only analyze these changed files: {CHANGED_FILES}. Update existing documents rather than rewriting from scratch." If full: "Perform a complete scan of the entire codebase."}
>
> MONOREPO: {MONOREPO}. {If true and package-scoped: "Scope analysis to package: {package_name} at {package_path}." If true and not scoped: "Analyze each package separately and document inter-package boundaries."}
>
> **Scan targets:** Directory structure (via Glob), import/export statements (via Grep), route definitions, middleware chains, configuration files, entry points (main/index files), API endpoint definitions
>
> **ARCHITECTURE.md must contain:**
> - High-level architecture pattern (MVC, layered, microservices, monolith, etc.)
> - Module/layer structure with dependency directions
> - API surface (endpoints, routes, public interfaces)
> - Data flow (request lifecycle, state management, persistence layer)
> - Key architectural decisions visible in code structure
> - Entry points and bootstrap sequence
>
> **STRUCTURE.md must contain:**
> - Annotated directory tree (purpose of each top-level directory)
> - File type distribution (how many .ts, .py, .md, etc.)
> - Naming conventions observed (kebab-case files, PascalCase components, etc.)
> - Key files and their roles (config files, entry points, shared utilities)
> - File organization pattern (feature-based, layer-based, hybrid)
>
> Write both documents to `.planning/codebase/` using the Write tool.

---

**Mapper 3 -- Quality Mapper**

Focus: Code quality signals, testing patterns, coding conventions.

Produces:
- `CONVENTIONS.md` -- Naming patterns, file organization rules, code style, common idioms
- `TESTING.md` -- Test framework, coverage patterns, test file locations, testing conventions

Prompt for mapper description:

> You are a Quality Mapper. Your job is to analyze this codebase and produce two documents in the `.planning/codebase/` directory.
>
> SECURITY: NEVER read files matching these patterns: .env, .env.*, .env.local, .env.production, .env.development, *.pem, *.key, *.cert, *.p12, *.pfx, credentials.json, secrets.json, service-account*.json, node_modules/, .git/, dist/, build/. If a file path matches any exclusion pattern, skip it entirely. Do not report its contents. Additionally, respect all patterns listed in the project's .gitignore file.
>
> MODE: {MAPPING_MODE}. {If incremental: "Only analyze these changed files: {CHANGED_FILES}. Update existing documents rather than rewriting from scratch." If full: "Perform a complete scan of the entire codebase."}
>
> MONOREPO: {MONOREPO}. {If true and package-scoped: "Scope analysis to package: {package_name} at {package_path}." If true and not scoped: "Analyze each package separately and note convention differences between packages."}
>
> **Scan targets:** Source files for naming patterns (via Grep), test files (*.test.*, *.spec.*, test/, __tests__/), linting configs (.eslintrc.*, .prettierrc.*, .stylelintrc.*), formatting configs (.editorconfig, .prettierrc), type configs (tsconfig.json, mypy.ini, pyrightconfig.json)
>
> **CONVENTIONS.md must contain:**
> - Naming conventions (variables, functions, classes, files, directories)
> - Import organization patterns (grouping, ordering)
> - Code style rules (from linting/formatting configs or observed patterns)
> - Common idioms and patterns used throughout the codebase
> - Error handling conventions
> - Documentation conventions (JSDoc, docstrings, README patterns)
>
> **TESTING.md must contain:**
> - Test framework(s) in use (Jest, pytest, Go testing, etc.)
> - Test file location pattern (co-located, separate test/ directory, both)
> - Test naming conventions
> - Testing patterns (unit, integration, e2e -- which are present)
> - Coverage configuration (if present)
> - Test utilities and helpers (shared fixtures, factories, mocks)
> - CI test execution (how tests run in CI)
>
> Write both documents to `.planning/codebase/` using the Write tool.

---

**Mapper 4 -- Concerns Mapper**

Focus: Technical debt, risks, security patterns, known issues.

Produces:
- `CONCERNS.md` -- Technical debt, TODO/FIXME density, complexity hotspots, potential risks, missing error handling

Prompt for mapper description:

> You are a Concerns Mapper. Your job is to analyze this codebase and produce one document in the `.planning/codebase/` directory.
>
> SECURITY: NEVER read files matching these patterns: .env, .env.*, .env.local, .env.production, .env.development, *.pem, *.key, *.cert, *.p12, *.pfx, credentials.json, secrets.json, service-account*.json, node_modules/, .git/, dist/, build/. If a file path matches any exclusion pattern, skip it entirely. Do not report its contents. Additionally, respect all patterns listed in the project's .gitignore file.
>
> MODE: {MAPPING_MODE}. {If incremental: "Only analyze these changed files: {CHANGED_FILES}. Update existing documents rather than rewriting from scratch." If full: "Perform a complete scan of the entire codebase."}
>
> MONOREPO: {MONOREPO}. {If true and package-scoped: "Scope analysis to package: {package_name} at {package_path}." If true and not scoped: "Analyze each package separately and flag cross-package concerns."}
>
> **Scan targets:** Source files for TODO/FIXME/HACK/WORKAROUND/XXX comments (via Grep), functions with high line counts (complexity indicators), error handling patterns (try/catch density, unhandled promises), deprecated API usage, console.log/print statements left in production code, hardcoded values that should be configurable
>
> **CONCERNS.md must contain:**
> - Technical debt inventory (TODO/FIXME/HACK comments with file locations)
> - Complexity hotspots (files or functions that are unusually large or complex)
> - Missing error handling (unhandled promise rejections, bare except clauses, missing try/catch)
> - Security concerns (hardcoded secrets patterns, SQL injection risks, XSS vectors -- document patterns, not actual secrets)
> - Deprecated or outdated patterns in use
> - Risk assessment (high/medium/low for each concern category)
> - Recommended priorities for addressing concerns
>
> Write the document to `.planning/codebase/` using the Write tool.

---

**After all 4 mapper agents complete:**

Verify that the expected documents exist in `.planning/codebase/`:
- STACK.md (from Tech Stack Mapper)
- DEPENDENCIES.md (from Tech Stack Mapper)
- ARCHITECTURE.md (from Architecture Mapper)
- STRUCTURE.md (from Architecture Mapper)
- CONVENTIONS.md (from Quality Mapper)
- TESTING.md (from Quality Mapper)
- CONCERNS.md (from Concerns Mapper)

If any document is missing, report which mapper failed and what document was not produced. Do not proceed to synthesis until all 7 documents exist.

### Step 5: Synthesis -- produce INDEX.md and PATTERNS.md (CMAP-02)

After all 4 mapper agents complete and all 7 documents are verified, the parent command (not a subagent) performs synthesis by reading all mapper outputs and producing two cross-referencing documents.

**5a. Create INDEX.md**

Read all 7 mapping documents from `.planning/codebase/`. Create `.planning/codebase/INDEX.md` containing:

```markdown
# Codebase Mapping Index

## Documents

### STACK.md
**Covers:** Technology stack, frameworks, languages, build tools, runtimes
**Key findings:**
- {2-3 line summary of most important findings}
**Cross-references:** DEPENDENCIES.md (version constraints), ARCHITECTURE.md (framework usage in modules), TESTING.md (test framework)

### DEPENDENCIES.md
**Covers:** Dependency graph, version constraints, vulnerability patterns
**Key findings:**
- {2-3 line summary}
**Cross-references:** STACK.md (framework versions), CONCERNS.md (outdated dependencies)

### ARCHITECTURE.md
**Covers:** Code organization, layers, modules, API surface, data flow
**Key findings:**
- {2-3 line summary}
**Cross-references:** STRUCTURE.md (directory layout), CONVENTIONS.md (naming patterns), STACK.md (framework architecture)

### STRUCTURE.md
**Covers:** Directory tree, file types, naming patterns, file organization
**Key findings:**
- {2-3 line summary}
**Cross-references:** ARCHITECTURE.md (module boundaries), CONVENTIONS.md (naming rules)

### CONVENTIONS.md
**Covers:** Naming conventions, code style, idioms, documentation patterns
**Key findings:**
- {2-3 line summary}
**Cross-references:** STRUCTURE.md (file naming), TESTING.md (test naming), CONCERNS.md (convention violations)

### TESTING.md
**Covers:** Test framework, coverage, test locations, testing patterns
**Key findings:**
- {2-3 line summary}
**Cross-references:** STACK.md (test framework dependency), CONVENTIONS.md (test naming conventions), CONCERNS.md (coverage gaps)

### CONCERNS.md
**Covers:** Technical debt, complexity hotspots, risks, missing error handling
**Key findings:**
- {2-3 line summary}
**Cross-references:** ARCHITECTURE.md (complexity in modules), DEPENDENCIES.md (vulnerable packages), CONVENTIONS.md (style violations)
```

Populate the key findings and cross-references by actually reading the mapper outputs -- do not use placeholder text.

**5b. Create PATTERNS.md**

Read all 7 mapping documents and extract recurring patterns that appear across multiple mapper outputs. Create `.planning/codebase/PATTERNS.md` containing:

```markdown
# Codebase Patterns

Recurring patterns observed across multiple mapping documents.

## Architectural Patterns
- {Pattern name}: {description} (observed in: ARCHITECTURE.md, STRUCTURE.md)
- Examples: MVC, event-driven, microservices, layered, hexagonal, serverless

## Naming Conventions
- {Pattern name}: {description} (observed in: CONVENTIONS.md, STRUCTURE.md)
- Examples: camelCase files, PascalCase components, snake_case modules, kebab-case routes

## Quality Patterns
- {Pattern name}: {description} (observed in: TESTING.md, CONVENTIONS.md)
- Examples: tests co-located with source, barrel exports, error boundary pattern, factory test helpers

## Concern Patterns
- {Pattern name}: {description} (observed in: CONCERNS.md, ARCHITECTURE.md)
- Examples: inconsistent error handling in /api/, no input validation in controllers, TODO clusters in legacy modules

## Dependency Patterns
- {Pattern name}: {description} (observed in: DEPENDENCIES.md, STACK.md)
- Examples: pinned major versions, workspace hoisting, shared utility packages
```

Populate with actual patterns extracted from mapper outputs.

### Step 6: Cross-document validation (CMAP-03)

After synthesis, validate consistency across mapper outputs. Check for contradictions:

1. **Stack vs Architecture:** Compare STACK.md framework list against ARCHITECTURE.md module references. If STACK.md lists a framework that ARCHITECTURE.md doesn't reference in any module, flag it.
2. **Conventions vs Structure:** Compare CONVENTIONS.md naming patterns against STRUCTURE.md actual file names. If conventions describe a pattern that structure contradicts, flag it.
3. **Testing vs Stack:** Compare TESTING.md test framework against STACK.md dependencies. If TESTING.md references a test framework not in STACK.md's dependency list, flag it.
4. **Concerns vs Architecture:** If CONCERNS.md flags complexity in a module that ARCHITECTURE.md describes as simple, flag the contradiction.

Add a "Validation Notes" section at the end of INDEX.md:

```markdown
## Validation Notes

{If no contradictions found:}
No contradictions detected between mapper outputs.

{If contradictions found:}
### Warnings
- ⚠ {Description of contradiction between Document A and Document B}
- ⚠ {Description of contradiction}
```

### Step 7: Create META.md (CMAP-04)

Write `.planning/codebase/META.md` for staleness tracking:

```markdown
---
mapped_at: {ISO 8601 timestamp, e.g., 2026-02-06T15:30:00Z}
git_hash: {current HEAD hash from git rev-parse HEAD, or "no-git" if not a git repo}
file_count: {total source files scanned across all mappers}
documents:
  - STACK.md
  - DEPENDENCIES.md
  - ARCHITECTURE.md
  - STRUCTURE.md
  - CONVENTIONS.md
  - TESTING.md
  - CONCERNS.md
  - INDEX.md
  - PATTERNS.md
mode: {full or incremental}
monorepo: {true or false}
packages: [{comma-separated list of package names if monorepo, empty list otherwise}]
refresh_trigger: "Run /vbw:map --incremental when git diff shows >10 changed files since last mapping"
---

# Codebase Mapping Metadata

Last mapped: {human-readable date}
Mode: {full or incremental}
Files scanned: {count}
Documents produced: 9

## Staleness Indicators

- If more than 50 commits since mapping: consider full refresh
- If more than 20% of files changed: full refresh recommended
- If only config/dependency changes: incremental sufficient
- Check with: `git rev-list {git_hash}..HEAD --count`

## Refresh Commands

- Full refresh: `/vbw:map`
- Incremental refresh: `/vbw:map --incremental`
- Single package: `/vbw:map --package=name`
```

### Step 8: Present mapping summary

Display mapping completion using @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md formatting.

```
╔══════════════════════════════════════════╗
║  Codebase Mapped                         ║
║  Mode: {full | incremental}              ║
╚══════════════════════════════════════════╝
```

List all produced documents:
```
✓ STACK.md          -- Tech stack and frameworks
✓ DEPENDENCIES.md   -- Dependency graph and versions
✓ ARCHITECTURE.md   -- Code organization and data flow
✓ STRUCTURE.md      -- Directory tree and file patterns
✓ CONVENTIONS.md    -- Naming rules and code style
✓ TESTING.md        -- Test framework and coverage
✓ CONCERNS.md       -- Technical debt and risks
✓ INDEX.md          -- Cross-referenced document index
✓ PATTERNS.md       -- Recurring codebase patterns
```

Show key findings summary (3-5 bullet points extracted from INDEX.md):
```
Key Findings:
  ◆ {Finding 1 from INDEX.md}
  ◆ {Finding 2 from INDEX.md}
  ◆ {Finding 3 from INDEX.md}
```

If incremental mode was used:
```
Incremental Refresh:
  ◆ {N} files changed since last mapping
  ◆ Documents updated: {list of affected documents}
  ◆ Documents unchanged: {list of unaffected documents}
```

If validation found warnings:
```
⚠ Validation Notes:
  ⚠ {Warning 1}
  ⚠ {Warning 2}
```

Next steps:
```
➜ Next Up: Run /vbw:plan {next-phase} to plan with codebase context.
```

### Step 9: Post-mapping security verification (CMAP-10)

After all documents are written and the summary is displayed, perform a post-mapping safety check.

Search all produced mapping documents for common secret patterns:

1. Read each `.planning/codebase/*.md` file
2. Search for these patterns using Grep:
   - `API_KEY=` or `api_key:` followed by an actual value (not a placeholder)
   - `SECRET=` or `secret:` followed by an actual value
   - `PASSWORD=` or `password:` followed by an actual value
   - `PRIVATE_KEY` followed by actual key content (BEGIN PRIVATE KEY)
   - `Bearer ` followed by an actual token (long alphanumeric string)
   - Actual `.env` file contents (lines matching `KEY=value` patterns from env files)

3. **If a match is found** that appears to reference actual secret file contents (not just documenting patterns like "error handling for missing API_KEY"):
   - Log a warning: "⚠ Potential secret content detected in {document}. Review and redact if necessary."
   - Do NOT automatically delete the document -- let the user review

4. **If no matches found:**
   - Log: "✓ Security check passed -- no secret content detected in mapping documents."

This is a safety net, not the primary enforcement. The primary enforcement is the security exclusion list injected into every mapper prompt in Step 2.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand.md for all visual formatting:
- Double-line box (╔═╗║╚═╝) for mapping completion banner
- Checkmark (✓) for each produced document
- Diamond (◆) for key findings
- Warning (⚠) for validation notes and security concerns
- Arrow (➜) for Next Up navigation
- No ANSI color codes
