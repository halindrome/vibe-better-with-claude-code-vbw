// R190, phase P146 (evidence level L1, the stand-in for Claude Code's mods API):
// the 9 October list's P3, checked on the panel as it shipped in M34. The first
// thing under Mission Control's tab row is the 'what's happening now' box, in
// every state VBW can be in (planning, building a phase, proving, checking,
// waiting for you, nothing running), with or without a What's next pick and a
// working crew. What the box says in each state and how fast it follows a
// change are R189's checks (tests/panel/r189/now-box.test.mjs), which R190 runs
// as its own check; this file adds only where the box stands.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { screen } from '../r189/helpers/screen.mjs'
import { writeCrew, working, building } from '../r189/helpers/crew.mjs'

const S = 1000
const WIDTH = 60
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const PLANS = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]
const PICK = { at: iso(T0 - 600 * S), top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most.', size: 'small', source: 'T4' }, runners: [] }
const TABS = /\bNow\b.*\bPlan\b/
// The portrait beside the tabs (an Image, drawn as ▓ by the screen model) belongs to the head.
const PORTRAIT = /^▓+$/

async function session(rec, nx, files = {}) {
  const h = await mount({ files })
  h.git()
  h.project(rec, nx)
  await h.start()
  await h.advance(4000)
  return h
}

const pane = (h, bodyRows = 80) => h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: WIDTH, placement: 'dock', scroll: { offset: 0, bodyRows }, view: {} } })

// The lines under the tab row, blank lines and the rest of the portrait beside it dropped:
// the first must be the box's top edge and the next its state sentence.
async function underTabs(h, bodyRows) {
  const lines = screen(await pane(h, bodyRows), WIDTH)
  const at = lines.findIndex((l) => TABS.test(l))
  assert.ok(at >= 0, 'no tab row:\n' + lines.join('\n'))
  return lines.slice(at + 1).filter((l) => l.trim() !== '' && !PORTRAIT.test(l.trim()))
}

const STATES = [
  ['planning', () => [record({ lease: lease('plan', T0) }), next({ action: 'run' }), {}], /planning/i],
  ['building', () => [record({ lease: lease('build', T0), plans: PLANS }), next({ action: 'run' }), {}], /building.*P44/i],
  ['proving', () => [record(), next({ action: 'prove' }), { [ROOT + '/.vbw/runtime/proving.sess-1']: '4242\n' }], /proving/i],
  ['checking', () => [record({ lease: lease('qa', T0) }), next({ action: 'run' }), {}], /checking/i],
  ['waiting for you', () => [record(), next({ action: 'approve', gate: true }), {}], /waiting for you/i],
  ['nothing running', () => [record(), next(), {}], /nothing (is )?running/i],
]

test('in every state the first thing under the tab row is the box, its first line the state sentence', async () => {
  for (const [name, make, state] of STATES) {
    const [rec, nx, files] = make()
    const lines = await underTabs(await session(rec, nx, files))
    assert.match(lines[0], /^╭─+╮$/, name + ': the first thing under the tabs is not the box:\n' + lines.slice(0, 4).join('\n'))
    assert.match(lines[1], /^│/, name)
    assert.match(lines[1], state, name + ': the box opens on the state sentence: ' + lines[1])
  }
})

test("a What's next pick never comes between the tab row and the box", async () => {
  for (const [name, make] of STATES) {
    const [rec, nx, files] = make()
    const lines = await underTabs(await session({ ...rec, recommendation: PICK }, nx, files))
    assert.match(lines[0], /^╭─+╮$/, name + ': ' + lines.slice(0, 3).join(' / '))
    const pick = lines.findIndex((l) => /Refunds for paid orders/.test(l))
    const end = lines.findIndex((l) => /^╰─+╯$/.test(l))
    assert.ok(pick > end && end > 0, name + ": the pick is not below the box:\n" + lines.join('\n'))
  }
})

test('with a crew at work the box still comes first, above the helper cards', async () => {
  const { h, at } = await building(working(3))
  writeCrew(h, at, working(3))
  const lines = await underTabs(h)
  assert.match(lines[0], /^╭─+╮$/, lines.slice(0, 3).join(' / '))
  assert.match(lines[1], /building/i)
  const card = lines.findIndex((l) => /P142\.1/.test(l))
  const end = lines.findIndex((l) => /^╰─+╯$/.test(l))
  assert.ok(card > end, 'a helper card is drawn above the box:\n' + lines.join('\n'))
})

test('in a short pane the box is still the first thing under the tab row', async () => {
  for (const rows of [12, 8]) {
    const lines = await underTabs(await session(record(), next()), rows)
    assert.match(lines[0], /^╭─+╮$/, rows + ' rows: ' + lines.slice(0, 3).join(' / '))
  }
})
