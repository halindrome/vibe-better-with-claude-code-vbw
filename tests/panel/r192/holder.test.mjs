// R192, phase P153 (evidence level L1): the panel names who holds the run. One JS
// helper (plugin/hooks/panel-sessions.js) resolves a holder's display name in
// the shared order: Claude Code's list of chats (its current name for the
// lease's session, newest updatedAt first), else the name vbw run start stored
// (.vbw/runtime/holder.json), else the first 8 characters of the id. Names are
// untrusted text: control characters and escape sequences go, long names are
// cut with an ellipsis. Comms' record-change line reads `VBW · build run started
// by <name>` (or `by this chat` in the holder); the Now box's state sentence ends
// with `, held by <name>` when another chat holds the run; /vbw-why reads `held
// by this chat ("<name>")` or `held by "<name>"`, the id in brackets only when
// no name is known; /vbw-status shows the same holder wording as the Now box.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, PLUGIN, T0 } from '../helpers/fake-mod.mjs'
import { ENV } from '../helpers/run.mjs'

const S = await import(pathToFileURL(PLUGIN + '/hooks/panel-sessions.js').href)
const L = await import(pathToFileURL(PLUGIN + '/hooks/panel-lines.js').href)
const V = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const C = await import(pathToFileURL(PLUGIN + '/hooks/panel-commands.js').href)

const SID = '0123456789abcdef-aaaa'
const OTHER = 'fedcba9876543210-bbbb'
const NOW = Date.parse('2026-10-05T15:00:00Z')
const entry = (over = {}) => JSON.stringify({ sessionId: SID, cwd: '/proj', name: 'Payments work', nameSource: 'auto', status: 'busy', updatedAt: 1792300000000, ...over })
const registry = (...texts) => S.registryEntries(texts)
const PLANS = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]
const build = (extra = {}) => record({ plans: PLANS, lease: lease('build', T0 - 480000, { session: SID, files: ['a.js', 'b.js', 'c.js'], ...extra }) })
const lines = (s) => s.split('\n')

test('names are cleaned of control characters and escape sequences, and cut with an ellipsis', () => {
  assert.equal(S.cleanName('Pay\u001b[31mments\u0007 work\u001b]0;title\u0007 now\r\n'), 'Payments work now')
  assert.equal(S.cleanName('plain'), 'plain')
  assert.equal(S.cleanName(null), '')
  assert.equal(S.cleanName(42), '')
  const long = 'A very long chat name that keeps going on and on past forty'
  assert.equal(S.cutName(long, 40), long.slice(0, 39) + '…')
  assert.equal([...S.cutName(long, 40)].length, 40)
  assert.equal(S.cutName('short', 40), 'short')
  assert.equal(S.cutName('exactly-twenty-chars', 20), 'exactly-twenty-chars')
})

test('the list of chats: valid entries newest first, malformed files and entries without an id skipped', () => {
  const r = registry(entry({ name: 'Old', updatedAt: 1 }), '{"sessionId": "x", "name": ', 'not json', '[1, 2]', '{"name": "no id"}', entry({ name: 'Newest', updatedAt: 3 }), entry({ sessionId: OTHER, name: 'Other', updatedAt: 2 }))
  assert.deepEqual(r.map((e) => e.name), ['Newest', 'Other', 'Old'])
  assert.deepEqual(registry(), [])
  assert.deepEqual(S.registryEntries(null), [])
})

test('holderName: the list\'s current name, else the stored name, else 8 characters of the id; null without a session', () => {
  const l = lease('build', T0, { session: SID })
  const stored = { run: l.run, session: SID, session_name: 'Stored name' }
  assert.deepEqual(S.holderName({ lease: l, registry: registry(entry({ name: 'Old', updatedAt: 1 }), entry({ name: 'Renamed', updatedAt: 2 })), stored, sessionId: OTHER }), { name: 'Renamed', self: false, known: true })
  assert.deepEqual(S.holderName({ lease: l, registry: registry(entry({ sessionId: OTHER, name: 'Someone else' })), stored, sessionId: SID }), { name: 'Stored name', self: true, known: true })
  assert.deepEqual(S.holderName({ lease: l, registry: [], stored: { run: l.run, session: OTHER, session_name: 'Not the holder' }, sessionId: OTHER }), { name: '01234567', self: false, known: false })
  assert.deepEqual(S.holderName({ lease: l, registry: null, stored: null, sessionId: null }), { name: '01234567', self: false, known: false })
  assert.equal(S.holderName({ lease: lease('build', T0), registry: registry(entry()), stored: null, sessionId: SID }), null)
  assert.equal(S.holderName({ lease: null, registry: registry(entry()), stored: null, sessionId: SID }), null)
  // Cleaned and cut on the way out, whatever the source.
  const dirty = S.holderName({ lease: l, registry: registry(entry({ name: 'Pay\u001b[31mments\u0007 work' })), stored: null, sessionId: OTHER })
  assert.equal(dirty.name, 'Payments work')
  const long = 'A very long chat name that keeps going on and on past forty'
  assert.equal(S.holderName({ lease: l, registry: [], stored: { run: l.run, session: SID, session_name: long }, sessionId: OTHER }).name, long.slice(0, 39) + '…')
})

test('Comms: the record-change line names who started the run, or this chat; unchanged without a holder', () => {
  const opened = '@@ -1 +1 @@\n-  "lease": null,\n+  "lease": {\n+    "run": "build-1",\n+    "kind": "build",\n+    "session": "' + SID + '",\n'
  assert.equal(L.recordDiffIntent(opened, { name: 'Payments work', self: false, known: true }), 'VBW · build run started by Payments work')
  assert.equal(L.recordDiffIntent(opened, { name: 'Payments work', self: true, known: true }), 'VBW · build run started by this chat')
  assert.equal(L.recordDiffIntent(opened, { name: '01234567', self: false, known: false }), 'VBW · build run started by 01234567')
  assert.equal(L.recordDiffIntent(opened), 'VBW · build run started')
  assert.equal(L.recordDiffIntent(opened, null), 'VBW · build run started')
  assert.equal(L.recordDiffIntent('-  "lease": {\n-    "kind": "build",\n+  "lease": null,\n', { name: 'Payments work', self: false, known: true }), 'VBW · run closed')
  const edit = { tool: 'Edit', input: { file_path: '/proj/.vbw/record.json', old_string: '"lease": null', new_string: '"lease": {"kind": "qa", "session": "' + SID + '"}' } }
  assert.equal(L.recordEditIntent(edit, { name: 'Payments work', self: false, known: true }), 'VBW · qa run started by Payments work')
  assert.equal(L.recordEditIntent(edit), 'VBW · qa run started')
})

test('the Now box: the state sentence ends with held by <name> when another chat holds the run, unchanged in the holder', () => {
  const other = V.panelView({ record: build(), next: next({ action: 'run' }), now: NOW, holder: { name: 'Payments work', self: false, known: true } })
  assert.equal(other.box.state.text, 'VBW is building phase P44 (Show the cost), held by Payments work.')
  const mine = V.panelView({ record: build(), next: next({ action: 'run' }), now: NOW, holder: { name: 'Payments work', self: true, known: true } })
  assert.equal(mine.box.state.text, 'VBW is building phase P44 (Show the cost).')
  const none = V.panelView({ record: build(), next: next({ action: 'run' }), now: NOW })
  assert.equal(none.box.state.text, 'VBW is building phase P44 (Show the cost).')
  const id = V.panelView({ record: build(), next: next({ action: 'run' }), now: NOW, holder: { name: '01234567', self: false, known: false } })
  assert.equal(id.box.state.text, 'VBW is building phase P44 (Show the cost), held by 01234567.')
  // The rows the pane draws from the box's record stay the same shape (protected tests of R51 and R189 keep passing).
  assert.equal(other.rows.find((r) => r.id === 'doing').term, 'build')
})

test('/vbw-why names the holder: this chat with its name in quotes, another chat by name, the id only when no name is known', () => {
  const l = lease('build', Date.parse('2026-10-05T14:52:00Z'), { session: SID, files: ['a.js', 'b.js', 'c.js'] })
  const mine = C.whyText({ record: record({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: SID, holder: { name: 'Payments work', self: true, known: true } })
  assert.equal(lines(mine)[0], 'A build run is open, held by this chat ("Payments work") since 14:52 UTC (8 min ago); its agents may write 3 files.')
  const theirs = C.whyText({ record: record({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: OTHER, holder: { name: 'Payments work', self: false, known: true } })
  assert.equal(lines(theirs)[0], 'A build run is open, held by "Payments work" since 14:52 UTC (8 min ago); its agents may write 3 files.')
  assert.match(theirs, /wait for it/i)
  assert.doesNotMatch(theirs, /run end|end it/i)
  assert.doesNotMatch(theirs, /01234567/)
  const unnamed = C.whyText({ record: record({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: OTHER, holder: { name: '01234567', self: false, known: false } })
  assert.match(lines(unnamed)[0], /^A build run is open, held by another session \(01234567\) since 14:52 UTC/)
  const self = C.whyText({ record: record({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: SID, holder: { name: '01234567', self: true, known: false } })
  assert.match(lines(self)[0], /^A build run is open, held by this session \(01234567\) since 14:52 UTC/)
  const nobody = C.whyText({ record: record({ lease: lease('fix', NOW - 120000, { files: null }) }), next: null, now: NOW, sessionId: SID, holder: null })
  assert.match(lines(nobody)[0], /held by a session VBW cannot name/)
})

test('/vbw-status says the same about the holder as the Now box', () => {
  const theirs = lines(C.statusText({ record: build(), next: next({ action: 'run' }), now: NOW, sessionId: OTHER, holder: { name: 'Payments work', self: false, known: true } }))
  assert.ok(theirs[2].endsWith(', held by Payments work.'), theirs[2])
  assert.ok(theirs[2].startsWith('VBW is building'), theirs[2])
  const mine = lines(C.statusText({ record: build(), next: next({ action: 'run' }), now: NOW, sessionId: SID, holder: { name: 'Payments work', self: true, known: true } }))
  assert.doesNotMatch(mine[2], /held by/)
  const plain = lines(C.statusText({ record: build(), next: next({ action: 'run' }), now: NOW }))
  assert.doesNotMatch(plain[2], /held by/)
})

test('mounted: the panel reads the list and holder.json while a lease is open, and /vbw-why and /vbw-status name the holder', async () => {
  const h = await mount({ env: ENV })
  h.project(build(), next({ action: 'run' }))
  h.write('/home/u/.claude/sessions/1.json', entry({ name: 'Payments work' }))
  h.write('/home/u/.claude/sessions/2.json', 'not json')
  h.write('/proj/.vbw/runtime/holder.json', { run: 'build-1', session: SID, session_name: 'Stored name' })
  await h.start()
  await h.settle()
  const why = (await h.cmd('vbw-why')).text
  assert.match(lines(why)[0], /^A build run is open, held by "Payments work" since /)
  assert.match((await h.cmd('vbw-status')).text, /, held by Payments work\./)
  // The list is gone: the stored name stands in.
  h.remove('/home/u/.claude/sessions/1.json')
  await h.advance(6000)
  assert.match(lines((await h.cmd('vbw-why')).text)[0], /held by "Stored name"/)
})

test('mounted: with no lease the list is not read at all', async () => {
  const h = await mount({ env: ENV })
  h.project(record(), next())
  h.write('/home/u/.claude/sessions/1.json', entry())
  await h.start()
  await h.advance(6000)
  assert.ok(!h.callsOf('fs.list').some((a) => a[0].endsWith('/sessions')), 'the list was read with no lease')
  assert.ok(!h.callsOf('fs.read').some((a) => a[0].endsWith('holder.json')))
})
