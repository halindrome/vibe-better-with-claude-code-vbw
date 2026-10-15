// R189, phase P144 (evidence level L1, the stand-in for Claude Code's mods API):
// Mission Control's Now tab opens on a 'what's happening now' box: VBW's state as
// a plain sentence (planning, building which phase, proving, checking, waiting
// for you and for what, or nothing running), the current step with the HH:MM it
// started, and the session cost line (D106). The box follows the state within
// one refresh (2 s). Every event and message line starts with the local time as
// HH:MM: Mission Control's need and time-left sentences ('[14:20] About 2 min
// left in this step.'), a helper card's state (started, finished, failed), the
// all-checks-pass line on Comms and the What's next recommendation. A message
// keeps the time it began saying what it says, so the clock alone redraws nothing.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, find, walk, deepFreeze, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen, textOf, hhmm } from './helpers/screen.mjs'

const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)
const TICK = 2000
const NEXT = ROOT + '/.vbw/runtime/next.json'
const STEPS = ROOT + '/.git/vbw/steps.json'
const S = 1000
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, started_at: iso(T0 - 1e7 - i * 1e5), ended_at: iso(T0 - 1e7 - i * 1e5 + s * 1000), seconds: s }))
const HISTORY = { steps: [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])] }
const PLANS = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]
const WIDTH = 60
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

async function session(rec = record(), nx = next(), files = {}) {
  const h = await mount({ files })
  h.git()
  h.project(rec, nx)
  await h.start()
  await h.advance(4000)
  return h
}
const pane = (h) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: WIDTH, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} } })
const paneLines = async (h) => screen(await pane(h), WIDTH)

// The box: the first bordered Box of the Now tab, drawn before the milestone sentence.
async function nowBox(h) {
  const tree = await pane(h)
  const order = []
  walk(tree, (n) => order.push(n))
  const box = order.find((n) => n.type === 'Box' && n.props.borderStyle)
  assert.ok(box, 'the Now tab has no box')
  const milestone = order.findIndex((n) => n.type === 'Text' && /^Working on /.test(textOf(n)))
  assert.ok(milestone < 0 || order.indexOf(box) < milestone, 'the box is not at the top of the Now tab')
  return screen(box, WIDTH).join('\n')
}

test("the Now tab opens on the box: the state, the step with the time it started, and the session cost, above everything else", async () => {
  const started = T0 - 300 * S
  const h = await session(record({ lease: lease('build', started), plans: PLANS }), next({ action: 'run' }))
  const box = await nowBox(h)
  assert.match(box, /building/i)
  assert.match(box, /P44/)
  assert.ok(box.includes(hhmm(started)), 'the step has no start time ' + hhmm(started) + ':\n' + box)
  assert.match(box, /\$1\.42/, 'the session cost line is in the box')
  assert.equal((await paneLines(h)).filter((l) => /\$1\.42/.test(l)).length, 1, 'the cost line is drawn once')
})

test('each state reads as a plain sentence: planning, building which phase, proving, checking, waiting for you and for what, nothing running', async () => {
  const cases = [
    [record({ lease: lease('plan', T0) }), next({ action: 'run' }), {}, [/planning/i]],
    [record({ lease: lease('build', T0), plans: PLANS }), next({ action: 'run' }), {}, [/building/i, /P44/]],
    [record(), next({ action: 'prove' }), { [ROOT + '/.vbw/runtime/proving.sess-1']: '4242\n' }, [/proving/i]],
    [record({ lease: lease('qa', T0) }), next({ action: 'run' }), {}, [/checking/i]],
    [record(), next({ action: 'approve', gate: true }), {}, [/waiting for you/i, /approv/i]],
    [record(), next(), {}, [/nothing (is )?running/i]],
  ]
  for (const [rec, nx, files, want] of cases) {
    const h = await session(rec, nx, files)
    const box = await nowBox(h)
    for (const re of want) assert.match(box, re, JSON.stringify(nx) + ' ' + JSON.stringify(rec.lease))
  }
})

test('the box follows the state within one refresh, with no other event', async () => {
  const h = await session()
  assert.match(await nowBox(h), /nothing (is )?running/i)
  h.project(record({ lease: lease('build', h.now()), plans: PLANS }), next({ action: 'run' }))
  await h.advance(TICK)
  assert.match(await nowBox(h), /building/i)
  h.project(record(), next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  assert.match(await nowBox(h), /waiting for you/i)
})

test("Mission Control's need sentence starts with the time the gate was reached", async () => {
  const h = await session()
  const at = h.now()
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  const line = (await paneLines(h)).find((l) => /Please approve/.test(l))
  assert.ok(line, 'no need sentence')
  assert.ok(line.trim().startsWith('[' + hhmm(at) + '] '), "'" + line + "' does not start with [" + hhmm(at) + ']')
})

test('the time-left sentences start with [HH:MM], as in "[14:20] About 2 min left in this step."', async () => {
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY) })
  const lines = await paneLines(h)
  const left = lines.filter((l) => /About \d+ min left/.test(l))
  assert.ok(left.length >= 1, 'no time-left sentence')
  for (const l of left) assert.match(l.trim(), /^\[\d\d:\d\d\] About \d+ min left/)
})

test('a message keeps the time it began saying what it says: the clock moving alone redraws nothing', async () => {
  const h = await session()
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  const first = (await paneLines(h)).find((l) => /Please approve/.test(l))
  const draws = h.invalidations()
  await h.advance(3 * 60000)
  assert.equal(h.invalidations(), draws, 'the clock alone redrew the panel')
  assert.equal((await paneLines(h)).find((l) => /Please approve/.test(l)), first)
})

test("a helper's card starts its state line with the time: when it started, finished or failed", async () => {
  const NOW = T0 + 3600 * S
  const agent = (over) => ({ id: 'a', role: 'dev', label: 'P44.1', state: 'working', activity: { kind: 'tool', text: 'editing a.js' }, startedAt: NOW - 900 * S, endedAt: null, lastSeenAt: NOW - S, tokens: 1000, result: null, ...over })
  const run = deepFreeze({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 1000 * S, endedAt: null, status: 'running', agents: [
    agent({ id: 'w', startedAt: NOW - 900 * S }),
    agent({ id: 'd', label: 'P44.2', state: 'done', startedAt: NOW - 3000 * S, endedAt: NOW - 1500 * S, result: 'ok' }),
    agent({ id: 'f', label: 'P44.3', state: 'failed', startedAt: NOW - 3000 * S, endedAt: NOW - 2400 * S, result: 'boom' }),
  ] })
  const tree = live.renderNow(UI, live.nowModel({ run, now: NOW }))
  const cardLines = (id) => screen(find(tree, (n) => n.type === 'Box' && n.props.key === 'card-box:' + id), Infinity).join('\n')
  assert.ok(cardLines('w').includes('[' + hhmm(NOW - 900 * S) + '] ● running'), cardLines('w'))
  assert.ok(cardLines('d').includes('[' + hhmm(NOW - 1500 * S) + '] ✓ done'), cardLines('d'))
  assert.ok(cardLines('f').includes('[' + hhmm(NOW - 2400 * S) + '] ✗ failed'), cardLines('f'))
})

test('the all-checks-pass line on Comms starts with the time the proof passed', async () => {
  const h = await session()
  const at = h.now()
  h.project(record({ evidence: { at: iso(at), passed: true, contract: 'c1', checks: {} } }))
  await h.advance(TICK)
  const lines = screen(await h.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100 }), 100)
  const pass = lines.find((l) => /All checks pass/.test(l))
  assert.ok(pass, 'no all-checks-pass line')
  assert.ok(pass.trim().startsWith('[' + hhmm(at) + '] '), "'" + pass + "'")
})

test("the What's next recommendation shows the time it was written as [HH:MM]", async () => {
  const at = T0 - 7200 * S
  const h = await session(record({ recommendation: { at: iso(at), top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most.', size: 'small', source: 'T4' }, runners: [] } }))
  const section = find(await pane(h), (n) => n.type === 'Box' && n.props.key === 'whats-next')
  assert.ok(section)
  const lines = screen(section, WIDTH)
  assert.ok(lines.some((l) => l.trim().startsWith('[' + hhmm(at) + ']')), lines.join('\n'))
})

test('a state change that touches nothing else still redraws the box within one refresh: a proof starting, then ending', async () => {
  const mark = ROOT + '/.vbw/runtime/proving.sess-1'
  const h = await session()
  assert.match(await nowBox(h), /nothing (is )?running/i)
  let draws = h.invalidations()
  h.write(mark, '4242\n')
  await h.advance(TICK)
  assert.ok(h.invalidations() > draws, 'the panel was not asked to redraw when the proof began')
  assert.match(await nowBox(h), /proving/i)
  draws = h.invalidations()
  h.remove(mark)
  await h.advance(TICK)
  assert.ok(h.invalidations() > draws, 'the panel was not asked to redraw when the proof ended')
  assert.match(await nowBox(h), /nothing (is )?running/i)
})

test('a time-left sentence keeps the time it began saying what it says while the words stay the same', async () => {
  // A step far past its usual time says "taking longer than usual" and goes on saying it.
  const h = await session(record({ lease: lease('build', T0 - 3 * 3600 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY) })
  const sentence = async () => (await paneLines(h)).find((l) => /taking longer than usual/.test(l))
  const first = await sentence()
  assert.ok(first, 'no taking-longer sentence')
  assert.match(first.trim(), /^\[\d\d:\d\d\] /)
  await h.advance(10 * 60000)
  assert.equal(await sentence(), first, 'the time moved with the clock')
})
