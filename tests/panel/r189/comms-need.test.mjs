// R189, phase P142 (evidence level L1, the stand-in for Claude Code's mods API):
// Comms, the strip above the prompt, shows a standing human gate as exactly one
// amber line, 'HH:MM ⚑ VBW needs you · <what>', with no button, for every gate
// kind (the card with buttons and its Later collapse are gone). The line, and
// Mission Control's need sentence with it, disappear at the first redraw after
// the gate leaves next.json or the record (plan approved, milestone shipped,
// human check answered, question answered, a run started), within one refresh
// interval (2 s) and with no other event. A gate that a running run made stale
// is never shown. After a ship no 'ready to ship' stays anywhere (the 2026-10-09
// screenshot). The strip is called Comms and the pane Mission Control (D406).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, find, walk, PLUGIN, ROOT } from '../helpers/fake-mod.mjs'
import { screen, textOf, hhmm } from './helpers/screen.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const TICK = 2000 // the panel's refresh interval
const NEXT = ROOT + '/.vbw/runtime/next.json'
const LINE = /^(\d\d:\d\d) ⚑ VBW needs you · (\S.*)$/
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')

const comms = (h, props = {}) => h.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100, ...props })
const commsLines = async (h) => screen(await comms(h), 100)
const needLines = async (h) => (await commsLines(h)).filter((l) => /⚑|needs you/i.test(l))

async function session(rec = record(), nx = next(), options = {}) {
  const h = await mount(options)
  h.project(rec, nx)
  await h.start()
  await h.advance(4000)
  return h
}

// next.json gets a gate; one refresh sees it. Returns when the gate was written.
async function gate(h, action, detail = {}) {
  const at = h.now()
  h.write(NEXT, next({ action, gate: true, detail }))
  await h.advance(TICK)
  return at
}

const GATES = [
  ['approve', {}, /approv/i],
  ['approve', { files: ['tests/login.bats'] }, /login\.bats|test file/i],
  ['accept', { requirements: ['R54'] }, /R54/],
  ['ship', {}, /ship/i],
  ['unblock', { plans: ['P44.1'], blocked: [{ id: 'P44.1', note: 'no API key' }] }, /block/i],
  ['escalate', { fixes: ['F3'] }, /F3/],
  ['scope', {}, /outside|review/i],
  ['deviations', { deviations: [{ phase: 'P1', file: 'NOTES.md', plan: 'P1.1', change: 'deleted' }] }, /NOTES\.md.*keep|keep.*NOTES\.md/i],
  ['spec', {}, /requirement|what to build/i],
  ['milestone', {}, /milestone|next/i],
  ['convert', {}, /VBW 1|convert/i],
]
// The record that makes each gate true (a gate the record has answered is not shown).
const STANDING = {
  unblock: { plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'blocked' }] },
  escalate: { fixes: [{ id: 'F3', status: 'escalated' }] },
  scope: { evidence: { scope: [{ file: 'src/x.js' }] } },
  milestone: { milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' } },
}

test('every gate kind is one amber line "HH:MM ⚑ VBW needs you · <what>", with no button', async () => {
  for (const [action, detail, what] of GATES) {
    const h = await session(record(STANDING[action]))
    const at = await gate(h, action, detail)
    const tree = await comms(h)
    const name = action + ' ' + JSON.stringify(detail)
    assert.equal(find(tree, (n) => n.type === 'Button'), undefined, name + ': Comms draws no button')
    const lines = screen(tree, 100)
    assert.equal(lines.length, 1, name + ': exactly one line, got ' + JSON.stringify(lines))
    const m = LINE.exec(lines[0])
    assert.ok(m, name + ': "' + lines[0] + '" is not "HH:MM ⚑ VBW needs you · <what>"')
    assert.equal(m[1], hhmm(at), name + ': the time the gate was reached')
    assert.match(m[2], what, name)
    const flag = []
    walk(tree, (n) => { if (n.type === 'Text' && textOf(n).includes('⚑')) flag.push(n) })
    assert.ok(flag.length >= 1, name + ': the flag is drawn')
    for (const t of flag) assert.equal(t.props.color, P.NEED, name + ': the line is in the needs-you colour')
    assert.deepEqual(h.errors, [], name)
  }
})

test('compact first is a gate kind too: one amber line naming /compact, no button', async () => {
  const h = await session()
  h.setUsage({ cost: { usd: 1 }, context: { percent: 90 } })
  h.write(NEXT, next({ action: 'build', gate: false }))
  await h.advance(TICK)
  const tree = await comms(h)
  assert.equal(find(tree, (n) => n.type === 'Button'), undefined, 'no /compact button')
  const lines = screen(tree, 100)
  assert.equal(lines.length, 1, JSON.stringify(lines))
  const m = LINE.exec(lines[0])
  assert.ok(m, lines[0])
  assert.match(m[2], /\/compact/)
})

test('nothing on Comms puts a standing gate away: no Later, the line stays while the gate stands', async () => {
  const h = await session()
  await gate(h, 'approve')
  assert.doesNotMatch((await commsLines(h)).join('\n'), /\bLater\b/)
  await h.advance(60000)
  assert.equal((await needLines(h)).length, 1, 'still standing a minute later')
})

test('plan approved: the line and the need sentence clear at the next refresh, with no other event', async () => {
  const h = await session()
  await gate(h, 'approve')
  assert.equal((await needLines(h)).length, 1)
  assert.match(await h.text(), /Please approve/)
  await h.advance(1000)
  h.project(record({ decisions: [{ id: 'D1', text: 'Contract approved: 3 requirements, 4 checks, 5 plans (abc123def456)', at: iso(h.now()) }] }))
  const draws = h.invalidations()
  await h.advance(TICK)
  assert.ok(h.invalidations() > draws, 'the panel redrew by itself')
  assert.deepEqual(await needLines(h), [], 'Comms still shows the approve gate')
  assert.doesNotMatch(await h.text(), /Please approve/, 'Mission Control still asks for the approval')
  const hint = await h.draw('PromptHint', {})
  assert.doesNotMatch(String((hint.props || {}).tail || ''), /needs you/i, 'the hint line still asks for the approval')
  assert.doesNotMatch(String((await h.cmd('vbw-status')).text), /Please approve/, '/vbw-status still asks for the approval')
})

test('an approval older than the gate, or a record change that is not about it, leaves the line standing', async () => {
  const h = await session(record({ decisions: [{ id: 'D1', text: 'Contract approved: 1 requirements, 1 checks, 1 plans (000000000000)', at: iso(1_700_000_000_000) }] }))
  await gate(h, 'approve')
  assert.equal((await needLines(h)).length, 1, 'an earlier approval does not answer this gate')
  h.project(record({
    decisions: [{ id: 'D1', text: 'Contract approved: 1 requirements, 1 checks, 1 plans (000000000000)', at: iso(1_700_000_000_000) }],
    todos: [{ id: 'T1', text: 'an idea for later', status: 'open' }],
  }))
  await h.advance(TICK * 3)
  assert.equal((await needLines(h)).length, 1, 'a parked idea does not answer the gate')
  assert.match(await h.text(), /Please approve/)
})

test('milestone shipped: the ship line clears at the next refresh, though next.json still says ship', async () => {
  const h = await session()
  await gate(h, 'ship')
  assert.equal((await needLines(h)).length, 1)
  await h.advance(1000)
  h.project(record({ milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' }, shipped: [{ id: 'M9', title: 'Live VBW panel', at: iso(h.now()) }] }))
  await h.advance(TICK)
  assert.equal((await needLines(h)).filter((l) => /ship/i.test(l)).length, 0, 'Comms still offers the ship')
})

test('regression 2026-10-09: after a ship completes, no "ready to ship" stays on Comms or in Mission Control', async () => {
  const h = await session()
  await gate(h, 'ship')
  await h.advance(1000)
  h.project(record({ milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' }, shipped: [{ id: 'M9', title: 'Live VBW panel', at: iso(h.now()) }] }))
  await h.advance(TICK)
  const stale = /ready to ship|go-ahead to ship|ready: your go-ahead/i
  assert.doesNotMatch((await commsLines(h)).join('\n'), stale, 'Comms')
  assert.doesNotMatch(await h.text(), stale, 'Mission Control as it opened')
  await h.press('tab-now')
  assert.doesNotMatch(await h.text(), stale, "Mission Control's Now tab")
  assert.deepEqual(h.errors, [])
})

test('human check answered: the line clears at the next refresh', async () => {
  const req = (status) => ({ id: 'R54', text: 'It reads well', proof: 'human', status, milestone: 'M9' })
  const h = await session(record({ requirements: [req('open')] }))
  await gate(h, 'accept', { requirements: ['R54'] })
  assert.equal((await needLines(h)).length, 1)
  h.project(record({ requirements: [req('accepted')] }))
  await h.advance(TICK)
  assert.deepEqual(await needLines(h), [])
  assert.doesNotMatch(await h.text(), /check the result by hand/i)
})

test('a run started: the line clears at the next refresh and Mission Control says nothing is needed', async () => {
  const h = await session()
  await gate(h, 'approve')
  h.project(record({ lease: lease('build', h.now()), plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }] }))
  await h.advance(TICK)
  assert.deepEqual(await needLines(h), [])
  assert.doesNotMatch(await h.text(), /Please approve/)
})

test('the gate leaves next.json: the line clears at the next refresh', async () => {
  const h = await session()
  await gate(h, 'approve')
  h.write(NEXT, next())
  await h.advance(TICK)
  assert.deepEqual(await needLines(h), [])
  assert.match(await h.text(), /not waiting on you/i)
})

test('a question: the line stands while the menu is open and is gone at the redraw after it is answered', async () => {
  const h = await session()
  let answer
  const asking = h.fire('tool.call', { tool: 'AskUserQuestion', tool_use_id: 'q1', questions: [{ question: 'Which?' }] }, () => new Promise((r) => (answer = r)))
  await h.settle()
  const open = await needLines(h)
  assert.equal(open.length, 1)
  assert.match(open[0], LINE)
  answer({ result: 'A' })
  await asking
  await h.settle()
  assert.deepEqual(await needLines(h), [], 'the answered question still shows')
  await h.advance(TICK)
  assert.deepEqual(await needLines(h), [])
})

test('a gate in next.json that a running run made stale (a lease is held) is never shown', async () => {
  const h = await session(record({ lease: lease('build', 1_800_000_000_000) }), next({ action: 'approve', gate: true }))
  assert.deepEqual(await needLines(h), [])
  await h.advance(10000)
  assert.deepEqual(await needLines(h), [])
  assert.doesNotMatch(await h.text(), /Please approve/)
})

test('names: the strip is Comms and the pane Mission Control; nothing VBW draws or says calls them the band or Telemetry', async () => {
  const h = await session()
  const reg = h.callsOf('command.register').map((a) => a[0]).find((c) => c && c.name === 'vbw-panel')
  assert.ok(reg, '/vbw-panel is still registered')
  assert.match(String(reg.description), /Mission Control/)
  assert.match(String((await h.cmd('vbw-panel')).text), /Mission Control/)
  await gate(h, 'approve')
  const said = [...(await commsLines(h)), await h.text(), String((await h.cmd('vbw-status')).text), String((await h.cmd('vbw-why')).text)]
  for (const t of said) assert.doesNotMatch(t, /\bband\b|telemetry/i, t)
  for (const reg2 of h.callsOf('command.register').map((a) => a[0])) assert.doesNotMatch(String(reg2.description), /\bband\b|telemetry/i)
})

// Every gate kind clears when the record says it is done, with next.json left as it was.
const DONE = {
  milestone: [{ milestone: { id: 'M10', title: 'Next work', status: 'active' } }, /shipped|what to build next/i],
  spec: [{ requirements: [{ id: 'R1', text: 'It works', proof: 'auto', status: 'open', milestone: 'M9' }] }, /needs you to say what to build/i],
  unblock: [{ plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'planned' }] }, /blocked/i],
  escalate: [{ fixes: [{ id: 'F3', status: 'closed' }] }, /decision is needed from you on F3/i],
  scope: [{ evidence: { scope: [] } }, /outside/i],
  deviations: [{ fixes: [{ id: 'F1', req: 'R1', restore: 'NOTES.md', attempts: 0, status: 'open', note: 'Restore NOTES.md' }] }, /NOTES\.md/],
  convert: [{ converted: { from: '.vbw-planning', at: '2026-10-16T10:00:00Z' } }, /VBW 1/],
}
const DETAIL = { unblock: { plans: ['P44.1'] }, escalate: { fixes: ['F3'] }, deviations: { deviations: [{ phase: 'P1', file: 'NOTES.md', plan: 'P1.1', change: 'deleted' }] } }

test('every other gate kind clears too once the record says it is done, with next.json unchanged: Comms, Mission Control, the hint line and /vbw-status', async () => {
  for (const [action, [done, said]] of Object.entries(DONE)) {
    const h = await session(record(STANDING[action]))
    await gate(h, action, DETAIL[action] || {})
    assert.equal((await needLines(h)).length, 1, action + ': the gate stands first')
    await h.advance(1000)
    h.project(record(done))
    await h.advance(TICK)
    assert.deepEqual(await needLines(h), [], action + ': Comms still shows the answered gate')
    assert.doesNotMatch(await h.text(), said, action + ': Mission Control still shows it')
    const hint = await h.draw('PromptHint', {})
    assert.doesNotMatch(String((hint.props || {}).tail || ''), /needs you/i, action + ': the hint line still asks')
    assert.doesNotMatch(String((await h.cmd('vbw-status')).text), said, action + ': /vbw-status still says it')
  }
})

test('after a newer "Contract approved" decision no /vbw:approve is suggested, in the running session or in a new one', async () => {
  const h = await session()
  await gate(h, 'approve')
  assert.equal(h.callsOf('prompt.suggest').length, 1, 'the open approve gate suggests it once')
  const approved = record({ decisions: [{ id: 'D1', text: 'Contract approved: 3 requirements, 4 checks, 5 plans (abc123def456)', at: iso(h.now() + 1000) }] })
  const fresh = await mount()
  fresh.project(approved, next({ action: 'approve', gate: true }))
  fresh.write(NEXT, next({ action: 'approve', gate: true }))
  await fresh.start()
  await fresh.advance(4000)
  assert.equal(fresh.callsOf('prompt.suggest').length, 0, 'a new session suggested /vbw:approve for an approved plan')
})
