// R64: VBW's own real-app test sessions (their project holds the marker file
// .vbw/runtime/test-mode, written by tools/l3.sh; the panel reads no
// environment, R55) never play the sound aloud and never read or change the user's own panel and
// sound choices: they keep their choices under test keys. Outside test mode
// the panel uses the user's keys. And every redraw names 'ui.render', as Claude
// Code requires (an unnamed redraw is dropped). Driven through the stand-in (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, PANE, ROOT } from './helpers/fake-mod.mjs'

const approve = () => next({ action: 'approve', gate: true })
// Claude Code's question menu, answered at once: since R189 (B1) the request that sounds.
const ask = (h) => h.fire('tool.call', { tool: 'AskUserQuestion', tool_use_id: 'q1', questions: [{ question: 'Approve the plan?' }] }, async () => ({ result: 'Yes' }))
const USER_KEYS = ['vbw-panel.closed', 'vbw-panel.sound']

const TEST_MODE = { [ROOT + '/.vbw/runtime/test-mode']: '1' }

async function session(files) {
  const store = new Map([['vbw-panel.closed', false], ['vbw-panel.sound', true]])
  const h = await mount({ files, store })
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  return { h, store }
}

test('in test mode a need records the sound but plays nothing aloud', async () => {
  const { h } = await session(TEST_MODE)
  await ask(h)
  await h.advance(30000)
  assert.equal(h.plays.length, 0, 'no audio in a test session')
})

test('in test mode the sound switch and a close never touch the user keys', async () => {
  const { h, store } = await session(TEST_MODE)
  const before = USER_KEYS.map((k) => store.get(k))
  await h.cmd('vbw-sound', 'off')
  await h.fire('ui.close', { id: PANE, origin: { kind: 'person' } })
  assert.deepEqual(USER_KEYS.map((k) => store.get(k)), before, 'user choices unchanged')
  assert.ok([...store.keys()].some((k) => k.startsWith('test.')), 'test choices kept under test keys')
})

test('outside test mode the sound plays and the switch uses the user keys', async () => {
  const { h, store } = await session({})
  await ask(h)
  await h.advance(30000)
  assert.equal(h.plays.length, 1)
  await h.cmd('vbw-sound', 'off')
  assert.equal(store.get('vbw-panel.sound'), false)
})

test('a change on disk redraws the panel by itself, with the redraw naming ui.render', async () => {
  const { h } = await session({})
  const n = h.invalidations()
  h.project(undefined, approve())
  await h.advance(6000)
  assert.ok(h.invalidations() > n, 'the panel asked Claude Code to redraw')
})

// Real-app test sessions each run in a fresh project; their panel choices are the
// project's own, so one scenario's close never keeps the next one's pane shut
// (the panel L3 scenario closes the pane on purpose, and its next run saw no pane).
test('in test mode each project keeps its own panel choices: a pane closed in one test project opens by itself in the next', async () => {
  const store = new Map()
  const a = await mount({ files: TEST_MODE, store })
  a.project(record(), next())
  await a.start()
  await a.advance(4000)
  await a.fire('ui.close', { id: PANE, origin: { kind: 'person' } })
  const b = await mount({ root: '/other', files: { '/other/.vbw/runtime/test-mode': '1' }, store })
  b.project(record(), next())
  await b.start()
  await b.advance(4000)
  assert.ok(b.opens.length > 0, 'the second test project opens its pane by itself')
  const c = await mount({ files: TEST_MODE, store })
  c.project(record(), next())
  await c.start()
  await c.advance(4000)
  assert.equal(c.opens.length, 0, 'the first project, closed by hand, stays closed')
})
