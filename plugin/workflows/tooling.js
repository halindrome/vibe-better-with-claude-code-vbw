export const meta = {
  name: 'tooling',
  description: 'VBW: one Scout per angle (safety, quality, tests, skills) looks for the best tools for the project, then a short sourced list is kept',
  whenToUse: 'Started by /vbw:skills (and the interview) after the user agreed to a tool search',
  phases: [{ title: 'Scout', detail: 'a Scout per angle, in parallel' }],
}

// Kernel refusals reach the user as written (docs/workflows.md, "Refusals reach the user"):
// every agent schema requires refused, and the result carries them all, each named by
// the agent that saw it, so the router shows them word for word.
const REFUSED = {
  type: 'array',
  description: 'Each refusal VBW gave you: a vbw command that refused (it exited non-zero with a message starting "vbw:") or a tool call a guard blocked (a reason starting "VBW guard:"), each copied verbatim and whole, through its Next: line; [] when none',
  items: { type: 'string' },
}
// The project folder (args.root: vbw next --json or vbw root). A session started in a subfolder
// starts its agents there, so each agent is told where the project's paths are.
const projectRoot = (args && typeof args === 'object' && typeof args.root === 'string' && args.root) || ''
const where = projectRoot ? `\n\nThe project folder is ${projectRoot}. Every path VBW names (plan and check files, .vbw/...) is relative to it, whatever folder you start in: give file tools and shell redirects absolute paths under it, and run other shell commands from it (cd "${projectRoot}" && ...).` : ''
const refused = []
const ask = async (prompt, o) => {
  const r = await agent(prompt + where, o)
  for (const text of r && Array.isArray(r.refused) ? r.refused : []) {
    if (typeof text !== 'string' || !text.trim()) continue
    refused.push({ by: o.label, text })
    log(`${o.label} was refused: ${text}`)
  }
  return r
}
const reply = o => Object.assign(o, { refused })

// args: {stack: "...", profile?: {level, depth, involvement}, models?: {scout?}}.
const stack = args && typeof args === 'object' && typeof args.stack === 'string' ? args.stack.trim() : ''
const models = (args && typeof args === 'object' && args.models) || {}
const model = models.scout ? { model: models.scout } : {}
// The effort the profile gives a role and step (args.effort, from vbw next --json): the option
// for an agent call, or nothing when there is no table or no value (agents then run as before).
const table = (args && typeof args === 'object' && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : {}
const effortOf = (role, step) => {
  const e = table[role] && typeof table[role] === 'object' ? table[role][step] : null
  return e ? { effort: e } : {}
}
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

const ANGLES = [
  { key: 'safety', ask: 'automated code-safety scanners: security and vulnerability scanners, dependency audits and secret detection' },
  { key: 'quality', ask: 'code-quality tools: linters, formatters and type checkers' },
  { key: 'tests', ask: 'unit-test and other test frameworks and runners (integration, end-to-end, coverage)' },
  { key: 'skills', ask: 'community Claude Code skills and plugins that help with this stack' },
]

const PICKS = {
  type: 'object',
  required: ['picks', 'refused'],
  properties: {
    refused: REFUSED,
    picks: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'what', 'why', 'sources', 'origin'],
        properties: {
          name: { type: 'string' },
          what: { type: 'string' },
          why: { type: 'string' },
          sources: { type: 'array', items: { type: 'string' } },
          origin: { type: 'string', enum: ['respected-open-source', 'other'] },
        },
      },
    },
  },
}

const WARNING = 'Not from a respected open-source project: check who maintains it and read what it does before you approve it.'
const PER_ANGLE = 2
const TOTAL = 6

if (!stack) {
  return reply({ picks: [], missing: [], note: 'The project\'s stack is not known yet, so no tool search was started. Say what is being built and run it again.' })
}

phase('Scout')
const found = await Promise.all(ANGLES.map(a =>
  ask(`Find the current best-in-class options for one angle of this project: ${a.ask}.\n\nProject stack: ${stack}\n\nReturn at most ${PER_ANGLE} picks, each with what it is, why it fits this stack, one or more source links (https), and its origin: "respected-open-source" only for a well-known, actively maintained open-source project, otherwise "other". Prefer current, widely used options. Install nothing and change nothing.${voice}`,
    Object.assign({ agentType: 'vbw:scout', label: `scout ${a.key}`, phase: 'Scout', schema: PICKS }, model, effortOf('scout', 'survey')))
    .catch(() => null)))

const missing = []
let picks = []
ANGLES.forEach((a, i) => {
  const r = found[i]
  const kept = ((r && Array.isArray(r.picks)) ? r.picks : [])
    .filter(p => p && p.name && Array.isArray(p.sources) && p.sources.some(s => /^https?:\/\//.test(s)))
    .map(p => {
      const trusted = p.origin === 'respected-open-source'
      const out = { angle: a.key, name: p.name, what: p.what, why: p.why, origin: p.origin, trusted, sources: p.sources.filter(s => /^https?:\/\//.test(s)) }
      if (!trusted) out.warning = WARNING
      return out
    })
    .sort((x, y) => Number(y.trusted) - Number(x.trusted))
    .slice(0, PER_ANGLE)
  if (kept.length === 0) missing.push(a.key)
  picks = picks.concat(kept)
})
picks = picks.sort((x, y) => Number(y.trusted) - Number(x.trusted)).slice(0, TOTAL)

if (missing.length > 0) log(`no picks for: ${missing.join(', ')}`)
const result = { picks, missing }
if (picks.length === 0) result.note = 'No tools could be found right now. Nothing was installed; you can run the search again later.'
return reply(result)
