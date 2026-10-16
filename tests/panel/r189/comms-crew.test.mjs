// R189, phase P142 (evidence level L1, the stand-in for Claude Code's mods API,
// with a VBW workflow run written as Claude Code writes it): Comms' crew rows
// show only what is true now. A helper that finishes leaves at the next redraw
// (no 60-second hold) and is counted in the header's 'N done'; a failed one
// stays as a red '✗' row until the user opens it in Mission Control, never green
// or amber; the rows leave as soon as the run ends, and a working run is never
// drawn as ended nor an ended one as working. At full motion at most 3 working
// helpers are pixel figures (D405), the rest text rows; at calm or off every
// helper is one text row; rows beyond the room fold into one
// '+N more · [m] Mission Control' line. A row shows the role as a word and the
// step ('dev P142.1'), what the helper does and the time it started (HH:MM).
// Mission Control's cards change on the same redraw.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { find, walk, PLUGIN } from '../helpers/fake-mod.mjs'
import { TICK, writeCrew, endRun, working as steps, building } from './helpers/crew.mjs'
import { screen, textOf, hhmm } from './helpers/screen.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const FOLD = /^\+(\d+) more · \[m\] Mission Control$/

const commsTree = (h, props = {}) => h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100, ...props })
const commsLines = async (h, props = {}) => screen(await commsTree(h, props), props.bodyColumns || 100)
const rowsWith = (lines, step) => lines.filter((l) => l.includes(step))
// The row Box of a step in a tree: the first Box laid out as a row whose words name it.
const rowBox = (tree, step) => find(tree, (n) => n.type === 'Box' && n.props.flexDirection !== 'column' && textOf(n).includes(step))
const card = (tree, step) => find(tree, (n) => n.type === 'Button' && String(n.props.label).includes(step))

test('a helper that turns done leaves the crew rows at the next redraw, with no hold, and is counted in "N done"', async () => {
  const crew = steps(3)
  const { h, at } = await building(crew)
  assert.equal(rowsWith(await commsLines(h), 'P142.1').length, 1, 'the working helper has its row')
  writeCrew(h, at, crew.map((c) => (c.n === 'P142.1' ? { ...c, state: 'done' } : c)))
  await h.advance(TICK)
  const lines = await commsLines(h)
  assert.deepEqual(rowsWith(lines, 'P142.1'), [], 'the finished helper is still on Comms')
  assert.match(lines[0], /\b1 done\b/, "the header counts it: '" + lines[0] + "'")
  assert.equal(rowsWith(lines, 'P142.2').length, 1, 'the others stay')
  const pane = await h.render()
  const c = card(pane, 'P142.1')
  assert.ok(c, 'Mission Control still has its card')
  const box = find(pane, (n) => n.type === 'Box' && n.props.borderStyle && n.children.includes(c))
  assert.doesNotMatch(textOf(box || c), /running/, "Mission Control's card changed on the same redraw")
})

test('a failed helper stays as a red ✗ row, never green or amber, until it is opened in Mission Control, then it leaves', async () => {
  const crew = steps(3)
  const { h, at } = await building(crew)
  writeCrew(h, at, crew.map((c) => (c.n === 'P142.2' ? { ...c, state: 'failed' } : c)))
  await h.advance(TICK)
  for (const wait of [0, 90000]) {
    await h.advance(wait)
    const tree = await commsTree(h)
    const rows = rowsWith(screen(tree, 100), 'P142.2')
    assert.equal(rows.length, 1, 'the failed helper has one row after ' + wait + ' ms')
    assert.match(rows[0], /✗/)
    const row = rowBox(tree, 'P142.2')
    const glyph = []
    walk(row, (n) => {
      if (n.type !== 'Text') return
      if (textOf(n).includes('✗')) glyph.push(n)
      assert.ok(![P.stateColor('done'), P.stateColor('running'), P.NEED].includes(n.props.color), 'a failed row has no green or amber: ' + textOf(n) + ' ' + n.props.color)
    })
    assert.ok(glyph.length >= 1)
    for (const g of glyph) assert.equal(g.props.color, P.stateColor('failed'), 'the ✗ is red')
  }
  const c = card(await h.render(), 'P142.2')
  assert.ok(c, 'Mission Control shows the failed helper')
  await c.props.onPress({ surface: 'terminal' })
  await h.settle()
  await h.advance(TICK)
  assert.deepEqual(rowsWith(await commsLines(h), 'P142.2'), [], 'seen in Mission Control, it leaves Comms')
})

test('the crew rows leave Comms as soon as the run ends; a working run is never drawn as ended, an ended one never as working', async () => {
  const crew = steps(2)
  const { h, at } = await building(crew)
  const during = await commsLines(h)
  assert.ok(during.length >= 2, 'the crew is on Comms while the run works')
  assert.doesNotMatch(during.join('\n'), /\b(completed|ended|finished|stopped)\b/i, 'a working run drawn as ended')
  writeCrew(h, at, crew.map((c) => ({ ...c, state: 'done' })))
  endRun(h, at)
  await h.advance(TICK)
  assert.deepEqual(await commsLines(h), [], 'the ended run still has rows on Comms')
  const pane = await h.render()
  const words = []
  walk(pane, (n) => { if (n.type === 'Text') words.push(textOf(n)) })
  assert.ok(!words.some((t) => /● running|^\s*running\b|· running\b/.test(t)), 'Mission Control draws the ended run as working: ' + words.filter((t) => /running/.test(t)).join(' | '))
})

test("an unseen failed helper outlives the run's end, alone on Comms, until it is opened", async () => {
  const crew = steps(2)
  const { h, at } = await building(crew)
  writeCrew(h, at, [{ n: 'P142.1', state: 'done' }, { n: 'P142.2', state: 'failed' }])
  endRun(h, at)
  await h.advance(TICK)
  const lines = await commsLines(h)
  assert.equal(rowsWith(lines, 'P142.2').length, 1, 'the failure is still on Comms')
  assert.deepEqual(rowsWith(lines, 'P142.1'), [])
  assert.ok(!lines.some((l) => /●/.test(l)), 'nothing is drawn as working')
  const c = card(await h.render(), 'P142.2')
  await c.props.onPress({ surface: 'terminal' })
  await h.settle()
  await h.advance(TICK)
  assert.deepEqual(await commsLines(h), [])
})

test('at full motion at most 3 working helpers are pixel figures, the rest text rows; at calm or off every helper is one text row', async () => {
  for (const motion of ['full', 'calm', 'off']) {
    const { h } = await building(steps(5), { profile: 'balanced', motion })
    const tree = await commsTree(h, { maxRows: 30 })
    let rasters = 0
    walk(tree, (n) => { if (n.type === 'Raster') rasters++ })
    if (motion === 'full') assert.equal(rasters, 3, 'full motion draws exactly 3 figures for 5 working helpers')
    else assert.equal(rasters, 0, motion + ' draws no figure')
    const lines = screen(tree, 100)
    for (const c of steps(5)) assert.equal(rowsWith(lines, c.n).length, 1, motion + ': ' + c.n + ' is on one line')
  }
})

test("rows beyond the room Claude Code gives fold into one '+N more · [m] Mission Control' line", async () => {
  for (const [motion, maxRows] of [['calm', 6], ['calm', 4], ['full', 8]]) {
    const { h } = await building(steps(10), { profile: 'balanced', motion })
    const lines = await commsLines(h, { maxRows })
    const name = motion + ' in ' + maxRows + ' rows'
    assert.ok(lines.length <= maxRows, name + ': ' + lines.length + ' lines')
    const m = FOLD.exec(lines[lines.length - 1].trim())
    assert.ok(m, name + ": the last line is not the fold: '" + lines[lines.length - 1] + "'")
    const shown = steps(10).filter((c) => rowsWith(lines, c.n).length > 0).length
    assert.equal(shown + Number(m[1]), 10, name + ': ' + shown + ' shown and ' + m[1] + ' folded')
  }
})

test('each helper row shows its role as a word, its step, what it is doing and the time it started as HH:MM', async () => {
  const { h, at } = await building(steps(2))
  const row = rowsWith(await commsLines(h), 'P142.1')[0]
  assert.ok(row, 'no row for P142.1')
  assert.match(row, /\bdev\b.*P142\.1/, row)
  assert.match(row, /editing a\.js/, row)
  assert.ok(row.includes(hhmm(at - 5000)), "'" + row + "' lacks the start time " + hhmm(at - 5000))
})

test("a failed helper's details button on Comms counts as opening it in Mission Control: the row leaves at the next redraw", async () => {
  const crew = steps(2)
  const { h, at } = await building(crew)
  writeCrew(h, at, crew.map((c) => (c.n === 'P142.2' ? { ...c, state: 'failed' } : c)))
  await h.advance(TICK)
  const details = find(await commsTree(h), (n) => n.type === 'Button' && n.props.label === 'details')
  assert.ok(details, 'the failed row has its details button')
  await details.props.onPress({ surface: 'terminal' })
  await h.settle()
  await h.advance(TICK)
  assert.deepEqual(rowsWith(await commsLines(h), 'P142.2'), [], 'opened through details, it still stands on Comms')
  assert.equal(rowsWith(await commsLines(h), 'P142.1').length, 1, 'the working helper stays')
})

test('while the run works, Mission Control draws its working helpers as running, never as cut off or ended', async () => {
  const { h } = await building(steps(2))
  const words = []
  walk(await h.render(), (n) => { if (n.type === 'Text') words.push(textOf(n)) })
  assert.ok(words.some((t) => /running/.test(t)), 'a working helper is drawn as running: ' + words.join(' | '))
  assert.ok(!words.some((t) => /cut off|ended/.test(t)), 'a working run is drawn as ended: ' + words.join(' | '))
})

test('a card opened while its helper still works does not hide the later failure: Comms shows the red row until it is opened after the failure', async () => {
  const crew = steps(2)
  const { h, at } = await building(crew)
  const c = card(await h.render(), 'P142.2')
  assert.ok(c, 'Mission Control shows the working helper')
  await c.props.onPress({ surface: 'terminal' }) // selects the card while the helper works
  await h.settle()
  writeCrew(h, at, crew.map((x) => (x.n === 'P142.2' ? { ...x, state: 'failed' } : x)))
  await h.advance(TICK)
  const rows = rowsWith(await commsLines(h), 'P142.2')
  assert.equal(rows.length, 1, 'the failure was hidden by a selection made before it')
  assert.match(rows[0], /✗/)
  const again = card(await h.render(), 'P142.2')
  await again.props.onPress({ surface: 'terminal' })
  await h.settle()
  await h.advance(TICK)
  const after = rowsWith(await commsLines(h), 'P142.2')
  assert.deepEqual(after, [], 'opened after the failure, it leaves Comms')
})
