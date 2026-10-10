// R150: the panel shows the same on a format-4 record (schema 4, the protected
// list right after lease) as on the same project as an older VBW wrote it
// (schema 3, no list), with 0 checks and with 60, and with no error. Driven
// through the stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, T0 } from './helpers/fake-mod.mjs'

const REQS = [['R1', 'M9', 'proven'], ['R2', 'M9', 'open'], ['R3', 'M9', 'failing']]
  .map(([id, milestone, status]) => ({ id, text: id, proof: 'auto', status, milestone }))

const checks = (n) => [...Array(n).keys()].map((i) => ({
  id: 'C' + (i + 1), req: REQS[i % 3].id, run: ['sh', 'tests/c' + (i + 1) + '.sh'], files: ['tests/c' + (i + 1) + '.sh', 'tests/shared.sh'],
}))

// The two formats of one record: schema 3 without the list, schema 4 with it
// placed right after lease (an empty list when there are no checks).
function formats(rec, n) {
  const older = { ...rec, schema: 3, checks: checks(n) }
  const protectedFiles = [...new Set(older.checks.flatMap((c) => c.files))].sort()
  const { schema: _older, lease: l, checks: cs, ...rest } = older
  const four = { schema: 4, lease: l ?? null, protected: protectedFiles, checks: cs, ...rest }
  return { older, four }
}

async function shown(rec, nxt) {
  const h = await mount()
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return { text: await h.text(), errors: h.errors }
}

for (const n of [0, 60]) {
  for (const [name, rec, nxt] of [
    ['idle', record({ requirements: REQS }), next()],
    ['building', record({ requirements: REQS, lease: lease('build', T0 - 90000), plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }] }), next({ action: 'run' })],
  ]) {
    test('R150: the pane reads the same on a format-4 record as on an older one (' + n + ' checks, ' + name + ')', async () => {
      const { older, four } = formats(rec, n)
      assert.deepEqual(Object.keys(four).slice(0, 4), ['schema', 'lease', 'protected', 'checks'])
      assert.equal(four.protected.length, n === 0 ? 0 : n + 1)
      const a = await shown(older, nxt)
      const b = await shown(four, nxt)
      assert.deepEqual(a.errors, [])
      assert.deepEqual(b.errors, [])
      assert.ok(b.text.length > 0)
      assert.equal(b.text, a.text)
    })
  }
}
