// R191, phase P151 (evidence level L1, the stand-in for Claude Code's mods API):
// Mission Control's Now tab shows the milestone's end as the kernel's road sentence
// ('Milestone end: about 2 h 10 min, until around 16:40, counting 2 fix rounds per
// deep phase (the usual here)'), in place of the old 'About N min left in the
// milestone' row: in the estimate colour, stamped [HH:MM] like the other estimate
// rows; 'No estimate yet: <the kernel's reason>' when road.end is null. The panel
// reads road from the running step's note (.vbw/runtime/step.json) while a step
// runs and from next.json (the last vbw next) otherwise; it works no milestone
// time out itself: a history alone shows no milestone row, and a road of null
// shows none. panel-estimate.js keeps only the step median the Timeline's bars use.
// Times are local to Europe/Zurich (UTC+01:00, +02:00 in summer), so a UTC clock shows.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, walk, deepFreeze, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen, hhmm } from '../r189/helpers/screen.mjs'

process.env.TZ = 'Europe/Zurich'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const pane = await import(pathToFileURL(PLUGIN + '/hooks/panel-pane.js').href)
const est = await import(pathToFileURL(PLUGIN + '/hooks/panel-estimate.js').href)

const NOTE = ROOT + '/.vbw/runtime/step.json'
const STEPS = ROOT + '/.git/vbw/steps.json'
const S = 1000
const MIN = 60 * S
const TICK = 2000
const WIDTH = 200
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
const STEP_END = NOW + 12 * MIN
const ROAD_END = NOW + 130 * MIN
const OTHER_END = NOW + 61 * MIN
// The kernel's road as vbw next --json and the note carry it.
const road = (end, over = {}) => ({
  seconds: Math.round((end - NOW) / 1000), end: iso(end), rounds: { deep: 2 },
  basis: '2 waves, 2 proofs, 1 QA check, 2 fix rounds per deep phase (median of 4 finished deep phases)',
  say: 'Milestone end: about 2 h 10 min, until around ' + hhmm(end) + ', counting 2 fix rounds per deep phase (the usual here)', ...over,
})
const NO_ROAD = { seconds: null, end: null, rounds: {}, basis: 'VBW has timed fewer than 3 proofs here', say: 'no milestone end time yet (VBW has timed fewer than 3 proofs here)' }
const note = (over = {}) => ({
  kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(T0 - 300 * S), ids: ['P44.1', 'P44.2'],
  doing: 'building P44.1, P44.2', parts: { done: 1, total: 2 }, proof: null, first_end: iso(STEP_END), end: iso(STEP_END), late: false,
  road: road(ROAD_END), ...over,
})
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

async function session(rec, nx, files = {}) {
  const h = await mount({ files })
  h.git()
  h.project(rec, nx)
  await h.start()
  await h.advance(4000)
  return h
}
const draw = (h) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: WIDTH, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} } })
const paneText = async (h) => screen(await draw(h), Infinity).join('\n').replace(/\s+/g, ' ')
const OLD = /min left in the milestone|No estimate yet: there are not enough/

test("while a step runs, the Now tab shows the kernel's road sentence from the note, stamped, in place of the old milestone row", async () => {
  const h = await session(building(), next({ action: 'run' }), { [NOTE]: JSON.stringify(note()) })
  const text = await paneText(h)
  assert.match(text, new RegExp('\\[\\d\\d:\\d\\d\\] Milestone end: about 2 h 10 min, until around ' + hhmm(ROAD_END) + ', counting 2 fix rounds per deep phase \\(the usual here\\)\\.'), text)
  assert.match(text, new RegExp('until around ' + hhmm(STEP_END)), 'the step time is gone: ' + text)
  assert.doesNotMatch(text, OLD)
  assert.deepEqual(h.errors, [])
})

test('the road sentence keeps the estimate colour; with no end it reads No estimate yet with the kernel reason, plain', () => {
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
  const [text, c] = colour(timed, 'estimate-milestone')
  assert.ok(text.endsWith('Milestone end: about 2 h 10 min, until around ' + hhmm(ROAD_END) + ', counting 2 fix rounds per deep phase (the usual here).'), text)
  assert.equal(c, P.ESTIMATE)
  const none = view.panelView({ record: busy, next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: [], step: note({ road: NO_ROAD }) })
  const [plain, nc] = colour(none, 'estimate-milestone')
  assert.equal(plain, 'No estimate yet: VBW has timed fewer than 3 proofs here.')
  assert.equal(nc, undefined)
})

test('with nothing running the road comes from the last vbw next (next.json), and no step time shows', async () => {
  const h = await session(record(), next({ action: 'build', road: road(ROAD_END) }))
  const text = await paneText(h)
  assert.match(text, new RegExp('Milestone end: about 2 h 10 min, until around ' + hhmm(ROAD_END)), text)
  assert.doesNotMatch(text, /This step/)
  assert.doesNotMatch(text, OLD)
})

test("the note's road wins while its step runs; a note of another run is not this step's, so next.json's road shows", async () => {
  const live = await session(building(), next({ action: 'run', road: road(OTHER_END) }), { [NOTE]: JSON.stringify(note()) })
  const liveText = await paneText(live)
  assert.match(liveText, new RegExp('until around ' + hhmm(ROAD_END) + ', counting'), liveText)
  assert.doesNotMatch(liveText, new RegExp('until around ' + hhmm(OTHER_END) + ', counting'))
  const stale = await session(building(), next({ action: 'run', road: road(OTHER_END) }), { [NOTE]: JSON.stringify(note({ run: 'build-0' })) })
  const staleText = await paneText(stale)
  assert.match(staleText, new RegExp('until around ' + hhmm(OTHER_END) + ', counting'), staleText)
  assert.doesNotMatch(staleText, new RegExp('until around ' + hhmm(ROAD_END) + ', counting'))
})

test('when the step ends, the road of the last vbw next takes over at the next refresh', async () => {
  const h = await session(building(), next({ action: 'run', road: road(OTHER_END) }), { [NOTE]: JSON.stringify(note()) })
  assert.match(await paneText(h), new RegExp('until around ' + hhmm(ROAD_END) + ', counting'))
  h.remove(NOTE)
  h.project(record({ plans: PLANS.map((p) => ({ ...p, status: 'done' })) }))
  await h.advance(TICK)
  const text = await paneText(h)
  assert.match(text, new RegExp('until around ' + hhmm(OTHER_END) + ', counting'), text)
  assert.doesNotMatch(text, new RegExp('until around ' + hhmm(ROAD_END)))
})

test('a road of null, or none at all, shows no milestone row', async () => {
  for (const nx of [next({ action: 'ship', gate: true, road: null }), next({ action: 'build' })]) {
    const h = await session(record(), nx)
    const text = await paneText(h)
    assert.doesNotMatch(text, /Milestone end|No estimate yet/, text)
    assert.doesNotMatch(text, OLD)
  }
})

test('the panel works no milestone time out itself: a history alone, with phases left, shows no milestone row', async () => {
  const h = await session(building(), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY) })
  const text = await paneText(h)
  assert.doesNotMatch(text, /Milestone end|No estimate yet/, text)
  assert.doesNotMatch(text, OLD)
  const r = est.estimate({ steps: HISTORY.steps, lease: lease('build', NOW - 300 * S), phasesLeft: 4, now: NOW })
  assert.equal(r.milestone, undefined, 'panel-estimate.js still works a milestone time out')
  assert.deepEqual(r.step, { state: 'approx', seconds: 600 }, "the Timeline's step median is gone")
})

test('the panel only reads: no file is written while it shows the road', async () => {
  const h = await session(building(), next({ action: 'run', road: road(OTHER_END) }), { [NOTE]: JSON.stringify(note()) })
  await h.advance(60000)
  assert.equal(h.count('fs.write'), 0)
  assert.deepEqual(h.errors, [])
})
