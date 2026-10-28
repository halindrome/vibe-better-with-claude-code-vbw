// Mission Control's live tabs (mods_4_vbw.md §3.3): Now and Timeline (its lanes, and its runs with their cost).
// Pure models tested by value, renders by tree shape (evidence level L1).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { collect, find, walk, deepFreeze } from './helpers/fake-mod.mjs'
import { ROLE_COLORS as R } from '../../plugin/hooks/panel-palette.js'
import { nowModel, timelineModel, renderNow, renderTimeline } from '../../plugin/hooks/panel-mission-live.js'
import { runsModel, renderRuns } from '../../plugin/hooks/panel-runs.js'

const S = 1_800_000_000_000
const MIN = 60_000
const UI = { Box: Object.freeze({ element: 'Box' }), Text: Object.freeze({ element: 'Text' }), Button: Object.freeze({ element: 'Button' }) }

const agent = (over) => ({ id: 'a1', role: 'dev', label: 'P55.1', model: 'sonnet', state: 'working', activity: null, startedAt: S, endedAt: null, lastSeenAt: S, tokens: null, result: null, ...over })
const run = (agents, over = {}) => ({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: S, endedAt: null, status: 'running', agents, ...over })
const step = (kind, seconds) => ({ kind, run: kind + '-x', started_at: '2026-10-01T00:00:00Z', ended_at: '2026-10-01T00:10:00Z', seconds })

test('nowModel: no run, or a damaged one, gives no model and never throws', () => {
  for (const r of [null, undefined, 42, 'x', {}, { agents: 'no' }]) assert.equal(nowModel({ run: r, now: S }), null)
  assert.equal(nowModel(null), null)
  assert.equal(nowModel(undefined), null)
})

test('nowModel: the crew is one row per helper still at work, the longest-running first; finished ones are gone', () => {
  const r = deepFreeze(run([
    agent({ id: 'q', role: 'qa', label: 'P55', startedAt: S + 3 * MIN }),
    agent({ id: 'l', role: 'lead', label: 'P55', state: 'done', startedAt: S, endedAt: S + MIN }),
    agent({ id: 'd1', role: 'dev', label: 'P55.1', startedAt: S + MIN }),
    agent({ id: 'd2', role: 'dev', label: 'P55.2', state: 'quiet', startedAt: S + 30_000 }),
  ]))
  const m = nowModel({ run: r, now: S + 4 * MIN })
  assert.deepEqual(m.rows.map((x) => x.id), ['d2', 'd1', 'q'], 'the done lead left; the oldest first')
  assert.deepEqual(m.header, { kind: 'building', status: 'running', elapsed: '4 min', done: 1 })
})

test('nowModel: a row is "role label  ● doing · 2 min 10 s": the role colour, the state mark and word in the state colour', () => {
  const m = nowModel({ run: run([agent({ id: 'a9', role: 'qa', label: 'P55', startedAt: S, activity: { kind: 'tool', text: 'reading spec.md' } })]), now: S + 130_000 })
  assert.deepEqual(m.rows[0], {
    id: 'a9', title: 'qa P55', role: 'qa', roleColor: R.qa, state: 'working', mark: '●', word: 'running', stateColor: '#ffaf00',
    doing: 'reading spec.md', tool: true, elapsed: '2 min 10 s', selected: false, action: { select: 'a9' }, fresh: false, motion: undefined,
  })
  const quiet = nowModel({ run: run([agent({ state: 'quiet' })]), now: S }).rows[0]
  assert.deepEqual([quiet.mark, quiet.word, quiet.doing, quiet.stateColor], ['…', 'quiet', 'quiet', 'gray'])
  const idle = nowModel({ run: run([agent()]), now: S }).rows[0]
  assert.equal(idle.doing, 'running', 'no activity yet: the state word says it')
})

test('nowModel: a failed helper stays as a red row with its reason, first, until it is seen; then it leaves', () => {
  const r = run([agent({ id: 'w', startedAt: S }), agent({ id: 'f', state: 'failed', startedAt: S + MIN, endedAt: S + 3 * MIN, result: 'tests failed' })])
  const m = nowModel({ run: r, now: S + 5 * MIN })
  assert.deepEqual(m.rows.map((x) => [x.id, x.mark + ' ' + x.word, x.stateColor, x.doing, x.elapsed, x.fresh]),
    [['f', '✗ failed', 'red', 'tests failed', '2 min', true], ['w', '● running', '#ffaf00', 'running', '5 min', false]])
  assert.deepEqual(nowModel({ run: r, now: S + 5 * MIN, seen: ['f'] }).rows.map((x) => x.id), ['w'])
})

test('nowModel: a run that has ended keeps no row but the failures not yet seen; the header says how it ended', () => {
  const agents = [agent({ id: 'w', state: 'working' }), agent({ id: 'q', state: 'quiet' }), agent({ id: 'd', state: 'done' }), agent({ id: 'f', state: 'failed' })]
  for (const status of ['completed', 'failed', 'stopped']) {
    const m = nowModel({ run: run(agents, { status, endedAt: S + MIN }), now: S + 2 * MIN })
    assert.deepEqual(m.rows.map((x) => x.id), ['f'], status)
    assert.equal(m.header.status, status)
    assert.equal(m.header.elapsed, '1 min', 'timed to its end')
  }
})

test('nowModel: no run, or a damaged one, gives no model; the selected helper opens its detail', () => {
  for (const r of [null, undefined, 42, 'x', {}, { agents: 'no' }]) assert.equal(nowModel({ run: r, now: S }), null)
  assert.equal(nowModel(null), null)
  const r = run([agent({ id: 'd', state: 'done', startedAt: S + MIN, endedAt: S + 4 * MIN + 12_000, result: 'built P55.1' }), agent({ id: 'w', role: 'scout', label: 'docs', model: null })])
  const m = nowModel({ run: r, now: S + 10 * MIN, selected: 'd' })
  assert.deepEqual(m.detail, { id: 'd', label: 'dev P55.1', role: 'dev', model: 'sonnet', activity: null, result: 'built P55.1', elapsed: '3 min 12 s' })
  const w = nowModel({ run: r, now: S + 45_000, selected: 'w' })
  assert.deepEqual([w.detail.model, w.detail.elapsed, w.rows[0].selected], [null, '45 s', true])
  assert.equal(nowModel({ run: r, now: S, selected: 'nope' }).detail, null)
})

test('timelineModel: one lane per agent, start and end as column spans on the run clock', () => {
  const r = run([
    agent({ id: 'a', startedAt: S, endedAt: S + 5 * MIN, state: 'done' }),
    agent({ id: 'b', startedAt: S + 5 * MIN, endedAt: null }),
  ])
  // A 36-column row: 'dev P55.1' and a space, the bar, then ' 5 min'.
  const m = timelineModel({ run: r, now: S + 10 * MIN, steps: [], width: 36 })
  assert.deepEqual(m.lanes.map((l) => [l.id, l.from, l.to, l.seconds, l.slow]), [['a', 0, 10, 300, false], ['b', 10, 20, 300, false]])
  assert.deepEqual([m.width, m.nameW], [20, 9])
  const tiny = timelineModel({ run: run([agent({ startedAt: S, endedAt: S + 1000 })], { endedAt: S + 10 * MIN, status: 'completed' }), now: S + 99 * MIN, steps: [], width: 20 })
  assert.deepEqual([tiny.lanes[0].from, tiny.lanes[0].to], [0, 1])
  assert.equal(timelineModel({ run: null, now: S }), null)
})

test('renderTimeline: a lane is one line; the bar leaves room for the name and the longest time (#696)', () => {
  const scouts = [132, 130, 42, 26].map((s, i) => agent({ id: 's' + i, role: 'scout', label: 'architecture-' + i, startedAt: S, endedAt: S + s * 1000, state: 'done' }))
  for (const width of [30, 40, 60, 100]) {
    const m = timelineModel({ run: run(scouts, { endedAt: S + 132_000, status: 'completed' }), now: S + 132_000, steps: [], width })
    const rows = []
    walk(renderTimeline(UI, m), (n) => { if (n.type === 'Box' && n.props.flexDirection === 'row') rows.push(collect(n).join('')) })
    assert.equal(rows.length, 4)
    for (const line of rows) assert.ok([...line].length <= width, width + ': ' + line.length + ' ' + JSON.stringify(line))
    assert.ok(rows[0].endsWith('█ 2 min 12 s'), 'the longest lane still fills its bar: ' + rows[0])
  }
})

test('timelineModel: the three slowest agents are highlighted when there are more than three', () => {
  const secs = [60, 600, 120, 900, 300]
  const r = run(secs.map((s, i) => agent({ id: 'a' + i, startedAt: S, endedAt: S + s * 1000, state: 'done' })), { endedAt: S + 900_000, status: 'completed' })
  const m = timelineModel({ run: r, now: S + 900_000, steps: [], width: 30 })
  assert.deepEqual(m.lanes.filter((l) => l.slow).map((l) => l.id), ['a1', 'a3', 'a4'])
  const few = timelineModel({ run: { ...r, agents: r.agents.slice(0, 3) }, now: S + 900_000, steps: [], width: 30 })
  assert.equal(few.lanes.some((l) => l.slow), false)
})

test('timelineModel: a sparkline of past steps of this kind, the median marked, and the time left', () => {
  const steps = [step('build', 600), step('qa', 9999), step('build', 1200), step('build', 300), step('build', 900)]
  const m = timelineModel({ run: run([agent({})]), now: S + 5 * MIN, steps, width: 20 })
  assert.deepEqual(m.spark, { bars: '▃█▁▆', median: 750, mark: 0, kind: 'build' })
  assert.equal(m.left, null, 'the Timeline works no time out from the history')
  const note = (end, over = {}) => ({ kind: 'build', run: 'build-1', parts: { done: 1, total: 2 }, end: new Date(end).toISOString(), late: false, ...over })
  const told = timelineModel({ run: run([agent({})]), now: S + 5 * MIN, steps, width: 20, step: note(S + 17 * MIN) })
  assert.match(told.left, /^about 12 min, until around \d\d:\d\d$/)
  const late = timelineModel({ run: run([agent({})]), now: S + 30 * MIN, steps, width: 20, step: note(S + 17 * MIN, { late: true }) })
  assert.match(late.left, /^until around \d\d:\d\d, later than usual$/)
  const noEnd = timelineModel({ run: run([agent({})]), now: S, steps, width: 20, step: note(S, { end: null }) })
  assert.match(noEnd.left, /^No end time yet/)
  const thin = timelineModel({ run: run([agent({})]), now: S, steps: steps.slice(0, 2), width: 20 })
  assert.deepEqual([thin.spark.bars, thin.spark.median, thin.spark.mark, thin.left], ['▄', null, null, null])
  const none = timelineModel({ run: run([agent({})], { kind: 'researching' }), now: S, steps, width: 20 })
  assert.deepEqual([none.spark, none.left], [null, null])
  const done = timelineModel({ run: run([agent({})], { endedAt: S + MIN, status: 'completed' }), now: S + MIN, steps, width: 20, step: note(S + 17 * MIN) })
  assert.equal(done.left, null)
  const qa = timelineModel({ run: run([agent({})], { kind: 'verifying' }), now: S, steps: [step('qa', 60), step('qa', 60), step('qa', 60)], width: 20 })
  assert.deepEqual([qa.spark.bars, qa.spark.median, qa.spark.kind], ['▄▄▄', 60, 'qa'])
})

test('runsModel (Timeline, Runs this session): cost per run as "about", its time from its steps or the clock, totals per kind, the session total, both bars to one scale', () => {
  const runs = deepFreeze([
    { key: 'build-1@a', kind: 'building', startedAt: S, costStart: 0.1, costEnd: 1.1 },
    { key: 'qa-1@b', kind: 'verifying', startedAt: S + MIN, costStart: 1.1, costEnd: 1.35 },
    { key: 'build-2@c', kind: 'building', startedAt: S + 2 * MIN, costStart: 1.35, costEnd: 1.85 },
    { kind: 'broken', costStart: 'x' }, null,
    { key: 'fix-1@d', kind: 'fixing', startedAt: S + 3 * MIN, costStart: 1.85 },
  ])
  const steps = [{ run: 'build-1', seconds: 600 }, { run: 'build-1', seconds: 300 }, { run: 'qa-1', seconds: 90 }]
  const m = runsModel({ runs, steps, sessionCost: 2.0, now: S + 5 * MIN, width: 80 })
  assert.deepEqual(m.rows.map((r) => [r.name, r.time, r.money, r.open]), [
    ['building 1', '15 min', 'about $1.00', false], ['verifying 1', '1 min 30 s', 'about $0.25', false],
    ['building 2', 'time unknown', 'about $0.50', false], ['broken 1', 'time unknown', 'cost unknown', false], ['fixing 1', '2 min', 'about $0.15', true],
  ])
  assert.equal(m.rows[0].timeBar, m.bar, 'the longest run fills its bar')
  assert.equal(m.rows[0].costBar, m.bar, 'the dearest run fills its bar')
  assert.deepEqual(m.kinds.map((k) => [k.kind, k.runs, k.cost]), [['building', 2, 1.5], ['verifying', 1, 0.25], ['fixing', 1, 0.15]])
  assert.equal(m.session, 'This session: $2.00')
  const empty = runsModel({ runs: [], sessionCost: null })
  assert.deepEqual([empty.rows, empty.kinds, empty.session], [[], [], 'The session cost is not available.'])
  assert.deepEqual(runsModel(null).rows, [])
})

test('renderNow: the header, then one row per helper; pressing a row asks to select it', () => {
  const m = nowModel({ run: run([agent({ id: 'a1', state: 'working', activity: { kind: 'tool', text: 'editing x.js' } }), agent({ id: 'a2', state: 'done' })]), now: S + MIN, selected: 'a1' })
  const acts = []
  const tree = renderNow(UI, m, (a) => acts.push(a))
  const row = find(tree, (n) => n.type === 'Box' && n.props.key === 'crew:a1')
  assert.ok(row, 'a row for the working helper')
  assert.equal(find(tree, (n) => n.type === 'Box' && n.props.key === 'crew:a2'), undefined, 'none for the done one')
  const btn = find(row, (n) => n.type === 'Button')
  btn.props.onPress({ surface: 'terminal' })
  assert.deepEqual(acts, [{ select: 'a1' }])
  const texts = collect(tree)
  for (const t of ['building · running · 1 min · 1 done', 'dev P55.1', '● ', 'editing', ' x.js', ' · 1 min', 'Model: sonnet']) assert.ok(texts.some((x) => x.includes(t)), t + ' in ' + JSON.stringify(texts))
  assert.ok(collect(renderNow(UI, null)).join(' ').includes('No VBW workflow'))
  assert.ok(collect(renderNow(UI, nowModel({ run: run([]), now: S }))).join(' ').includes('No helper has started yet'))
  assert.ok(collect(renderNow(UI, nowModel({ run: run([agent({ state: 'done' })]), now: S }))).join(' ').includes('No helper is at work right now'))
})

test('renderNow: the row degrades to the width: the doing text is cut, the name, mark and time stay', () => {
  const long = 'editing ' + 'a-long-file-name-'.repeat(8) + '.js'
  for (const width of [40, 80, 100, 140]) {
    const m = nowModel({ run: run([agent({ activity: { kind: 'tool', text: long } })]), now: S + 130_000, width })
    const row = find(renderNow(UI, m), (n) => n.type === 'Box' && n.props.key === 'crew:a1')
    const line = collect(row).join('')
    assert.ok([...line].length <= width, width + ': ' + line.length)
    assert.ok(line.startsWith('dev P55.1') && line.includes('● ') && line.endsWith(' · 2 min 10 s'), line)
  }
})

test('renderTimeline and renderRuns draw lanes, sparkline and bars', () => {
  const r = run([agent({ id: 'a', startedAt: S, endedAt: S + 5 * MIN, state: 'done' }), agent({ id: 'b', role: 'qa', label: 'P55', startedAt: S + 5 * MIN })])
  const tl = renderTimeline(UI, timelineModel({ run: r, now: S + 10 * MIN, steps: [step('build', 600), step('build', 1200), step('build', 300)], width: 26, step: { kind: 'build', run: 'build-1', parts: { done: 1, total: 2 }, end: new Date(S + 7 * MIN).toISOString(), late: true } }))
  const texts = collect(tl)
  assert.ok(texts.includes('█'.repeat(5)) && texts.includes('     ' + '█'.repeat(5)), JSON.stringify(texts))
  assert.ok(texts.some((t) => t.includes('▃█▁')) && texts.some((t) => t.includes('median 10 min')) && texts.some((t) => t.includes('later than usual')))
  let rows = 0
  walk(tl, (n) => { if (n.type === 'Box' && n.props.flexDirection === 'row') rows++ })
  assert.equal(rows, 2)
  const cs = collect(renderRuns(UI, runsModel({ runs: [{ key: 'b@1', kind: 'building', startedAt: S, costStart: 0, costEnd: 0.5 }], steps: [{ run: 'b', seconds: 60 }], sessionCost: 0.7, now: S, width: 40 })))
  for (const t of ['building 1', 'about $0.50', '1 min', '█', 'This session: $0.70']) assert.ok(cs.some((x) => x.includes(t)), t)
  assert.ok(collect(renderTimeline(UI, null)).length > 0)
  assert.ok(collect(renderRuns(UI, null)).length > 0)
})

test('timelineModel: with no run, a live proof says it is running, checks done of total, and points to the Proof tab; anything else stays the empty line', () => {
  const proving = { kind: 'prove', doing: 'proving 12 of 40 checks', proof: { done: 12, total: 40 } }
  const m = timelineModel({ run: null, now: S, steps: [], step: proving, width: 40 })
  assert.deepEqual(m, { idle: 'A proof is running: 12 of 40 checks done. The Proof tab shows each check.' })
  assert.deepEqual(collect(renderTimeline(UI, m)), ['A proof is running: 12 of 40 checks done. The Proof tab shows each check.'])
  const starting = timelineModel({ run: null, now: S, steps: [], step: { kind: 'prove', proof: null }, width: 40 })
  assert.deepEqual(starting, { idle: 'A proof is running. The Proof tab shows each check.' })
  for (const step of [null, { kind: 'build', parts: { done: 1, total: 2 } }, { kind: 'prove', proof: { done: 'x', total: 40 } }]) {
    const none = timelineModel({ run: null, now: S, steps: [], step, width: 40 })
    if (step && step.kind === 'prove') assert.deepEqual(none, { idle: 'A proof is running. The Proof tab shows each check.' })
    else assert.equal(none, null)
  }
  assert.deepEqual(collect(renderTimeline(UI, null)), ['No VBW workflow runs in this session right now.'])
})

test('docs/panel.md says what the Timeline shows while a proof runs', async () => {
  const { readFile } = await import('node:fs/promises')
  const doc = await readFile(new URL('../../docs/panel.md', import.meta.url), 'utf8')
  assert.match(doc.replace(/\s+/g, ' '), /A proof is running: 12 of 40 checks done\. The Proof tab shows each check\./)
})
