export const meta = {
  name: 'fixing',
  description: 'VBW: work the open fix items, a Dev per group of fixes that share files, groups in parallel',
  whenToUse: 'Started by /vbw:vibe when vbw next says fix, inside a vbw run start fix lease',
  phases: [{ title: 'Fix', detail: 'a Dev per group of fixes; groups have disjoint files' }],
}

// args: {groups: [["F1", "F3"], ["F2"]], models?: {dev?}, rigor?: {P1: {tier, models}}} (docs/workflows.md).
// Fixes in one group share files, so one Dev works them together.
const groups = ((args && args.groups) || []).filter(g => Array.isArray(g) && g.length > 0)
const models = (args && args.models) || {}
// R186, D369: the closing step is a few fixed commands and the record stays the source of truth.
const CLOSE_MODEL = 'haiku'
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
// The Dev model of the highest-tier phase (a fix has no phase of its own).
const RANK = { express: 0, standard: 1, deep: 2 }
const top = Object.values((args && args.rigor) || {}).filter(c => c && c.models && c.models.dev)
  .reduce((a, c) => (!a || (RANK[c.tier] || 0) > (RANK[a.tier] || 0) ? c : a), null)
const devModel = top ? top.models.dev : models.dev
// The effort the profile gives a role and step (args.effort, from vbw next --json): the option
// for an agent call, or nothing when there is no table or no value (agents then run as before).
const table = (args && typeof args === 'object' && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : {}
const effortOf = (role, step) => {
  const e = table[role] && typeof table[role] === 'object' ? table[role][step] : null
  return e ? { effort: e } : {}
}
if (groups.length === 0) return { results: [], error: 'no fix groups given: pass args.groups from vbw next --json (detail.groups)' }

const FIXDONE_PROPS = {
  fixdone: { type: 'string', enum: ['ran', 'failed'] },
  closed: { type: 'array', items: { type: 'string' } },
  open: { type: 'array', items: { type: 'object', required: ['fix', 'reason'], properties: { fix: { type: 'string' }, reason: { type: 'string' } } } },
}
const CLOSE_RESULT = {
  type: 'object',
  required: ['fixdone', 'closed', 'open', 'ended', 'recorded', 'report'],
  properties: Object.assign({ ended: { type: 'boolean' }, recorded: { type: 'boolean' }, report: { type: 'string' } }, FIXDONE_PROPS),
}
const ALONE_RESULT = {
  type: 'object',
  required: ['fixdone', 'closed', 'open', 'report'],
  properties: Object.assign({ report: { type: 'string' } }, FIXDONE_PROPS),
}

const FIX_RESULT = {
  type: 'object',
  required: ['status', 'summary', 'notes'],
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    summary: { type: 'string' },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

// The round's one vbw fix done (R182), run after every Dev has returned, for the fixes whose Dev
// reported done. It may outlast one shell command's 10-minute limit.
const session = (args && args.session) || ''
const sh = c => (session ? `VBW_SESSION_ID=${session} ${c}` : c)
const WAIT = 'It may run past one shell command\'s 10-minute limit: if Claude Code moves it to the background, wait for it to finish and read its whole output (it ends with the two count lines) before anything else.'
const FIXDONE_ANSWER = 'Answer fixdone ("ran" when it ran, "failed" when it stopped with an error), closed (the fix ids it closed) and open (each fix it left open: {fix, reason})'
// The run's own last step (R78, R81): the round's vbw fix done, then confirm what the agents
// recorded, say plainly what was not, and end the run. Only when the router passed args.session.
const closeRun = async (ids, fixCmd) => {
  const confirm = sh(`vbw run confirm ${ids.join(' ')}`)
  const end = sh('vbw run end')
  const first = fixCmd ? `First run ${fixCmd}. ${WAIT} ` : ''
  const done = await agent(`Close this VBW run (your own instructions, Close a run, allow it). ${first}Then run ${confirm} (it exits 1 when some fixes were not recorded), then, whatever it said, run ${end}. ${FIXDONE_ANSWER}${fixCmd ? '' : ' (no fix is to be closed: answer "ran" with empty lists)'}, ended (run end succeeded), recorded (confirm exited 0) and report (the lines for what was not recorded, else "all recorded; run ended"). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, { model: CLOSE_MODEL }, effortOf('lead', 'close')))
  if (!done) log(`the closing agent stopped: run by hand: ${fixCmd ? fixCmd + ' ; then ' : ''}${confirm} ; then ${end}`)
  else {
    if (!done.recorded || !done.ended) log(done.report)
    if (!done.recorded) log(`not everything was recorded: check by hand with ${confirm}`)
    if (!done.ended) log(`the run did not end: run by hand: ${end}`)
  }
  return done
}
// Without a session there is no closing Lead: an agent of its own runs the round's vbw fix done.
const fixDoneAlone = async fixCmd => {
  const done = await agent(`Close the fixes of this VBW round (your own instructions, Close a run, allow it). Run ${fixCmd}. ${WAIT} ${FIXDONE_ANSWER}, and report (what it printed for fixes left open). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'fix done', schema: ALONE_RESULT }, { model: CLOSE_MODEL }, effortOf('lead', 'close')))
  if (!done) log(`the fix done agent stopped: run by hand: ${fixCmd}`)
  return done
}

phase('Fix')
const NO_SUITE = ' Read the full output and the failing test names with vbw show fix instead of rerunning the suite. Do not run the project\'s test command or its quick command: run only your fixes\' checks (vbw check). Commit your fix (a requirement fix commits its own requirement\'s check files with vbw commit --fix FIX MSG FILE..., and they wait for one approval by the user; code goes through its plan with vbw commit PLAN), check it with vbw check, then return. Do not run vbw fix done: the workflow runs it once for the round, after every Dev returns. The whole test command runs once, in the proof after this round. If your fix is for a failure of the test command itself, run only the failing tests you need to fix.'
// T123: a decision recorded after the approval may correct the plan the fix serves; the brief names them.
const SINCE = 'vbw show decisions --since-approval (decisions recorded after the contract was approved: where one differs from the plan, the decision wins).'
// A fix a QA finding opened is a gap in the tests too: the Dev adds the regression test (R160).
const QA_TEST = ' If a fix came from a QA finding (its source says qa), first write a test that fails while the problem exists (it may create new test files), register it with vbw fix check FIX (a check document on stdin), and commit it with the fix. Edits to an approved check file of the finding\'s requirement wait for one approval by the user before the proof: say so in notes, never approve.'
const results = await pipeline(groups, ids =>
  agent(ids.length === 1
    ? `Fix VBW fix item ${ids[0]}. Start with: vbw show fix ${ids[0]}; then ${SINCE}${NO_SUITE}${QA_TEST}${voice}`
    : `Fix VBW fix items ${ids.join(', ')} together: they touch the same files and may share one cause. Start with: ${ids.map(id => `vbw show fix ${id}`).join('; ')}; then ${SINCE}${NO_SUITE}${QA_TEST}${voice}`,
    Object.assign({ agentType: 'vbw:dev', label: ids.join('+'), phase: 'Fix', schema: FIX_RESULT },
      devModel ? { model: devModel } : {}, effortOf('dev', 'fix'))))

const out = groups.map((ids, i) => results[i]
  ? Object.assign({ fixes: ids }, results[i])
  : { fixes: ids, status: 'interrupted', summary: 'the Dev stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} fixer(s) stopped before reporting; their fixes stay open`)
const doneIds = out.filter(r => r.status === 'done').flatMap(r => r.fixes)
const leftOut = out.filter(r => r.status !== 'done').flatMap(r => r.fixes.map(fix => ({ fix, status: r.status })))
leftOut.forEach(l => log(`${l.fix} is left open: its Dev ${l.status}`))
const fixCmd = doneIds.length ? sh(`vbw fix done ${doneIds.join(' ')}`) : ''
let confirmation = null
let fd = null
if (session) { confirmation = await closeRun(groups.flat(), fixCmd); fd = confirmation }
else if (fixCmd) fd = await fixDoneAlone(fixCmd)
const failed = Boolean(fixCmd) && (!fd || fd.fixdone === 'failed')
if (failed) log(`vbw fix done did not finish: run by hand: ${fixCmd}`)
const closed = fd && fixCmd && Array.isArray(fd.closed) ? fd.closed : []
const open = fd && fixCmd && Array.isArray(fd.open) ? fd.open : []
open.forEach(o => log(`${o.fix} stays open: ${o.reason}`))
const fixdone = { command: fixCmd || null, closed, open, left_out: leftOut }
const complete = interrupted === 0 && !failed && (!session || Boolean(confirmation && confirmation.recorded && confirmation.ended))
return confirmation ? { results: out, complete, fixdone, confirmation } : { results: out, complete, fixdone }
