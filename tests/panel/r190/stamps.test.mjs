// R190, phase P146 (evidence level L1, the stand-in for Claude Code's mods API):
// the 9 October list's P6, checked on the panel as it shipped in M34. Every
// 'VBW needs you' sentence and every time-left sentence in Mission Control starts
// with the local time it began saying so, as '[HH:MM] '. A redraw where only the
// clock moved keeps the stamp; a sentence with no known start time has no stamp,
// never a wrong or empty one; with no basis for an estimate the panel says so
// plainly. R189's tests/panel/r189/now-box.test.mjs covers the approve gate and
// the 'taking longer' sentence; this file covers every other gate kind, both
// time-left sentences, and the edges.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen, hhmm } from '../r189/helpers/screen.mjs'

const { panelView } = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const TICK = 2000
const S = 1000
const NEXT = ROOT + '/.vbw/runtime/next.json'
const STEPS = ROOT + '/.git/vbw/steps.json'
const WIDTH = 200
const STAMP = /^\[(\d\d:\d\d)\] /
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, started_at: iso(T0 - 1e7 - i * 1e5), ended_at: iso(T0 - 1e7 - i * 1e5 + s * 1000), seconds: s }))
// Usual times: a build 20 min, a check 5 min.
const HISTORY = { steps: [...steps('build', [1200, 1200, 1200]), ...steps('qa', [300, 300, 300])] }
const PLANS = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]

async function session(rec = record(), nx = next(), files = {}) {
  const h = await mount({ files })
  h.git()
  h.project(rec, nx)
  await h.start()
  await h.advance(4000)
  return h
}
// The box at the top of the Now tab says the state in its own words (R189); the need
// sentence is the row below it.
const sentences = async (h) => (await paneLines(h)).filter((l) => !/^[│╭╰]/.test(l))
const paneLines = async (h) => screen(await h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: WIDTH, placement: 'dock', scroll: { offset: 0, bodyRows: 120 }, view: {} } }), WIDTH).map((l) => l.trim())

// Every gate kind, the record that keeps it standing, and the words of its need sentence.
const GATES = [
  ['approve', {}, {}, /Please approve the plan/],
  ['approve', { files: ['tests/login.bats'] }, {}, /Please approve the plan/],
  ['accept', { requirements: ['R54'] }, {}, /check the result by hand: R54/],
  ['ship', {}, {}, /ready: your go-ahead to ship/],
  ['spec', {}, {}, /say what to build/],
  ['escalate', { fixes: ['F3'] }, { fixes: [{ id: 'F3', status: 'escalated' }] }, /decision is needed from you on F3/],
  ['unblock', { plans: ['P44.1'] }, { plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'blocked' }] }, /blocked and needs you: P44\.1/],
  ['scope', {}, { evidence: { scope: [{ file: 'src/x.js' }] } }, /outside their planned files/],
  ['milestone', {}, { milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' } }, /shipped: say what to build next/],
  ['convert', {}, {}, /VBW 1 plan is here/],
]

test("every gate kind's need sentence in Mission Control starts with [HH:MM] of when the gate was reached", async () => {
  for (const [action, detail, standing, words] of GATES) {
    const h = await session(record(standing))
    await h.advance(90 * S) // the gate comes later than the session start, in another minute
    const at = h.now()
    h.write(NEXT, next({ action, gate: true, detail }))
    await h.advance(TICK)
    const line = (await sentences(h)).find((l) => words.test(l))
    const name = action + ' ' + JSON.stringify(detail)
    assert.ok(line, name + ': no need sentence in Mission Control')
    const m = STAMP.exec(line)
    assert.ok(m, name + ": '" + line + "' does not start with [HH:MM]")
    assert.equal(m[1], hhmm(at), name + ': the stamp is not the time the gate was reached')
  }
})

test('the question and the /compact need sentences start with [HH:MM] of when VBW began needing it', async () => {
  const q = await session()
  await q.advance(90 * S)
  const asked = q.now()
  const asking = q.fire('tool.call', { tool: 'AskUserQuestion', tool_use_id: 'q1', questions: [{ question: 'Which?' }] }, () => new Promise(() => {}))
  await q.settle()
  const line = (await sentences(q)).find((l) => /question for you/.test(l))
  assert.ok(line, 'no question sentence')
  assert.equal((STAMP.exec(line) || [])[1], hhmm(asked), "'" + line + "'")
  void asking

  const c = await session()
  await c.advance(90 * S)
  c.setUsage({ cost: { usd: 1 }, context: { percent: 90 } })
  const at = c.now()
  c.write(NEXT, next({ action: 'build', gate: false }))
  await c.advance(TICK)
  const compact = (await sentences(c)).find((l) => /\/compact/.test(l))
  assert.ok(compact, 'no /compact sentence')
  assert.equal((STAMP.exec(compact) || [])[1], hhmm(at), "'" + compact + "'")
})

test("both time-left sentences, this step's and the milestone's, start with [HH:MM]", async () => {
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY) })
  const lines = await paneLines(h)
  const step = lines.find((l) => /About \d+ min left in this step/.test(l))
  const milestone = lines.find((l) => /About \d+ min left in the milestone/.test(l))
  assert.ok(step && milestone, lines.join('\n'))
  assert.match(step, /^\[\d\d:\d\d\] About \d+ min left in this step/)
  assert.match(milestone, /^\[\d\d:\d\d\] About \d+ min left in the milestone/)
})

test('a redraw where only the clock moved keeps the stamp; new words get the time they began', async () => {
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY) })
  const seen = []
  for (let i = 0; i < 150; i++) {
    const line = (await paneLines(h)).find((l) => /min left in this step/.test(l))
    const m = /^\[(\d\d:\d\d)\] (.*)$/.exec(line || '')
    assert.ok(m, "no stamped time-left sentence at tick " + i + ": '" + line + "'")
    seen.push({ clock: hhmm(h.now()), stamp: m[1], words: m[2] })
    await h.advance(TICK)
  }
  let held = 0
  for (let i = 1; i < seen.length; i++) {
    const [a, b] = [seen[i - 1], seen[i]]
    if (a.words === b.words) {
      assert.equal(b.stamp, a.stamp, "the stamp of '" + b.words + "' moved with the clock")
      if (a.clock !== b.clock) held++
    } else assert.equal(b.stamp, b.clock, "'" + b.words + "' is stamped " + b.stamp + ', not when it began, ' + b.clock)
  }
  assert.ok(held > 0, 'the clock never moved a minute while the words stayed: the check proves nothing')
})

test('a sentence with no known start time has no stamp, never a wrong or empty one', () => {
  const rec = record({ lease: lease('build', T0 - 300 * S), plans: PLANS })
  for (const stamps of [{}, { need: NaN, 'estimate-step': undefined, 'estimate-milestone': null }, { need: 'soon', 'estimate-step': Infinity, 'estimate-milestone': '' }]) {
    const view = panelView({ record: rec, next: next(), now: T0, steps: HISTORY.steps, cost: 1, stamps })
    const left = view.rows.filter((r) => /^estimate-/.test(r.id))
    assert.equal(left.length, 2, JSON.stringify(view.rows))
    for (const r of left) assert.match(r.text, /^About \d+ min left/, JSON.stringify(stamps) + ': ' + r.text)
    const gate = panelView({ record: record(), next: next({ action: 'approve', gate: true }), nextAt: null, now: T0, stamps })
    const need = gate.rows.find((r) => r.id === 'need')
    assert.equal(need.text, 'Please approve the plan before VBW builds it.', JSON.stringify(stamps))
    for (const r of [...view.rows, ...gate.rows]) assert.doesNotMatch(r.text, /\[\s*\]|\[:\]|\[NaN|\[undefined|\[null|\[Invalid/, r.text)
  }
})

test('with no basis for an estimate the panel says so plainly, with no stamp and no number', async () => {
  const few = { steps: steps('build', [1200, 1200]) }
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(few) })
  const lines = await paneLines(h)
  const none = lines.filter((l) => /No estimate yet/.test(l))
  assert.ok(none.length >= 1, lines.join('\n'))
  for (const l of none) assert.equal(l, 'No estimate yet: there are not enough finished steps to go on.')
  assert.ok(!lines.some((l) => /min left/.test(l)), 'a time left is shown without a basis')
})

test('no stamp anywhere in Mission Control is empty or malformed, in any state', async () => {
  const cases = [
    [record(), next()],
    [record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' })],
    [record(), next({ action: 'approve', gate: true })],
    [record({ milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' } }), next({ action: 'milestone', gate: true })],
  ]
  for (const [rec, nx] of cases) {
    const lines = await paneLines(await session(rec, nx, { [STEPS]: JSON.stringify(HISTORY) }))
    for (const l of lines) {
      assert.doesNotMatch(l, /\[\s*\]|\[:\]|\[NaN|\[undefined|\[null|\[Invalid/, l)
      const m = /\[(\d\d):(\d\d)\]/.exec(l)
      if (m) assert.ok(Number(m[1]) < 24 && Number(m[2]) < 60, l)
    }
  }
})
