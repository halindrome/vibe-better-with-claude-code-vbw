// R189, phase P144 (evidence level L1, the stand-in for Claude Code's mods API):
// each What's next row (the top pick and up to two runners-up) is one pressable
// Button showing the item, a size chip and, where VBW gave one, the reason in dim
// text; pressing it puts the item's command in the prompt (/vbw:vibe with its T
// or R id, else with its text) and never sends it; Suggest next stays and only
// fills (R124). Every new thing (a new recommendation, a newly failed helper, a
// new needs-you line) is marked until the user has seen it (pressed it, opened
// it, or opened its tab), not for 4 seconds: at full motion the R125 shimmer and
// pulse mark the arrival and the mark stays; at calm the mark is steady; with
// motion off it is a text 'new' mark only. What was seen stays seen after a
// restart, kept in the user's store; a test session uses only test.* keys.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, find, walk, ROOT } from '../helpers/fake-mod.mjs'
import { TICK, writeCrew, working, building } from './helpers/crew.mjs'
import { textOf } from './helpers/screen.mjs'

const NEXT = ROOT + '/.vbw/runtime/next.json'
const TEST_MODE = { [ROOT + '/.vbw/runtime/test-mode']: '1' }
const REQUEST = "/vbw:vibe what's next"
const REC = (at = '2026-10-09T10:00:00Z') => ({
  at,
  top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most this month.', size: 'small', source: 'T4' },
  runners: [{ text: 'Gift cards', size: 'large', source: 'T9' }, { text: 'Dark mode', size: 'medium' }],
})
const motion = (m) => ({ settings: { profile: 'balanced', autonomy_cap: 25, motion: m } })

async function session(rec, options = {}) {
  const h = await mount(options)
  h.project(rec, next())
  await h.start()
  await h.advance(4000)
  return h
}

const section = async (h) => find(await h.render(), (n) => n.type === 'Box' && n.props.key === 'whats-next')
const whole = (b) => String(b.props.label ?? '') + ' ' + textOf(b)
const rows = (s) => {
  const out = []
  walk(s, (n) => { if (n.type === 'Button' && n.props.label !== 'Suggest next') out.push(n) })
  return out
}
const row = async (h, re) => rows(await section(h)).find((b) => re.test(whole(b)))
const press = async (h, b) => {
  assert.ok(b && typeof b.props.onPress === 'function', 'no row Button to press')
  await b.props.onPress({ surface: 'terminal' })
  await h.settle()
}
// Every piece of text a node draws, with how it is drawn.
const styled = (node, skip = () => false) => {
  const out = []
  walk(node, (n) => {
    if (n.type === 'Button' && n.props.label !== undefined) out.push(['button', String(n.props.label), n.props.color, n.props.variant])
    if (n.type === 'Text' && !skip(n)) out.push([textOf(n), n.props.color, n.props.dimColor, n.props.bold, n.props.inverse, n.props.backgroundColor])
  })
  return JSON.stringify(out)
}
const isNew = (n) => n.type === 'Text' && textOf(n).trim() === 'new'
const hasNew = (node) => Boolean(find(node, isNew))

test("each row is one Button with the item, its size chip and, where VBW gave one, the reason in dim text", async () => {
  const h = await session(record({ recommendation: REC(), ...motion('off') }))
  const s = await section(h)
  const bs = rows(s)
  assert.equal(bs.length, 3, 'the top pick and two runners-up, one Button each: ' + bs.map(whole).join(' | '))
  const [top, gift, dark] = bs
  assert.match(whole(top), /Refunds for paid orders/)
  assert.match(whole(top), /\bsmall\b/)
  const reason = find(top, (n) => n.type === 'Text' && /Customers ask for it most/.test(textOf(n)))
  assert.ok(reason, 'the reason is inside the top row')
  assert.equal(reason.props.dimColor, true, 'the reason is dim')
  assert.match(whole(gift), /Gift cards/)
  assert.match(whole(gift), /\blarge\b/)
  assert.match(whole(dark), /Dark mode/)
  assert.match(whole(dark), /\bmedium\b/)
})

test("pressing a row puts the item's command in the prompt and never sends it", async () => {
  const h = await session(record({ recommendation: REC(), ...motion('off') }))
  await press(h, await row(h, /Refunds/))
  await press(h, await row(h, /Gift cards/))
  await press(h, await row(h, /Dark mode/))
  assert.deepEqual(h.callsOf('prompt.fill').map((a) => a[0].text), ['/vbw:vibe T4', '/vbw:vibe T9', '/vbw:vibe Dark mode'])
  assert.deepEqual(h.names().filter((n) => n.startsWith('prompt.') && n !== 'prompt.fill' && n !== 'prompt.suggest'), [], 'only fills, never sends')
})

test('Suggest next stays and still only fills the prompt (R124)', async () => {
  const h = await session(record({ recommendation: REC() }))
  const b = find(await section(h), (n) => n.type === 'Button' && n.props.label === 'Suggest next')
  assert.ok(b)
  await press(h, b)
  assert.deepEqual(h.callsOf('prompt.fill').map((a) => a[0].text), [REQUEST])
})

test('a new recommendation stays marked until it is seen, not for 4 seconds: shimmer then a mark at full, a steady mark at calm, a text "new" only with motion off', async () => {
  for (const m of ['full', 'calm', 'off']) {
    const h = await session(record({ recommendation: REC(), ...motion(m) }))
    await h.advance(10000)
    const unseen = await section(h)
    if (m === 'calm') {
      const frames = []
      for (let i = 0; i < 12; i++) {
        frames.push(styled(await section(h)))
        await h.advance(250)
      }
      assert.equal(new Set(frames).size, 1, 'the calm mark moves')
    }
    if (m === 'off') assert.ok(hasNew(unseen), 'no "new" mark with motion off')
    await press(h, await row(h, /Refunds/))
    await h.advance(TICK)
    const seen = await section(h)
    assert.notEqual(styled(unseen), styled(seen), m + ': nothing marked the new recommendation 10 s after it arrived')
    assert.ok(!hasNew(seen), m + ': still marked "new" after it was seen')
    if (m === 'off') assert.equal(styled(unseen, isNew), styled(seen), 'with motion off the mark is the text "new" only')
  }
})

test('opening its tab counts as seen: pressing the Now tab clears the mark', async () => {
  const h = await session(record({ recommendation: REC(), ...motion('off') }))
  assert.ok(hasNew(await section(h)))
  await h.press('tab-now')
  await h.advance(TICK)
  assert.ok(!hasNew(await section(h)))
})

test("what was seen stays seen after a restart, and what was not stays new; kept in the user's store, never in the project", async () => {
  const store = new Map()
  const first = await session(record({ recommendation: REC(), ...motion('off') }), { store })
  const again = await session(record({ recommendation: REC(), ...motion('off') }), { store })
  assert.ok(hasNew(await section(again)), 'an unseen recommendation lost its mark at a restart')
  await press(again, await row(again, /Refunds/))
  const third = await session(record({ recommendation: REC(), ...motion('off') }), { store })
  assert.ok(!hasNew(await section(third)), 'a seen recommendation is new again after a restart')
  assert.equal(first.count('fs.write') + again.count('fs.write') + third.count('fs.write'), 0)
  for (const [k] of [...again.callsOf('store.set'), ...third.callsOf('store.set')]) assert.match(k, /^vbw-panel\./, k)
})

test('a test session keeps what it has seen under test.* keys only', async () => {
  const store = new Map()
  const h = await session(record({ recommendation: REC() }), { store, files: TEST_MODE })
  assert.ok(hasNew(await section(h)), 'a test session (motion off) shows the text mark')
  await press(h, await row(h, /Refunds/))
  assert.ok(!hasNew(await section(h)))
  assert.ok(store.size > 0, 'nothing was kept')
  for (const k of store.keys()) assert.match(k, /^test\./, k)
  for (const [k] of h.callsOf('store.get')) assert.match(k, /^test\./, k)
})

test('a newly failed helper is marked on its Mission Control card until it is opened', async () => {
  const crew = working(2)
  const { h, at } = await building(crew, { profile: 'balanced', motion: 'off' })
  writeCrew(h, at, [{ n: 'P142.1', state: 'working' }, { n: 'P142.2', state: 'failed' }])
  await h.advance(TICK)
  const cardOf = async () => {
    const tree = await h.render()
    const b = find(tree, (n) => n.type === 'Button' && String(n.props.label).includes('P142.2'))
    return { b, box: find(tree, (n) => n.type === 'Box' && n.props.borderStyle && n.children.includes(b)) }
  }
  const before = await cardOf()
  assert.ok(before.b, 'no card for the failed helper')
  assert.ok(hasNew(before.box || before.b), 'the failed card is not marked "new"')
  await press(h, before.b)
  await h.advance(TICK)
  const after = await cardOf()
  assert.ok(!hasNew(after.box || after.b), 'still marked after it was opened')
})

test('a new needs-you line on Comms is marked until its tab is opened, and then stays unmarked while the gate stands', async () => {
  const h = await session(record(motion('off')))
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  const comms = () => h.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100 })
  assert.ok(hasNew(await comms()), 'the new needs-you line is not marked')
  await h.press('tab-now')
  await h.advance(TICK)
  const after = await comms()
  assert.ok(!hasNew(after), 'still marked after its tab was opened')
  assert.match(textOf(after), /VBW needs you/, 'the line itself stays while the gate stands')
})
