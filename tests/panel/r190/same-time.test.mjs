// R190, phase P147 (evidence level L1): the status line, Comms and Mission
// Control show the same end clock time at the same moment, because all three
// read it from one note of the kernel (.vbw/runtime/step.json) and none works
// the time out itself. One fixed note: the real status line script runs on a
// small project in a scratch folder (its own HOME); Comms and Mission Control
// are their pure models (panel-stage.js, panel-view.js) at the same moment.
// Times are local to Europe/Zurich (UTC+01:00, +02:00 in summer), so a UTC clock shows.
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
const CLOCK = /until (?:around )?(?:tomorrow )?(\d\d:\d\d)/

function project(rec, note) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vbw-r190-'))
  fs.mkdirSync(path.join(dir, '.vbw/runtime'), { recursive: true })
  fs.mkdirSync(path.join(dir, '.git'), { recursive: true })
  fs.mkdirSync(path.join(dir, 'home/.claude'), { recursive: true })
  fs.writeFileSync(path.join(dir, '.git/HEAD'), 'ref: refs/heads/main\n')
  fs.writeFileSync(path.join(dir, '.vbw/record.json'), JSON.stringify(rec))
  fs.writeFileSync(path.join(dir, '.vbw/runtime/step.json'), JSON.stringify(note))
  return dir
}

function statusLine(dir) {
  const input = JSON.stringify({ session_id: 'sess-1', workspace: { project_dir: dir, current_dir: dir }, version: '2.1.286' })
  const env = { PATH: process.env.PATH, HOME: path.join(dir, 'home'), CLAUDE_CONFIG_DIR: path.join(dir, 'home/.claude'), TZ: 'Europe/Zurich', NO_COLOR: '1' }
  return execFileSync('bash', [path.join(PLUGIN, 'scripts/vbw-statusline.sh')], { input, env, encoding: 'utf8' }).split('\n')[0]
}

test('one note, one moment: the status line, Comms and Mission Control show the identical HH:MM', () => {
  const now = Math.floor(Date.now() / S) * S
  const end = now + 12 * MIN
  const started = now - 5 * MIN
  const rec = record({
    lease: { run: 'build-1', kind: 'build', started_at: iso(started), files: null, session: 'sess-1' },
    plans: [
      { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building', reqs: [], files: ['a'], after: [] },
      { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'building', reqs: [], files: ['b'], after: [] },
    ],
  })
  const note = {
    kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(started), ids: ['P44.1', 'P44.2'],
    doing: 'building P44.1, P44.2', parts: { done: 1, total: 2 }, proof: null, first_end: iso(end), end: iso(end), late: false,
  }
  const dir = project(rec, note)
  try {
    const line = statusLine(dir)
    const at = Date.now()
    const mission = view.panelView({ record: rec, next: next({ action: 'run' }), now: at, cost: 1, steps: [], step: note })
    const missionText = mission.rows.map((r) => r.text).join('\n')
    const commsModel = stage.stageModel({ step: note, now: at, columns: 100, maxRows: 8 })
    const commsText = commsModel ? collect(stage.renderStage(UI, commsModel)).join('\n') : ''
    const want = hhmm(end)
    assert.equal((line.match(CLOCK) || [])[1], want, 'status line: ' + line)
    assert.equal((missionText.match(CLOCK) || [])[1], want, 'Mission Control: ' + missionText)
    assert.equal((commsText.match(CLOCK) || [])[1], want, 'Comms: ' + commsText)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
