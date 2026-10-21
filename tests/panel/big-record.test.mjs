// R149: the panel shows the same on a record larger than 2 MB as on a small
// one: the large record holds the same history with every text padded by
// filler (~), and the pane, once the filler is removed, reads the same, with
// no error. Driven through the stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, T0 } from './helpers/fake-mod.mjs'

const FILL = '~'.repeat(5000)

// A shipped milestone M1 of history: 200 requirements, phases, plans and decisions.
function history(fill) {
  const n = [...Array(200).keys()].map((i) => i + 100)
  return {
    shipped: [{ id: 'M1', title: 'Old work', at: '2026-01-01T00:00:00Z' }],
    requirements: n.map((i) => ({ id: 'R' + i, text: 'Old part ' + i + fill, proof: 'auto', status: 'proven', milestone: 'M1' })),
    phases: n.map((i) => ({ id: 'P' + i, title: 'Old phase ' + i, milestone: 'M1', goal: 'Old goal ' + i + fill, qa: { result: 'pass' } })),
    plans: n.map((i) => ({ id: 'P' + i + '.1', phase: 'P' + i, title: 'Old plan ' + i, status: 'done', tasks: ['Old task ' + i + fill] })),
    decisions: n.map((i) => ({ id: 'D' + i, text: 'Old decision ' + i + fill, at: '2026-01-01T00:00:00Z' })),
  }
}

// with(rec, fill): REC with the history placed before its own entries.
function withHistory(rec, fill) {
  const h = history(fill)
  return {
    ...rec,
    shipped: h.shipped,
    requirements: [...h.requirements, ...rec.requirements],
    phases: [...h.phases, ...rec.phases],
    plans: [...h.plans, ...rec.plans],
    decisions: h.decisions,
  }
}

const REQS = [['R1', 'M9', 'proven'], ['R2', 'M9', 'open'], ['R3', 'M9', 'failing']]
  .map(([id, milestone, status]) => ({ id, text: id, proof: 'auto', status, milestone }))

async function shown(rec, nxt) {
  const h = await mount()
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  const text = await h.text()
  return { text: text.replaceAll('~', ''), errors: h.errors }
}

for (const [name, rec, nxt] of [
  ['idle', record({ requirements: REQS }), next()],
  ['building', record({ requirements: REQS, lease: lease('build', T0 - 90000), plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }] }), next({ action: 'run' })],
]) {
  test('R149: the pane reads the same on a record over 2 MB (' + name + ')', async () => {
    const large = withHistory(rec, FILL)
    assert.ok(JSON.stringify(large).length > 2 * 1024 * 1024, 'the large record is over 2 MB')
    const small = await shown(withHistory(rec, ''), nxt)
    const big = await shown(large, nxt)
    assert.deepEqual(big.errors, [])
    assert.deepEqual(small.errors, [])
    assert.equal(big.text, small.text)
  })
}
