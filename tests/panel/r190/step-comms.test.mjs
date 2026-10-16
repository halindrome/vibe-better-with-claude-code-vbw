// R190, phase P147 (evidence level L1, the stand-in for Claude Code's mods API):
// Comms, the strip above the prompt, shows the running step and its end time
// from the kernel's note (.vbw/runtime/step.json) in full wording (D425):
// 'about 12 min, until around 14:20', also while the crew of a workflow shows
// and for a background proof ('proving 12 of 40 checks'); 'later than usual'
// and 'N min late' as in Mission Control. When the step ends its time is gone
// at the next refresh (2 s); with nothing running none shows.
// Times are local to Europe/Zurich (UTC+01:00, +02:00 in summer), so a UTC clock shows.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, collect, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen, hhmm } from '../r189/helpers/screen.mjs'

process.env.TZ = 'Europe/Zurich'

const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)

const NOTE = ROOT + '/.vbw/runtime/step.json'
const S = 1000
const MIN = 60 * S
const TICK = 2000
const NOW = T0 + 4 * S
const END = NOW + 12 * MIN
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const PLANS = [
  { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' },
  { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'building' },
]
const building = () => record({ lease: lease('build', T0 - 300 * S), plans: PLANS })
const note = (over = {}) => ({
  kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(T0 - 300 * S), ids: ['P44.1', 'P44.2'],
  doing: 'building P44.1, P44.2', parts: { done: 1, total: 2 }, proof: null, first_end: iso(END), end: iso(END), late: false, ...over,
})
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

async function session(rec, n) {
  const h = await mount({ files: n ? { [NOTE]: JSON.stringify(n) } : {} })
  h.git()
  h.project(rec, next({ action: 'run' }))
  await h.start()
  await h.advance(4000)
  return h
}
const comms = async (h) => screen(await h.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100 }), 100).join('\n')

test("Comms shows the running step's time in full: 'about 12 min, until around HH:MM'", async () => {
  const h = await session(building(), note())
  const text = await comms(h)
  assert.ok(text.includes('about 12 min, until around ' + hhmm(END)), text)
  assert.deepEqual(h.errors, [])
})

test("a background proof shows in Comms as 'proving 12 of 40 checks' with its time", async () => {
  const proof = note({ kind: 'proof', run: null, pid: 4242, ids: [], doing: 'proving 12 of 40 checks', parts: { done: 12, total: 40 }, proof: { done: 12, total: 40 } })
  const h = await session(record(), proof)
  const text = await comms(h)
  assert.ok(text.includes('proving 12 of 40 checks'), text)
  assert.ok(text.includes('until around ' + hhmm(END)), text)
})

test('later than usual and minutes late read in Comms as in Mission Control', async () => {
  const end = NOW + 20 * MIN
  const late = await session(building(), note({ first_end: iso(NOW - 2 * MIN), end: iso(end), late: true }))
  assert.ok((await comms(late)).includes('until around ' + hhmm(end) + ', later than usual'), await comms(late))
  const first = NOW - 6 * MIN - 20 * S
  const qa = record({ lease: lease('qa', T0 - 900 * S), plans: [] })
  const over = await session(qa, note({ kind: 'qa', run: 'qa-1', ids: ['P44'], doing: 'checking P44', parts: null, first_end: iso(first), end: iso(first) }))
  assert.ok((await comms(over)).includes('until around ' + hhmm(first) + ', 6 min late'), await comms(over))
})

test('when the step ends its time leaves Comms at the next refresh; with nothing running none shows', async () => {
  const h = await session(building(), note())
  assert.match(await comms(h), /until around/)
  h.project(record())
  await h.advance(TICK)
  assert.doesNotMatch(await comms(h), /until around/)
  const g = await session(building(), note())
  g.remove(NOTE)
  await g.advance(TICK)
  assert.doesNotMatch(await comms(g), /until around/)
  const idle = await session(record(), null)
  assert.doesNotMatch(await comms(idle), /until around/)
})

test('while a workflow crew shows, the step time shows with it', () => {
  const agent = (id, label) => ({ id, role: 'dev', label, state: 'working', activity: { kind: 'tool', text: 'editing a.js' }, startedAt: NOW - 60 * S, endedAt: null, lastSeenAt: NOW - S, tokens: 1000, result: null })
  const run = { runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 120 * S, endedAt: null, status: 'running', agents: [agent('a1', 'P44.1'), agent('a2', 'P44.2')] }
  const model = stage.stageModel({ run, step: note(), now: NOW, columns: 100, maxRows: 8 })
  assert.ok(model, 'Comms has nothing to show')
  const text = collect(stage.renderStage(UI, model)).join('\n')
  assert.match(text, /P44\.1/)
  assert.ok(text.includes('about 12 min, until around ' + hhmm(END)), text)
})

test('the step line is cut to the columns Comms has, never spilled', () => {
  for (const columns of [30, 50]) {
    const model = stage.stageModel({ step: note(), now: NOW, columns, maxRows: 8 })
    const lines = collect(stage.renderStage(UI, model))
    assert.ok(lines.length > 0, 'no step line')
    for (const l of lines) assert.ok([...l].length <= columns, columns + ' columns: ' + l)
    assert.match(lines.join('\n'), /…/)
  }
})

test("the step line never pushes out the needs-you line", () => {
  const need = { key: 'k', what: 'approve the plan', at: NOW }
  const alone = stage.stageModel({ step: note(), need, now: NOW, columns: 100, maxRows: 1 })
  const one = collect(stage.renderStage(UI, alone)).join('\n')
  assert.match(one, /VBW needs you/)
  assert.doesNotMatch(one, /until around/)
  const both = stage.stageModel({ step: note(), need, now: NOW, columns: 100, maxRows: 2 })
  const two = collect(stage.renderStage(UI, both)).join('\n')
  assert.match(two, /VBW needs you/)
  assert.match(two, /until around/)
})
