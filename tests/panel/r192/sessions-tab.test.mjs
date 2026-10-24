// R192, phase P154 (evidence level L1, the stand-in for Claude Code's mods API):
// Mission Control's Sessions tab (short label Sess) lists every chat of Claude
// Code's list (<claude-config-dir>/sessions/*.json) whose cwd is this project's
// root or a folder inside it, newest updatedAt first: name, state word, last
// active as HH:MM, and `claude --resume <id>` to copy; this chat's row says
// `this chat`; the chat holding the run shows `● holds the run` with the run
// kind in the accent colour; a holder with no entry is still listed from the
// lease, `closed or not seen`. Read-only. With nothing to list, one sentence.
// A malformed file skips its row and never breaks the panel. The panel re-reads
// the list on its tick only while the tab is shown or a lease is open.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, collect, walk, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { ENV, HOME } from '../helpers/run.mjs'

const S = await import(pathToFileURL(PLUGIN + '/hooks/panel-sessions.js').href)
const pane = await import(pathToFileURL(PLUGIN + '/hooks/panel-pane.js').href)
const palette = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)

const REG = HOME + '/.claude/sessions'
const ME = 'sess-1' // fake-mod's session id
const SID = '0123456789abcdef-aaaa'
const OTHER = 'fedcba9876543210-bbbb'
const TICK = 2000
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
process.env.TZ = 'UTC'

const entry = (over = {}) => JSON.stringify({ sessionId: SID, cwd: ROOT, name: 'Payments work', nameSource: 'auto', status: 'busy', updatedAt: T0 - 60000, ...over })
const registry = (...texts) => S.registryEntries(texts)
const PLANS = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]
const hhmm = (ms) => new Date(ms).toISOString().slice(11, 16)
const texts = (tree) => collect(tree)
const text = (tree) => texts(tree).join('\n')
const buttons = (tree) => { const out = []; walk(tree, (n) => { if (n.type === 'Button') out.push(n) }); return out }
const press = async (h, label) => {
  const b = buttons(await h.render()).find((x) => x.props.label === label)
  assert.ok(b, 'no button ' + label)
  await b.props.onPress({ surface: 'terminal' })
  await h.settle()
}
// The six full tab names fit one row from 65 columns; the stand-in's default pane is 50.
const WIDE = { title: 'VBW', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} }
const wide = (h) => { const render = h.render; h.render = (extra = {}) => render({ props: WIDE, ...extra }); return h }
const lists = (h) => h.calls.filter((c) => c.name === 'fs.list' && c.args[0] === REG).length

test('the tab row has Sessions after Timeline, Sess in a narrow pane', () => {
  const ids = pane.TABS.map(([id]) => id)
  assert.equal(ids.indexOf('sessions'), ids.indexOf('timeline') + 1)
  assert.deepEqual(pane.TABS.find(([id]) => id === 'sessions'), ['sessions', 'Sessions'])
  assert.equal(pane.SHORT.sessions, 'Sess')
})

test('the model lists this project\'s chats newest first with name, state, last active and the resume line; other projects are left out', () => {
  const reg = registry(
    entry({ sessionId: 'c', name: 'Oldest', cwd: ROOT + '/src/deep', status: 'idle', updatedAt: T0 - 3 * 3600000 }),
    entry({ sessionId: 'a', name: 'Newest', status: 'busy', updatedAt: T0 - 60000 }),
    entry({ sessionId: 'x', name: 'Elsewhere', cwd: '/other', updatedAt: T0 }),
    entry({ sessionId: 'y', name: 'Sibling', cwd: ROOT + '2', updatedAt: T0 }),
    entry({ sessionId: 'b', name: 'Middle', status: 'compacting', updatedAt: T0 - 7200000 }))
  const m = S.sessionsModel({ registry: reg, root: ROOT, sessionId: ME, lease: null, stored: null, now: T0, width: 80 })
  assert.deepEqual(m.rows.map((r) => r.id), ['a', 'b', 'c'])
  assert.deepEqual(m.rows.map((r) => r.name), ['Newest', 'Middle', 'Oldest'])
  assert.deepEqual(m.rows.map((r) => r.state), ['busy', 'compacting', 'idle'])
  assert.deepEqual(m.rows.map((r) => r.last), [hhmm(T0 - 60000), hhmm(T0 - 7200000), hhmm(T0 - 3 * 3600000)])
  assert.deepEqual(m.rows.map((r) => r.resume), ['claude --resume a', 'claude --resume b', 'claude --resume c'])
  assert.ok(m.rows.every((r) => r.self === false && r.holder === null && r.closed === false))
  assert.equal(m.empty, null)
})

test('this chat is marked, the holder carries the run kind, and a holder with no entry is listed from the lease as closed or not seen', () => {
  const l = lease('build', T0 - 480000, { session: SID })
  const reg = registry(entry({ sessionId: ME, name: 'Me' }), entry({ sessionId: SID, name: 'Payments work', updatedAt: T0 }))
  const m = S.sessionsModel({ registry: reg, root: ROOT, sessionId: ME, lease: l, stored: null, now: T0, width: 80, plans: PLANS })
  assert.deepEqual(m.rows.map((r) => [r.id, r.self, r.holder, r.closed]), [[SID, false, { kind: 'build P44.1' }, false], [ME, true, null, false]])
  const gone = S.sessionsModel({ registry: registry(entry({ sessionId: ME, name: 'Me' })), root: ROOT, sessionId: ME, lease: l, stored: { run: l.run, session: SID, session_name: 'Stored name' }, now: T0, width: 80, plans: PLANS })
  assert.deepEqual(gone.rows.map((r) => [r.id, r.name, r.holder, r.closed]), [[ME, 'Me', null, false], [SID, 'Stored name', { kind: 'build P44.1' }, true]])
  const noName = S.sessionsModel({ registry: [], root: ROOT, sessionId: ME, lease: lease('qa', T0, { session: SID }), stored: null, now: T0, width: 80 })
  assert.deepEqual(noName.rows.map((r) => [r.id, r.name, r.holder, r.closed]), [[SID, '01234567', { kind: 'qa' }, true]])
  assert.equal(noName.empty, 'No other chats are open on this project')
})

test('the empty sentence, cleaned names, and names cut to the width', () => {
  assert.equal(S.sessionsModel({ registry: [], root: ROOT, sessionId: ME, lease: null, stored: null, now: T0, width: 80 }).empty, 'No other chats are open on this project')
  assert.equal(S.sessionsModel({ registry: null, root: ROOT, sessionId: ME, lease: null, stored: null, now: T0, width: 80 }).empty, 'No other chats are open on this project')
  const mine = S.sessionsModel({ registry: registry(entry({ sessionId: ME, name: 'Me' })), root: ROOT, sessionId: ME, lease: null, stored: null, now: T0, width: 80 })
  assert.equal(mine.empty, 'No other chats are open on this project')
  assert.deepEqual(mine.rows.map((r) => [r.id, r.self]), [[ME, true]])
  const long = 'A very long chat name that keeps going on and on past forty'
  const m = S.sessionsModel({ registry: registry(entry({ name: 'Pay\u001b[31mments\u0007 work' }), entry({ sessionId: OTHER, name: long, updatedAt: T0 - 120000 })), root: ROOT, sessionId: ME, lease: null, stored: null, now: T0, width: 30 })
  assert.equal(m.rows[0].name, 'Payments work')
  assert.equal(m.rows[1].name, long.slice(0, 29) + '…')
})

test('the drawing: rows as text, this chat and the holder mark in the accent colour, no button or input', () => {
  const l = lease('build', T0 - 480000, { session: SID })
  const m = S.sessionsModel({ registry: registry(entry({ sessionId: ME, name: 'Me' }), entry({ sessionId: SID, name: 'Payments work', updatedAt: T0 })), root: ROOT, sessionId: ME, lease: l, stored: null, now: T0, width: 80, plans: PLANS })
  const tree = S.renderSessions(UI, m)
  const t = text(tree)
  assert.match(t, /Payments work/)
  assert.match(t, /● holds the run/)
  assert.match(t, /build P44\.1/)
  assert.match(t, /this chat/)
  assert.match(t, /claude --resume 0123456789abcdef-aaaa/)
  assert.match(t, new RegExp('last ' + hhmm(T0)))
  assert.match(t, /Payments work · busy/)
  let accent = false
  walk(tree, (n) => { if (n.type === 'Text' && n.props.color === palette.ACCENT && /holds the run/.test(n.children.join(''))) accent = true })
  assert.ok(accent, 'the holder mark is drawn in the accent colour')
  assert.equal(buttons(tree).length, 0)
  const empty = text(S.renderSessions(UI, S.sessionsModel({ registry: [], root: ROOT, sessionId: ME, lease: null, stored: null, now: T0, width: 80 })))
  assert.match(empty, /No other chats are open on this project/)
})

test('in the panel: the Sessions tab lists the chats from the files, skips a malformed one, and writes nothing', async () => {
  const h = await mount({ env: ENV, files: {
    [REG + '/10.json']: entry({ sessionId: ME, name: 'Me', updatedAt: T0 - 1000 }),
    [REG + '/11.json']: entry({ sessionId: OTHER, name: 'Market data recorder', updatedAt: T0 - 5000 }),
    [REG + '/12.json']: '{"sessionId": "zzz", "name": "Half',
    [REG + '/13.json']: entry({ sessionId: 'far', name: 'Elsewhere', cwd: '/other' }),
  } })
  wide(h)
  h.project(record(), next())
  await h.start()
  await h.settle()
  await press(h, 'Sessions')
  const t = await h.text()
  assert.match(t, /Market data recorder/)
  assert.match(t, /claude --resume fedcba9876543210-bbbb/)
  assert.match(t, /this chat/)
  assert.doesNotMatch(t, /Elsewhere|Half/)
  assert.deepEqual(h.errors, [])
  assert.equal(h.count('process.run'), 0)
  assert.ok(h.names().every((n) => !/write|remove|mkdir|append/.test(n)), h.names().join(', '))
})

test('the list is re-read on the tick only while the Sessions tab is shown or a lease is open', async () => {
  const h = await mount({ env: ENV, files: { [REG + '/10.json']: entry({ sessionId: ME, name: 'Me' }) } })
  wide(h)
  h.project(record(), next())
  await h.start()
  await h.settle()
  const before = lists(h)
  await h.advance(3 * TICK)
  assert.equal(lists(h), before, 'the Now tab with no lease reads the list on no tick')
  await press(h, 'Sessions')
  const shown = lists(h)
  await h.advance(2 * TICK)
  assert.ok(lists(h) >= shown + 2, 'each tick on the Sessions tab reads the list')
  await press(h, 'Now')
  const left = lists(h)
  await h.advance(2 * TICK)
  assert.equal(lists(h), left, 'leaving the tab stops the reads')
  h.project(record({ plans: PLANS, lease: lease('build', h.now(), { session: OTHER }) }), next({ action: 'run' }))
  h.write(REG + '/11.json', entry({ sessionId: OTHER, name: 'Payments work', updatedAt: T0 }))
  await h.advance(2 * TICK)
  assert.ok(lists(h) >= left + 2, 'a lease open reads the list on every tick, whatever the tab')
  await press(h, 'Sessions')
  const t = await h.text()
  assert.match(t, /Payments work/)
  assert.match(t, /● holds the run/)
  assert.match(t, /build P44\.1/)
  assert.deepEqual(h.errors, [])
})

test('with no list at all the tab shows the one sentence and this chat when known', async () => {
  const h = await mount({ env: ENV })
  wide(h)
  h.project(record(), next())
  await h.start()
  await h.settle()
  await press(h, 'Sessions')
  const t = await h.text()
  assert.match(t, /No other chats are open on this project/)
  assert.deepEqual(h.errors, [])
})
