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

test('the Now tab keeps the run\'s refusals as amber sentences with their time, whole on one line', async () => {
  const { h, at } = await building([{ n: 'P142.1', state: 'working' }])
  report(h, at, [SAID], true)
  await h.advance(TICK)
  const pane = await h.render()
  const texts = []
  walk(pane, (n) => { if (n.type === 'Text' && /VBW refused,/.test(textOf(n))) texts.push(n) })
  assert.equal(texts.length, 1)
  assert.equal(textOf(texts[0]), '[' + hhmm(at) + '] ⊘ VBW refused, dev P142.1: ' + SAID.replace('\n', ' '))
  assert.equal(texts[0].props.color, P.NEED)
})
