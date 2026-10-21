// R57: a short sound when VBW needs the user: once per request, even with the
// panel closed, on by default, one click or one command turns it off or on, and
// the choice is remembered. The sound is the plugin's own file; a missing file
// or player is silent. Since R189 (B1) the request that sounds is Claude Code's
// own question menu (AskUserQuestion), where the user answers an approval, a
// check or a question; a gate in next.json alone stays silent (that rule is held
// by tests/panel/r189/call.test.mjs). Driven through a stand-in for Claude
// Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, ROOT, PANE } from './helpers/fake-mod.mjs'

// One of the shipped sounds, plugin/assets/audio/<character>/<file>.mp3 (D109).
const SHIPPED = /^assets\/audio\/[^/]+\/[^/]+\.mp3$/
const approve = () => next({ action: 'approve', gate: true })
const accept = (r) => next({ action: 'accept', gate: true, detail: { requirements: [r] } })

// Claude Code opens its question menu; the call stays open until `answer` is called.
function ask(h, id) {
  let answer
  const done = h.fire('tool.call', { tool: 'AskUserQuestion', tool_use_id: id, questions: [{ question: 'Approve the plan?' }] }, () => new Promise((r) => (answer = r)))
  return { done, answer: async () => { answer({ result: 'Yes' }); await done } }
}

async function session(options = {}) {
  const h = await mount(options)
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  return h
}

test('a request for the user plays the sound once, and not again while it stands', async () => {
  const h = await session()
  assert.equal(h.plays.length, 0)
  const q = ask(h, 'q1')
  await h.advance(30000)
  assert.equal(h.plays.length, 1)
  assert.match(h.plays[0].asset, SHIPPED)
  await q.answer()
})

test('each new request plays it once; a request asked again after it was answered plays it again', async () => {
  const h = await session()
  const q1 = ask(h, 'q1')
  await h.advance(6000)
  assert.equal(h.plays.length, 1)
  await q1.answer()
  const q2 = ask(h, 'q2')
  await h.advance(6000)
  assert.equal(h.plays.length, 2)
  await q2.answer()
  await h.advance(6000)
  assert.equal(h.plays.length, 2, 'nothing is needed: no sound')
  const q3 = ask(h, 'q3')
  await h.advance(6000)
  assert.equal(h.plays.length, 3)
  await q3.answer()
})

test('a question for the user plays it once, and the need ends when it is answered', async () => {
  const h = await session()
  let answer
  const pending = new Promise((r) => (answer = r))
  const asking = h.fire('tool.call', { tool: 'AskUserQuestion', questions: [{ question: 'Which?' }] }, () => pending)
  await h.settle()
  assert.equal(h.plays.length, 1)
  assert.match(await h.text(), /question/i)
  await h.advance(20000)
  assert.equal(h.plays.length, 1)
  answer({ result: 'A' })
  assert.deepEqual(await asking, { result: 'A' })
  await h.advance(4000)
  assert.match(await h.text(), /nothing is needed/i)
})

test('other tool calls make no sound', async () => {
  const h = await session()
  await h.fire('tool.call', { tool: 'Bash', command: 'ls' }, async () => ({ result: 'ok' }))
  assert.equal(h.plays.length, 0)
})

test('the sound plays even when the panel is closed', async () => {
  const h = await session()
  await h.fire('ui.close', { id: PANE, origin: { kind: 'person' } })
  const q = ask(h, 'q1')
  await h.advance(6000)
  assert.equal(h.plays.length, 1)
  await q.answer()
})

test('it is on by default and a command switches it off and on, and says which', async () => {
  const h = await session()
  const off = await h.cmd('vbw-sound', 'off')
  assert.match(off.text, /\boff\b/i)
  assert.doesNotMatch(off.text, /\bon\b/i)
  const q1 = ask(h, 'q1')
  await h.advance(6000)
  assert.equal(h.plays.length, 0, 'with the sound off nothing plays')
  await q1.answer()
  const on = await h.cmd('vbw-sound', 'on')
  assert.match(on.text, /\bon\b/i)
  const q2 = ask(h, 'q2')
  await h.advance(6000)
  assert.equal(h.plays.length, 1)
  await q2.answer()
})

test('with no word, the command switches the sound over', async () => {
  const h = await session()
  assert.match((await h.cmd('vbw-sound', '')).text, /\boff\b/i)
  assert.match((await h.cmd('vbw-sound', '')).text, /\bon\b/i)
})

test('with the sound off, no need of any kind plays anything', async () => {
  const h = await session()
  await h.cmd('vbw-sound', 'off')
  for (const n of [approve(), accept('R1'), next({ action: 'ship', gate: true }), next({ action: 'escalate', gate: true })]) {
    h.project(undefined, n)
    await h.advance(6000)
  }
  await h.fire('tool.call', { tool: 'AskUserQuestion', questions: [] }, async () => ({ result: 'x' }))
  assert.equal(h.plays.length, 0)
})

test('the panel shows whether the sound is on, and one click switches it', async () => {
  const h = await session()
  assert.match(await h.text(), /sound.*\bon\b/i)
  await h.press('sound-toggle')
  assert.match(await h.text(), /sound.*\boff\b/i)
  h.project(undefined, approve())
  await h.advance(6000)
  assert.equal(h.plays.length, 0)
  await h.press('sound-toggle')
  assert.match(await h.text(), /sound.*\bon\b/i)
  assert.ok(h.count('ui.invalidate') > 0)
})

test('the choice survives a restart, and lives in the user store, not in the project', async () => {
  const store = new Map()
  const h = await session({ store })
  h.git()
  await h.cmd('vbw-sound', 'off')
  assert.equal(h.count('fs.write'), 0)
  const again = await session({ store })
  assert.match(await again.text(), /sound.*\boff\b/i)
  again.project(undefined, approve())
  await again.advance(6000)
  assert.equal(again.plays.length, 0)
  await again.cmd('vbw-sound', 'on')
  const third = await session({ store })
  assert.match(await third.text(), /sound.*\bon\b/i)
  for (const [k, v] of store) assert.doesNotMatch(JSON.stringify([k, v]), new RegExp(ROOT))
})

test('a missing file or no player is silent: nothing plays and nothing is shown', async () => {
  const h = await session({ audioFails: true })
  h.project(undefined, approve())
  const q = ask(h, 'q1')
  await h.advance(10000)
  await q.answer()
  assert.deepEqual(h.errors, [])
  for (const n of ['ui.toast', 'ui.log', 'ui.status', 'ui.notice']) assert.equal(h.count(n), 0, n)
  assert.match(await h.text(), /approve/i)
})

test('on a version without mods the sound command does not exist and the panel stays off', async () => {
  const h = await mount({ version: '2.1.286' })
  h.project(record(), approve())
  await h.start()
  await h.advance(10000)
  assert.equal(h.plays.length, 0)
  assert.equal(h.count('command.register'), 0)
})
