// Mission Control's record views (mods_4_vbw.md §3.3): Plan, Proof and the
// decisions under Plan. plugin/hooks/panel-mission-record.js turns the project record into
// plain models (tested by value) and draws them with h() (tested by tree
// shape). Pure: no Claude Code, no disk (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, deepFreeze, walk, find, collect } from './helpers/fake-mod.mjs'

import { screen, widest } from './r189/helpers/screen.mjs'

const mr = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-record.js').href)
const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button'), Input: EL('Input'), Code: EL('Code'), Markdown: EL('Markdown') }
const BASIC = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const all = (tree, pred) => { const out = []; walk(tree, (n) => { if (pred(n)) out.push(n) }); return out }
const buttons = (tree) => all(tree, (n) => n.type === 'Button')

// A record with two milestones' worth of work, evidence and decisions.
const rec = () => deepFreeze(record({
  milestone: { id: 'M9', title: 'Live VBW panel', status: 'active' },
  shipped: [{ id: 'M8', title: 'Before', at: '2026-10-01T10:00:00Z' }],
  requirements: [
    { id: 'R1', text: 'Old thing works', proof: 'auto', status: 'proven', milestone: 'M8' },
    { id: 'R2', text: 'The panel shows the cost', proof: 'auto', status: 'proven', milestone: 'M9' },
    { id: 'R3', text: 'The panel shows an estimate', proof: 'auto', status: 'failing', milestone: 'M9' },
    { id: 'R4', text: 'It feels right', proof: 'human', status: 'open', milestone: 'M9' },
  ],
  checks: [
    { id: 'C1', req: 'R1', run: ['bats', 'tests/old.bats'] },
    { id: 'C2', req: 'R2', run: ['bats', 'tests/cost.bats'] },
    { id: 'C3', req: 'R3', run: ['node', '--test', 'tests/my est.mjs'] },
    { id: 'C4', req: 'R3', run: ['bats', 'tests/est.bats'] },
    { id: 'C5', req: 'R2', run: ['bats', 'tests/cost2.bats'] },
  ],
  phases: [
    { id: 'P1', title: 'Old work', milestone: 'M8', reqs: ['R1'], qa: { result: 'pass' } },
    { id: 'P44', title: 'Cost', milestone: 'M9', reqs: ['R2'], goal: 'Show the **cost**.', qa: { result: 'pass' } },
    { id: 'P45', title: 'Estimates', milestone: 'M9', reqs: ['R3'], goal: 'Show the estimate.' },
  ],
  plans: [
    { id: 'P44.1', phase: 'P44', title: 'Show the cost', files: ['plugin/hooks/panel.js'], status: 'done' },
    { id: 'P45.1', phase: 'P45', title: 'Show the estimate', files: ['plugin/hooks/panel-estimate.js', 'docs/panel.md'], status: 'building' },
    { id: 'P45.2', phase: 'P45', title: 'Explain it', files: ['docs/panel.md'], status: 'planned' },
  ],
  decisions: [
    { id: 'D1', text: 'Old choice', at: '2026-09-30T10:00:00Z' },
    { id: 'D2', text: 'Which currency? Dollars', why: 'the ledger is in dollars', at: '2026-10-02T10:00:00Z' },
    { id: 'D3', text: 'Round to cents', at: '2026-10-03T10:00:00Z' },
  ],
  settings: { profile: 'quality', autonomy: 'hands-off', models: { dev: 'haiku', planner: 'sonnet' } },
  evidence: {
    at: '2026-10-03T11:00:00Z', passed: false,
    checks: {
      C1: { status: 'pass', exit: 0, seconds: 1, tail: 'ok' },
      C2: { status: 'pass', exit: 0, seconds: 2, tail: 'ok 1 cost' },
      C3: { status: 'fail', exit: 1, seconds: 3, tail: Array.from({ length: 30 }, (_, i) => 'line ' + (i + 1)).join('\n') },
      C4: { status: 'timeout', exit: null, seconds: 60, tail: '' },
    },
  },
}))

const ODD = [undefined, null, 7, 'x', [], {}, { record: null }, { record: { milestone: 'M1' } },
  { record: { milestone: { id: 'M1' }, phases: 'no', plans: [null, 3], checks: {}, decisions: [1], requirements: null, settings: 4, evidence: [] } }]

test('every model and render survives missing or odd input without throwing', () => {
  for (const x of ODD) {
    assert.ok(Array.isArray(mr.decisionsModel(x).items), 'decisionsModel returns its items')
    for (const f of ['planModel', 'proofModel']) {
      const m = mr[f](x)
      assert.ok(m && typeof m === 'object', f + ' returns an object')
      for (const ui of [UI, BASIC]) {
        const r = 'render' + f.slice(0, -5)[0].toUpperCase() + f.slice(1, -5)
        assert.doesNotThrow(() => mr[r](ui, m), r)
      }
    }
    assert.doesNotThrow(() => mr.checkDetail(x && x.record, 'C1'))
  }
  for (const f of ['renderPlan', 'renderProof']) {
    assert.doesNotThrow(() => mr[f](UI, null))
    assert.doesNotThrow(() => mr[f](UI, undefined))
  }
})

test('plan: the current milestone\'s phases are rows: a segmented done/total strip of their plans, a state mark and word in its colour, a press to {tab, phase}', () => {
  const m = mr.planModel({ record: rec() })
  assert.deepEqual(m.phases.map((p) => p.id), ['P44', 'P45'])
  assert.deepEqual(m.phases[1].press, { tab: 'plan', phase: 'P45' })
  // Default: the first phase not yet passed by QA.
  assert.equal(m.selected.id, 'P45')
  assert.equal(m.phases.find((p) => p.active).id, 'P45')
  const [p44, p45] = m.phases
  assert.deepEqual([p44.done, p44.total, p44.mark + ' ' + p44.word, p44.color], [1, 1, '✓ done', P.stateColor('done')])
  assert.deepEqual([p45.done, p45.total, p45.mark + ' ' + p45.word, p45.color], [0, 2, '● building', P.stateColor('running')])
  assert.deepEqual(p45.strip.map((s) => s.state), ['running', 'open'])
  // A blocked plan makes its phase blocked, in the failed colour.
  const blocked = mr.planModel({ record: { ...rec(), plans: [...rec().plans.slice(0, 2), { id: 'P45.2', phase: 'P45', title: 'Explain it', files: ['docs/panel.md'], status: 'blocked', note: 'the API is down: retry later' }] } })
  assert.equal(blocked.phases[1].mark + ' ' + blocked.phases[1].word, '✗ blocked')
})

test('plan: the chosen phase shows its goal, its requirements and plans as rows with their state, files a press away, and its checks', () => {
  const m = mr.planModel({ record: rec(), phase: 'P45' })
  assert.equal(m.selected.goal, 'Show the estimate.')
  assert.deepEqual(m.selected.reqs.map((r) => r.id + ' ' + r.mark + ' ' + r.word), ['R3 ✗ failing'])
  assert.deepEqual(m.selected.plans.map((p) => [p.id, p.title, p.mark + ' ' + p.word, p.files.length, p.toggle]), [
    ['P45.1', 'Show the estimate', '● building', 2, 'files:P45.1'],
    ['P45.2', 'Explain it', '○ planned', 1, 'files:P45.2'],
  ])
  assert.deepEqual(m.selected.checks, [
    { id: 'C3', req: 'R3', command: "node --test 'tests/my est.mjs'" },
    { id: 'C4', req: 'R3', command: 'bats tests/est.bats' },
  ])
  assert.deepEqual(m.ask, { ask: true, placeholder: 'Ask about this plan' })
  const p44 = mr.planModel({ record: rec(), phase: 'P44' })
  assert.equal(p44.selected.id, 'P44')
  assert.deepEqual(p44.selected.reqs.map((r) => r.id + ' ' + r.mark + ' ' + r.word), ['R2 ✓ proven'])
  // A requirement still open is building while a plan of it builds, else open.
  const open = mr.planModel({ record: { ...rec(), requirements: rec().requirements.map((r) => (r.id === 'R3' ? { ...r, status: 'open' } : r)) }, phase: 'P45' })
  assert.equal(open.selected.reqs[0].mark + ' ' + open.selected.reqs[0].word, '● building')
  // A phase of another milestone or an unknown one falls back to the default.
  assert.equal(mr.planModel({ record: rec(), phase: 'P1' }).selected.id, 'P45')
  assert.deepEqual(mr.planModel({ record: record({ phases: [] }) }).phases, [])
  assert.equal(mr.planModel({ record: record({ phases: [] }) }).selected, null)
})

test('plan: the milestone\'s decisions, newest first, each with its id and time (the day named when it is not today)', () => {
  const now = Date.parse('2026-10-03T12:00:00Z')
  const m = mr.planModel({ record: rec(), now })
  assert.deepEqual(m.decisions.map((d) => d.id), ['D3', 'D2'])
  const at = (iso) => { const d = new Date(iso); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0') }
  assert.equal(m.decisions[0].when, at('2026-10-03T10:00:00Z'))
  assert.match(m.decisions[1].when, new RegExp('^(yesterday|tomorrow|[A-Z][a-z]+day) ' + at('2026-10-02T10:00:00Z') + '$'))
})

test('plan render: each phase is one whole row (its title cut, never wrapped), the plans as rows with a files button, the decisions dim at the bottom', () => {
  const pressed = []
  const long = { ...rec(), phases: rec().phases.map((p) => (p.id === 'P44' ? { ...p, title: 'Cost of the whole thing shown in the pane with a very long title that goes on and on' } : p)) }
  const tree = mr.renderPlan(UI, mr.planModel({ record: long, phase: 'P45', now: Date.parse('2026-10-03T12:00:00Z') }), (a) => pressed.push(a), 60)
  const phaseButtons = buttons(tree).filter((b) => /^plan-P/.test(b.props.key))
  assert.deepEqual(phaseButtons.map((b) => b.props.key), ['plan-P44', 'plan-P45'])
  for (const b of phaseButtons) assert.ok([...b.props.label].length + 4 <= 60, 'the phase button is cut to the row: ' + b.props.label)
  assert.match(phaseButtons[0].props.label, /…$/)
  const lines = screen(tree, 60)
  assert.ok(widest(lines) <= 60, 'a line is wider than the pane: ' + widest(lines))
  assert.ok(!lines.some((l) => /^\s*\]\s*$/.test(l)), 'a lone ] on a line: ' + JSON.stringify(lines))
  const row44 = lines.find((l) => l.includes('[ P44 '))
  assert.match(row44, /1\/1 ✓ done/)
  phaseButtons[0].props.onPress({ surface: 'terminal' })
  assert.deepEqual(pressed, [{ tab: 'plan', phase: 'P44' }])
  assert.equal(find(tree, (n) => n.type === 'Markdown').props.text, 'Show the estimate.')
  const text = collect(tree).join('\n')
  assert.match(collect(find(tree, (n) => n.props && n.props.key === 'req-R3')).join(' '), /^R3 ✗ failing The panel shows an estimate$/)
  assert.match(text, /P45\.1 Show the estimate/)
  assert.doesNotMatch(text, /plugin\/hooks\/panel-estimate\.js/, 'files stay folded until pressed')
  const files = buttons(tree).find((b) => b.props.key === 'files-P45.1')
  assert.equal(files.props.label, '2 files')
  files.props.onPress({ surface: 'terminal' })
  assert.deepEqual(pressed[1], { toggle: 'files:P45.1' })
  const opened = collect(mr.renderPlan(UI, mr.planModel({ record: rec(), phase: 'P45', open: { 'files:P45.1': true } }), null, 60)).join('\n')
  assert.match(opened, /plugin\/hooks\/panel-estimate\.js/)
  const code = all(tree, (n) => n.type === 'Code')
  assert.deepEqual(code.map((c) => c.props.source), ["node --test 'tests/my est.mjs'", 'bats tests/est.bats'])
  const input = find(tree, (n) => n.type === 'Input')
  assert.equal(input.props.placeholder, 'Ask about this plan')
  input.props.onSubmit('why is P45.2 last?', {})
  assert.deepEqual(pressed[2], { ask: 'why is P45.2 last?' })
  // Decisions at the bottom, dim; the reason dim and italic.
  const d2 = find(tree, (n) => n.type === 'Text' && collect(n).join('') === 'Which currency? Dollars')
  assert.ok(d2 && d2.props.dimColor === true, 'a decision is dim')
  const why = find(tree, (n) => n.type === 'Text' && collect(n).join('') === 'because the ledger is in dollars')
  assert.ok(why && why.props.dimColor === true && why.props.italic === true)
  assert.ok(text.indexOf('D3') < text.indexOf('D2') && text.indexOf('P45.1') < text.indexOf('D3'), 'the decisions come last, newest first')
  // Without Code, Markdown or Input elements it still draws the words as Text.
  const plain = collect(mr.renderPlan(BASIC, mr.planModel({ record: rec(), phase: 'P45' }))).join('\n')
  assert.match(plain, /Show the estimate\./)
  assert.match(plain, /bats tests\/est\.bats/)
})

test('proof: one cell per check of the current milestone, coloured by its last result', () => {
  const m = mr.proofModel({ record: rec(), running: ['C5'] })
  assert.deepEqual(m.cells.map((c) => [c.id, c.state, c.color]), [
    ['C2', 'passed', 'green'],
    ['C3', 'failing', 'red'],
    ['C4', 'failing', 'red'],
    ['C5', 'running', '#ffaf00'],
  ])
  assert.equal(m.cells[1].hover, 'C3 · failing · R3: The panel shows an estimate')
  assert.deepEqual(m.cells[1].press, { check: 'C3' })
  assert.deepEqual(m.counts, { passed: 1, failing: 2, running: 1, none: 0 })
  const idle = mr.proofModel({ record: rec() })
  assert.equal(idle.cells[3].state, 'none')
  assert.equal(idle.cells[3].color, 'gray')
  // A proven requirement counts as passed even without evidence for the check.
  const noEv = mr.proofModel({ record: { ...rec(), evidence: null } })
  assert.deepEqual(noEv.cells.map((c) => c.state), ['passed', 'none', 'none', 'passed'])
})

test('proof: checkDetail is the command and the last lines of output', () => {
  const d = mr.checkDetail(rec(), 'C3')
  assert.equal(d.id, 'C3')
  assert.equal(d.command, "node --test 'tests/my est.mjs'")
  assert.equal(d.requirement, 'R3: The panel shows an estimate')
  assert.equal(d.status, 'fail')
  assert.equal(d.exit, 1)
  assert.equal(d.output.split('\n').length, 20)
  assert.match(d.output, /^line 11\nline 12/)
  assert.match(d.output, /line 30$/)
  assert.equal(mr.checkDetail(rec(), 'C5').output, '')
  assert.equal(mr.checkDetail(rec(), 'C5').status, null)
  assert.equal(mr.checkDetail(rec(), 'C99'), null)
  assert.deepEqual(mr.proofModel({ record: rec(), selected: 'C3' }).detail, d)
})

test('proof render: rows of coloured ■ cells with hover cards; presses ask for the detail', () => {
  const pressed = []
  const tree = mr.renderProof(UI, mr.proofModel({ record: rec(), running: ['C5'], selected: 'C3' }), (a) => pressed.push(a))
  const cells = all(tree, (n) => n.type === 'Text' && /^[✓✗●…]$/.test(n.children.join('')))
  assert.deepEqual(cells.map((c) => c.props.color), ['green', 'red', 'red', '#ffaf00'])
  // Colour off: the mark alone tells the states apart, and the hover card says the word.
  assert.deepEqual(cells.map((c) => c.children.join('')), ['✓', '✗', '✗', '●'])
  assert.match(collect(find(tree, (n) => n.type === 'Box' && n.props.display === 'none')).join(' '), /C\d · (passed|failing|running|not run) · /)
  const card = find(tree, (n) => n.type === 'Box' && n.props.display === 'none' && n.props.hover && n.props.hover.display === 'flex')
  assert.ok(card, 'a hover card revealed on hover')
  assert.match(collect(card).join(' '), /C2 · passed · R2: The panel shows the cost/)
  const press = buttons(tree).find((b) => b.props.label === 'C3')
  press.props.onPress({ surface: 'terminal' })
  assert.deepEqual(pressed, [{ check: 'C3' }])
  assert.equal(all(tree, (n) => n.type === 'Code').map((c) => c.props.source).join('\n').split('\n').length, 21)
  // Wide grids wrap into rows of at most `perRow` cells.
  const many = deepFreeze(record({
    requirements: [{ id: 'R1', text: 'x', proof: 'auto', status: 'open', milestone: 'M9' }],
    checks: Array.from({ length: 25 }, (_, i) => ({ id: 'C' + (i + 1), req: 'R1', run: ['true'] })),
  }))
  const grid = mr.renderProof(BASIC, mr.proofModel({ record: many }))
  const rows = all(grid, (n) => n.type === 'Box' && n.props.key && n.props.key.startsWith('proof-row-'))
  assert.deepEqual(rows.map((r) => all(r, (n) => n.type === 'Text' && n.children.join('') === '…').length), [20, 5])
})

test('decisions: the current milestone, newest first, with question, answer and why', () => {
  const m = mr.decisionsModel({ record: rec() })
  assert.deepEqual(m.items, [
    { id: 'D3', question: null, answer: 'Round to cents', why: null, at: '2026-10-03T10:00:00Z' },
    { id: 'D2', question: 'Which currency?', answer: 'Dollars', why: 'the ledger is in dollars', at: '2026-10-02T10:00:00Z' },
  ])
  // A shipped current milestone keeps its decisions up to its own ship time.
  const shipped = mr.decisionsModel({ record: { ...rec(),
    milestone: { id: 'M9', title: 'x', status: 'shipped' },
    shipped: [...rec().shipped, { id: 'M9', title: 'x', at: '2026-10-02T12:00:00Z' }] } })
  assert.deepEqual(shipped.items.map((d) => d.id), ['D2'])
  // Nothing shipped yet: every decision belongs to the first milestone.
  assert.equal(mr.decisionsModel({ record: { ...rec(), shipped: [] } }).items.length, 3)
})
