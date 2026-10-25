// 6.3, refusals visible to the person (docs/panel.md, Refusals; evidence level
// L1, the stand-in for Claude Code's mods API, with a VBW workflow run written as
// Claude Code writes it): a refusal an agent reported in its result (the
// workflow schema's `refused`) shows on Comms as one amber line with its time,
// 'HH:MM ⊘ VBW refused · <agent>: <first line>', and stays, after the run too,
// until the Now tab of Mission Control is shown; a later refusal shows again.
// The Now tab keeps the run's refusals as amber sentences, each whole on one line.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { find, walk, PLUGIN, ROOT } from './helpers/fake-mod.mjs'
import { line, usage, jsonl } from './helpers/feed-fs.mjs'
import { RUN_DIR, FINAL } from './helpers/run.mjs'
import { TICK, building, agentId } from './r189/helpers/crew.mjs'
import { screen, textOf, hhmm } from './r189/helpers/screen.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const SAID = 'vbw: apply refused: plan P142.1 is started\nNext: put it back as the record has it (vbw show plan P142.1)'
const LINE = /^(\d\d:\d\d) ⊘ VBW refused · dev P142\.1: vbw: apply refused: plan P142\.1 is started$/

const commsTree = (h) => h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100 })
const refusalLines = async (h) => screen(await commsTree(h), 100).filter((l) => /refused/.test(l))

// The crew of one Dev, P142.1, whose result reports the given refusals; ended when `end`.
function report(h, at, refused, end = false) {
  const c = { n: 'P142.1' }
  h.write(RUN_DIR + '/journal.jsonl', jsonl([
    { type: 'launched' },
    { type: 'started', agentId: agentId(c), label: 'dev P142.1', phase: 'Build' },
    { type: 'result', agentId: agentId(c), result: { status: 'done', summary: 'P142.1 done', notes: [], refused } },
  ]))
  h.write(RUN_DIR + '/agent-' + agentId(c) + '.jsonl', jsonl([line.user(at - 5000), line.tool(at, 'Edit', { file_path: ROOT + '/src/a.js' }, usage(10, 20000, 100))]))
  if (end) h.write(FINAL, { workflowName: 'building', status: 'completed', startTime: at - 5000, durationMs: 6000, phases: [{ title: 'Build' }] })
}

async function showNow(h) {
  const tab = find(await h.render(), (n) => n.type === 'Button' && n.props.label === 'Now')
  assert.ok(tab, 'Mission Control has a Now tab')
  await tab.props.onPress({ surface: 'terminal' })
  await h.settle()
  await h.advance(TICK)
}

test('a refusal an agent reported is one amber Comms line with its time, and stays after the run until the Now tab is shown', async () => {
  const { h, at } = await building([{ n: 'P142.1', state: 'working' }])
  assert.deepEqual(await refusalLines(h), [], 'no refusal yet')
  report(h, at, [SAID])
  await h.advance(TICK)
  const [l] = await refusalLines(h)
  assert.match(l || '', LINE)
  assert.equal(LINE.exec(l)[1], hhmm(at), 'timed when the agent reported it')
  const node = find(await commsTree(h), (n) => n.type === 'Text' && /⊘ VBW refused/.test(textOf(n)))
  assert.equal(node.props.color, P.NEED, 'amber, never red')
  report(h, at, [SAID], true)
  await h.advance(TICK)
  assert.equal((await refusalLines(h)).length, 1, 'the run ended and the refusal is still on Comms')
  await showNow(h)
  assert.deepEqual(await refusalLines(h), [], 'seen on the Now tab, it leaves Comms')
  report(h, at + TICK, [SAID, 'vbw: run end refused: run build-1 is not open\nNext: run vbw status'], true)
  await h.advance(TICK)
  assert.match((await refusalLines(h))[0] || '', /VBW refused · dev P142\.1: vbw: run end refused/, 'a later refusal shows again')
})

test('the Now tab keeps the run\'s refusals as short amber rows with their time; the whole text opens in place on a press', async () => {
  const { h, at } = await building([{ n: 'P142.1', state: 'working' }])
  report(h, at, [SAID], true)
  await h.advance(TICK)
  const pane = await h.render()
  const texts = []
  walk(pane, (n) => { if (n.type === 'Text' && /VBW refused,/.test(textOf(n))) texts.push(n) })
  assert.equal(texts.length, 1)
  assert.equal(textOf(texts[0]), '[' + hhmm(at) + '] ⊘ VBW refused, dev P142.1: ' + SAID.split('\n')[0])
  assert.equal(texts[0].props.color, P.NEED)
  let show = null
  walk(pane, (n) => { if (n.type === 'Button' && /^show:refused:/.test(String(n.props.key))) show = n })
  assert.ok(show, 'no show button for the whole text')
  await show.props.onPress({ surface: 'terminal' })
  await h.settle()
  const open = []
  walk(await h.render(), (n) => { if (n.type === 'Text' && textOf(n) === SAID.replace('\n', ' ')) open.push(n) })
  assert.equal(open.length, 1, 'the whole text, on one line, under the row')
})

// B3 (2.1.11): a refusal line is short. A guard refusal names the run's whole file
// list in its sentence; the line keeps the first clause, says how many files the run
// has, and shows the whole text on a press. Comms shows the first clause only.
const L = await import(pathToFileURL(PLUGIN + '/hooks/panel-lines.js').href)
const V = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)
const NINE = ['a.js', 'b.js', 'c.js', 'd.js', 'e.js', 'f.js', 'g.js', 'h.js', 'i.js']
const GUARD = "src/x.js is outside this run's files (" + NINE.join(', ') + "): agents write only their plan's files\nNext: leave src/x.js as it is; report that the plan needs it, so the plan can be replanned with vbw apply"
const AT = new Date(2026, 9, 24, 15, 41).getTime()
const NOW_B3 = new Date(2026, 9, 24, 15, 50).getTime()
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

test('a guard refusal row is its first clause and the count of the run\'s files; the whole text waits for a press', () => {
  const r = V.refusalRow({ id: 'a1#0', by: 'dev P5.2', at: AT, text: GUARD }, NOW_B3)
  assert.deepEqual(r, {
    id: 'refused:a1#0', term: 'refused', files: 9, more: '· 9 files in this run',
    text: '[' + hhmm(AT) + "] ⊘ VBW refused, dev P5.2: src/x.js is outside this run's files",
    full: GUARD.split('\n').join(' '),
  })
  for (const f of NINE) assert.ok(!r.text.includes(f), 'no file of the list in the line: ' + f)
  assert.equal(L.refusalLine({ by: 'dev P5.2', text: GUARD }), "⊘ VBW refused · dev P5.2: src/x.js is outside this run's files", 'Comms: the first clause only')
})

test('a kernel refusal keeps its first line whole; its Next: line waits for a press; a day not today is named', () => {
  const r = V.refusalRow({ id: 'a1#1', by: 'dev P142.1', at: AT - 86400000, text: SAID }, NOW_B3)
  assert.equal(r.text, '[yesterday ' + hhmm(AT) + '] ⊘ VBW refused, dev P142.1: vbw: apply refused: plan P142.1 is started')
  assert.equal(r.files, 0)
  assert.equal(r.more, null)
  assert.equal(r.full, SAID.split('\n').join(' '))
  assert.equal(V.refusalRow({ id: 'x', text: 'one line only' }, NOW_B3).full, null, 'nothing more to show')
  for (const bad of [null, 'x', {}, { text: '  ' }]) assert.equal(V.refusalRow(bad, NOW_B3), null)
})

test('the refusal row draws amber with "· N files in this run [ show ]"; a press asks to open it, open it shows the whole text', () => {
  const row = V.refusalRow({ id: 'a1#0', by: 'dev P5.2', at: AT, text: GUARD }, NOW_B3)
  const acts = []
  const shut = live.renderRefusal(UI, row, false, (a) => acts.push(a))
  const words = screen(shut, 140).filter((l) => l.trim()) // the row keeps one blank row under it, as every Now sentence does
  assert.equal(words.length, 2, words.join('\n'))
  assert.match(words[0], /^\[\d\d:\d\d\] ⊘ VBW refused, dev P5\.2: src\/x\.js is outside this run's files · 9 files in this run \[ show \]$/)
  assert.equal(words[1], 'refused')
  assert.equal(find(shut, (n) => n.type === 'Text' && textOf(n).startsWith('[')).props.color, P.NEED)
  find(shut, (n) => n.type === 'Button').props.onPress({ surface: 'terminal' })
  assert.deepEqual(acts, [{ toggle: 'refused:a1#0' }])
  const open = screen(live.renderRefusal(UI, row, true, () => {}), 400)
  assert.ok(open.some((l) => l.includes(GUARD.split('\n').join(' '))), open.join('\n'))
  assert.ok(open.some((l) => /\[ hide \]/.test(l)))
  const plain = screen(live.renderRefusal(UI, V.refusalRow({ id: 'x', at: AT, text: 'one line only' }, NOW_B3), false, () => {}), 140)
  assert.ok(!plain.some((l) => /show/.test(l)), 'no button when there is nothing more')
})
