export const meta = {
  name: 'mapping',
  description: 'VBW: map an existing codebase from several angles in parallel, then merge the findings into one map',
  whenToUse: 'Started by /vbw:map, usually before planning work on an existing codebase',
  phases: [
    { title: 'Scout', detail: 'one scout per angle, in parallel' },
    { title: 'Merge', detail: 'one map from all findings' },
  ],
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

// args: {models?: {scout?}}
const models = (args && args.models) || {}
// R186, D369: the closing step is a few fixed commands and the record stays the source of truth.
const CLOSE_MODEL = 'haiku'
const model = models.scout ? { model: models.scout } : {}
// The effort the profile gives a role and step (args.effort, from vbw next --json): the option
// for an agent call, or nothing when there is no table or no value (agents then run as before).
const table = (args && typeof args === 'object' && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : {}
const effortOf = (role, step) => {
  const e = table[role] && typeof table[role] === 'object' ? table[role][step] : null
  return e ? { effort: e } : {}
}
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

// The run's own last step (R81): end the run on every way out. Only when the
// router passed args.session.
const session = (args && args.session) || ''
const closeRun = async (phaseIds = []) => {
  if (!session) return null
  const end = `VBW_SESSION_ID=${session} vbw run end`
  const check = phaseIds.length === 0 ? '' : `First check that each planned phase has plans: ${phaseIds.map(id => `vbw show phase ${id}`).join('; ')}. `
  const done = await ask(`Close this VBW run (your own instructions, Close a run, allow it). ${check}Then, whatever you found, run ${end}. Answer ended (run end succeeded), recorded (${phaseIds.length === 0 ? 'true' : 'every phase has plans'}) and report (${phaseIds.length === 0 ? 'what it printed' : 'name each phase without plans, else "all recorded; run ended"'}). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, { model: CLOSE_MODEL }, effortOf('lead', 'close')))
  if (!done) log(`the closing agent stopped: run by hand: ${end}`)
  else {
    if (!done.recorded) log(done.report)
    if (!done.ended) log(`the run did not end: run by hand: ${end}`)
  }
  return done
}

const ANGLES = [
  { key: 'stack', ask: 'The stack and how to work with it: languages, frameworks, package manager, and the exact commands to install, build, run, test and lint (try the test and lint commands and report what happens).' },
  { key: 'structure', ask: 'The structure: the top-level layout, the entry points, the main modules and what each owns, and how a request or command flows through them.' },
  { key: 'conventions', ask: 'The conventions a new change must follow: code style, naming, error handling, logging, file organization, and anything in CLAUDE.md, CONTRIBUTING or a linter config.' },
  { key: 'tests', ask: 'The tests: framework, where they live, how they are organized, fixtures and helpers, what is well covered and what is not.' },
  { key: 'risks', ask: 'The risks for someone changing this code: fragile or complex areas, generated or vendored code not to edit, global state, missing tests around important paths.' },
]

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report', 'refused'],
  properties: {
    refused: REFUSED,
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}

const FINDINGS = {
  type: 'object',
  required: ['findings', 'refused'],
  properties: { refused: REFUSED, findings: { type: 'array', items: { type: 'string' } } },
}

const MAP = {
  type: 'object',
  required: ['map', 'refused'],
  properties: { refused: REFUSED, map: { type: 'string' } },
}

phase('Scout')
const found = await parallel(ANGLES.map(a => () =>
  ask(`Map this codebase from one angle. ${a.ask} What a test or lint run gave (passes, failures, which test failed) is a snapshot, true only of the code it ran on: write it with that commit and date, "as of <short commit>, <date>: ...", from git rev-parse --short HEAD and date +%F.${voice}`, Object.assign({ agentType: 'vbw:scout', label: `scout ${a.key}`, phase: 'Scout', schema: FINDINGS }, model, effortOf('scout', 'survey')))))

const sections = ANGLES.map((a, i) => ({ angle: a.key, findings: found[i] ? found[i].findings : [] }))
const missing = sections.filter(s => s.findings.length === 0).map(s => s.angle)
if (missing.length > 0) log(`no findings for: ${missing.join(', ')}`)

phase('Merge')
const map = await ask(`Merge these verified findings about this codebase into one concise markdown map, with the sections Stack and commands, Structure, Conventions, Tests, Risks. Keep every command and path exactly. Drop duplicates. The map is read long after this run, when the code has changed: keep each test or lint result with its "as of <commit>, <date>" and never state one as current, and make no recommendation that rests on a result (fixing a failing test is work for a plan, not advice in the map). No preamble.\n\n${JSON.stringify(sections)}${voice}`,
  Object.assign({ agentType: 'vbw:scout', label: 'scout merge', phase: 'Merge', schema: MAP }, model, effortOf('scout', 'merge')))

await closeRun()
return reply({ map: (map && map.map) || sections.map(s => `## ${s.angle}\n${s.findings.map(f => `- ${f}`).join('\n')}`).join('\n\n'), missing })
