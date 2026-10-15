// R189, phase P145 (evidence level L1, the stand-in for Claude Code's mods API
// and a model of Ink's layout, ./helpers/screen.mjs): nothing the panel draws
// spills past the room Claude Code gives it. Mission Control never draws more
// rows than scroll.bodyRows, on any tab or VBW Wrapped; where that size is not
// reported (inline, the main screen) it is capped at a fixed height and ends
// with '+N more · open Mission Control'. Its tab row never wraps onto a second
// line at 40 columns. Comms stays within its maxRows in every mode (crew,
// needs-you line, celebration, after a ship) and within its columns. Every
// surface is drawn at 80x24, at 40 columns and in a short terminal.
import test from 'node:test'
import assert from 'node:assert/strict'
import { record, next, lease, find, T0 } from '../helpers/fake-mod.mjs'
import { TICK, writeCrew, working, building } from './helpers/crew.mjs'
import { screen, widest } from './helpers/screen.mjs'

const TABS = ['now', 'plan', 'proof', 'timeline', 'decisions', 'team', 'costs']
const MORE = /^\+\d+ more · open Mission Control$/
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')

// A busy project: many phases, plans, checks, decisions and a recommendation.
function busy(extra = {}) {
  const phases = Array.from({ length: 12 }, (_, i) => ({ id: 'P' + (i + 1), title: 'Phase number ' + (i + 1) + ' with a long title that goes on', milestone: 'M9', reqs: ['R' + (i + 1)], goal: 'A goal that is long enough to wrap in a narrow pane, twice over.' }))
  const plans = phases.flatMap((p) => [1, 2, 3].map((k) => ({ id: p.id + '.' + k, phase: p.id, title: 'Plan ' + k + ' of ' + p.id, status: 'planned', files: ['src/a' + k + '.js', 'tests/a' + k + '.test.js'], reqs: p.reqs, after: [] })))
  const requirements = phases.map((p, i) => ({ id: 'R' + (i + 1), text: 'Requirement ' + (i + 1), proof: 'auto', status: i % 2 ? 'proven' : 'open', milestone: 'M9' }))
  const checks = requirements.flatMap((r) => [1, 2].map((k) => ({ id: 'C' + r.id.slice(1) + k, req: r.id, run: ['bats', 'tests/x.bats'] })))
  const decisions = Array.from({ length: 30 }, (_, i) => ({ id: 'D' + (i + 1), text: 'Decision ' + (i + 1) + ' says something long enough to wrap in a narrow pane', at: iso(T0 - i * 60000) }))
  return record({
    lease: lease('build', T0), phases, plans, requirements, checks, decisions,
    recommendation: { at: '2026-10-09T10:00:00Z', top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most this month.', size: 'small', source: 'T4' }, runners: [{ text: 'Gift cards', size: 'large', source: 'T9' }] },
    ...extra,
  })
}

async function crowded(n = 12, settings = { profile: 'balanced', motion: 'calm' }) {
  const { h, at } = await building(working(n), settings)
  h.project(busy({ settings }))
  await h.advance(TICK)
  return { h, at }
}

const dock = (h, columns, rows) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: columns, placement: 'dock', scroll: { offset: 0, bodyRows: rows }, view: {} } })
const inline = (h, columns) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: columns, placement: 'inline', view: {} } })
const comms = (h, columns, rows) => h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: rows, bodyColumns: columns })
const SIZES = [[80, 22], [40, 22], [80, 8], [40, 8], [40, 4]]

test('Mission Control never draws more rows than Claude Code reports, on every tab, at 80x24, at 40 columns and in a short terminal', async () => {
  const { h } = await crowded()
  for (const tab of TABS) {
    await h.press('tab-' + tab)
    for (const [columns, rows] of SIZES) {
      const lines = screen(await dock(h, columns, rows), columns)
      assert.ok(lines.length <= rows, tab + ' at ' + columns + 'x' + rows + ': ' + lines.length + ' rows')
    }
  }
})

test('VBW Wrapped, at a ship, stays within the rows Claude Code reports', async () => {
  const { h } = await crowded()
  h.project(busy({ lease: null, milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' }, shipped: [{ id: 'M9', title: 'Live VBW panel', at: iso(h.now()) }] }))
  await h.advance(TICK)
  for (const [columns, rows] of SIZES) {
    const lines = screen(await dock(h, columns, rows), columns)
    assert.ok(lines.length <= rows, 'Wrapped at ' + columns + 'x' + rows + ': ' + lines.length + ' rows')
  }
})

test("where Claude Code reports no height, Mission Control is capped at a fixed height and ends with '+N more · open Mission Control'", async () => {
  const heights = []
  for (const n of [12, 40]) {
    const { h } = await crowded(n)
    for (const columns of [80, 40]) {
      const lines = screen(await inline(h, columns), columns)
      assert.ok(lines.length <= 30, n + ' helpers at ' + columns + ' columns: ' + lines.length + ' rows')
      assert.match(lines[lines.length - 1].trim(), MORE, 'the last line is not the fold: ' + lines[lines.length - 1])
      if (columns === 80) heights.push(lines.length)
    }
  }
  assert.equal(heights[0], heights[1], 'the height is not fixed: ' + heights.join(' and '))
})

test('a short Mission Control without a reported height has no fold line', async () => {
  const { h } = await building([], { profile: 'balanced', motion: 'calm' })
  h.project(record())
  await h.press('tab-decisions')
  await h.advance(TICK)
  const lines = screen(await inline(h, 80), 80)
  assert.ok(!lines.some((l) => MORE.test(l.trim())), lines.join('\n'))
})

test('the tab row never wraps onto a second line at 40 columns', async () => {
  const { h } = await crowded()
  for (const tab of TABS) {
    await h.press('tab-' + tab)
    const tree = await dock(h, 40, 22)
    const tabs = find(tree, (n) => n.type === 'Box' && n.children.some((c) => c.type === 'Button' && /^tab-/.test(String(c.props.key))))
    assert.ok(tabs, 'no tab row')
    const head = find(tree, (n) => n.type === 'Box' && n.children.includes(tabs)) || { props: {}, children: [] }
    const image = head.children.find((c) => c.type === 'Image')
    const room = 40 - (image ? image.props.columns + (head.props.columnGap || 0) : 0)
    const lines = screen(tabs, room)
    assert.equal(lines.length, 1, tab + ': the tabs take ' + lines.length + ' lines in ' + room + ' columns')
    assert.ok(widest(screen(tabs, Infinity)) <= room, tab + ': the tabs are ' + widest(screen(tabs, Infinity)) + ' wide in ' + room + ' columns')
  }
})

test('Comms stays within its rows and columns with a crew, at full and calm motion, at every room Claude Code may give', async () => {
  for (const motion of ['full', 'calm']) {
    const { h } = await crowded(12, { profile: 'balanced', motion })
    for (const columns of [80, 40]) {
      for (const rows of [12, 8, 6, 4, 3, 2, 1]) {
        const tree = await comms(h, columns, rows)
        const name = motion + ' at ' + columns + 'x' + rows
        assert.ok(screen(tree, columns).length <= rows, name + ': ' + screen(tree, columns).length + ' rows')
        assert.ok(widest(screen(tree, Infinity)) <= columns, name + ': ' + widest(screen(tree, Infinity)) + ' columns')
      }
    }
  }
})

test('Comms stays within its rows and columns with the needs-you line', async () => {
  const { h } = await building([], { profile: 'balanced', motion: 'calm' })
  h.project(record(), next({ action: 'accept', gate: true, detail: { requirements: ['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8'] } }))
  await h.advance(TICK)
  for (const columns of [80, 40]) {
    for (const rows of [3, 1]) {
      const tree = await comms(h, columns, rows)
      assert.ok(screen(tree, columns).length <= rows, columns + 'x' + rows)
      assert.ok(widest(screen(tree, Infinity)) <= columns, columns + 'x' + rows + ': ' + widest(screen(tree, Infinity)) + ' columns')
    }
  }
})

test('Comms stays within its rows during a celebration (a phase passing QA, all checks passing) and after a ship', async () => {
  const settings = { profile: 'balanced', motion: 'full' }
  const { h, at } = await crowded(6, settings)
  const passed = busy({ settings })
  passed.phases[0] = { ...passed.phases[0], qa: { result: 'pass', at: iso(h.now()) } }
  passed.evidence = { at: iso(h.now()), passed: true, contract: 'c1', checks: {} }
  h.project(passed)
  writeCrew(h, at, working(6))
  await h.advance(TICK)
  for (const [columns, rows] of [[80, 8], [80, 4], [40, 3], [40, 1]]) {
    const tree = await comms(h, columns, rows)
    assert.ok(screen(tree, columns).length <= rows, 'celebration at ' + columns + 'x' + rows + ': ' + screen(tree, columns).length + ' rows')
  }
  h.project(busy({ settings, lease: null, milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' }, shipped: [{ id: 'M9', title: 'Live VBW panel', at: iso(h.now()) }] }))
  await h.advance(TICK)
  for (const [columns, rows] of [[80, 4], [40, 1]]) {
    const tree = await comms(h, columns, rows)
    assert.ok(screen(tree, columns).length <= rows, 'after a ship at ' + columns + 'x' + rows)
  }
})
