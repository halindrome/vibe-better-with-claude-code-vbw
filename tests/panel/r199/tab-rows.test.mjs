// R199, phase P159 (evidence level L1: the stand-in for Claude Code's mods API
// in ../helpers/fake-mod.mjs and the model of Ink's layout in
// ../r189/helpers/screen.mjs). Mission Control's title and tabs fit the pane at
// every width it draws at. Claude Code 2.1.302 draws a tab button as '[ Name ]',
// 4 cells of chrome around the label: the 2026-10-19 capture at 200x24 shows
// '[ Now ] [ Plan ]' in a pane about 64 columns wide, with 'VB' / 'W' and a lone
// ']' spilling down its right edge. So the stand-in draws a Button without a
// hotkey as '[ Name ]' (with one, '[k] Name': the same width), and the pane packs
// its eight tabs into whole rows: a name is never split, no row is wider than
// the pane, the layout with the fewest rows wins, at an equal count the full
// names win over the short ones, and the portrait (6 columns, 'VBW') stays only
// when it costs the tabs nothing (no row and no short name) and the pane is not
// short. The head's row count used to clip the body is the real count (the
// portrait's rows or the tab rows, whichever is more, plus the gap), so the pane
// never draws more rows than Claude Code reports; with no height reported it
// still ends with '+N more · open Mission Control' within its fixed height.
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { mount, record, next, find, walk, PLUGIN, T0 } from '../helpers/fake-mod.mjs'
import { screen, widest } from '../r189/helpers/screen.mjs'

// id, full name, short name
const TABS = [['now', 'Now', 'Now'], ['plan', 'Plan', 'Plan'], ['proof', 'Proof', 'Proof'], ['timeline', 'Timeline', 'Time'],
  ['decisions', 'Decisions', 'Log'], ['team', 'Team', 'Team'], ['sessions', 'Sessions', 'Sess'], ['costs', 'Costs', 'Cost']]
const FULL = TABS.map((t) => t[1])
const SHORT = TABS.map((t) => t[2])
const WIDTHS = [100, 64, 60, 50, 40]
const NAME = '(?:' + [...new Set([...FULL, ...SHORT])].join('|') + ')'
const BUTTONS = new RegExp('\\[ ' + NAME + ' \\]', 'g')
const HAS_BUTTON = new RegExp('\\[ ' + NAME + ' \\]')
// A line of the head: the portrait's 6 cells or none, then whole buttons one space apart, or nothing (the gap row).
const HEAD_LINE = new RegExp('^(?:▓{6} ?)?(?:\\[ ' + NAME + ' \\](?: \\[ ' + NAME + ' \\])*)?$')
const MORE = /^\+\d+ more · open Mission Control$/
const PORTRAIT = '▓'.repeat(6)
const FIXED_ROWS = 30
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const EL = (name) => Object.freeze({ element: name })

// A busy project, so every tab is taller than the pane.
function busy() {
  const phases = Array.from({ length: 12 }, (_, i) => ({ id: 'P' + (i + 1), title: 'Phase number ' + (i + 1) + ' with a long title that goes on', milestone: 'M9', reqs: ['R' + (i + 1)], goal: 'A goal that is long enough to wrap in a narrow pane, twice over.' }))
  const plans = phases.flatMap((p) => [1, 2, 3].map((k) => ({ id: p.id + '.' + k, phase: p.id, title: 'Plan ' + k + ' of ' + p.id, status: 'planned', files: ['src/a' + k + '.js', 'tests/a' + k + '.test.js'], reqs: p.reqs, after: [] })))
  const requirements = phases.map((p, i) => ({ id: 'R' + (i + 1), text: 'Requirement ' + (i + 1), proof: 'auto', status: i % 2 ? 'proven' : 'open', milestone: 'M9' }))
  const checks = requirements.flatMap((r) => [1, 2].map((k) => ({ id: 'C' + r.id.slice(1) + k, req: r.id, run: ['bats', 'tests/x.bats'] })))
  const decisions = Array.from({ length: 30 }, (_, i) => ({ id: 'D' + (i + 1), text: 'Decision ' + (i + 1) + ' says something long enough to wrap in a narrow pane', at: iso(T0 - i * 60000) }))
  return record({
    phases, plans, requirements, checks, decisions,
    recommendation: { at: '2026-10-09T10:00:00Z', top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most this month.', size: 'small', source: 'T4' }, runners: [{ text: 'Gift cards', size: 'large', source: 'T9' }] },
  })
}

async function opened() {
  const h = await mount({ env: { HOME: '/home/u' } })
  h.project(busy(), next())
  await h.start()
  await h.settle()
  return h
}
const dock = (h, columns, rows) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: columns, placement: 'dock', scroll: { offset: 0, bodyRows: rows }, view: {} } })
const inline = (h, columns) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: columns, placement: 'inline', view: {} } })

const holdsTabs = (n) => {
  let hit = false
  walk(n, (x) => { if (x.type === 'Button' && x.props.key === 'tab-now') hit = true })
  return hit
}
// The pane is one column: the head (the portrait and the tab rows) first, then the clipped body (the Box with a height).
function parts(tree, where) {
  assert.ok(tree && tree.type === 'Box' && Array.isArray(tree.children), where + ': no pane: ' + JSON.stringify(tree).slice(0, 160))
  const head = tree.children[0]
  assert.ok(head && typeof head === 'object' && holdsTabs(head), where + ': the first part of the pane is not the head with the tabs')
  const body = tree.children.find((c, i) => i > 0 && c && typeof c === 'object' && Number.isInteger((c.props || {}).height))
  return { head, body, image: find(head, (n) => n.type === 'Image') }
}
// The names on the head's lines: every line is whole buttons (and the portrait), and each tab shows exactly one of its names.
function names(lines, where) {
  for (const l of lines) assert.match(l, HEAD_LINE, where + ': a head line with a cut name or stray chrome: "' + l + '"')
  const shown = lines.flatMap((l) => (l.match(BUTTONS) || []).map((b) => b.slice(2, -2)))
  for (const [, full, short] of TABS) {
    const n = shown.filter((x) => x === full || x === short).length
    assert.equal(n, 1, where + ': ' + full + ' shows ' + n + ' times in ' + JSON.stringify(lines))
  }
  return shown
}
const tabRows = (lines) => lines.filter((l) => HAS_BUTTON.test(l)).length

// One drawing of the pane, read: its lines, the head's lines, the names, the rows the tabs take, the portrait.
async function drawn(h, columns, rows, where) {
  const tree = rows ? await dock(h, columns, rows) : await inline(h, columns)
  const lines = screen(tree, columns)
  assert.ok(!lines.some((l) => /could not draw/.test(l)), where + ': ' + lines.join('\n'))
  const { head, body, image } = parts(tree, where)
  const headLines = screen(head, columns)
  const shown = names(headLines, where)
  assert.ok(widest(screen(head, Infinity)) <= columns, where + ': the head is ' + widest(screen(head, Infinity)) + ' wide in ' + columns + ' columns')
  if (image) {
    assert.equal(image.props.columns, 6, where + ': the portrait is not 6 columns wide')
    assert.equal(image.props.alt, 'VBW', where + ": the portrait's text is not 'VBW'")
    for (const l of headLines.slice(0, image.props.rows)) assert.ok(l.startsWith(PORTRAIT), where + ': the portrait is squeezed: "' + l + '"')
  }
  return { tree, lines, head, body, image, headLines, shown, rows: tabRows(headLines) }
}

test("the stand-in draws a Button without a hotkey as '[ Name ]', and one with a hotkey as '[k] Name': the same 4 cells of chrome", () => {
  const Button = EL('Button')
  assert.deepEqual(screen(h(Button, { label: 'Now' })), ['[ Now ]'])
  assert.deepEqual(screen(h(Button, { label: 'Timeline' })), ['[ Timeline ]'])
  assert.deepEqual(screen(h(Button, { label: 'Now', hotkey: 'p' })), ['[p] Now'])
  assert.equal(widest(screen(h(Button, { label: 'Now' }))), widest(screen(h(Button, { label: 'Now', hotkey: 'p' }))))
  assert.equal(widest(screen(h(Button, { label: 'Timeline' }))), 'Timeline'.length + 4)
})

test("the pane's width model names a button's chrome (4 cells) and the gap between tabs (1 cell) as constants", () => {
  const src = readFileSync(PLUGIN + '/hooks/panel-pane.js', 'utf8')
  assert.match(src, /\bBUTTON_CHROME\s*=\s*4\b/, 'no BUTTON_CHROME = 4 in panel-pane.js')
  assert.match(src, /\bTAB_GAP\s*=\s*1\b/, 'no TAB_GAP = 1 in panel-pane.js')
})

test('on every tab at 100, 64, 60, 50 and 40 body columns each of the eight names is whole on one line, no row is wider than the pane, and the head is clipped as drawn', async () => {
  const h = await opened()
  for (const [id] of TABS) {
    await h.press('tab-' + id)
    for (const columns of WIDTHS) {
      const where = id + ' at ' + columns + ' columns'
      const d = await drawn(h, columns, 30, where)
      assert.ok(d.lines.length <= 30, where + ': ' + d.lines.length + ' rows of 30')
      assert.ok(d.body, where + ': no clipped body')
      assert.equal(d.headLines.length, 30 - d.body.props.height, where + ': the head draws ' + d.headLines.length + ' rows but the body is clipped as if it took ' + (30 - d.body.props.height))
    }
  }
  assert.deepEqual(h.errors, [])
})

test('the layout with the fewest rows wins: at 90 or more body columns the eight full names sit on one row; the portrait stays from 91, where it fits beside them', async () => {
  const h = await opened()
  for (const columns of [120, 100, 91]) {
    const d = await drawn(h, columns, 30, columns + ' columns')
    assert.deepEqual(d.shown, FULL, columns + ' columns: ' + JSON.stringify(d.headLines))
    assert.equal(d.rows, 1, columns + ' columns: the tabs take ' + d.rows + ' rows')
    assert.ok(d.image, columns + ' columns: no portrait, though it fits beside the full names')
  }
  for (const columns of [90, 85]) {
    const d = await drawn(h, columns, 30, columns + ' columns')
    assert.deepEqual(d.shown, FULL, columns + ' columns: ' + JSON.stringify(d.headLines))
    assert.equal(d.rows, 1, columns + ' columns: the tabs take ' + d.rows + ' rows')
    assert.ok(!d.image, columns + ' columns: the portrait is kept though it would cost the full names a row')
  }
})

test('at about 64 body columns the full names sit on two rows beside the portrait: at an equal number of rows the full names win over the short ones', async () => {
  const h = await opened()
  for (const columns of [69, 64, 60, 54]) {
    const d = await drawn(h, columns, 30, columns + ' columns')
    assert.deepEqual(d.shown, FULL, columns + ' columns: ' + JSON.stringify(d.headLines))
    assert.equal(d.rows, 2, columns + ' columns: the tabs take ' + d.rows + ' rows')
    assert.ok(d.image, columns + ' columns: no portrait, though it costs the tabs nothing')
  }
})

test('the portrait is left out when keeping it would force the short names: at 50 body columns the full names sit on two rows with no portrait', async () => {
  const h = await opened()
  for (const columns of [50, 45]) {
    const d = await drawn(h, columns, 30, columns + ' columns')
    assert.deepEqual(d.shown, FULL, columns + ' columns: ' + JSON.stringify(d.headLines))
    assert.equal(d.rows, 2, columns + ' columns: the tabs take ' + d.rows + ' rows')
    assert.ok(!d.image, columns + ' columns: the portrait is kept though the full names fit on two rows only without it')
  }
})

test('at 40 body columns the short names sit on two rows and the portrait is left out (beside it they would take three); at 44 it stays beside them', async () => {
  const h = await opened()
  const narrow = await drawn(h, 40, 30, '40 columns')
  assert.deepEqual(narrow.shown, SHORT, '40 columns: ' + JSON.stringify(narrow.headLines))
  assert.equal(narrow.rows, 2, '40 columns: the tabs take ' + narrow.rows + ' rows')
  assert.ok(!narrow.image, '40 columns: the portrait is kept though it costs the tabs a row')
  const mid = await drawn(h, 44, 30, '44 columns')
  assert.deepEqual(mid.shown, SHORT, '44 columns: ' + JSON.stringify(mid.headLines))
  assert.equal(mid.rows, 2, '44 columns: the tabs take ' + mid.rows + ' rows')
  assert.ok(mid.image, '44 columns: no portrait, though it costs the tabs nothing')
})

test('the portrait is left out when the pane is short, at any width, and the names stay whole', async () => {
  const h = await opened()
  for (const columns of [100, 64]) {
    const d = await drawn(h, columns, 6, columns + ' columns, 6 rows')
    assert.ok(!d.image, columns + ' columns, 6 rows: the portrait is drawn in a short pane')
    assert.ok(d.lines.length <= 6, columns + ' columns, 6 rows: ' + d.lines.length + ' rows')
  }
})

test('on every tab the pane draws no more rows than Claude Code reports, the head counted as the portrait rows or the tab rows plus the gap, at 22, 8, 6 and 4 rows', async () => {
  const h = await opened()
  for (const [id] of TABS) {
    await h.press('tab-' + id)
    for (const columns of [64, 40]) {
      for (const rows of [22, 8, 6, 4]) {
        const where = id + ' at ' + columns + 'x' + rows
        const d = await drawn(h, columns, rows, where)
        assert.ok(d.lines.length <= rows, where + ': ' + d.lines.length + ' rows')
        assert.ok(d.body, where + ': no clipped body')
        assert.equal(d.headLines.length, rows - d.body.props.height, where + ': the head draws ' + d.headLines.length + ' rows but the body is clipped as if it took ' + (rows - d.body.props.height))
        const base = Math.max(d.image ? d.image.props.rows : 0, d.rows)
        assert.ok(d.headLines.length === base || d.headLines.length === base + 1, where + ': the head is not the portrait rows or the tab rows, whichever is more, plus at most the gap: ' + JSON.stringify(d.headLines))
      }
    }
  }
  assert.deepEqual(h.errors, [])
})

test("with no height reported the head counts the same way and the pane still ends with '+N more · open Mission Control' within its fixed height", async () => {
  const h = await opened()
  for (const id of ['decisions', 'plan']) {
    await h.press('tab-' + id)
    for (const columns of [80, 40]) {
      const where = id + ' inline at ' + columns + ' columns'
      const d = await drawn(h, columns, 0, where)
      assert.equal(d.lines.length, FIXED_ROWS, where + ': ' + d.lines.length + ' rows')
      assert.match(d.lines[d.lines.length - 1].trim(), MORE, where + ': the last line is not the fold: ' + d.lines[d.lines.length - 1])
      assert.ok(d.body, where + ': no clipped body')
      assert.equal(d.headLines.length, FIXED_ROWS - 1 - d.body.props.height, where + ': the head draws ' + d.headLines.length + ' rows but the body is clipped as if it took ' + (FIXED_ROWS - 1 - d.body.props.height))
    }
  }
  assert.deepEqual(h.errors, [])
})

test('a pane 1 or 2 rows high draws no more rows than Claude Code reports, on every tab, at 40, 64 and 100 columns', async () => {
  const h = await opened()
  for (const [id] of TABS) {
    await h.press('tab-' + id)
    for (const columns of [40, 64, 100]) {
      for (const rows of [1, 2]) {
        const lines = screen(await dock(h, columns, rows), columns)
        assert.ok(lines.length <= rows, id + ' at ' + columns + ' columns, ' + rows + ' rows: drew ' + lines.length)
      }
    }
  }
  assert.deepEqual(h.errors, [])
})
