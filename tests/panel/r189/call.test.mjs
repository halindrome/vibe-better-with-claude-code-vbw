// R189, phase P143 (evidence level L1, the stand-in for Claude Code's mods API):
// VBW calls the user once, when the question is actually on screen. The
// needs-you sound plays exactly once when Claude Code opens its own question
// menu (AskUserQuestion) in a VBW project, at that moment; never for a gate alone
// (next.json or the record), never for a re-render of the open menu, an answer
// or the menu closing; a second question plays once more, and one question never
// plays two clips (B1: two clips together, a clip after answering). The native
// notification ($.ui.notify, title 'VBW', a plain sentence of what VBW needs)
// fires once with it, and once when a new What's next recommendation is written
// (one already seen, by its stored time, never again after a restart). Both
// follow the sound switch, remembered across sessions (R57); a test session (R64)
// plays and raises nothing and neither reads nor changes the user's choices.
// Without $.ui.notify or audio nothing fails and nothing shows in their place.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, ROOT } from '../helpers/fake-mod.mjs'

const SHIPPED = /^assets\/audio\/[^/]+\/[^/]+\.mp3$/
const NEXT = ROOT + '/.vbw/runtime/next.json'
const TEST_MODE = { [ROOT + '/.vbw/runtime/test-mode']: '1' }
const SENTENCE = /^[A-Z].*\S[.!?]$/
const REC = (at = '2026-10-09T10:00:00Z') => ({
  at, top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most.', size: 'small', source: 'T4' }, runners: [],
})

async function session(options = {}, rec = record()) {
  const h = await mount(options)
  h.project(rec, next())
  await h.start()
  await h.advance(4000)
  return h
}

// Claude Code opens its question menu: the AskUserQuestion call stays open until answered.
function ask(h, id = 'q1') {
  let answer
  const done = h.fire('tool.call', { tool: 'AskUserQuestion', tool_use_id: id, questions: [{ question: 'Which plan?', options: [{ label: 'A' }, { label: 'B' }] }] },
    () => new Promise((r) => (answer = r)))
  return { answer: (v = { result: 'A' }) => answer(v), done }
}
const menu = (h) => h.draw('AskUserQuestion', { questions: [{ question: 'Which plan?' }] })

test('the sound plays exactly once, at the moment the question menu opens', async () => {
  const h = await session()
  assert.equal(h.plays.length, 0)
  const q = ask(h)
  await h.settle()
  assert.equal(h.plays.length, 1, 'no clip when the menu opened')
  assert.match(h.plays[0].asset, SHIPPED)
  q.answer()
  await q.done
})

test('a gate in next.json or the record, with no question menu open, plays no sound', async () => {
  const h = await session()
  for (const nx of [next({ action: 'approve', gate: true }), next({ action: 'accept', gate: true, detail: { requirements: ['R54'] } }), next({ action: 'ship', gate: true })]) {
    h.write(NEXT, nx)
    await h.advance(30000)
  }
  h.project(record({ requirements: [{ id: 'R54', text: 'It reads well', proof: 'human', status: 'open', milestone: 'M9' }] }))
  await h.advance(30000)
  assert.equal(h.plays.length, 0, 'a gate on its own made a sound')
})

test('re-renders of the open menu, pressing an option and the menu closing play no sound', async () => {
  const h = await session()
  const q = ask(h)
  await h.settle()
  for (let i = 0; i < 5; i++) {
    await menu(h)
    await h.advance(3000)
  }
  assert.equal(h.plays.length, 1, 're-renders of the same menu')
  q.answer({ result: 'A' })
  await q.done
  await h.advance(6000)
  assert.equal(h.plays.length, 1, 'answering made a sound')
  const q2 = ask(h, 'q2')
  await h.settle()
  assert.equal(h.plays.length, 2, 'a second question plays once more')
  q2.answer({ error: 'The user dismissed the question' })
  await q2.done
  await h.advance(6000)
  assert.equal(h.plays.length, 2, 'closing the menu made a sound')
})

test('B1: a gate standing when the question opens gives one clip, not two, and none after answering', async () => {
  const h = await session()
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(2000)
  const q = ask(h)
  await h.settle()
  await h.advance(4000)
  assert.equal(h.plays.length, 1, 'two clips together')
  q.answer()
  await q.done
  await h.advance(10000)
  assert.equal(h.plays.length, 1, 'a clip after answering, with the gate still in next.json')
})

test('with the sound off nothing plays and nothing is raised; the choice is remembered across sessions, and the switch in Mission Control turns it on', async () => {
  const store = new Map()
  const h = await session({ store })
  await h.cmd('vbw-sound', 'off')
  const q = ask(h)
  await h.settle()
  q.answer()
  await q.done
  assert.equal(h.plays.length, 0)
  assert.equal(h.notifies.length, 0, 'a notification with the sound off')
  const again = await session({ store })
  const q2 = ask(again)
  await again.settle()
  assert.equal(again.plays.length, 0, 'the choice did not survive a restart')
  assert.equal(again.notifies.length, 0)
  q2.answer()
  await q2.done
  await again.press('sound-toggle')
  const q3 = ask(again, 'q3')
  await again.settle()
  assert.equal(again.plays.length, 1, 'the switch in Mission Control turned it on')
  assert.equal(again.notifies.length, 1)
  q3.answer()
  await q3.done
})

test("a test session plays nothing aloud, raises nothing, and neither reads nor changes the user's choices", async () => {
  const store = new Map([['vbw-panel.sound', true], ['vbw-panel.closed', false]])
  const h = await mount({ files: TEST_MODE, store })
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  const q = ask(h)
  await h.settle()
  q.answer()
  await q.done
  h.project(record({ recommendation: REC() }))
  await h.advance(6000)
  await h.cmd('vbw-sound', 'off')
  assert.equal(h.plays.length, 0, 'audio in a test session')
  assert.equal(h.notifies.length, 0, 'a notification in a test session')
  assert.equal(store.get('vbw-panel.sound'), true)
  assert.equal(store.get('vbw-panel.closed'), false)
  for (const [k] of h.callsOf('store.get')) assert.match(k, /^test\./, 'read the user key ' + k)
  for (const [k] of h.callsOf('store.set')) assert.match(k, /^test\./, 'wrote the user key ' + k)
})

test('the notification fires once when the menu opens, titled VBW, with a plain sentence of what VBW needs, and not again for the same question', async () => {
  const h = await session()
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(2000)
  assert.equal(h.notifies.length, 0, 'a gate alone raised a notification')
  const q = ask(h)
  await h.settle()
  assert.equal(h.notifies.length, 1, 'no notification when the menu opened')
  assert.equal(h.notifies[0].title, 'VBW')
  assert.match(String(h.notifies[0].text), SENTENCE)
  assert.match(String(h.notifies[0].text), /approv/i, 'it names what VBW needs')
  for (let i = 0; i < 3; i++) {
    await menu(h)
    await h.advance(3000)
  }
  q.answer()
  await q.done
  await h.advance(6000)
  assert.equal(h.notifies.length, 1, 'the same question notified again')
  h.write(NEXT, next())
  await h.advance(2000)
  const q2 = ask(h, 'q2')
  await h.settle()
  assert.equal(h.notifies.length, 2, 'a second question notifies once more')
  assert.match(String(h.notifies[1].text), SENTENCE)
  q2.answer()
  await q2.done
})

test('a new What\'s next recommendation raises one notification; one already seen does not, even after a restart', async () => {
  const store = new Map()
  const h = await session({ store })
  h.project(record({ recommendation: REC() }))
  await h.advance(4000)
  assert.equal(h.notifies.length, 1, 'no notification for a new recommendation')
  assert.equal(h.notifies[0].title, 'VBW')
  assert.match(String(h.notifies[0].text), SENTENCE)
  await h.advance(30000)
  assert.equal(h.notifies.length, 1, 'it notified again')
  const again = await session({ store }, record({ recommendation: REC() }))
  await again.advance(10000)
  assert.equal(again.notifies.length, 0, 'a recommendation already seen notified after a restart')
  again.project(record({ recommendation: REC('2026-10-10T09:00:00Z') }))
  await again.advance(4000)
  assert.equal(again.notifies.length, 1, 'a newer recommendation did not notify')
})

test('the recommendation notification follows the sound switch too', async () => {
  const h = await session()
  await h.cmd('vbw-sound', 'off')
  h.project(record({ recommendation: REC() }))
  await h.advance(6000)
  assert.equal(h.notifies.length, 0)
})

test('without $.ui.notify, or with notify and audio failing, nothing fails and nothing is shown in their place', async () => {
  for (const options of [{ noNotify: true }, { notifyFails: true, audioFails: true }]) {
    const h = await session(options)
    const q = ask(h)
    await h.settle()
    q.answer()
    await q.done
    h.project(record({ recommendation: REC() }))
    await h.advance(6000)
    assert.deepEqual(h.errors, [], JSON.stringify(options))
    for (const n of ['ui.toast', 'ui.log', 'ui.status', 'ui.notice']) assert.equal(h.count(n), 0, n + ' with ' + JSON.stringify(options))
    assert.match(await h.text(), /Working on/, 'the panel still draws')
  }
})

test('one failing call does not stop the other, nor the redraw that shows the question', async () => {
  const noPlayer = await session({ audioFails: true })
  const q = ask(noPlayer)
  await noPlayer.settle()
  assert.equal(noPlayer.notifies.length, 1, 'the notification was lost with the audio failing')
  q.answer()
  await q.done
  const noToast = await session({ notifyFails: true })
  const q2 = ask(noToast)
  await noToast.settle()
  assert.equal(noToast.plays.length, 1)
  assert.match(await noToast.text(), /question/i, 'the question was not drawn at once with notify failing')
  q2.answer()
  await q2.done
})
