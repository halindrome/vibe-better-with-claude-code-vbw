// R89: Mission Control's tabs stay visible at the top of the pane however long
// its content is, and each sentence of the pane shows its key value in colour
// (progress green, estimate amber, cost in the accent colour, a need of the
// user yellow). Pure: panelView and renderPane, no Claude Code needed
// (evidence level L1). Since R190 (D425) the step's time comes from the
// kernel's note (the `step` input of panelView) in full wording, 'about 5 min,
// until around HH:MM', and without a basis 'No end time yet: ...'.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, lease, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const pane = await import(pathToFileURL(PLUGIN + '/hooks/panel-pane.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = Date.parse('2026-10-05T15:00:00Z')
const S = 1000
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
const TABS = ['now', 'plan', 'proof', 'timeline', 'sessions', 'settings']

const reqs = (done, total) => Array.from({ length: total }, (_, i) => ({ id: 'R' + (i + 1), text: 'R' + (i + 1) + ' holds', proof: 'auto', status: i < done ? 'proven' : 'open', milestone: 'M9' }))
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, seconds: s, started_at: new Date(NOW - 1e7 - i * 1e5).toISOString(), ended_at: new Date(NOW - 1e7 - i * 1e5 + s * 1000).toISOString() }))
const HISTORY = [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])]
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const step = (over = {}) => ({ kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(NOW - 300 * S), ids: ['P44.1'],
  doing: 'building P44.1', parts: { done: 0, total: 1 }, proof: null, first_end: iso(NOW + 300 * S), end: iso(NOW + 300 * S), late: false,
  road: { seconds: 7800, end: iso(NOW + 7800 * S), rounds: { deep: 2 }, basis: '2 waves, 2 proofs', say: 'milestone end: about 2 h 10 min, until around 16:40' }, ...over })
const busy = () => deepFreeze(record({
  requirements: reqs(2, 5),
  lease: lease('build', NOW - 300 * S),
  plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }],
}))

const texts = (tree) => {
  const out = []
  walk(tree, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const input = (v, over = {}) => ({
  st: { tab: 'now', record: record(), run: null, steps: [], leases: [], cost: 1.42, sound: true, agent: null, phase: null, check: null },
  v, now: NOW, width: 60, wrapped: null, portrait: null, sweep: null, ...over,
})
const on = { act: () => {}, sound: () => {} }
const sentence = (tree, text) => texts(tree).filter((t) => t.text === text)

// --- key values in colour -------------------------------------------------------

test('progress is green, the estimate amber and the cost in the accent colour, each sentence whole', () => {
  const v = view.panelView({ record: busy(), next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: HISTORY, step: step() })
  const tree = pane.renderPane(UI, input(v), on)
  const row = (id) => v.rows.find((r) => r.id === id)
  assert.match(row('progress').text, /2 of 5 requirements done/)
  assert.match(v.box.step.end, /about 5 min, until around \d\d:\d\d/)
  assert.match(row('cost').text, /\$1\.42/)
  for (const [text, colour, what] of [[row('progress').text, P.PROGRESS, 'progress'], [v.box.step.end, P.ESTIMATE, 'the step in the box'], [row('estimate-milestone').text, P.ESTIMATE, 'the milestone'], [row('cost').text, P.ACCENT, 'cost']]) {
    const hit = sentence(tree, text)
    assert.equal(hit.length, 1, what + ' is drawn once, as one piece of text')
    assert.equal(hit[0].props.color, colour, what)
  }
})

test("a need of the user is the box's amber sentence, drawn once; with nothing needed the line is plain", () => {
  const needing = view.panelView({ record: record(), next: next({ action: 'approve', gate: true }), now: NOW, cost: 1, steps: [] })
  assert.ok(needing.need)
  const t1 = pane.renderPane(UI, input(needing), on)
  const hit = sentence(t1, needing.need.text)
  assert.equal(hit.length, 1, 'the need sentence is drawn once: in the box, not again below')
  assert.equal(hit[0].props.color, P.NEED)
  assert.equal(needing.box.state.text, needing.need.text)

  const quiet = view.panelView({ record: record(), next: next(), now: NOW, cost: 1, steps: [] })
  assert.equal(quiet.need, null)
  const plain = sentence(pane.renderPane(UI, input(quiet), on), quiet.rows.find((r) => r.id === 'need').text)
  assert.equal(plain.length, 1)
  assert.equal(plain[0].props.color, undefined)
})

test('a sentence with no value in it stays plain: no requirements, no estimate basis, no cost', () => {
  const v = view.panelView({ record: deepFreeze(record({ requirements: [], lease: lease('build', NOW - 60 * S) })), next: next(), now: NOW, cost: undefined, steps: [],
    step: step({ first_end: null, end: null }) })
  const tree = pane.renderPane(UI, input(v), on)
  const row = (id) => v.rows.find((r) => r.id === id)
  assert.match(row('progress').text, /No requirements/)
  assert.match(v.box.step.end, /No end time yet/)
  assert.match(row('cost').text, /not available/)
  for (const [text, what] of [[row('progress').text, 'progress'], [v.box.step.end, 'the step'], [row('cost').text, 'cost']]) {
    const hit = sentence(tree, text)
    assert.equal(hit.length, 1, what)
    assert.equal(hit[0].props.color, undefined, what + ' has no value to colour')
  }
})

test('the milestone sentence keeps its colour (none), and every term drawn stays dim', () => {
  const v = view.panelView({ record: busy(), next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: HISTORY })
  const tree = pane.renderPane(UI, input(v), on)
  assert.equal(sentence(tree, v.rows.find((r) => r.id === 'milestone').text)[0].props.color, undefined)
  // What VBW is doing is the box's state sentence, not a row of its own: it is not drawn twice.
  assert.equal(sentence(tree, v.rows.find((r) => r.id === 'doing').text).length, 0, 'the doing sentence is not drawn below the box')
  for (const r of v.rows.filter((x) => x.id !== 'doing')) assert.ok(texts(tree).some((t) => t.text === r.term && t.props.dimColor === true), r.term + ' is dim')
})

// --- the tabs stay on top -------------------------------------------------------

const agent = (i) => ({
  id: 'a' + i, role: ROLES[i % ROLES.length], label: 'P' + Math.floor(i / 3) + '.' + (i % 3), state: 'working', activity: { kind: 'tool', text: 'editing f' + i + '.js' },
  startedAt: NOW - (600 - i) * S, endedAt: null, lastSeenAt: NOW - S, tokens: 1000 + i, result: null,
})
const longRun = () => deepFreeze({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 700 * S, endedAt: null, status: 'running', agents: Array.from({ length: 60 }, (_, i) => agent(i)) })
const longInput = (tab, scroll) => input(view.panelView({ record: busy(), next: next(), now: NOW, cost: 1, steps: [] }),
  { st: { tab, record: busy(), run: longRun(), steps: [], leases: [], cost: 1, sound: true, agent: null, phase: null, check: null }, ...(scroll ? { scroll } : {}) })
const tabsIn = (node) => { const out = []; walk(node, (n) => { if (n.type === 'Button' && /^tab-/.test(String(n.props.key))) out.push(n.props.key) }); return out }

test('the tabs are the first thing in the pane, whatever the tab, however long its content and however far it is scrolled', () => {
  for (const tab of TABS) {
    for (const offset of [0, 7, 500]) {
      const tree = pane.renderPane(UI, longInput(tab, { offset, bodyRows: 30 }), on)
      assert.equal(tabsIn(tree.children[0]).length, 6, tab + ' at ' + offset + ': all six tabs open the pane')
      assert.equal(tabsIn(find(tree, (n) => n.props && n.props.key === 'body') || { children: [] }).length, 0, tab + ': the tabs are not inside what scrolls')
    }
  }
})

test('the content under the tabs is a clipped window of the pane height, so a long tab cannot push the tabs away', () => {
  for (const bodyRows of [12, 30, 60]) {
    const tree = pane.renderPane(UI, longInput('now', { offset: 0, bodyRows }), on)
    const body = find(tree, (n) => n.props && n.props.key === 'body')
    assert.ok(body, 'a body under the tabs')
    assert.equal(body.props.overflow, 'hidden')
    assert.ok(Number.isInteger(body.props.height) && body.props.height >= 1 && body.props.height < bodyRows, 'height ' + body.props.height + ' leaves room for the tabs in ' + bodyRows)
  }
})

test('scrolling still moves the content: the body shows other rows at another offset', () => {
  const at = (offset) => JSON.stringify(find(pane.renderPane(UI, longInput('now', { offset, bodyRows: 30 }), on), (n) => n.props && n.props.key === 'body'))
  assert.notEqual(at(0), at(10))
  assert.notEqual(at(10), at(25))
})

test('without a scroll hint the pane still draws its tabs and its content', () => {
  const tree = pane.renderPane(UI, longInput('now'), on)
  assert.equal(tabsIn(tree).length, 6)
  assert.ok(texts(tree).length > 20)
})
