// R190, phase P147 (evidence level L1, the stand-in for Claude Code's mods API):
// Mission Control shows the running step's end time from the kernel's note
// (.vbw/runtime/step.json) in full wording (D425): 'about 12 min, until around
// 14:20'; its Now box names what the step is doing now. Later than usual with
// parts: '..., later than usual'. Late without parts: 'until around 14:20, 6 min
// late'. No basis: 'No end time yet: VBW has timed fewer than 3 steps like this
// here', and no time. Local 24-hour HH:MM; an end on another day names the day
// ('until around tomorrow 00:20'); under a minute left, 'less than a minute'.
// The time keeps the estimate colour. It is gone at the next refresh (2 s) once
// the step ends. The panel never works the step's time out itself: a lease and a
// history without a note show no step time; the milestone estimate (R58) stays.
// Times are local to Europe/Zurich (UTC+01:00, +02:00 in summer), so a UTC clock shows.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { spawnSync } from 'node:child_process'
import { mount, record, next, lease, walk, deepFreeze, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen, hhmm } from '../r189/helpers/screen.mjs'

process.env.TZ = 'Europe/Zurich'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const pane = await import(pathToFileURL(PLUGIN + '/hooks/panel-pane.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)

const NOTE = ROOT + '/.vbw/runtime/step.json'
const STEPS = ROOT + '/.git/vbw/steps.json'
const S = 1000
const MIN = 60 * S
const TICK = 2000
const WIDTH = 60
// The first drawing comes 4 s after the clock starts at T0.
const NOW = T0 + 4 * S
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, started_at: iso(T0 - 1e7 - i * 1e5), ended_at: iso(T0 - 1e7 - i * 1e5 + s * 1000), seconds: s }))
const HISTORY = { steps: [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])] }
const PLANS = [
  { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' },
  { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'building' },
]
const building = () => record({ lease: lease('build', T0 - 300 * S), plans: PLANS })
const END = NOW + 12 * MIN
const note = (over = {}) => ({
  kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(T0 - 300 * S), ids: ['P44.1', 'P44.2'],
  doing: 'building P44.1, P44.2', parts: { done: 1, total: 2 }, proof: null, first_end: iso(END), end: iso(END), late: false, ...over,
})
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

async function session(rec, n, files = {}) {
  const h = await mount({ files: { ...files, ...(n ? { [NOTE]: JSON.stringify(n) } : {}) } })
  h.git()
  h.project(rec, next({ action: 'run' }))
  await h.start()
  await h.advance(4000)
  return h
}
const draw = (h) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: WIDTH, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} } })
const paneText = async (h) => screen(await draw(h), Infinity).join('\n')
async function nowBox(h) {
  let box
  walk(await draw(h), (n) => {
    if (!box && n.type === 'Box' && n.props.borderStyle) box = n
  })
  assert.ok(box, 'the Now tab has no box')
  return screen(box, Infinity).join('\n')
}

test("Mission Control gives the running step's time in full: 'about 12 min, until around HH:MM'", async () => {
  const h = await session(building(), note())
  const text = await paneText(h)
  assert.ok(text.includes('about 12 min, until around ' + hhmm(END)), text)
  assert.ok(text.includes('This step: about 12 min, until around ' + hhmm(END) + '.'), text)
  assert.doesNotMatch(text, /left in this step/i, 'the old sentence is replaced')
  assert.deepEqual(h.errors, [])
})

test('the Now box names what the step is doing now, also a proof inside a fix', async () => {
  const h = await session(building(), note())
  assert.ok((await nowBox(h)).includes('building P44.1, P44.2'), await nowBox(h))
  const fixing = record({ lease: lease('fix', T0 - 300 * S), plans: [] })
  const f = await session(fixing, note({ kind: 'fix', run: 'fix-1', ids: ['F3'], doing: 'proving 12 of 40 checks', parts: { done: 0, total: 1 }, proof: { done: 12, total: 40 } }))
  assert.ok((await nowBox(f)).includes('proving 12 of 40 checks'), await nowBox(f))
  assert.ok((await paneText(f)).includes('until around ' + hhmm(END)))
})

test('later than usual with parts: the moved time, marked in full wording', async () => {
  const end = NOW + 20 * MIN
  const h = await session(building(), note({ first_end: iso(NOW - 2 * MIN), end: iso(end), late: true }))
  const text = await paneText(h)
  assert.ok(text.includes('until around ' + hhmm(end) + ', later than usual'), text)
})

test('late without parts: the first time stays and the panel says how many minutes late', async () => {
  const first = NOW - 6 * MIN - 20 * S
  const rec = record({ lease: lease('qa', T0 - 900 * S), plans: [] })
  const h = await session(rec, note({ kind: 'qa', run: 'qa-1', ids: ['P44'], doing: 'checking P44', parts: null, first_end: iso(first), end: iso(first) }))
  const text = await paneText(h)
  assert.ok(text.includes('until around ' + hhmm(first) + ', 6 min late'), text)
})

test('no basis: the panel says so in its own words and shows no time', async () => {
  const h = await session(building(), note({ first_end: null, end: null }))
  const text = await paneText(h)
  assert.ok(text.includes('No end time yet: VBW has timed fewer than 3 steps like this here'), text)
  assert.doesNotMatch(text, /until around/)
})

test("under a minute left the panel says 'less than a minute'", async () => {
  const end = NOW + 30 * S
  const h = await session(building(), note({ first_end: iso(end), end: iso(end) }))
  const text = await paneText(h)
  assert.ok(text.includes('less than a minute') && text.includes('until around ' + hhmm(end)), text)
})

test('an end on another day names the day, in 24-hour local time', async () => {
  const d = new Date(NOW)
  const end = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 0, 20).getTime()
  const h = await session(building(), note({ first_end: iso(end), end: iso(end) }))
  const text = await paneText(h)
  assert.ok(text.includes('until around tomorrow 00:20'), text)
})

test('when the step ends its time is gone at the next refresh', async () => {
  const h = await session(building(), note())
  assert.match(await paneText(h), /until around/)
  h.project(record({ plans: PLANS.map((p) => ({ ...p, status: 'done' })) }))
  await h.advance(TICK)
  assert.doesNotMatch(await paneText(h), /until around/)
  const g = await session(building(), note())
  g.remove(NOTE)
  await g.advance(TICK)
  assert.doesNotMatch(await paneText(g), /until around/)
})

test("with nothing running no step time shows; a note of another run is not this step's", async () => {
  const idle = await session(record(), null, { [STEPS]: JSON.stringify(HISTORY) })
  assert.doesNotMatch(await paneText(idle), /until around|this step/i)
  const other = await session(building(), note({ run: 'build-0' }))
  assert.doesNotMatch(await paneText(other), /until around/)
  const control = await session(building(), note())
  assert.match(await paneText(control), /until around/)
})

test("the panel never works the step's time out itself; the milestone estimate stays", async () => {
  const h = await session(building(), null, { [STEPS]: JSON.stringify(HISTORY) })
  const text = await paneText(h)
  assert.doesNotMatch(text, /until around|this step/i)
  assert.match(text, /About \d+ min left in the milestone/)
  const timeline = { runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: T0 - 300 * S, endedAt: null, status: 'running', agents: [] }
  const bare = live.timelineModel({ run: timeline, now: NOW, steps: HISTORY.steps, width: 20 })
  assert.equal(bare.left, null, 'the Timeline worked a time out from the history')
  const told = live.timelineModel({ run: timeline, now: NOW, steps: HISTORY.steps, width: 20, step: note() })
  assert.ok(String(told.left).includes('until around ' + hhmm(END)), String(told.left))
})

test('the time keeps the estimate colour; a sentence with no time stays plain', () => {
  const busy = deepFreeze(building())
  const input = (v) => ({
    st: { tab: 'now', record: busy, run: null, steps: [], leases: [], cost: 1.42, sound: true, agent: null, phase: null, check: null },
    v, now: NOW, width: WIDTH, wrapped: null, portrait: null, sweep: null,
  })
  const on = { act: () => {}, sound: () => {} }
  const colour = (v, id) => {
    const row = v.rows.find((r) => r.id === id)
    assert.ok(row, 'no ' + id + ' row')
    let hit
    walk(pane.renderPane(UI, input(v), on), (n) => {
      if (!hit && n.type === 'Text' && n.children.filter((c) => typeof c === 'string').join('') === row.text) hit = n
    })
    assert.ok(hit, row.text + ' is not drawn as one piece of text')
    return [row.text, hit.props.color]
  }
  const timed = view.panelView({ record: busy, next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: [], step: note() })
  const [text, c] = colour(timed, 'estimate-step')
  assert.ok(text.includes('until around ' + hhmm(END)), text)
  assert.equal(c, P.ESTIMATE)
  const none = view.panelView({ record: busy, next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: [], step: note({ first_end: null, end: null }) })
  const [plain, nc] = colour(none, 'estimate-step')
  assert.match(plain, /No end time yet/)
  assert.equal(nc, undefined)
})

test("a proof of another session is not this panel's step; a proof of its own is", async () => {
  const proof = (session) => note({ kind: 'proof', run: null, session, pid: process.pid, ids: [], doing: 'proving 12 of 40 checks', parts: { done: 12, total: 40 }, proof: { done: 12, total: 40 } })
  const other = await session(record(), proof('sess-9'))
  assert.doesNotMatch(await paneText(other), /until around/)
  const own = await session(record(), proof('sess-1'))
  assert.match(await paneText(own), /until around/)
})

test("a proof of this session whose process is gone is no step in Mission Control; a live one is", async () => {
  const dead = spawnSync(process.execPath, ['-e', '0']).pid
  const proof = (pid) => note({ kind: 'proof', run: null, session: 'sess-1', pid, ids: [], doing: 'proving 12 of 40 checks', parts: { done: 12, total: 40 }, proof: { done: 12, total: 40 } })
  assert.doesNotMatch(await paneText(await session(record(), proof(dead))), /until around/)
  assert.match(await paneText(await session(record(), proof(process.pid))), /until around/)
})
