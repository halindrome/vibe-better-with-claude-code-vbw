// R191, phase P151 (evidence level L1): with one fixed note and next.json, the status
// line, Comms and Mission Control show the identical HH:MM for the running step, and
// the milestone's end (the kernel's road) shows in Mission Control only (D435): the
// status line keeps the step's clock time alone, and Comms the step's sentence. The
// real status line script runs on a small project in a scratch folder (its own HOME);
// Comms and Mission Control are their pure models (panel-stage.js, panel-view.js) at
// the same moment. Times are local to Europe/Zurich (UTC+01:00, +02:00 in summer).
import test from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { record, next, collect, PLUGIN } from '../helpers/fake-mod.mjs'
import { hhmm } from '../r189/helpers/screen.mjs'

process.env.TZ = 'Europe/Zurich'

const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)

const S = 1000
const MIN = 60 * S
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const CLOCKS = /until (?:around )?(?:tomorrow )?(\d\d:\d\d)/g
const times = (text) => [...String(text).matchAll(CLOCKS)].map((m) => m[1])

function project(rec, note, nx) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vbw-r191-'))
  fs.mkdirSync(path.join(dir, '.vbw/runtime'), { recursive: true })
  fs.mkdirSync(path.join(dir, '.git'), { recursive: true })
  fs.mkdirSync(path.join(dir, 'home/.claude'), { recursive: true })
  fs.writeFileSync(path.join(dir, '.git/HEAD'), 'ref: refs/heads/main\n')
  fs.writeFileSync(path.join(dir, '.vbw/record.json'), JSON.stringify(rec))
  fs.writeFileSync(path.join(dir, '.vbw/runtime/step.json'), JSON.stringify(note))
  fs.writeFileSync(path.join(dir, '.vbw/runtime/next.json'), JSON.stringify(nx))
  return dir
}

function statusLine(dir) {
  const input = JSON.stringify({ session_id: 'sess-1', workspace: { project_dir: dir, current_dir: dir }, version: '2.1.286' })
  const env = { PATH: process.env.PATH, HOME: path.join(dir, 'home'), CLAUDE_CONFIG_DIR: path.join(dir, 'home/.claude'), TZ: 'Europe/Zurich', NO_COLOR: '1' }
  return execFileSync('bash', [path.join(PLUGIN, 'scripts/vbw-statusline.sh')], { input, env, encoding: 'utf8' })
}

test('one note, one moment: the step HH:MM is identical in the status line, Comms and Mission Control; the road HH:MM shows in Mission Control only', () => {
  const now = Math.floor(Date.now() / S) * S
  const end = now + 12 * MIN
  const roadEnd = now + 130 * MIN
  const started = now - 5 * MIN
  const rec = record({
    lease: { run: 'build-1', kind: 'build', started_at: iso(started), files: null, session: 'sess-1' },
    plans: [
      { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building', reqs: [], files: ['a'], after: [] },
      { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'building', reqs: [], files: ['b'], after: [] },
    ],
  })
  const road = {
    seconds: 130 * 60, end: iso(roadEnd), rounds: { deep: 2 }, basis: '2 waves, 2 proofs, 1 QA check, 2 fix rounds per deep phase (median of 4 finished deep phases)',
    say: 'Milestone end: about 2 h 10 min, until around ' + hhmm(roadEnd) + ', counting 2 fix rounds per deep phase (the usual here)',
  }
  const note = {
    kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(started), ids: ['P44.1', 'P44.2'],
    doing: 'building P44.1, P44.2', parts: { done: 1, total: 2 }, proof: null, first_end: iso(end), end: iso(end), late: false, road,
  }
  const nx = next({ action: 'run', road })
  const dir = project(rec, note, nx)
  try {
    const lines = statusLine(dir)
    const line = lines.split('\n')[0]
    const at = Date.now()
    const mission = view.panelView({ record: rec, next: nx, now: at, cost: 1, steps: [], step: note })
    const missionText = mission.rows.map((r) => r.text).join('\n')
    const commsModel = stage.stageModel({ step: note, now: at, columns: 100, maxRows: 8 })
    const commsText = commsModel ? collect(stage.renderStage(UI, commsModel)).join('\n') : ''
    const want = hhmm(end)
    const roadAt = hhmm(roadEnd)
    assert.notEqual(want, roadAt, 'the fixture needs two different clock times')
    assert.deepEqual(times(line), [want], 'status line: ' + line)
    assert.doesNotMatch(lines, /Milestone end/, 'the status line shows the milestone time: ' + lines)
    assert.ok(!times(lines).includes(roadAt), 'the status line shows the road clock time: ' + lines)
    assert.deepEqual(times(commsText), [want], 'Comms: ' + commsText)
    assert.doesNotMatch(commsText, /Milestone end/, 'Comms shows the milestone time: ' + commsText)
    assert.ok(times(missionText).includes(want), 'Mission Control lacks the step time: ' + missionText)
    assert.ok(times(missionText).includes(roadAt), 'Mission Control lacks the road time: ' + missionText)
    assert.match(missionText, /Milestone end: about 2 h 10 min, until around /)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
