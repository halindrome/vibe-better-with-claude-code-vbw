// R189, phase P144 (evidence level L1, the stand-in for Claude Code's mods API):
// Mission Control's Now tab opens on a 'what's happening now' box: VBW's state as
// a plain sentence (planning, building which phase, proving, checking, or
// nothing running), the current step with the HH:MM it started and the HH:MM it
// is expected to end (R190, from the kernel's note .vbw/runtime/step.json), and
// the session cost line (D106). When VBW needs the user the box holds the need
// sentence, the command that answers it and since when it waits; what the box
// says is not said again below it. The box follows the state within one refresh
// (2 s). Every event and message line starts with the local time as HH:MM: the
// milestone's time-left sentence ('[14:08] Milestone end: about 40 min, until
// around 14:50.'), a helper card's state (started, finished, failed), the
// all-checks-pass line on Comms and the What's next recommendation. A message
// keeps the time it began saying what it says, so the clock alone redraws nothing.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, lease, find, walk, deepFreeze, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen, textOf, hhmm } from './helpers/screen.mjs'

const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)
const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const TICK = 2000
const NEXT = ROOT + '/.vbw/runtime/next.json'
const STEPS = ROOT + '/.git/vbw/steps.json'
const NOTE = ROOT + '/.vbw/runtime/step.json'
const S = 1000
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, started_at: iso(T0 - 1e7 - i * 1e5), ended_at: iso(T0 - 1e7 - i * 1e5 + s * 1000), seconds: s }))
const HISTORY = { steps: [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])] }
// The kernel's note for the build of P44.1 (R190): it ends at END.
const note = (end, over = {}) => JSON.stringify({ kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(T0 - 300 * S),
  ids: ['P44.1'], doing: 'building P44.1', parts: { done: 0, total: 1 }, proof: null, first_end: iso(end), end: iso(end), late: false,
  road: { seconds: 7800, end: iso(end + 7200000), rounds: { deep: 2 }, basis: '2 waves, 2 proofs', say: 'milestone end: about 2 h 10 min, until around 16:40' }, ...over })
const PLANS = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]
const WIDTH = 60
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

async function session(rec = record(), nx = next(), files = {}) {
  const h = await mount({ files })
  h.git()
  h.project(rec, nx)
  await h.start()
  await h.advance(4000)
  return h
}
const pane = (h) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: WIDTH, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} } })
const paneLines = async (h) => screen(await pane(h), WIDTH)

// The box: the first bordered Box of the Now tab, drawn before the milestone sentence.
async function nowBox(h) {
  const tree = await pane(h)
  const order = []
  walk(tree, (n) => order.push(n))
  const box = order.find((n) => n.type === 'Box' && n.props.borderStyle)
  assert.ok(box, 'the Now tab has no box')
  const milestone = order.findIndex((n) => n.type === 'Text' && /^Working on /.test(textOf(n)))
  assert.ok(milestone < 0 || order.indexOf(box) < milestone, 'the box is not at the top of the Now tab')
  return screen(box, WIDTH).join('\n')
}

test("the Now tab opens on the box: the state, the step with the time it started, and the session cost, above everything else", async () => {
  const started = T0 - 300 * S
  const h = await session(record({ lease: lease('build', started), plans: PLANS }), next({ action: 'run' }))
  const box = await nowBox(h)
  assert.match(box, /building/i)
  assert.match(box, /P44/)
  assert.ok(box.includes(hhmm(started)), 'the step has no start time ' + hhmm(started) + ':\n' + box)
  assert.match(box, /\$1\.42/, 'the session cost line is in the box')
  assert.equal((await paneLines(h)).filter((l) => /\$1\.42/.test(l)).length, 1, 'the cost line is drawn once')
})

test('each state reads as a plain sentence: planning, building which phase, proving, checking, waiting for you and for what, nothing running', async () => {
  const cases = [
    [record({ lease: lease('plan', T0) }), next({ action: 'run' }), {}, [/planning/i]],
    [record({ lease: lease('build', T0), plans: PLANS }), next({ action: 'run' }), {}, [/building/i, /P44/]],
    [record(), next({ action: 'prove' }), { [ROOT + '/.vbw/runtime/proving.sess-1']: '4242\n' }, [/proving/i]],
    [record({ lease: lease('qa', T0) }), next({ action: 'run' }), {}, [/checking/i]],
    [record(), next({ action: 'approve', gate: true }), {}, [/Please approve the plan/, /\/vbw:approve/]],
    [record(), next(), {}, [/nothing (is )?running/i]],
  ]
  for (const [rec, nx, files, want] of cases) {
    const h = await session(rec, nx, files)
    const box = await nowBox(h)
    for (const re of want) assert.match(box, re, JSON.stringify(nx) + ' ' + JSON.stringify(rec.lease))
  }
})

test('the box follows the state within one refresh, with no other event', async () => {
  const h = await session()
  assert.match(await nowBox(h), /nothing (is )?running/i)
  h.project(record({ lease: lease('build', h.now()), plans: PLANS }), next({ action: 'run' }))
  await h.advance(TICK)
  assert.match(await nowBox(h), /building/i)
  h.project(record(), next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  assert.match(await nowBox(h), /Please approve the plan/)
})

test('the box says since when VBW waits: the time the gate was reached', async () => {
  const h = await session()
  const at = h.now()
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  const box = await nowBox(h)
  assert.ok(box.includes('Waiting since ' + hhmm(at) + '.'), box)
})

test('when VBW needs the user the box holds the one sentence and the command, and nothing below repeats them', async () => {
  const cases = [
    [{ action: 'approve', gate: true }, 'Please approve the plan before VBW builds it.', '/vbw:approve'],
    [{ action: 'accept', gate: true, detail: { requirements: ['R2'] } }, 'Please check the result by hand: R2.', '/vbw:verify'],
    [{ action: 'spec', gate: true }, 'VBW needs you to say what to build: the requirements.', '/vbw:vibe'],
  ]
  for (const [nx, sentence, command] of cases) {
    const h = await session(record(), next(nx))
    const box = await nowBox(h)
    assert.ok(box.includes(sentence), box)
    assert.ok(box.includes('Type ' + command + '.'), box)
    const all = (await paneLines(h)).join('\n')
    assert.equal(all.split(sentence).length - 1, 1, 'the need sentence is said once:\n' + all)
    assert.equal(all.split(command).length - 1, 1, 'the command is said once:\n' + all)
    assert.doesNotMatch(all, /VBW is not waiting on you/)
    assert.doesNotMatch(all, /VBW is waiting for you/)
  }
})

test('a question names no command; the compact warning already says its own', async () => {
  const h = await session()
  let box = ''
  await h.fire('tool.call', { tool: 'AskUserQuestion', questions: [{ question: 'Which?' }] }, async () => {
    box = await nowBox(h)
    return { result: 'x' }
  })
  assert.match(box, /VBW has a question for you/)
  assert.doesNotMatch(box, /Type \//)
  const full = view.panelView({ record: record(), next: next({ action: 'build' }), now: T0, health: { contextPct: 90 } })
  assert.match(full.box.state.text, /run \/compact first/)
  assert.equal(full.box.command, null)
})

test('the box carries the step with its start and its end, and the sentences below do not repeat them', async () => {
  const end = T0 + 600 * S
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY), [NOTE]: note(end) })
  const box = await nowBox(h)
  assert.ok(box.includes('Current step: building P44.1, started at ' + hhmm(T0 - 300 * S) + '.'), box)
  assert.ok(box.includes('This step: about 10 min, until around ' + hhmm(end) + '.'), box)
  const all = (await paneLines(h)).join('\n')
  assert.equal(all.split('This step:').length - 1, 1, 'the end time is in the box only')
  assert.equal(all.split('until around ' + hhmm(end)).length - 1, 1, 'the end time is said once:\n' + all)
  assert.equal(all.split('VBW is building').length - 1, 1, 'what VBW is doing is said once, in the box:\n' + all)
  assert.equal(all.split('This session has cost').length - 1, 1, 'the cost is said once')
})

test('the milestone sentence starts with [HH:MM], as in "[14:08] Milestone end: about 2 h 10 min, until around 16:40."', async () => {
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [STEPS]: JSON.stringify(HISTORY), [NOTE]: note(T0 + 600 * S) })
  const left = (await paneLines(h)).filter((l) => /Milestone end: about 2 h/.test(l))
  assert.equal(left.length, 1, 'no milestone time-left sentence')
  assert.match(left[0].replace(/[│╭╮╰╯─]/g, '').trim(), /^\[\d\d:\d\d\] /, 'in the box, dated')
})

test('a message keeps the time it began saying what it says: the clock moving alone redraws nothing', async () => {
  const h = await session()
  h.write(NEXT, next({ action: 'approve', gate: true }))
  await h.advance(TICK)
  const first = (await paneLines(h)).find((l) => /Please approve/.test(l))
  const draws = h.invalidations()
  await h.advance(3 * 60000)
  assert.equal(h.invalidations(), draws, 'the clock alone redrew the panel')
  assert.equal((await paneLines(h)).find((l) => /Please approve/.test(l)), first)
})

test("a helper's crew row says its role, state and doing and for how long, the longest-running first; finished ones are gone", async () => {
  const NOW = T0 + 3600 * S
  const agent = (over) => ({ id: 'a', role: 'dev', label: 'P44.1', state: 'working', activity: { kind: 'tool', text: 'editing a.js' }, startedAt: NOW - 900 * S, endedAt: null, lastSeenAt: NOW - S, tokens: 1000, result: null, ...over })
  const run = deepFreeze({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 3000 * S, endedAt: null, status: 'running', agents: [
    agent({ id: 'w', startedAt: NOW - 900 * S }),
    agent({ id: 'o', role: 'qa', label: 'P44', startedAt: NOW - 1300 * S, activity: null }),
    agent({ id: 'd', label: 'P44.2', state: 'done', startedAt: NOW - 3000 * S, endedAt: NOW - 1500 * S, result: 'ok' }),
  ] })
  const lines = screen(live.renderNow(UI, live.nowModel({ run, now: NOW, width: 80 })), 80)
  const rows = lines.filter((l) => /●/.test(l))
  assert.equal(rows.length, 2, lines.join('\n'))
  assert.match(rows[0], /^qa P44\s+● running · 21 min 40 s$/)
  assert.match(rows[1], /^dev P44\.1\s+● editing a\.js · 15 min$/)
  assert.ok(!lines.some((l) => /P44\.2/.test(l)), 'the done helper left')
})

test('the all-checks-pass line on Comms starts with the time the proof passed', async () => {
  const h = await session()
  const at = h.now()
  h.project(record({ evidence: { at: iso(at), passed: true, contract: 'c1', checks: {} } }))
  await h.advance(TICK)
  const lines = screen(await h.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100 }), 100)
  const pass = lines.find((l) => /All checks pass/.test(l))
  assert.ok(pass, 'no all-checks-pass line')
  assert.ok(pass.trim().startsWith('[' + hhmm(at) + '] '), "'" + pass + "'")
})

test("the What's next recommendation shows the time it was written as [HH:MM]", async () => {
  const at = T0 - 7200 * S
  const h = await session(record({ recommendation: { at: iso(at), top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most.', size: 'small', source: 'T4' }, runners: [] } }))
  const section = find(await pane(h), (n) => n.type === 'Box' && n.props.key === 'whats-next')
  assert.ok(section)
  const lines = screen(section, WIDTH)
  assert.ok(lines.some((l) => l.trim().startsWith('[' + hhmm(at) + ']')), lines.join('\n'))
})

test('a state change that touches nothing else still redraws the box within one refresh: a proof starting, then ending', async () => {
  const mark = ROOT + '/.vbw/runtime/proving.sess-1'
  const h = await session()
  assert.match(await nowBox(h), /nothing (is )?running/i)
  let draws = h.invalidations()
  h.write(mark, '4242\n')
  await h.advance(TICK)
  assert.ok(h.invalidations() > draws, 'the panel was not asked to redraw when the proof began')
  assert.match(await nowBox(h), /proving/i)
  draws = h.invalidations()
  h.remove(mark)
  await h.advance(TICK)
  assert.ok(h.invalidations() > draws, 'the panel was not asked to redraw when the proof ended')
  assert.match(await nowBox(h), /nothing (is )?running/i)
})

test('a time-left sentence keeps the time it began saying what it says while the words stay the same', async () => {
  // A step with parts past even its moved end time says "until around HH:MM, later than usual" and goes on saying it.
  const h = await session(record({ lease: lease('build', T0 - 3 * 3600 * S), plans: PLANS }), next({ action: 'run' }),
    { [STEPS]: JSON.stringify(HISTORY), [NOTE]: note(T0 - 3600 * S, { first_end: iso(T0 - 2 * 3600 * S), late: true }) })
  const milestone = async () => (await paneLines(h)).find((l) => /Milestone end/.test(l))
  const first = await milestone()
  assert.ok(first, 'no milestone sentence')
  assert.match(first.replace(/[│╭╮╰╯─]/g, '').trim(), /^\[\d\d:\d\d\] /, 'in the box, dated')
  const box = await nowBox(h)
  assert.match(box, /later than usual/)
  await h.advance(10 * 60000)
  assert.equal(await milestone(), first, 'the milestone time moved with the clock')
  assert.equal(await nowBox(h), box, 'the step line moved with the clock')
})

test('the state sentence itself, the box\'s first line, names each state; the step line below it never stands in for it', async () => {
  const first = async (h) => (await nowBox(h)).split('\n').map((l) => l.replace(/[│╭╮╰╯─]/g, '').trim()).filter(Boolean)[0]
  const proving = await session(record(), next({ action: 'prove' }), { [ROOT + '/.vbw/runtime/proving.sess-1']: '4242\n' })
  assert.match(await first(proving), /proving/i)
  assert.doesNotMatch(await first(proving), /nothing/i)
  const idle = await session()
  assert.match(await first(idle), /nothing (is )?running/i)
})

// P2 (tidy the pane): one message per fact. The box already says that nothing runs, so the
// Now tab adds no "No VBW workflow runs" line under it; that line stays for a run held by
// another chat (the box says it runs, the line says it is not in this chat). And without
// the kernel's note the step line says only when it started, not the word the state used.
test('the Now tab does not say again under the box that no workflow runs; it still says a held run is not in this chat', async () => {
  const idle = await session()
  assert.match(await nowBox(idle), /Nothing is running/)
  assert.doesNotMatch((await paneLines(idle)).join('\n'), /No VBW workflow runs/)
  // R227: the 'your turn' row says only what the panel knows: VBW is not waiting on the user.
  assert.match((await paneLines(idle)).join('\n'), /VBW is not waiting on you\./)
  assert.doesNotMatch((await paneLines(idle)).join('\n'), /Nothing is needed from you/)
  const need = await session(record(), next({ action: 'approve', gate: true }))
  assert.doesNotMatch((await paneLines(need)).join('\n'), /No VBW workflow runs/)
  const held = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }))
  assert.match((await paneLines(held)).join('\n'), /No VBW workflow runs in this session right now/)
})

test('without the kernel\'s note the step line says when it started, and does not repeat the state\'s word', async () => {
  const h = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }))
  const box = await nowBox(h)
  assert.ok(box.includes('Started at ' + hhmm(T0 - 300 * S) + '.'), box)
  assert.doesNotMatch(box, /Current step/)
  const proving = await session(record(), next({ action: 'prove' }), { [ROOT + '/.vbw/runtime/proving.sess-1']: '4242\n' })
  assert.doesNotMatch(await nowBox(proving), /Current step: proving/)
  const noted = await session(record({ lease: lease('build', T0 - 300 * S), plans: PLANS }), next({ action: 'run' }), { [NOTE]: note(T0 + 600 * S) })
  assert.ok((await nowBox(noted)).includes('Current step: building P44.1, started at ' + hhmm(T0 - 300 * S) + '.'))
})

// B5 (2.1.11): the box as Lane B's pure model and drawing (nowBoxModel, renderNowBox in
// panel-mission-live.js): 2.1.8's contents, plus a thin done/total strip under the step
// line when the step has parts, the session cost line in its colour, and the milestone's
// end with its basis. Every time names its day when it is not today (design rule 5).
const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const B_NOW = T0 + 3600 * S
const ROAD = { seconds: 7800, end: iso(B_NOW + 7800 * S), rounds: { deep: 2 }, basis: '2 waves, 2 proofs', say: 'milestone end: about 2 h 10 min, until around 16:40' }
const building = (over = {}) => ({
  record: record({ lease: lease('build', B_NOW - 300 * S), plans: PLANS }), cost: 1.42, now: B_NOW, stamps: { 'estimate-milestone': B_NOW - 60 * S },
  step: { kind: 'build', run: 'build-1', doing: 'building P44.1', started_at: iso(B_NOW - 300 * S), parts: { done: 3, total: 8 }, end: iso(B_NOW + 720 * S), late: false, road: ROAD },
  ...over,
})

test('B5: the box model while building: the state, the step with start and end, its parts, the milestone end with its basis, the cost', () => {
  const b = view.nowBoxModel(building())
  assert.deepEqual(b.state, { text: 'VBW is building phase P44 (Show the cost).', need: false })
  assert.equal(b.command, null)
  assert.equal(b.step.text, 'Current step: building P44.1, started at ' + hhmm(B_NOW - 300 * S) + '.')
  assert.equal(b.step.end, 'This step: about 12 min, until around ' + hhmm(B_NOW + 720 * S) + '.')
  assert.equal(b.step.timed, true)
  assert.deepEqual(b.parts, { done: 3, total: 8 })
  assert.deepEqual(b.milestone, { text: '[' + hhmm(B_NOW - 60 * S) + '] Milestone end: about 2 h 10 min, until around 16:40.', basis: 'basis: 2 waves, 2 proofs', known: true, term: 'estimate, approximate' })
  assert.deepEqual(b.cost, { text: 'This session has cost $1.42 so far.', known: true, term: 'session cost' })
})

test('B5: when VBW needs you the box says the need, the command and since when, with the day when not today; no step, no strip', () => {
  const since = B_NOW - 18 * 3600 * S
  const b = view.nowBoxModel({ record: record(), need: { key: 'approve', kind: 'approve', text: 'Please approve the plan before VBW builds it.', at: since }, cost: null, now: B_NOW, next: next({ action: 'approve', gate: true }) })
  assert.deepEqual(b.state, { text: 'Please approve the plan before VBW builds it.', need: true })
  assert.equal(b.command, '/vbw:approve')
  const day = new Date(since).getDate() === new Date(B_NOW).getDate() ? '' : 'yesterday '
  assert.equal(b.step.text, 'Waiting since ' + day + hhmm(since) + '.')
  assert.equal(b.parts, null)
  assert.deepEqual(b.cost, { text: 'The cost so far is not available.', known: false, term: 'cost, not available' })
  const idle = view.nowBoxModel({ record: record(), cost: 0.42, now: B_NOW })
  assert.deepEqual([idle.state.text, idle.step, idle.milestone], ['Nothing is running.', null, null])
  const noBasis = view.nowBoxModel(building({ step: null, next: next({ road: { end: null, basis: 'no finished build steps yet' } }) }))
  assert.deepEqual(noBasis.milestone, { text: 'No estimate yet: no finished build steps yet.', basis: null, known: false, term: 'estimate, no basis' })
  assert.equal(view.nowBoxModel({ record: null }), null)
})

test('B5: the box draws the strip in the progress colour beside the figure, the end and milestone in the estimate colour, the cost in the accent, at 80, 100 and 140 columns', () => {
  for (const width of [80, 100, 140]) {
    const tree = live.renderNowBox(UI, view.nowBoxModel(building()), { width })
    const lines = screen(tree, width)
    for (const l of lines) assert.ok([...l].length <= width, width + ': ' + l)
    const strip = find(tree, (n) => n.type === 'Box' && n.props.key === 'parts')
    assert.ok(strip, 'a parts strip')
    const cells = []
    walk(strip, (n) => { if (n.type === 'Text') cells.push(n) })
    assert.equal(cells[0].props.color, P.PROGRESS)
    assert.equal(textOf(cells[0]), '▰'.repeat(3))
    assert.equal(textOf(cells[1]), '▱'.repeat(5))
    assert.equal(cells[1].props.dimColor, true)
    assert.equal(textOf(cells[2]), ' 3 of 8 done')
    const colour = (re) => find(tree, (n) => n.type === 'Text' && re.test(textOf(n))).props
    assert.equal(colour(/^This step:/).color, P.ESTIMATE)
    assert.equal(colour(/Milestone end/).color, P.ESTIMATE)
    assert.equal(colour(/^basis:/).dimColor, true)
    assert.equal(colour(/^This session has cost/).color, P.ACCENT)
  }
  const many = live.renderNowBox(UI, view.nowBoxModel(building({ step: { ...building().step, parts: { done: 40, total: 120 } } })), { width: 80 })
  for (const l of screen(many, 80)) assert.ok([...l].length <= 80, l)
  assert.ok(screen(many, 80).some((l) => / 40 of 120 done/.test(l)))
})

test('B5: the dim labels under sentences go with one switch; nothing in the box is said twice', () => {
  const tree = live.renderNowBox(UI, view.nowBoxModel(building()), { width: 100, labels: false })
  const lines = screen(tree, 100).join('\n')
  assert.doesNotMatch(lines, /session cost|estimate, approximate/)
  const all = screen(live.renderNowBox(UI, view.nowBoxModel(building()), { width: 100 }), 100).map((l) => l.replace(/[│╭╮╰╯─|+]/g, '').trim()).filter(Boolean)
  assert.equal(new Set(all).size, all.length, 'a line said twice: ' + all.join(' / '))
})
