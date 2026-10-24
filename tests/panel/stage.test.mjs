// Comms (mods_4_vbw.md §3.1, §3.2, §3.8; R189, D406): the strip above the prompt.
// plugin/hooks/panel-stage.js turns the run model, a `need` (the needs-you line,
// given by panel-view.js) and the session's health into a model (tested by
// value) and draws it with h() (tested by tree shape). Pure: no Claude Code
// needed (evidence level L1). The same behaviour through the stand-in for
// Claude Code's mods API is checked by C360 and C361 (tests/panel/r189).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, next, deepFreeze, walk, find, collect } from './helpers/fake-mod.mjs'

const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)
const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const candy = await import(pathToFileURL(PLUGIN + '/hooks/panel-candy.js').href)
const NOW = 1_800_000_000_000
const S = 1000
const UI = { Box: Object.freeze({ element: 'Box' }), Text: Object.freeze({ element: 'Text' }), Button: Object.freeze({ element: 'Button' }) }
const RUI = { ...UI, Raster: Object.freeze({ element: 'Raster' }) }
const len = (s) => [...s].length
const hm = (ms) => String(new Date(ms).getHours()).padStart(2, '0') + ':' + String(new Date(ms).getMinutes()).padStart(2, '0')

const agent = (over = {}) => ({
  id: 'a1', role: 'architect', label: 'scope', model: 'opus', state: 'working',
  activity: { kind: 'tool', text: 'reading .vbw/spec.md' },
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents, over = {}) => ({
  runId: 'wf_1', kind: 'planning', phase: 'wave 1 of 2', startedAt: NOW - 604 * S, endedAt: null, status: 'running', agents, ...over,
})
const model = (input) => stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'full', ...input })
const need = (what = 'the plan is ready: review it, then approve it to build', over = {}) => ({ key: 'approve', what, at: NOW - 90 * S, ...over })
const many = (n, over = {}) => Array.from({ length: n }, (_, i) => agent({ id: 'x' + i, label: 'P9.' + i, ...over }))
const words = (tree) => collect(tree).join('')
const buttons = (tree) => {
  const out = []
  walk(tree, (n) => n.type === 'Button' && out.push(n))
  return out
}

// --- nothing to show ---------------------------------------------------------

test('nothing runs and nothing is needed: Comms draws nothing (the hint line covers it)', () => {
  assert.equal(model({ run: null, next: next() }), null)
  assert.equal(model({}), null)
  assert.equal(stage.stageModel(), null)
  assert.equal(stage.stageModel(null), null)
  assert.equal(model({ run: run([]), next: next() }), null, 'a run without helpers yet has no crew to show')
})

test('garbage in never throws and gives null or a model', () => {
  const bad = [42, 'x', [], { run: 'x' }, { run: { agents: 'x' } }, { run: run([null, 7, 'a', {}]) },
    { need: 'x' }, { need: { what: 7 } }, { seen: 'a1', run: run([agent()]) }, { run: run([agent({ activity: 5, tokens: 'x', startedAt: 'y' })]) },
    { next: { gate: true, action: 7, detail: 'x' }, health: 'x' }, { health: { contextPct: 'x' }, next: next() }]
  for (const b of bad) assert.doesNotThrow(() => stage.stageModel(typeof b === 'object' && b && !Array.isArray(b) ? { now: NOW, ...b } : b))
  const m = model({ run: run([null, 7, {}, agent()]) })
  assert.equal(m.rows.length, 1, 'only the well-formed helper is drawn')
})

test('the input is never changed', () => {
  const input = deepFreeze({ run: run([agent(), agent({ id: 'a2', state: 'done', endedAt: NOW - 5 * S, result: 'ok' }), agent({ id: 'a3', state: 'failed' })]), need: need(),
    seen: ['a3'], now: NOW, maxRows: 12, columns: 100, motion: 'full', health: { contextPct: 90, weekPct: 85 }, next: next({ action: 'build' }) })
  assert.doesNotThrow(() => stage.stageModel(input))
  assert.ok(stage.stageModel(input))
})

// --- the needs-you line (R189.1 to R189.3) -----------------------------------

test('a need is one line "HH:MM ⚑ VBW needs you · <what>", timed when the gate was reached', () => {
  const m = model({ need: need() })
  assert.equal(m.kind, 'need')
  assert.equal(m.need.text, hm(NOW - 90 * S) + ' ⚑ VBW needs you · the plan is ready: review it, then approve it to build')
  assert.equal(m.need.key, 'approve')
  const tree = stage.renderStage(UI, m)
  const line = find(tree, (n) => n.type === 'Text' && /needs you/.test(words(n)))
  assert.equal(line.props.color, P.NEED, 'in the needs-you colour')
  assert.equal(collect(tree).length, 1, 'one line and nothing else')
})

test('the needs-you line has no button, no Later and no collapse, for any `what`, and for /compact first', () => {
  for (const what of ['the plan is ready', 'check by hand what only you can judge: R54', 'the context is nearly full: run /compact first', 'the fix limit was reached for F3: decide how to go on']) {
    const m = model({ need: need(what, { key: what }) })
    const tree = stage.renderStage(UI, m, () => {})
    assert.deepEqual(buttons(tree), [], what)
    assert.match(words(tree), new RegExp('⚑ VBW needs you · ' + what.replace(/[/:]/g, '.')), what)
    assert.doesNotMatch(words(tree), /Later/)
    assert.equal(m.buttons, undefined)
  }
})

test('a need is cut to the columns, with an ellipsis, and fits any room', () => {
  const long = need('check by hand what only you can judge: ' + Array.from({ length: 40 }, (_, i) => 'REQUIREMENT-' + i).join(', '))
  for (const columns of [20, 40, 80]) {
    const m = model({ need: long, columns })
    assert.ok(len(m.need.text) <= columns, columns + ': ' + len(m.need.text))
    assert.match(m.need.text, /…$/)
  }
  assert.ok(model({ need: need(), maxRows: 1 }), 'one row of room still shows the line')
})

test('a need without a sentence, or no need at all, draws no line; a need without a time is just the sentence', () => {
  assert.equal(model({ need: { key: 'k', at: NOW } }), null)
  assert.equal(model({ need: null }), null)
  assert.equal(model({ need: { key: 'k', what: 'say what to build' } }).need.text, '⚑ VBW needs you · say what to build')
})

test('a need stands above a crew that works (a question opens mid-run) and the crew keeps the rest of the room', () => {
  const m = model({ need: need(), run: run([agent()]), maxRows: 6 })
  assert.equal(m.kind, 'crew')
  assert.match(m.need.text, /needs you/)
  const tree = stage.renderStage(UI, m)
  const lines = collect(tree)
  assert.match(lines[0], /^\d\d:\d\d ⚑ VBW needs you/)
  assert.ok(m.rows.length <= 4)
  const tight = model({ need: need(), run: run(many(6)), maxRows: 4 })
  assert.equal(tight.mode, 'line', 'the need takes one of 4 rows, the crew keeps 3: the top line alone')
  const six = model({ need: need(), run: run(many(6)), maxRows: 8, motion: 'calm' })
  assert.equal(1 + 1 + six.rows.length + (six.more ? 1 : 0), 8, 'the line, the top line, the rows and the fold fill the room')
  assert.equal(model({ need: need(), run: run(many(6)), maxRows: 1 }).kind, 'need', 'with one row, the need wins')
})

// --- health nudges (§3.8) ----------------------------------------------------

test('weekly limit at 80% or more adds a line under the need, or alone before a run; not below 80', () => {
  const m = model({ need: need(), next: next({ action: 'approve', gate: true }), health: { contextPct: 10, weekPct: 84, weekPerRun: 6 } })
  const line = m.lines.find((l) => /Weekly limit/.test(l.text))
  assert.match(line.text, /Weekly limit 84%: a run like this used about 6% last time/)
  assert.equal(line.color, P.NEED)
  assert.equal(model({ need: need(), next: next({ action: 'approve' }), health: { weekPct: 93 } }).lines[0].color, P.NEED)
  assert.equal(model({ need: need(), next: next({ action: 'approve' }), health: { weekPct: 79 } }).lines.length, 0)
  assert.equal(model({ need: need(), next: next({ action: 'ship' }), health: { weekPct: 95 } }).lines.length, 0, 'shipping starts no run')
  const alone = model({ next: next({ action: 'build' }), health: { weekPct: 90 } })
  assert.equal(alone.kind, 'nudge')
  assert.doesNotMatch(alone.title, /needs you/)
  assert.match(alone.title, /build/)
  assert.deepEqual(buttons(stage.renderStage(UI, alone)), [], 'a nudge has no button')
})

test('a run about to start shows a nudge only when health asks for it; context alone is the need, not a nudge', () => {
  assert.equal(model({ next: next({ action: 'build' }), health: { contextPct: 90, weekPct: 50 } }), null)
  assert.equal(model({ next: next({ action: 'build' }), health: { contextPct: 50, weekPct: 50 } }), null)
  assert.equal(model({ next: next({ action: 'prove' }), health: { weekPct: 99 } }), null, 'prove starts no workflow')
})

// --- the crew (§3.1) ---------------------------------------------------------

test('the header: kind, phase, elapsed, cost when known, and Mission Control on p', () => {
  const m = model({ run: run([agent()]), cost: 3.2 })
  assert.equal(m.kind, 'crew')
  assert.equal(m.header.text, 'VBW ▸ planning · wave 1 of 2 · 10m04s · ≈$3.20 this run')
  assert.deepEqual(m.header.button, { key: 'p', label: 'Mission Control', action: { open: 'mission' } })
  assert.equal(model({ run: run([agent()], { phase: null }) }).header.text, 'VBW ▸ planning · 10m04s')
  assert.equal(model({ run: run([agent()], { startedAt: NOW - 3725 * S }) }).header.text, 'VBW ▸ planning · wave 1 of 2 · 1h02m')
})

test('a running crew shows over a stale gate in next.json (no need is given while a lease is held)', () => {
  assert.equal(model({ run: run([agent()]), next: next({ action: 'approve', gate: true }) }).kind, 'crew')
})

test('a helper row: the mark in the amber working colour, the role in its colour, step, what it does, start time, elapsed and tokens', () => {
  const r = model({ run: run([agent()]) }).rows[0]
  assert.equal(r.glyph, P.STATE_MARKS.running)
  assert.equal(r.glyphColor, P.stateColor('running'), 'amber while working')
  assert.equal(r.roleColor, P.roleColor('architect'))
  assert.equal(r.role, 'architect')
  assert.equal(r.label, 'scope')
  assert.match(r.activity, /reading \.vbw\/spec\.md/)
  assert.equal(r.time, hm(NOW - 130 * S))
  assert.equal(r.elapsed, '2m10s')
  assert.equal(r.tokens, '41k')
  assert.ok(r.tail.includes(hm(NOW - 130 * S)) && r.tail.includes('2m10s') && r.tail.includes('41k'), r.tail)
  for (const role of ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs', 'agent', 'mystery']) assert.equal(model({ run: run([agent({ role })]) }).rows[0].roleColor, P.roleColor(role), role)
})

test('the start time survives a narrow row; elapsed and tokens go first', () => {
  const full = model({ run: run([agent()]), columns: 100 }).rows[0]
  assert.ok(full.tail.includes('41k'))
  const narrow = model({ run: run([agent()]), columns: 44, maxRows: 5 }).rows[0]
  assert.equal(narrow.tokens, '')
  assert.ok(narrow.tail === '' || narrow.tail.trim() === hm(NOW - 130 * S), JSON.stringify(narrow.tail))
  const mid = model({ run: run([agent()]), columns: 64, maxRows: 5 }).rows[0]
  assert.equal(mid.tail.trim(), hm(NOW - 130 * S))
})

test('streamed text is quoted; tokens read as k or M; none is blank', () => {
  const rows = model({ run: run([
    agent({ id: 'a', activity: { kind: 'text', text: 'Splitting R69 into two plans' }, tokens: 950 }),
    agent({ id: 'b', tokens: 1_250_000 }), agent({ id: 'c', tokens: null, activity: null }),
  ]) }).rows
  assert.equal(rows[0].activity, '"Splitting R69 into two plans"')
  assert.equal(rows[0].tokens, '950')
  assert.equal(rows[1].tokens, '1.3M')
  assert.equal(rows[2].tokens, '')
  assert.equal(rows[2].activity, 'working')
})

test('the spinner cycles with time unless motion is off', () => {
  const at = (now, motion) => stage.stageModel({ run: run([agent()]), now, maxRows: 5, columns: 100, motion }).rows[0].spin
  assert.ok(new Set([0, 1, 2, 3, 4, 5].map((i) => at(NOW + i * 250, 'full'))).size > 1, 'full motion moves')
  assert.equal(new Set([0, 1, 2, 3].map((i) => at(NOW + i * 1000, 'off'))).size, 1, 'motion off stands still')
})

test('quiet: no sign of life for 45 s is marked quiet in grey, told apart from slow', () => {
  const r = model({ run: run([agent({ lastSeenAt: NOW - 46 * S })]) }).rows[0]
  assert.match(r.activity, /^quiet/)
  assert.equal(r.activityColor, P.stateColor('quiet'))
  assert.equal(r.glyph, P.STATE_MARKS.quiet)
  assert.equal(r.glyphColor, P.stateColor('quiet'))
  assert.equal(r.spin, '')
  assert.match(model({ run: run([agent({ state: 'quiet' })]) }).rows[0].activity, /^quiet/)
  assert.doesNotMatch(model({ run: run([agent({ lastSeenAt: NOW - 44 * S })]) }).rows[0].activity, /quiet/)
})

test('done: a finished helper leaves at once, with no hold, and is counted in the top line', () => {
  const done = (id, ago) => agent({ id, role: 'scout', state: 'done', endedAt: NOW - ago * S, result: '4 findings' })
  const m = model({ run: run([agent(), done('d1', 0), done('d2', 90)]) })
  assert.deepEqual(m.rows.map((r) => r.id), ['a1'])
  assert.match(m.header.text, /\b2 done\b/)
  assert.equal(m.tally, undefined)
  const none = model({ run: run([done('d1', 0)]) })
  assert.equal(none.rows.length, 0, 'every helper done, the run still on: the top line alone')
  assert.match(none.header.text, /1 done/)
})

test('failed: a red ✗ with its reason and a details button stays until seen; only the first takes d', () => {
  const failed = (id) => agent({ id, role: 'dev', state: 'failed', endedAt: NOW - 3 * S, result: 'bats exited 1' })
  const m = model({ run: run([failed('f1'), failed('f2')]) })
  const [a, b] = m.rows
  assert.equal(a.glyph, '✗')
  assert.equal(a.glyphColor, P.stateColor('failed'))
  assert.equal(a.activity, 'bats exited 1')
  assert.deepEqual(a.button, { key: 'd', label: 'details', action: { open: 'mission', tab: 'now', agent: 'f1' } })
  assert.equal(b.button.key, undefined, 'one hotkey, one button')
  assert.equal(b.button.action.agent, 'f2')
  assert.equal(model({ run: run([agent({ state: 'failed', result: null })]) }).rows[0].activity, 'failed')
})

// 6.3: a refusal is one amber line with a time (docs/panel.md, Refusals).
const refusal = (over = {}) => ({ id: 'a1#0', by: 'dev P1.1', at: NOW - 30 * S, text: 'vbw: apply refused: plan P1.1 is started\nNext: put it back', ...over })

test('a refusal is one amber line "HH:MM ⊘ VBW refused · <by>: <first line>", under the needs-you line and above the crew', () => {
  const line = hm(NOW - 30 * S) + ' ⊘ VBW refused · dev P1.1: vbw: apply refused: plan P1.1 is started'
  const alone = model({ refusal: refusal() })
  assert.equal(alone.refusal.text, line)
  const tree = stage.renderStage(UI, alone)
  assert.deepEqual(collect(tree), [line], 'one line and nothing else')
  assert.equal(find(tree, (n) => n.type === 'Text' && /refused/.test(words(n))).props.color, P.NEED, 'in amber')
  const busy = model({ need: need(), refusal: refusal(), run: run([agent()]) })
  const lines = collect(stage.renderStage(UI, busy))
  assert.match(lines[0], /needs you/)
  assert.equal(lines[1], line)
  assert.match(lines[2], /^VBW ▸ planning/)
  assert.equal(model({ refusal: refusal(), columns: 30 }).refusal.text.length, 30, 'cut to the columns')
  assert.equal(model({ refusal: refusal({ at: null }) }).refusal.text, '⊘ VBW refused · dev P1.1: vbw: apply refused: plan P1.1 is started', 'no time, no stamp')
  for (const bad of [null, 'x', {}, { text: '  ' }]) assert.equal(model({ refusal: bad }), null)
  assert.equal(model({ need: need(), refusal: refusal(), maxRows: 1 }).refusal, undefined, 'one row: the needs-you line keeps it')
})

test('seen: a failed helper whose id is in `seen` leaves at the next redraw; the others stay', () => {
  const crew = [agent({ id: 'f1', state: 'failed', result: 'x' }), agent({ id: 'f2', state: 'failed', result: 'y' }), agent({ id: 'w' })]
  assert.deepEqual(model({ run: run(crew), seen: ['f1'] }).rows.map((r) => r.id), ['f2', 'w'])
  assert.deepEqual(model({ run: run(crew), seen: ['f1', 'f2', 7] }).rows.map((r) => r.id), ['w'])
  assert.deepEqual(model({ run: run(crew), seen: 'f1' }).rows.map((r) => r.id), ['f1', 'f2', 'w'], 'a bad list hides nothing')
})

test('the run ended: the crew leaves at once; only a failure not yet seen stays, alone, until opened', () => {
  const ended = (agents, seen) => model({ run: run(agents, { status: 'completed', endedAt: NOW - 1 * S }), seen })
  const crew = [agent({ id: 'd', state: 'done', endedAt: NOW - S }), agent({ id: 'w' }), agent({ id: 'f', state: 'failed', result: 'boom' })]
  assert.equal(ended([agent({ id: 'd', state: 'done' }), agent({ id: 'w' })]), null, 'nothing of the crew once the run ended')
  const m = ended(crew)
  assert.deepEqual(m.rows.map((r) => r.id), ['f'])
  assert.ok(!m.sprites)
  assert.equal(ended(crew, ['f']), null, 'seen, it is gone')
  assert.equal(model({ run: run(crew, { status: 'failed', endedAt: NOW - 3600 * S }) }).rows[0].id, 'f', 'however long ago')
})

test('a working run is never drawn as ended, and an ended one never shows a working row', () => {
  const m = model({ run: run([agent()]) })
  assert.doesNotMatch(m.header.text, /completed|ended|finished|stopped/i)
  const e = model({ run: run([agent({ id: 'f', state: 'failed', result: 'x' }), agent()], { status: 'completed', endedAt: NOW - S }) })
  assert.ok(e.rows.every((r) => r.glyph !== P.STATE_MARKS.running))
})

// --- shrinking and width -----------------------------------------------------

const crew = [agent({ id: 'a' }), agent({ id: 'b', role: 'lead', label: 'P53' }), agent({ id: 'c', role: 'dev', label: 'P53.2' })]

test('full rows at 8 rows of room, compact at 4, one summary line below that', () => {
  const full = model({ run: run(crew), maxRows: 8 })
  assert.equal(full.mode, 'full')
  assert.equal(full.rows.length, 3)
  assert.ok(full.rows.every((r) => r.elapsed && r.tokens))
  const compact = model({ run: run(crew), maxRows: 5 })
  assert.equal(compact.mode, 'compact')
  assert.equal(compact.rows.length, 3)
  assert.ok(compact.rows.every((r) => r.elapsed === '' && r.tokens === '' && r.time))
  const one = model({ run: run([...crew, agent({ id: 'z', state: 'done', endedAt: NOW - 120 * S })]), maxRows: 3 })
  assert.equal(one.mode, 'line')
  assert.equal(one.rows.length, 0)
  assert.equal(one.header.text, 'VBW ▸ planning · 3 working · 1 done · 10m04s')
})

test('more helpers than rows: the overflow is counted, never drawn past the room', () => {
  for (const maxRows of [4, 5, 6, 8, 12]) {
    const m = model({ run: run(many(12)), maxRows, motion: 'calm' })
    assert.equal(1 + m.rows.length + (m.more ? 1 : 0), maxRows, String(maxRows))
    assert.equal(m.more, 12 - m.rows.length)
  }
  assert.equal(model({ run: run(many(2)), maxRows: 4 }).more, 0, 'a fit is no fold')
})

test('every line fits the columns', () => {
  const long = agent({ activity: { kind: 'text', text: 'x'.repeat(300) }, label: 'a-very-long-label-indeed' })
  for (const columns of [30, 50, 80, 140]) {
    for (const maxRows of [3, 5, 10]) {
      const tree = stage.renderStage(UI, model({ run: run([long, ...crew, agent({ id: 'f', state: 'failed', result: 'y'.repeat(300) })]), need: need(), cost: 12.5, columns, maxRows }))
      walk(tree, (n) => {
        if (n.type === 'Box' && n.props.flexDirection === 'row' && n.props.key !== 'buttons') {
          const t = collect(n).join('')
          assert.ok(len(t) <= columns, columns + 'x' + maxRows + ': ' + len(t) + ' ' + t)
        }
      })
    }
  }
})

// --- rendering ---------------------------------------------------------------

test('render: nothing for nothing, and never throws on a bad model', () => {
  assert.equal(stage.renderStage(UI, null), null)
  assert.equal(stage.renderStage(UI, { kind: 'crew' }), null)
  assert.equal(stage.renderStage(UI, { kind: 'gate', title: 'x', buttons: [] }), null, 'the gate card is gone')
  assert.equal(stage.renderStage(null, model({ need: need() })), null)
})

test('render the crew: the header with its button, then one row per helper, colours on Text', () => {
  const pressed = []
  const m = model({ run: run([agent(), agent({ id: 'f', role: 'dev', state: 'failed', result: 'boom', endedAt: NOW })]), cost: 1 })
  const tree = stage.renderStage(UI, m, (a) => pressed.push(a))
  const header = find(tree, (n) => n.type === 'Box' && n.props.key === 'header')
  assert.match(collect(header)[0], /^VBW ▸ planning/)
  const mc = find(header, (n) => n.type === 'Button')
  assert.equal(mc.props.hotkey, 'p')
  mc.props.onPress()
  assert.deepEqual(pressed, [{ open: 'mission' }])
  const dot = find(tree, (n) => n.type === 'Text' && collect(n)[0] === '●')
  assert.equal(dot.props.color, P.stateColor('running'))
  const cross = find(tree, (n) => n.type === 'Text' && collect(n)[0] === '✗')
  assert.equal(cross.props.color, P.stateColor('failed'))
  const role = find(tree, (n) => n.type === 'Text' && collect(n)[0].trim() === 'architect')
  assert.equal(role.props.color, P.roleColor('architect'), 'the role is a word in its own colour')
  const details = find(tree, (n) => n.type === 'Button' && n.props.label === 'details')
  assert.equal(details.props.hotkey, 'd')
  walk(tree, (n) => {
    if (n.type === 'Text') for (const c of n.children) assert.equal(typeof c, 'string')
  })
})

test('the row is: mark, role, step, what it does, start time', () => {
  const tree = stage.renderStage(UI, model({ run: run([agent({ id: 'w', role: 'dev', label: 'P142.1', activity: { kind: 'tool', text: 'editing a.js' } })]), columns: 100 }))
  const row = find(tree, (n) => n.type === 'Box' && n.props.key === 'agent-w')
  assert.match(collect(row).join('').replace(/\s+/g, ' '), new RegExp('^● dev P142\\.1 (\\S+ )?editing a\\.js ' + hm(NOW - 130 * S)))
})

// --- the figures (full motion) -------------------------------------------------

test('at full motion at most 3 working helpers are figures, posed by what they do; the rest are text rows', () => {
  const m = model({ run: run([agent(), agent({ id: 'b', role: 'lead', activity: { kind: 'text', text: 'Splitting' } }), agent({ id: 'c', role: 'dev', activity: { kind: 'tool', text: 'editing panel.js' } }),
    agent({ id: 'd' }), agent({ id: 'e' })]), maxRows: 30 })
  assert.equal(m.sprites, true)
  const posed = m.rows.filter((r) => r.pose)
  assert.deepEqual(posed.map((r) => [r.id, r.pose]), [['a1', 'reading'], ['b', 'streaming'], ['c', 'editing']])
  assert.ok(posed.every((r) => r.spin === ''), 'the figure is the motion')
  assert.ok(m.rows.filter((r) => !r.pose).every((r) => r.spin !== ''), 'the others are text rows with a spinner')
  const tree = stage.renderStage(RUI, m)
  const rasters = []
  walk(tree, (n) => n.type === 'Raster' && rasters.push(n))
  assert.equal(rasters.length, 3)
  assert.deepEqual(rasters.map((r) => r.props.key), ['vbw-sprite-a1', 'vbw-sprite-b', 'vbw-sprite-c'])
  assert.deepEqual([rasters[0].props.columns, rasters[0].props.rows], [5, 3])
  assert.equal(rasters[0].props.cells, candy.encodeCells(candy.spriteFrame({ role: 'architect', pose: 'reading', frame: 0 })))
  assert.ok(collect(tree).filter((t) => t === '●').length === 2, 'the two text rows keep their dots')
})

test('fewer than 3 working helpers: a figure each; none for quiet or failed ones', () => {
  const m = model({ run: run([agent(), agent({ id: 'q', lastSeenAt: NOW - 90 * S }), agent({ id: 'f', state: 'failed', result: 'x' })]), maxRows: 16 })
  assert.deepEqual(m.rows.filter((r) => r.pose).map((r) => r.id), ['a1'])
})

test('no figures when calm or off, after the run ended, or without room for them', () => {
  const crew4 = [agent(), agent({ id: 'b' }), agent({ id: 'c' })]
  for (const motion of ['calm', 'off', undefined]) assert.ok(!model({ run: run(crew4), maxRows: 16, motion }).sprites, String(motion))
  assert.ok(!model({ run: run([agent({ state: 'failed', result: 'x' })], { status: 'completed', endedAt: NOW - 5 * S }), maxRows: 16 }).sprites, 'a finished run')
  const tight = model({ run: run(crew4), maxRows: 8 })
  assert.equal(tight.rows.filter((r) => r.pose).length, 2, '1 + 3 rows + 2 x 2 more rows for two figures fit in 8; three do not')
  const none = model({ run: run(many(10)), maxRows: 8 })
  assert.ok(!none.sprites && none.more > 0, 'ten helpers in 8 rows: text rows and the fold')
})

test('a table without Raster draws dots; a figure row stays within the columns', () => {
  const m = model({ run: run(crew), maxRows: 16, columns: 60 })
  assert.equal(m.sprites, true)
  const plain = stage.renderStage(UI, m)
  assert.ok(collect(plain).includes('●'))
  assert.equal(find(plain, (n) => n.type === 'Raster'), undefined)
  const long = [agent({ activity: { kind: 'tool', text: 'x'.repeat(200) } })]
  for (const columns of [40, 60, 100]) {
    walk(stage.renderStage(RUI, model({ run: run(long), maxRows: 16, columns })), (n) => {
      if (n.type === 'Box' && /^agent-/.test(n.props.key || '')) assert.ok(len(collect(n).join('')) + 5 <= columns, columns + ': ' + collect(n).join(''))
    })
  }
})

test("rows beyond the room fold into one '+N more · [m] Mission Control' line", () => {
  const pressed = []
  const tree = stage.renderStage(UI, model({ run: run(many(10)), maxRows: 6, motion: 'calm' }), (a) => pressed.push(a))
  const fold = find(tree, (n) => n.type === 'Box' && n.props.key === 'more')
  assert.equal(collect(fold).join(''), '+6 more ·Mission Control', 'the text and the [m] button side by side')
  const b = find(fold, (n) => n.type === 'Button')
  assert.equal(b.props.hotkey, 'm')
  assert.equal(b.props.label, 'Mission Control')
  b.props.onPress()
  assert.deepEqual(pressed, [{ open: 'mission' }])
  assert.equal(find(stage.renderStage(UI, model({ run: run(many(2)), maxRows: 6 })), (n) => n.props && n.props.key === 'more'), undefined)
})

test('colour off: Comms reads state from the palette marks, working, failed and quiet apart', () => {
  const m = model({ run: run([agent({ id: 'w' }), agent({ id: 'q', lastSeenAt: NOW - 90 * S }), agent({ id: 'f', state: 'failed', endedAt: NOW - 5 * S, result: 'boom' })]), maxRows: 16, columns: 80, motion: 'calm' })
  const glyph = (id) => m.rows.find((r) => r.id === id).glyph
  assert.deepEqual([glyph('w'), glyph('q'), glyph('f')], [P.STATE_MARKS.running, P.STATE_MARKS.quiet, P.STATE_MARKS.failed])
})

test('a needs-you line not yet seen carries a mark after its text, within the columns; a seen one carries none', () => {
  for (const motion of ['full', 'calm', 'off']) {
    const fresh = model({ need: need(), fresh: true, motion, columns: 60 })
    const tree = stage.renderStage(UI, fresh)
    const mark = find(tree, (n) => n.type === 'Text' && words(n).trim() === 'new')
    assert.ok(mark, motion + ': no mark')
    assert.ok(len(words(tree)) <= 60, motion + ': the marked line overflows')
    assert.ok(!find(stage.renderStage(UI, model({ need: need(), fresh: false, motion })), (n) => n.type === 'Text' && words(n).trim() === 'new'), motion + ': a seen line is marked')
  }
})
