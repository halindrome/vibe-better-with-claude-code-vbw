// R58: estimates of the time left, from the durations of earlier steps in this
// project. plugin/hooks/panel-estimate.js is pure: finished steps in, an honest
// estimate out. Too little history: no number. Never negative (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze } from './helpers/fake-mod.mjs'

const mod = await import(pathToFileURL(PLUGIN + '/hooks/panel-estimate.js').href)
const NOW = Date.parse('2026-10-05T15:00:00Z')
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const steps = (kind, secs) =>
  secs.map((s, i) => ({ kind, run: kind + '-' + i, started_at: iso(NOW - 1e7 - i * 1e5), ended_at: iso(NOW - 1e7 - i * 1e5 + s * 1000), seconds: s }))
const lease = (kind, elapsedSec) => ({ run: kind + '-x', kind, started_at: iso(NOW - elapsedSec * 1000) })
const est = (o) => mod.estimate({ steps: [], lease: null, phasesLeft: 0, now: NOW, ...o })

test('the least history it will estimate from is stated: 3 finished steps', () => {
  assert.equal(mod.MIN_STEPS, 3)
})

test('the step: too little history says there is no basis and gives no number', () => {
  const r = est({ steps: steps('build', [600, 900]), lease: lease('build', 60) })
  assert.equal(r.step.state, 'none')
  assert.equal('seconds' in r.step, false)
})

test('the step: the usual time is the median of earlier steps of the same kind', () => {
  const r = est({ steps: steps('build', [600, 900, 1200]), lease: lease('build', 300) })
  assert.deepEqual(r.step, { state: 'approx', seconds: 600 })
})

test('only the latest 10 steps of a kind count', () => {
  const r = est({ steps: [...steps('build', [5000, 5000]), ...steps('build', Array(10).fill(100))], lease: lease('build', 40) })
  assert.deepEqual(r.step, { state: 'approx', seconds: 60 })
})

test('steps of another kind are not counted', () => {
  const r = est({ steps: [...steps('plan', [100, 100, 100, 100]), ...steps('build', [100, 100])], lease: lease('build', 10) })
  assert.equal(r.step.state, 'none')
})

test('a step that runs past its usual time is taking longer than usual, with no negative time', () => {
  for (const elapsed of [900, 901, 5000, 1e6]) {
    const r = est({ steps: steps('build', [600, 900, 1200]), lease: lease('build', elapsed) })
    assert.deepEqual(r.step, { state: 'longer' }, 'elapsed ' + elapsed)
  }
})

test('no step is running: no step estimate', () => {
  assert.equal(est({ steps: steps('build', [600, 900, 1200]), phasesLeft: 3 }).step, null)
})

test("the panel works no milestone time out of the history: the milestone's end is the kernel's road (R191.42)", () => {
  const s = [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])]
  for (const l of [null, lease('build', 300), lease('qa', 50), lease('build', 5000)]) {
    const r = est({ steps: s, lease: l, phasesLeft: 4 })
    assert.equal(r.milestone, undefined)
    assert.equal('milestone' in r, false)
  }
})

test('bad history is ignored, never a crash or a wrong number', () => {
  const bad = [null, 7, 'x', {}, { kind: 'build' }, { kind: 'build', seconds: -5 }, { kind: 'build', seconds: 'x' }, { kind: 'build', seconds: NaN }, { kind: 'build', seconds: 0 }]
  for (const steps of [bad, 'nope', null, undefined, {}]) {
    const r = est({ steps, lease: lease('build', 10), phasesLeft: 2 })
    assert.equal(r.step.state, 'none')
    assert.equal('milestone' in r, false)
  }
  const r = est({ steps: [...bad, ...steps('build', [600, 900, 1200])], lease: lease('build', 300) })
  assert.deepEqual(r.step, { state: 'approx', seconds: 600 })
})

test('a lease with an unreadable start gives no step estimate and no crash', () => {
  const r = est({ steps: steps('build', [600, 900, 1200]), lease: { kind: 'build', started_at: 'soon' } })
  assert.notEqual(r.step && r.step.state, 'approx')
})

test('estimating changes nothing in its input', () => {
  const input = deepFreeze({ steps: steps('build', [600, 900, 1200]), lease: lease('build', 5), phasesLeft: 2, now: NOW })
  assert.doesNotThrow(() => mod.estimate(input))
})
