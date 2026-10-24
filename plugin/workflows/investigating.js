export const meta = {
  name: 'investigating',
  description: 'VBW: Debuggers investigate a bug from three angles in parallel and diagnose its root cause; with a diagnosis given, one Debugger fixes it',
  whenToUse: 'Started by /vbw:debug with a description of the problem, and again with the diagnosis once the user wants it fixed',
  phases: [
    { title: 'Investigate', detail: 'a Debugger per angle: reproduce, trace, history' },
    { title: 'Diagnose', detail: 'one Debugger weighs the evidence into a root cause' },
    { title: 'Fix', detail: 'one Debugger: minimal fix, regression test, verify' },
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

// args: {problem: "...", models?: {debugger?}} to investigate, or the problem as
// a plain string; {problem, fix: <the diagnosis returned before>, models?} to fix.
const problem = typeof args === 'string' ? args : args && args.problem
if (!problem) return reply({ error: 'no problem given: pass args.problem' })
const models = (args && typeof args === 'object' && args.models) || {}
const model = models.debugger ? { model: models.debugger } : {}
// The effort the profile gives a role and step (args.effort, from vbw next --json): the option
// for an agent call, or nothing when there is no table or no value (agents then run as before).
const table = (args && typeof args === 'object' && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : {}
const effortOf = (role, step) => {
  const e = table[role] && typeof table[role] === 'object' ? table[role][step] : null
  return e ? { effort: e } : {}
}
const fix = args && typeof args === 'object' ? args.fix : null
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

const DONE = {
  type: 'object',
  required: ['status', 'summary', 'root_cause', 'files', 'commit', 'regression_test', 'refused'],
  properties: {
    refused: REFUSED,
    status: { type: 'string', enum: ['fixed', 'not_fixed'] },
    summary: { type: 'string' },
    root_cause: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    commit: { type: 'string' },
    regression_test: { type: 'string' },
    pre_existing: { type: 'array', items: { type: 'string' } },
  },
}

if (fix) {
  phase('Fix')
  const done = await ask(`Fix mode (steps 5 to 7). Fix this bug at its root cause, add a regression test, verify, and document.\n\nProblem: ${problem}\n\nDiagnosis: ${JSON.stringify(fix)}${voice}`,
    Object.assign({ agentType: 'vbw:debugger', label: 'debugger fix', phase: 'Fix', schema: DONE }, model, effortOf('debugger', 'fix')))
  return reply({ fixed: done })
}

const LENSES = [
  { key: 'reproduce', ask: 'Reproduce it: find the smallest command or test that shows the problem, run it, and report the exact steps and output (or that it does not reproduce).' },
  { key: 'trace', ask: 'Trace the code path involved, from the entry point to where the behavior goes wrong: name the exact place and why.' },
  { key: 'history', ask: 'Check the recent changes (git log, git show, git blame of the files involved) for what introduced or touched this behavior.' },
]

const EVIDENCE = {
  type: 'object',
  required: ['hypotheses', 'refused'],
  properties: {
    refused: REFUSED,
    reproduction: { type: 'string' },
    hypotheses: {
      type: 'array',
      items: {
        type: 'object',
        required: ['cause', 'evidence_for', 'evidence_against', 'confidence'],
        properties: {
          cause: { type: 'string' },
          evidence_for: { type: 'string' },
          evidence_against: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}
const DIAGNOSIS = {
  type: 'object',
  required: ['root_cause', 'evidence', 'confidence', 'rejected', 'fix', 'unknowns', 'refused'],
  properties: {
    refused: REFUSED,
    root_cause: { type: 'string' },
    evidence: { type: 'string' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    rejected: { type: 'array', items: { type: 'string' } },
    fix: { type: 'string' },
    unknowns: { type: 'array', items: { type: 'string' } },
  },
}

phase('Investigate')
const reports = await parallel(LENSES.map(l => () =>
  ask(`Investigation mode (steps 1 to 4), from one angle only. Change nothing.\n\nProblem: ${problem}\n\nYour angle: ${l.ask}${voice}`,
    Object.assign({ agentType: 'vbw:debugger', label: `debugger ${l.key}`, phase: 'Investigate', schema: EVIDENCE }, model, effortOf('debugger', 'investigate')))))

const evidence = LENSES.map((l, i) => ({ angle: l.key, report: reports[i] }))

phase('Diagnose')
const diagnosis = await ask(`Investigation mode, step 4: weigh this evidence into the root cause. Prefer causes with reproduced or traced evidence; check the deciding fact yourself before you conclude; list the hypotheses you rejected and why. Propose the minimal fix for the root cause, not the symptom. Change nothing.\n\nProblem: ${problem}\n\nEvidence: ${JSON.stringify(evidence)}${voice}`,
  Object.assign({ agentType: 'vbw:debugger', label: 'debugger diagnose', phase: 'Diagnose', schema: DIAGNOSIS }, model, effortOf('debugger', 'diagnose')))

return reply({ diagnosis, evidence })
