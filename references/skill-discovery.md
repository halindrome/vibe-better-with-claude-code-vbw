# Skill Discovery Protocol

## Overview

VBW discovers installed Claude Code skills, analyzes the project stack, suggests relevant skills from a curated mapping, and falls back to the Skills.sh registry for stacks not covered by curated mappings. It maintains a persistent capability map in `.vbw-planning/STATE.md`. This protocol is the single source of truth for how skills are discovered, suggested, and tracked across all VBW commands and agents.

Skill behavior is controlled by two config settings:
- `skill_suggestions` (default: true) -- controls whether skills are suggested during init and planning
- `auto_install_skills` (default: false) -- controls whether suggested skills are auto-installed without prompting

## Discovery Protocol

**(SKIL-01)** Scan for installed skills in three locations, in order:

### 1. Global skills

Scan `~/.claude/skills/` for directories containing skill definitions (e.g., SKILL.md or similar). Each directory name is a skill identifier (e.g., `nextjs-skill`, `testing-skill`). Record each as scope: `global`.

### 2. Project skills

Scan `.claude/skills/` in the project root for project-scoped skills. These override or supplement global skills. Record each as scope: `project`.

### 3. MCP tools

Check `.claude/mcp.json` (if it exists) for configured MCP servers. Each server name represents an available tool capability. Record each as scope: `mcp`.

### Skill record format

For each discovered skill, record:
- **name:** The directory name or server name (e.g., `nextjs-skill`)
- **scope:** One of `global`, `project`, or `mcp`
- **path:** Full path to the skill directory or MCP config entry

## find-skills Bootstrap

**(SKIL-06)** The `find-skills` meta-skill enables dynamic registry lookups via Skills.sh. It is checked once per session and its availability is cached.

### Procedure

1. Check if `find-skills` is installed:
   ```bash
   ls ~/.claude/skills/find-skills/ 2>/dev/null
   ```
2. If **installed**: mark `find_skills_available = true` for the session. Dynamic discovery (SKIL-07) can use it.
3. If **not installed** and `skill_suggestions` is `true`: display a brief note:
   ```
   ○ Optional: Skills.sh registry not installed (curated mappings still work fine).
     To enable dynamic skill search: npx skills find find-skills
   ```
   Do not block on this. Do not present it as an error or warning. Continue with curated mappings only.

## Stack Detection Protocol

**(SKIL-02)** Analyze the project to determine its technology stack and recommend relevant skills.

### Procedure

1. Read `${CLAUDE_PLUGIN_ROOT}/config/stack-mappings.json` for the mapping table.
2. For each category (`frameworks`, `testing`, `services`, `quality`, `devops`):
   - For each entry's `detect` array:
     - **File-based pattern** (e.g., `next.config.js`): Check if the file exists using Glob.
     - **Dependency-based pattern** (e.g., `package.json:react`): Split on `:` to get the manifest filename and dependency name. Read the manifest file and check if the dependency string appears in the content (in `dependencies` or `devDependencies` for `package.json`, in requirements for `requirements.txt`, etc.).
3. Collect all matched entries with their `skills` arrays and `description` fields.

### Output

A list of matched stack entries:
```
{ category, entry_name, description, recommended_skills[] }
```

## Dynamic Discovery

**(SKIL-07)** When curated mappings produce no match for a detected stack component, fall back to the Skills.sh registry.

### When to trigger

Dynamic discovery runs during `/vbw:plan` (not `/vbw:init`) for any detected technology that has **no entry** in `stack-mappings.json`. For example, if the project uses Hono or Drizzle and neither appears in curated mappings, those become dynamic search queries.

### Procedure

1. **Curated fast path first.** Run the Stack Detection Protocol (SKIL-02) as normal. Collect all matched entries. This requires no network and is always preferred.
2. **Identify gaps.** For each technology detected in the project (via manifest files, config files, etc.) that produced zero matches in curated mappings, build a search query. Use descriptive terms: e.g., `"Hono HTTP framework"`, `"Drizzle ORM"`, `"testing framework for React"`.
3. **Registry search.** If `find_skills_available` is `true` (see SKIL-06), run:
   ```bash
   npx skills find "<query>"
   ```
   Parse the output to extract skill name, description, and install command.
4. **Cache results.** Write registry results to `.vbw-planning/config.json` under the `skill_cache` key:
   ```json
   {
     "skill_cache": {
       "<query>": {
         "results": [
           { "name": "skill-name", "description": "...", "install": "npx skills find skill-name" }
         ],
         "cached_at": "2026-02-07T12:00:00Z"
       }
     }
   }
   ```
   On subsequent runs, use cached results if `cached_at` is less than 7 days old. Otherwise re-query.
5. **Skip if unavailable.** If `find_skills_available` is `false`, skip dynamic discovery silently. Curated mappings are sufficient for common stacks.

### Source Attribution

When displaying skill suggestions (in SKIL-03/SKIL-04), tag each suggestion with its source:

- **Curated mappings:** `(curated)` -- from `stack-mappings.json`, no network required.
- **Registry search:** `(registry)` -- from Skills.sh dynamic lookup. Include the description and install command from the registry result.

Example output:
```
Suggested skills (not installed):
- nextjs-skill (curated) -- recommended for Next.js framework
- hono-skill (registry) -- Hono web framework best practices. Install: npx skills find hono-skill
```

## Suggestion Protocol

**(SKIL-03, SKIL-04)** Compare detected stack skills against installed skills to generate suggestions.

### Procedure

1. Flatten all `recommended_skills` from stack detection (SKIL-02) into a unique set. Tag each as `source: "curated"`.
2. If dynamic discovery (SKIL-07) ran, merge registry results into the set. Tag each as `source: "registry"`. If a skill name appears in both curated and registry, keep the curated entry (it is authoritative).
3. Flatten all installed skill names from the discovery step (SKIL-01) into a unique set.
4. Skills that are recommended but NOT installed become suggestions.
5. Read `skill_suggestions` from `.vbw-planning/config.json`:
   - If `false`: skip suggestion display entirely. End here.
6. Read `auto_install_skills` from `.vbw-planning/config.json`:
   - If `true`: for each suggested skill, run `npx @anthropic-ai/claude-code skills add {skill-name}` without prompting. Display result (success or failure) for each.
   - If `false` (default): display suggestions in a formatted list with source attribution (see SKIL-07 Source Attribution). Show the installation command for each:
     ```
     npx @anthropic-ai/claude-code skills add {skill-name}
     ```

## Capability Map

**(SKIL-05)** The capability map is a persistent section in `.vbw-planning/STATE.md` under `### Skills`. It is written during `/vbw:init` and refreshed when `/vbw:plan` reads it.

### Format

```markdown
### Skills

**Installed:**
- {skill-name} ({scope})
- ...
(or "None detected" if no skills found)

**Suggested (not installed):**
- {skill-name} (curated) -- recommended for {detected-stack-item}
- {skill-name} (registry) -- {description}
- ...
(or "None" if all recommended skills are installed)

**Stack detected:** {comma-separated list of detected frameworks/tools}
**Registry available:** yes/no
```

This section is read by Lead, Dev, and QA agents during their respective protocols to make skill-aware decisions.

## Agent Usage

Each agent type consumes the capability map differently. Detailed protocols live in the respective agent `.md` files; this is a summary.

- **Lead:** References installed skills in plan context sections. When creating plans, the Lead notes which installed skills are relevant to each task. If a recommended skill is not installed, the Lead may suggest it in the plan objective.
- **Dev:** Before executing a task, the Dev checks the capability map for relevant installed skills (e.g., `testing-skill` for test tasks, `nextjs-skill` for Next.js work). Installed skills inform implementation approach and best practices.
- **QA:** Checks for quality-related skills (`linting-skill`, `security-audit`, `a11y-check`) to augment verification. When a quality skill is installed, QA incorporates its checks into the verification pass.

## Config Settings

**(SKIL-10)** Two settings in `.vbw-planning/config.json` control skill behavior:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `skill_suggestions` | boolean | `true` | Controls whether skills are suggested during init and planning. When false, skill discovery still runs (for the capability map) but suggestions are not displayed. |
| `auto_install_skills` | boolean | `false` | Controls whether suggested skills are auto-installed. When true, runs the install command automatically. When false, displays suggestions for user to act on. |
| `skill_cache` | object | `{}` | Cache of Skills.sh registry search results. Keyed by query string. Each entry contains `results` array and `cached_at` timestamp. Entries older than 7 days are re-queried. Managed automatically by SKIL-07; not user-editable. |

`skill_suggestions` and `auto_install_skills` are defined in `config/defaults.json` and documented in `commands/config.md` Settings Reference. `skill_cache` is runtime-managed and not present in defaults.
