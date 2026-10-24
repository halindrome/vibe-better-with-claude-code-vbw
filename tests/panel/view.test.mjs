// R51: what the panel says. plugin/hooks/panel-view.js turns the project's record
// and its last `vbw next` into plain sentences, each with its technical term
// beside it (D107). Pure data in, rows out: no Claude Code needed (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, lease, deepFreeze } from './helpers/fake-mod.mjs'

const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const NOW = Date.parse('2026-10-05T15:00:00Z')
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const row = (v, id) => v.rows.find((r) => r.id === id)
const show = (input) => view.panelView({ now: NOW, ...input })

// Requirements of the current milestone and their states, as the kernel stores them.
const reqs = (...xs) => xs.map(([id, milestone, status]) => ({ id, text: id + ' holds', proof: 'auto', status, milestone }))

test('the milestone and its progress are plain sentences: requirements done of total', () => {
  const r = record({ requirements: reqs(['R1', 'M1', 'proven'], ['R2', 'M9', 'proven'], ['R3', 'M9', 'accepted'],
    ['R4', 'M9', 'failing'], ['R5', 'M9', 'open'], ['R6', 'M9', 'rejected']) })
  const v = show({ record: r, next: next() })
  assert.match(row(v, 'milestone').text, /M9/)
  assert.match(row(v, 'milestone').text, /Live VBW panel/)
  // R2 is proven and R3 accepted; R4, R5 and R6 are not done; R1 belongs to another milestone.
  assert.equal(row(v, 'progress').text, '2 of 5 requirements done.')
  assert.equal(row(v, 'progress').term, 'requirements')
})

test('M11 defect: progress counts requirements as the status line does, not phases ("1 of 1 phase" beside "1/15")', () => {
  const list = reqs(['R1', 'M9', 'proven'], ...Array.from({ length: 14 }, (_, i) => ['R' + (i + 2), 'M9', 'open']))
  const r = record({ phases: [{ id: 'P1', title: 'A', milestone: 'M9', qa: { result: 'pass' } }], requirements: list })
  assert.equal(row(show({ record: r, next: next() }), 'progress').text, '1 of 15 requirements done.')
})

test('progress counts a single requirement in the singular and says when none is set', () => {
  const one = record({ requirements: reqs(['R1', 'M9', 'accepted']) })
  assert.equal(row(show({ record: one, next: next() }), 'progress').text, '1 of 1 requirement done.')
  for (const requirements of [[], undefined, 'x', [null, 5]]) {
    assert.match(row(show({ record: record({ requirements }), next: next() }), 'progress').text, /no requirements/i)
  }
})

test('what VBW is doing: idle, planning, building (naming the parts), checking, fixing, mapping', () => {
  const doing = (l) => row(show({ record: record({ lease: l }), next: next() }), 'doing').text
  assert.match(doing(null), /idle|nothing is running/i)
  assert.match(doing(lease('plan', NOW - 5000)), /planning/i)
  assert.match(doing(lease('qa', NOW - 5000)), /checking/i)
  assert.match(doing(lease('fix', NOW - 5000)), /fixing/i)
  assert.match(doing(lease('map', NOW - 5000)), /mapping|reading the project/i)
  const building = record({
    lease: lease('build', NOW - 5000),
    plans: [
      { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' },
      { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'building' },
      { id: 'P44.3', phase: 'P44', title: 'Write the docs', status: 'planned' },
    ],
  })
  const text = row(show({ record: building, next: next() }), 'doing').text
  assert.match(text, /building/i)
  assert.match(text, /Show the cost/)
  assert.match(text, /Show the estimate/)
  assert.doesNotMatch(text, /Write the docs/)
})

test('how long the current run has gone on is told in whole minutes', () => {
  const t = (ms) => row(show({ record: record({ lease: lease('build', NOW - ms) }), next: next() }), 'doing').text
  assert.match(t(4 * 60000 + 20000), /4 min/)
  assert.match(t(5000), /just started|less than a minute/i)
})

test('when nothing needs the user it says so, and the need is empty', () => {
  const v = show({ record: record(), next: next() })
  assert.equal(v.need, null)
  assert.match(row(v, 'need').text, /nothing is needed/i)
})

test('when VBW needs the user it says what for', () => {
  const need = (n, over) => show({ record: record(over), next: next(n) })
  assert.match(need({ action: 'approve', gate: true }).need.text, /approve/i)
  assert.match(need({ action: 'approve', gate: true }).need.text, /plan/i)
  const accept = need({ action: 'accept', gate: true, detail: { requirements: ['R54'] } })
  assert.match(accept.need.text, /check/i)
  assert.match(accept.need.text, /R54/)
  assert.match(need({ action: 'ship', gate: true }).need.text, /ship/i)
  assert.match(need({ action: 'spec', gate: true }).need.text, /requirements|what to build/i)
  assert.match(need({ action: 'escalate', gate: true, detail: { fixes: ['F3'] } }, { fixes: [{ id: 'F3', status: 'escalated' }] }).need.text, /decision|decide/i)
  const v = need({ action: 'approve', gate: true })
  assert.equal(row(v, 'need').text, v.need.text)
})

test('a gate is dated by the kernel\'s since, the time VBW reached it, not by when the panel first saw it', () => {
  const since = iso(NOW - 3 * 86400e3)
  const v = show({ record: record(), next: next({ action: 'approve', gate: true, since }) })
  assert.equal(v.need.at, Date.parse(since))
  // Rewriting next.json (a restart's vbw next) does not move it; without a since, the time next.json was written dates it.
  assert.equal(show({ record: record(), next: next({ action: 'approve', gate: true, since }), nextAt: NOW - 60e3 }).need.at, Date.parse(since))
  assert.equal(show({ record: record(), next: next({ action: 'approve', gate: true }), nextAt: NOW - 60e3 }).need.at, NOW - 60e3)
})

test('a plan changed after its approval is offered as changed, never as a new plan', () => {
  const v = show({ record: record(), next: next({ action: 'approve', gate: true, detail: { changed: true } }) })
  assert.match(v.need.what, /changed since you approved it/)
  assert.doesNotMatch(v.need.what, /plan is ready/)
  assert.match(v.need.text, /changed/)
  assert.notEqual(v.need.key, show({ record: record(), next: next({ action: 'approve', gate: true }) }).need.key)
})

test('every human gate is a need, so the panel never says nothing is needed while VBW waits', () => {
  const STANDING = {
    unblock: { plans: [{ id: 'P44.1', status: 'blocked' }, { id: 'P44.2', status: 'blocked' }] },
    scope: { evidence: { scope: [{ file: 'src/x.js' }] } },
    milestone: { milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' } },
  }
  const need = (n) => show({ record: record(STANDING[n.action]), next: next(n) }).need
  const blocked = need({ action: 'unblock', gate: true, detail: { plans: ['P44.1'], blocked: [{ id: 'P44.1', note: 'no API key' }] } })
  assert.match(blocked.text, /blocked/i)
  assert.match(blocked.text, /P44\.1/)
  assert.notEqual(blocked.key, need({ action: 'unblock', gate: true, detail: { plans: ['P44.2'] } }).key)
  assert.match(need({ action: 'scope', gate: true }).text, /outside/i)
  assert.match(need({ action: 'milestone', gate: true }).text, /shipped/i)
  assert.match(need({ action: 'convert', gate: true }).text, /VBW 1/)
  assert.match(need({ action: 'something-new', gate: true }).text, /waiting for you/i)
  for (const a of ['unblock', 'scope', 'milestone', 'convert', 'something-new']) {
    const t = need({ action: a, gate: true }).text
    assert.doesNotMatch(t, /\b(QA|lease|gate|contract|workflow)\b/i, a)
  }
  assert.equal(need({ action: 'build', gate: false }), null)
})

test('a question the user has to answer is a need', () => {
  const v = show({ record: record(), next: next(), question: { id: 'q1' } })
  assert.match(v.need.text, /question/i)
  assert.match(v.need.key, /^question/)
})

test('a need has a stable key: the same need keeps it, another need changes it', () => {
  const key = (n) => show({ record: record(), next: next(n) }).need.key
  const a = key({ action: 'accept', gate: true, detail: { requirements: ['R54'] } })
  assert.equal(a, key({ action: 'accept', gate: true, detail: { requirements: ['R54'] } }))
  assert.notEqual(a, key({ action: 'accept', gate: true, detail: { requirements: ['R55'] } }))
  assert.notEqual(a, key({ action: 'approve', gate: true }))
})

test('while a run is open VBW is busy, not waiting for the user', () => {
  const v = show({ record: record({ lease: lease('build', NOW - 60000) }), next: next({ action: 'approve', gate: true }) })
  assert.equal(v.need, null)
})

test('D107: every row is a plain sentence with its technical term beside it', () => {
  const rec = record({ lease: lease('qa', NOW - 90000) })
  const inputs = [
    { record: record(), next: next() },
    { record: rec, next: next() },
    { record: record(), next: next({ action: 'approve', gate: true }) },
    { record: record(), next: next(), question: { id: 'q' } },
  ]
  for (const input of inputs) {
    for (const r of show(input).rows) {
      assert.ok(r.text && r.text.length > 8, 'text of ' + r.id)
      assert.ok(r.term && r.term.length > 0 && r.term.split(/\s+/).length <= 4, 'term of ' + r.id)
      assert.notEqual(r.text, r.term)
      assert.doesNotMatch(r.text, /\b(QA|lease|gate|contract|workflow|vbw run|record\.json)\b/i, 'jargon in the plain text of ' + r.id)
    }
  }
  assert.equal(row(show({ record: rec, next: next() }), 'doing').term.toLowerCase(), 'qa')
})

test('a missing, empty or invalid project state gives one neutral line and never throws', () => {
  for (const input of [{ record: null, next: null }, { record: {}, next: null }, { record: 'x', next: 5 }, { record: { milestone: null, phases: 3 }, next: [] }, {}]) {
    const v = show(input)
    assert.equal(v.need, null)
    assert.equal(v.rows.length, 1)
    assert.equal(v.rows[0].id, 'neutral')
    assert.ok(v.rows[0].text.length > 8 && v.rows[0].term.length > 0)
  }
})

test('a record without a next step still shows the milestone and progress', () => {
  const v = show({ record: record(), next: null })
  assert.match(row(v, 'milestone').text, /Live VBW panel/)
  assert.equal(v.need, null)
})

test('the dated rows (panel.js dates them before drawing) are the need and the estimates exactly as the view says them', () => {
  const note = (over) => ({ kind: 'build', run: 'build-1', doing: 'building P44.1', end: iso(NOW + 12 * 60000), ...over })
  const road = { end: iso(NOW + 3 * 3600000), say: 'the milestone ends around 18:00' }
  const inputs = [
    {}, { record: null }, { record: record({ milestone: { id: '' } }) },
    { record: record(), next: next() },
    { record: record(), next: next({ action: 'approve', gate: true }), nextAt: NOW - 60000 },
    { record: record(), next: next(), question: { id: 'q' }, questionAt: NOW - 5000 },
    { record: record({ lease: lease('build', NOW - 300000) }), next: next({ road }), step: note({ parts: { done: 1, total: 2 } }) },
    { record: record({ lease: lease('build', NOW - 300000) }), next: next({ road: { basis: 'fewer than 3 milestones.' } }), step: note({ end: null }) },
    { record: record(), next: next({ road }), stamps: { 'estimate-milestone': NOW - 120000 } },
    { record: record({ lease: lease('build', NOW - 300000) }), step: note({ parts: {}, late: true }), stamps: { 'estimate-step': NOW - 60000, proving: NOW - 1000 } },
  ]
  for (const input of inputs) {
    const v = show(input)
    assert.deepEqual(view.datedRows({ now: NOW, ...input }), { need: v.need, rows: v.rows.filter((r) => r.id.startsWith('estimate-')) }, JSON.stringify(input))
  }
  assert.ok(inputs.some((input) => show(input).rows.filter((r) => r.id.startsWith('estimate-')).length === 2), 'a case with both estimates')
})

// 6.3: the last run's refusals stay readable on the Now tab (docs/panel.md, Refusals).
test('the run\'s refusals are Now sentences before the need, each with its time, whole on one line; the newest five', () => {
  const said = 'vbw: apply refused: plan P1.1 is started\nNext: put it back as the record has it (vbw show plan P1.1)'
  const refusals = Array.from({ length: 7 }, (_, i) => ({ id: 'a#' + i, by: 'dev P1.' + i, at: NOW - (7 - i) * 60000, text: said }))
  const v = show({ record: record(), next: next(), refusals: deepFreeze(refusals) })
  const rows = v.rows.filter((r) => r.id.startsWith('refused:'))
  assert.deepEqual(rows.map((r) => r.id), ['refused:a#2', 'refused:a#3', 'refused:a#4', 'refused:a#5', 'refused:a#6'])
  assert.deepEqual(rows[4], { id: 'refused:a#6', text: '[' + view.clock(NOW - 60000) + '] ⊘ VBW refused, dev P1.6: vbw: apply refused: plan P1.1 is started Next: put it back as the record has it (vbw show plan P1.1)', term: 'refused' })
  const ids = v.rows.map((r) => r.id)
  assert.equal(ids.indexOf('need'), ids.length - 1, 'the need stays last')
  assert.equal(ids.indexOf('refused:a#6'), ids.length - 2)
  for (const bad of [undefined, 'x', [null, { text: '' }, { id: 'b', text: 5 }]]) {
    assert.deepEqual(show({ record: record(), next: next(), refusals: bad }).rows.filter((r) => r.id.startsWith('refused:')), [], String(bad))
  }
  assert.equal(show({ record: record(), next: next(), refusals: [{ id: 'c', by: 'lead', text: 'vbw: x' }] }).rows.find((r) => r.id === 'refused:c').text, '⊘ VBW refused, lead: vbw: x', 'no time, no stamp')
})

test('building the view changes nothing in its input', () => {
  const input = deepFreeze({ record: record({ lease: lease('build', NOW - 5000) }), next: next({ action: 'accept', gate: true, detail: { requirements: ['R1'] } }), question: { id: 'q' }, now: NOW })
  assert.doesNotThrow(() => view.panelView(input))
})

test('the Claude Code versions with mods start at 2.1.287', () => {
  const ok = (v) => view.supports(v)
  for (const v of ['2.1.287', '2.1.289', '2.1.1000', '2.2.0', '3.0.0', '2.1.287-dev.20261001.t1.sha1']) assert.equal(ok(v), true, v)
  for (const v of ['2.1.286', '2.1.99', '2.0.999', '1.9.9', '', undefined, null, 'garbage', '2.1']) assert.equal(ok(v), false, String(v))
  assert.equal(view.MIN_VERSION, '2.1.287')
})
