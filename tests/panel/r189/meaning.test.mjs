// R189, phase P145 (evidence level L1): one colour per meaning (D407). Each
// helper role has its own colour, from a set without green, red, amber or grey,
// and is written as a word; green means only done, red only failed, amber only
// needs you or running, grey only idle or quiet, the same on Comms, in Mission
// Control and in VBW Wrapped. A helper that overruns its estimate is amber,
// never red. Every state has its glyph beside its colour. The palette tests that
// pinned R84's old role colours were rewritten to the D407 rule.
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze, find, walk } from '../helpers/fake-mod.mjs'
import { TICK, writeCrew, working, building } from './helpers/crew.mjs'
import { textOf } from './helpers/screen.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)
const candy = await import(pathToFileURL(PLUGIN + '/hooks/panel-candy.js').href)
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000
const GLYPHS = /[●✓✗…■⚑]/

// Hue (0-360) and saturation (0-1) of a palette colour, as its pixel value.
function hsl(color) {
  const n = P.rgb(color)
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((x) => x / 255)
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const l = (max + min) / 2
  const d = max - min
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1))
  let hue = 0
  if (d) hue = max === r ? 60 * (((g - b) / d) % 6) : max === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4)
  return { hue: (hue + 360) % 360, sat: s }
}
const kind = (color) => {
  const { hue, sat } = hsl(color)
  if (sat < 0.25) return 'grey'
  if (hue >= 345 || hue < 15) return 'red'
  if (hue >= 30 && hue < 70) return 'amber'
  if (hue >= 80 && hue < 160) return 'green'
  return 'other'
}

test('each helper role has its own colour, from a set without green, red, amber or grey', () => {
  const colours = ROLES.map((r) => P.roleColor(r))
  assert.equal(new Set(colours.map((c) => P.rgb(c))).size, ROLES.length, 'two roles share a colour')
  const states = new Set([...Object.values(P.STATE_COLORS), P.NEED, P.PROGRESS, P.NEUTRAL].map((c) => P.rgb(c)))
  for (const role of ROLES) {
    const c = P.roleColor(role)
    assert.ok(!states.has(P.rgb(c)), role + ' wears a state colour: ' + c)
    assert.equal(kind(c), 'other', role + ' is ' + kind(c) + ' (' + c + ')')
  }
})

test('the states keep one meaning each: green done, red failed, amber running and needs you, grey quiet and cut off', () => {
  assert.equal(kind(P.stateColor('done')), 'green')
  assert.equal(kind(P.stateColor('failed')), 'red')
  assert.equal(kind(P.stateColor('running')), 'amber')
  assert.equal(P.NEED, P.stateColor('running'), 'needs you is the same amber as running')
  assert.equal(kind(P.stateColor('quiet')), 'grey')
  assert.equal(kind(P.stateColor('cut')), 'grey')
  assert.equal(kind(P.NEUTRAL), 'grey')
})

test('on Comms a working helper is an amber glyph, its role a word in the role colour; a failed one keeps red', async () => {
  const crew = working(2)
  const { h, at } = await building(crew, { profile: 'balanced', motion: 'calm' })
  writeCrew(h, at, [{ n: 'P142.1', state: 'working' }, { n: 'P142.2', state: 'failed' }])
  await h.advance(TICK)
  const tree = await h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100 })
  const rowOf = (step) => find(tree, (n) => n.type === 'Box' && n.props.flexDirection !== 'column' && textOf(n).includes(step))
  const texts = (node) => { const out = []; walk(node, (n) => { if (n.type === 'Text') out.push(n) }); return out }
  const w = texts(rowOf('P142.1'))
  assert.equal(w.find((t) => textOf(t).includes('●')).props.color, P.stateColor('running'), 'the working glyph is amber')
  assert.equal(w.find((t) => textOf(t).trim() === 'dev').props.color, P.roleColor('dev'), 'the role is a word in its colour')
  const f = texts(rowOf('P142.2'))
  assert.equal(f.find((t) => textOf(t).includes('✗')).props.color, P.stateColor('failed'))
})

test('every state colour on Comms and on the Mission Control crew rows sits beside its glyph', async () => {
  const crew = working(3)
  const { h, at } = await building(crew, { profile: 'balanced', motion: 'calm' })
  writeCrew(h, at, [{ n: 'P142.1', state: 'working' }, { n: 'P142.2', state: 'failed' }, { n: 'P142.3', state: 'done' }])
  await h.advance(TICK)
  const meaning = new Set([P.stateColor('done'), P.stateColor('failed'), P.stateColor('running'), P.NEED])
  const comms = await h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100 })
  const pane = await h.render()
  const rowsOf = (tree) => {
    const out = []
    walk(tree, (n) => {
      if (n.type === 'Box' && (n.props.borderStyle || (n.props.flexDirection !== 'column' && !n.children.some((c) => c.type === 'Box')))) out.push(n)
    })
    return out
  }
  let checked = 0
  const crewRows = []
  walk(pane, (n) => { if (n.type === 'Box' && String(n.props.key).startsWith('crew:')) crewRows.push(n) })
  assert.ok(crewRows.length >= 2, 'the crew rows are drawn')
  for (const r of [...rowsOf(comms), ...crewRows]) {
    let coloured = false
    walk(r, (n) => { if (n.type === 'Text' && meaning.has(n.props.color)) coloured = true })
    if (!coloured) continue
    checked++
    assert.match(textOf(r), GLYPHS, 'a state colour without its glyph: ' + textOf(r))
  }
  assert.ok(checked >= 3, 'state colours were found to check: ' + checked)
})

test('a helper that overruns its estimate is drawn amber on the Timeline, never red', () => {
  const agent = (i, secs) => ({ id: 'a' + i, role: ROLES[i % ROLES.length], label: 'P1.' + i, state: 'working', activity: null, startedAt: NOW - secs * S, endedAt: null, lastSeenAt: NOW - S, tokens: 10, result: null })
  const run = deepFreeze({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 4000 * S, endedAt: null, status: 'running', agents: [agent(0, 3900), agent(1, 3000), agent(2, 2000), agent(3, 100), agent(4, 50)] })
  const model = live.timelineModel({ run, now: NOW, steps: [], width: 40 })
  assert.ok(model.lanes.some((l) => l.slow), 'the slowest lanes are marked')
  const tree = live.renderTimeline(UI, model)
  walk(tree, (n) => { if (n.type === 'Text') assert.notEqual(n.props.color, P.stateColor('failed'), 'red on the Timeline without a failure: ' + textOf(n)) })
  let amber = 0
  walk(tree, (n) => { if (n.type === 'Text' && n.props.color === P.stateColor('running')) amber++ })
  assert.ok(amber >= 1, 'the overrunning lanes are amber')
})

test('VBW Wrapped keeps green for done only and draws no amber or red', () => {
  const tree = candy.renderWrapped(UI, { milestone: { id: 'M9', title: 'Live VBW panel' }, requirements: { proven: 2, total: 2 }, checks: { passing: 3, total: 3 }, agents: 4, fixRounds: 1, seconds: 600, cost: 1.5, fastest: null, slowest: null })
  walk(tree, (n) => {
    for (const k of ['color', 'borderColor']) {
      if (n.props && n.props[k] !== undefined) assert.ok(![P.stateColor('failed'), P.stateColor('running'), P.NEED].includes(n.props[k]), k + ' ' + n.props[k])
    }
  })
})

test("the palette tests that pinned R84's old role colours are rewritten to the D407 rule, naming D407", () => {
  const src = fs.readFileSync(new URL('../palette.test.mjs', import.meta.url), 'utf8')
  assert.match(src, /D407/)
  assert.doesNotMatch(src, /dev:\s*'green'|qa:\s*'yellow'|debugger:\s*'red'/, 'the old role colours are still pinned')
})

test('red is drawn only for a failure: the weekly limit and the other Comms and Mission Control text never use the failed colour without one', async () => {
  const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)
  const red = (tree, where) => walk(tree, (n) => {
    for (const k of ['color', 'borderColor']) if (n.props && n.props[k] === P.stateColor('failed')) assert.fail(where + ': red without a failure: ' + textOf(n))
  })
  const need = { key: 'approve', what: 'the plan is ready: review it, then approve it to build', at: NOW - 90 * S }
  for (const weekPct of [80, 95]) {
    const gate = { action: 'approve', gate: true }
    const m = stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'full', need, next: gate, health: { contextPct: 95, weekPct, weekPerRun: 6 } })
    const line = m.lines.find((l) => /Weekly limit/.test(l.text))
    assert.equal(line.color, P.NEED, 'the weekly limit at ' + weekPct + '% is amber')
    red(stage.renderStage(UI, m), 'Comms need at ' + weekPct + '%')
    const alone = stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'full', next: { action: 'build' }, health: { contextPct: 95, weekPct } })
    red(stage.renderStage(UI, alone), 'Comms nudge at ' + weekPct + '%')
  }
  const { h, at } = await building(working(2), { profile: 'balanced', motion: 'calm' })
  writeCrew(h, at, working(2))
  await h.advance(TICK)
  red(await h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100 }), 'Comms crew')
  red(await h.render(), 'Mission Control')
})
