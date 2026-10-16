// R58 (and R56): the panel shows the estimated time left for the current step
// and for the milestone, from the clone's own record of finished steps, and
// says plainly when it has no basis yet. Approximate, never negative, never
// from anywhere but local files (L1, stand-in for the mods API).
// R190 (D425) replaced the step's sentence: the running step's time comes from
// the kernel's note (.vbw/runtime/step.json), in full wording ('about 10 min,
// until around HH:MM'; 'later than usual' when late); the milestone estimate is
// unchanged.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, ROOT, T0, ALLOWED } from './helpers/fake-mod.mjs'

const STEPS = ROOT + '/.git/vbw/steps.json'
const NOTE = ROOT + '/.vbw/runtime/step.json'
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, started_at: iso(T0 - 1e7 - i * 1e5), ended_at: iso(T0 - 1e7 - i * 1e5 + s * 1000), seconds: s }))
const HISTORY = { steps: [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])] }
// The kernel's note for the build: it ends ENDSEC seconds after the first drawing (T0 + 4 s).
const note = (elapsedSec, endSec, over = {}) => JSON.stringify({ kind: 'build', run: 'build-1', session: 'sess-1', pid: null,
  started_at: iso(T0 - elapsedSec * 1000), ids: ['P44.1'], doing: 'building P44.1', parts: { done: 0, total: 1 }, proof: null,
  first_end: iso(T0 + 4000 + endSec * 1000), end: iso(T0 + 4000 + endSec * 1000), late: false, ...over })
const building = (elapsedSec) => record({ lease: lease('build', T0 - elapsedSec * 1000), plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }] })

async function session(rec, files, options = {}) {
  const h = await mount({ ...options, files })
  h.git()
  h.project(rec, next({ action: 'run' }))
  await h.start()
  await h.advance(4000)
  return h
}

test('with no history the panel says plainly it has no basis yet, and shows no time', async () => {
  const h = await session(building(60))
  const text = await h.text()
  assert.match(text, /no estimate|not enough|no basis/i)
  assert.doesNotMatch(text, /about \d/i)
  assert.deepEqual(h.errors, [])
})

test('with too little history (2 finished steps) it still gives no number', async () => {
  const h = await session(building(60), { [STEPS]: JSON.stringify({ steps: steps('build', [600, 900]) }) })
  assert.doesNotMatch(await h.text(), /about \d/i)
})

test('with enough history it shows approximate time left for the step and for the milestone', async () => {
  const h = await session(building(300), { [STEPS]: JSON.stringify(HISTORY), [NOTE]: note(300, 600) })
  const texts = await h.texts()
  const about = texts.filter((t) => /about \d+/i.test(t))
  assert.equal(about.length, 2, 'one line for the step, one for the milestone')
  assert.ok(about.some((t) => /step/i.test(t) && /about 10 min/i.test(t)), '600 s left in the step: ' + about.join(' / '))
  assert.ok(about.some((t) => /milestone/i.test(t)))
  assert.doesNotMatch(texts.join(' '), /exactly|precisely/i)
})

test('a step that runs past its usual time says it is later than usual', async () => {
  const h = await session(building(5000), { [STEPS]: JSON.stringify(HISTORY), [NOTE]: note(5000, 600, { first_end: iso(T0 - 4000 * 1000), late: true }) })
  const text = await h.text()
  assert.match(text, /later than usual/i)
  assert.doesNotMatch(text, /-\d|negative|overdue|ago/i)
})

test('idle: only the milestone is estimated', async () => {
  const h = await session(record(), { [STEPS]: JSON.stringify(HISTORY) })
  const texts = await h.texts()
  assert.ok(texts.some((t) => /milestone/i.test(t) && /about \d+/i.test(t)))
  assert.ok(!texts.some((t) => /this step/i.test(t)))
})

test('no phase left: no milestone estimate', async () => {
  const done = record().phases.map((p) => (p.milestone === 'M9' ? { ...p, qa: { result: 'pass' } } : p))
  const h = await session(record({ phases: done }), { [STEPS]: JSON.stringify(HISTORY) })
  assert.doesNotMatch(await h.text(), /about \d+|no estimate|not enough/i)
})

test('a clone cache that is missing, empty or garbled means no history, never an error', async () => {
  for (const bad of ['', '{"steps": 5}', 'not json', '[]', '{"steps": [null, 3]}']) {
    const h = await session(building(60), { [STEPS]: bad })
    assert.doesNotMatch(await h.text(), /about \d/i)
    assert.deepEqual(h.errors, [], JSON.stringify(bad))
  }
})

test('in a linked worktree the history is read from the clone it belongs to', async () => {
  const files = {
    [ROOT + '/.git']: 'gitdir: /main/.git/worktrees/w1\n',
    '/main/.git/worktrees/w1/commondir': '../..\n',
    '/main/.git/vbw/steps.json': JSON.stringify(HISTORY),
    [NOTE]: note(300, 600),
  }
  const h = await mount({ files })
  h.project(building(300), next({ action: 'run' }))
  await h.start()
  await h.advance(4000)
  assert.ok(h.callsOf('fs.read').some((a) => a[0] === '/main/.git/vbw/steps.json'))
  assert.match(await h.text(), /about 10 min/i)
})

test('the history is read only from the clone cache, never written, with no network', async () => {
  const h = await session(building(300), { [STEPS]: JSON.stringify(HISTORY) })
  await h.advance(60000)
  assert.equal(h.count('fs.write'), 0)
  for (const n of h.names()) assert.ok(ALLOWED.has(n), n)
  for (const [p] of h.callsOf('fs.read')) assert.ok(p.startsWith(ROOT + '/'), p)
  assert.equal(h.files.get(STEPS).text, JSON.stringify(HISTORY))
})

test('the estimate follows the clock: a minute later it has gone down, and it redraws only for that', async () => {
  const h = await session(building(300), { [STEPS]: JSON.stringify(HISTORY), [NOTE]: note(300, 600) })
  assert.match(await h.text(), /about 10 min/i)
  await h.advance(5 * 60000)
  assert.match(await h.text(), /about 5 min/i)
})

test('the cost and the estimates share the panel', async () => {
  const h = await session(building(300), { [STEPS]: JSON.stringify(HISTORY) })
  const text = await h.text()
  assert.match(text, /\$1\.42/)
  assert.match(text, /about \d+/i)
})
