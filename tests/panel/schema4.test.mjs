// R150: the panel shows the same on a schema-4 record (more than 50 checks,
// the protected field right after lease) as on the same project at schema 3,
// with no error. Driven through the stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, T0 } from './helpers/fake-mod.mjs'

const REQS = [['R1', 'M9', 'proven'], ['R2', 'M9', 'open'], ['R3', 'M9', 'failing']]
  .map(([id, milestone, status]) => ({ id, text: id, proof: 'auto', status, milestone }))

const CHECKS = [...Array(60).keys()].map((i) => ({
  id: 'C' + (i + 1), req: REQS[i % 3].id, run: ['sh', 'tests/c' + (i + 1) + '.sh'], files: ['tests/c' + (i + 1) + '.sh', 'tests/shared.sh'],
}))

// The two formats of one record: schema 3 without the field, schema 4 with it
// placed right after lease.
function formats(rec) {
  const three = { ...rec, schema: 3, checks: CHECKS }
  const protectedFiles = [...new Set(CHECKS.flatMap((c) => c.files))].sort()
  const { schema: _three, lease: l, checks, ...rest } = three
  const four = { schema: 4, lease: l ?? null, protected: protectedFiles, checks, ...rest }
  return { three, four }
}

async function shown(rec, nxt) {
  const h = await mount()
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return { text: await h.text(), errors: h.errors }
}

for (const [name, rec, nxt] of [
  ['idle', record({ requirements: REQS }), next()],
  ['building', record({ requirements: REQS, lease: lease('build', T0 - 90000), plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }] }), next({ action: 'run' })],
]) {
  test('R150: the pane reads the same on a schema-4 record as on schema 3 (' + name + ')', async () => {
    const { three, four } = formats(rec)
    assert.deepEqual(Object.keys(four).slice(0, 4), ['schema', 'lease', 'protected', 'checks'])
    const a = await shown(three, nxt)
    const b = await shown(four, nxt)
    assert.deepEqual(a.errors, [])
    assert.deepEqual(b.errors, [])
    assert.equal(b.text, a.text)
  })
}
