// R190, phase P146 (evidence level L1, the stand-in for Claude Code's mods API,
// with a VBW workflow run written as Claude Code writes it): the 9 October
// list's P5 as D405 and D420 replaced it. At full motion Comms draws a small
// pixel figure for at most 3 working helpers and every further helper is a
// one-line text row; at calm motion every helper is one text row with no
// figure; with motion off nothing moves (no figure, spinner, flash or frame:
// between redraws only the run's clock and the helpers' times change). Each
// setting with 1, 3, 4 and 6 working helpers.
import test from 'node:test'
import assert from 'node:assert/strict'
import { find, walk } from '../helpers/fake-mod.mjs'
import { TICK, writeCrew, working, building } from '../r189/helpers/crew.mjs'
import { screen, textOf } from '../r189/helpers/screen.mjs'

const COUNTS = [1, 3, 4, 6]
const comms = (h) => h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 30, bodyColumns: 100 })
// The row of a step: the Box laid out as a row whose words name it.
const rowOf = (tree, step) => find(tree, (n) => n.type === 'Box' && n.props.flexDirection !== 'column' && textOf(n).includes(step) && !n.children.some((c) => c && c.type === 'Box'))
const rasters = (tree) => {
  let n = 0
  walk(tree, (x) => { if (x.type === 'Raster') n++ })
  return n
}
const figureOf = (row) => row.children.some((c) => c && c.type === 'Raster')

test('full motion: a figure for at most 3 working helpers, every further helper one text row', async () => {
  for (const n of COUNTS) {
    const crew = working(n)
    const { h } = await building(crew, { profile: 'balanced', motion: 'full' })
    const tree = await comms(h)
    assert.equal(rasters(tree), Math.min(3, n), n + ' helpers: ' + rasters(tree) + ' figures')
    const figures = crew.filter((c) => figureOf(rowOf(tree, c.n)))
    assert.equal(figures.length, Math.min(3, n), n + ' helpers')
    for (const c of crew) {
      const row = rowOf(tree, c.n)
      assert.ok(row, n + ' helpers: no row for ' + c.n)
      if (!figureOf(row)) assert.equal(screen(row, 100).length, 1, n + ' helpers: ' + c.n + ' is not one line: ' + JSON.stringify(screen(row, 100)))
    }
    assert.deepEqual(h.errors, [])
  }
})

test('calm motion: every helper is one text row, with no figure', async () => {
  for (const n of COUNTS) {
    const crew = working(n)
    const { h } = await building(crew, { profile: 'balanced', motion: 'calm' })
    const tree = await comms(h)
    assert.equal(rasters(tree), 0, n + ' helpers: calm draws a figure')
    for (const c of crew) {
      const row = rowOf(tree, c.n)
      assert.ok(row, n + ' helpers: no row for ' + c.n)
      assert.equal(screen(row, 100).length, 1, n + ' helpers: ' + c.n + ' is not one line')
    }
    const lines = screen(tree, 100)
    for (const c of crew) assert.equal(lines.filter((l) => l.includes(c.n)).length, 1, n + ' helpers: ' + c.n)
  }
})

test('motion off: one text row per helper, and nothing moves between redraws', async () => {
  for (const n of COUNTS) {
    const crew = working(n)
    const { h, at } = await building(crew, { profile: 'balanced', motion: 'off' })
    const blits = h.count('ui.blit')
    const still = (tree) => screen(tree, 100).map((l) => l.replace(/\d+/g, '#')).join('\n')
    const first = await comms(h)
    assert.equal(rasters(first), 0, n + ' helpers: off draws a figure')
    for (const c of crew) assert.equal(screen(rowOf(first, c.n), 100).length, 1, n + ' helpers: ' + c.n)
    const frames = [still(first)]
    for (let i = 0; i < 6; i++) {
      await h.advance(TICK / 4)
      writeCrew(h, at, crew)
      const tree = await comms(h)
      walk(tree, (x) => assert.ok(!(x.props && x.props.inverse), n + ' helpers: a row flashes with motion off'))
      frames.push(still(tree))
    }
    for (const f of frames) assert.equal(f, frames[0], n + ' helpers: Comms moved with motion off')
    assert.equal(h.count('ui.blit'), blits, n + ' helpers: a frame was blitted with motion off')
  }
})

test('the settings differ where they should: calm still turns its spinner, full blits its figures, off does neither', async () => {
  const spins = async (motion) => {
    const { h } = await building(working(4), { profile: 'balanced', motion })
    const marks = new Set()
    for (let i = 0; i < 4; i++) {
      marks.add(screen(await comms(h), 100).filter((l) => l.includes('P142.4')).join().replace(/\d+/g, '#'))
      await h.advance(1000)
    }
    return { marks: marks.size, blits: h.count('ui.blit') }
  }
  const calm = await spins('calm')
  const off = await spins('off')
  const full = await spins('full')
  assert.ok(calm.marks > 1, 'calm motion does not turn its spinner')
  assert.equal(calm.blits, 0, 'calm motion blits a figure')
  assert.equal(off.marks, 1, 'motion off moves')
  assert.ok(full.blits > 0, 'full motion never moves its figures')
})
