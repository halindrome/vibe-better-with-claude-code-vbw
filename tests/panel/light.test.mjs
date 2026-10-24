// R55: the panel stays light. It reads only local project files, calls nothing
// that reaches the network or credentials, never writes (the record included),
// and does no redraw when nothing changed (L1, stand-in for the mods API). The
// drawings of the bench's cases are pinned, so work done for speed draws the same.
import test from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mount, record, next, lease, ALLOWED, ROOT, T0, PLUGIN } from './helpers/fake-mod.mjs'
import { building, writeCrew, working, TICK } from './r189/helpers/crew.mjs'

process.env.TZ = 'Europe/Zurich' // the drawings' HH:MM are local times

const REC = ROOT + '/.vbw/record.json'
const NEXT = ROOT + '/.vbw/runtime/next.json'

// A busy session: start, many changes, a need, a question, both commands, a close.
async function busySession(h) {
  h.project(record(), next())
  h.git()
  await h.start()
  await h.advance(3000)
  h.project(record({ lease: lease('build', h.now()), plans: [{ id: 'a', title: 'A', status: 'building' }] }), next({ action: 'run' }))
  await h.advance(3000)
  h.project(record(), next({ action: 'approve', gate: true }))
  await h.advance(3000)
  const asking = h.fire('tool.call', { tool: 'AskUserQuestion', questions: [] }, async () => ({ result: 'x' }))
  await asking
  await h.render()
  await h.cmd('vbw-panel')
  await h.cmd('vbw-sound', 'off')
  await h.cmd('vbw-sound', 'on')
  await h.fire('ui.close', { id: 'vbw-panel', origin: { kind: 'person' } })
  await h.advance(10000)
}

test('it only calls what a read-only panel needs: no network, no credentials, no processes', async () => {
  const h = await mount()
  await busySession(h)
  const used = h.names()
  const extra = used.filter((n) => !ALLOWED.has(n))
  assert.deepEqual(extra, [], 'calls outside the allowed set')
  for (const n of used) assert.doesNotMatch(n, /^(http|mcp|model|process|settings|agent|tool|telemetry)\.|^prompt\.submit$/)
  // The environment is read for two names only, to find this session's folder.
  for (const [name] of h.callsOf('env.get')) assert.ok(['HOME', 'CLAUDE_CONFIG_DIR'].includes(name), name)
  assert.deepEqual(h.errors, [])
})

test('it reads only the project, and the clone cache of finished steps', async () => {
  const h = await mount()
  await busySession(h)
  const paths = [...h.callsOf('fs.read'), ...h.callsOf('fs.stat'), ...h.callsOf('fs.exists')].map((a) => a[0])
  assert.ok(paths.length > 0)
  for (const p of paths) {
    assert.ok(p.startsWith(ROOT + '/') || p === ROOT, 'outside the project: ' + p)
    assert.doesNotMatch(p, /credentials|settings\.json|\.env|\.ssh|\.claude/i, p)
  }
})

test('it never writes: not the record, not any file', async () => {
  const h = await mount()
  await busySession(h)
  assert.equal(h.count('fs.write'), 0)
  // The record is exactly what the test last wrote: the panel did not touch it.
  assert.equal(h.files.get(REC).text, JSON.stringify(record()))
  assert.equal(h.files.get(NEXT).text, JSON.stringify(next({ action: 'approve', gate: true })))
})

test('nothing changed, no redraw: an idle project is only checked, not read or redrawn', async () => {
  const h = await mount()
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  const reads = h.count('fs.read')
  const draws = h.count('ui.invalidate')
  await h.advance(120000)
  assert.equal(h.count('fs.read'), reads, 'unchanged files are not read again')
  assert.equal(h.count('ui.invalidate'), draws, 'nothing to redraw')
  assert.ok(h.count('fs.stat') > 0, 'the files are checked cheaply')
})

test('during a run the panel redraws only when the minute it shows changes', async () => {
  const h = await mount()
  h.project(record({ lease: lease('build', T0), plans: [{ id: 'a', title: 'A', status: 'building' }] }), next({ action: 'run' }))
  await h.start()
  await h.advance(4000)
  const draws = h.count('ui.invalidate')
  await h.advance(5 * 60000)
  const redraws = h.count('ui.invalidate') - draws
  assert.ok(redraws >= 4 && redraws <= 6, 'redraws in 5 minutes: ' + redraws)
})

test('a changed file is read once and drawn once, however many ticks follow', async () => {
  const h = await mount()
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  const reads = h.count('fs.read')
  const draws = h.count('ui.invalidate')
  h.write(NEXT, next({ action: 'ship', gate: true }))
  await h.advance(30000)
  assert.ok(h.count('fs.read') - reads <= 2, 'the changed file is read once, not on every tick')
  assert.equal(h.count('ui.invalidate') - draws, 1)
})

test('the config folder is found once a session, not on every check while a run holds the lease', async () => {
  const { h } = await building(working(2))
  const from = h.calls.length
  await h.advance(10 * TICK)
  const ticks = h.calls.slice(from)
  assert.ok(ticks.some((c) => c.name === 'fs.list' && String(c.args[0]).endsWith('/sessions')), 'the list of chats is read on the checks')
  assert.deepEqual(ticks.filter((c) => c.name === 'env.get' || c.name === 'fs.exists').map((c) => c.name), [], 'the config folder is not looked for again')
  assert.ok(h.callsOf('env.get').length > 0, 'it was found at the start')
})

// The bench's cases (tools/bench-panel.mjs), each refresh as the bench makes it: its
// 20 warm-up refreshes and 30 more. The step case's lease starts at T0 (the bench
// takes the wall clock), so every run draws the same.
const STEPS_FILE = ROOT + '/.git/vbw/steps.json'
const NOTE = ROOT + '/.vbw/runtime/step.json'
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const pastSteps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, seconds: s }))
const RECOMMENDATION = (i) => ({ at: '2026-10-09T10:00:' + String(i % 60).padStart(2, '0') + 'Z', top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most this month.', size: 'small' }, runners: [{ text: 'Gift cards', size: 'large' }, { text: 'Dark mode', size: 'medium' }] })
async function idle(rec = record()) {
  const h = await mount()
  h.project(rec, next())
  h.git()
  await h.start()
  await h.advance(5000)
  await h.render()
  return h
}
const BENCH = {
  tick: [() => idle(), async (h) => {
    await h.advance(2000)
    return []
  }],
  refresh: [() => idle(), async (h, i) => {
    h.write(NEXT, next({ action: i % 2 ? 'build' : 'ship', gate: i % 2 === 0 }))
    await h.advance(2000)
    return [await h.render()]
  }],
  glance: [() => idle(), async (h, i) => {
    h.write(STEPS_FILE, { steps: [...pastSteps('build', [600, 900, 1200 + i]), ...pastSteps('qa', [100, 200, 300])] })
    h.setUsage({ cost: { usd: 1 + i / 100 } })
    await h.advance(2000)
    return [await h.render()]
  }],
  'whats-next': [() => idle(), async (h, i) => {
    h.project(record({ recommendation: RECOMMENDATION(i) }), next())
    await h.advance(2000)
    return [await h.render()]
  }],
  render: [async () => {
    const { h } = await building(working(5))
    h.git()
    return h
  }, async (h) => {
    writeCrew(h, h.now() + TICK, working(5))
    await h.advance(TICK)
    return [await h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100 }), await h.render()]
  }],
  step: [() => idle(record({ lease: lease('build', T0) })), async (h, i) => {
    const end = h.now() + (12 + (i % 5)) * 60000
    h.write(NOTE, {
      kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(h.now() - 300000), ids: ['P44.1'], doing: 'building P44.1',
      parts: { done: 1, total: 2 }, proof: null, first_end: iso(end), end: iso(end), late: false,
    })
    await h.advance(2000)
    return [await h.render()]
  }],
}
// A drawing as data: each element once (the stand-in's h() also keeps the children in
// props), a press handler as its name, the plugin's folder as a word.
const plain = (n) => (n && typeof n === 'object' && !Array.isArray(n) && 'type' in n
  ? { type: n.type, props: Object.fromEntries(Object.entries(n.props || {}).filter(([k]) => k !== 'children').map(([k, v]) => [k, typeof v === 'function' ? 'fn' : v])), children: (n.children || []).map(plain) }
  : Array.isArray(n) ? n.map(plain) : n)
// Each case's drawings and its redraw count after each refresh, as one sha256.
const PINNED = {
  tick: 'db362e790d4eba5e4d7f8b9078cad1aeef6b1bf583216186efdfe5cd9801e109',
  refresh: 'fea9f80d0c46f558d0162baf1d629e3f080e4f8ff427de7edfd4637595d661d4',
  glance: '76d3444e79d5382907674eb1b087dfb1a4e3cfefdc2627581cde421381701cbe',
  'whats-next': 'dfa9e9acfb131c4d22bb558c536f98b186bb2f460795377ecbba3d58702f2af7',
  render: 'e944f8bd0c7f2163a72823d0efbc2699c28883c110de99eedb2342ff7714defe',
  step: 'e01f26f631d10a00c4e4c25ebb390383fcb89e6f49089a576fdcfd09817c398b',
}

test("the bench's cases draw what they drew: work done for speed changes no drawing and no redraw", async () => {
  const got = {}
  for (const [name, [begin, refresh]] of Object.entries(BENCH)) {
    const h = await begin()
    const seen = []
    for (const runs of [20, 30]) for (let i = 0; i < runs; i++) seen.push((await refresh(h, i)).map(plain), h.invalidations())
    assert.deepEqual(h.errors, [], name)
    got[name] = createHash('sha256').update(JSON.stringify(seen).split(PLUGIN).join('<plugin>')).digest('hex')
  }
  assert.deepEqual(got, PINNED, 'a bench case drew something else: re-pin it only for a change meant to be seen')
})
