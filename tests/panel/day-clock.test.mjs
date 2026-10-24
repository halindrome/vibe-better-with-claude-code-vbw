// Times carry the day (design rule 5, docs/panel.md): every moment the panel
// prints goes through one function, dayClock in plugin/hooks/panel-step.js, which
// applies the kernel's step_clock rule (plugin/lib/steps.sh): 'HH:MM' today, else
// 'yesterday HH:MM', 'tomorrow HH:MM' or the weekday's name. A gate reached at
// 21:38 the evening before reads 'yesterday 21:38' at 15:40, never a bare '21:38'.
// Pure models and the stand-in for Claude Code's mods API (evidence level L1).
// Times are local to Europe/Zurich.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, lease } from './helpers/fake-mod.mjs'

process.env.TZ = 'Europe/Zurich'

const step = await import(pathToFileURL(PLUGIN + '/hooks/panel-step.js').href)
const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)
const lines = await import(pathToFileURL(PLUGIN + '/hooks/panel-lines.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)
const cmd = await import(pathToFileURL(PLUGIN + '/hooks/panel-commands.js').href)

// Saturday 24 October 2026, 15:40 local; the gate was reached Friday at 21:38.
const NOW = new Date(2026, 9, 24, 15, 40).getTime()
const YESTERDAY = new Date(2026, 9, 23, 21, 38).getTime()
const TODAY = new Date(2026, 9, 24, 9, 5).getTime()

test('dayClock: HH:MM today, yesterday HH:MM, tomorrow HH:MM, else the weekday; nothing for no moment', () => {
  assert.equal(step.dayClock(TODAY, NOW), '09:05')
  assert.equal(step.dayClock(YESTERDAY, NOW), 'yesterday 21:38')
  assert.equal(step.dayClock(new Date(2026, 9, 25, 0, 20).getTime(), NOW), 'tomorrow 00:20')
  assert.equal(step.dayClock(new Date(2026, 9, 19, 9, 10).getTime(), NOW), 'Monday 09:10')
  assert.equal(step.dayClock(new Date(2026, 9, 28, 9, 10).getTime(), NOW), 'Wednesday 09:10')
  for (const bad of [null, undefined, 'x', NaN, Infinity]) assert.equal(step.dayClock(bad, NOW), '')
})

test('Comms: the needs-you line of a gate reached yesterday names the day', () => {
  const m = stage.stageModel({ now: NOW, columns: 120, maxRows: 8, need: { key: 'approve', what: 'the plan is ready', at: YESTERDAY } })
  assert.equal(m.need.text, 'yesterday 21:38 ⚑ VBW needs you · the plan is ready')
})

test('Comms: a refusal of yesterday and a helper started yesterday name the day', () => {
  const refusal = { id: 'r1', by: 'dev P1.1', at: YESTERDAY, text: 'vbw: apply refused: plan P1.1 is started' }
  const agent = { id: 'a1', role: 'dev', label: 'P1.1', state: 'working', startedAt: YESTERDAY, lastSeenAt: NOW - 1000, activity: { kind: 'tool', text: 'Edit a.js' } }
  const run = { runId: 'wf_1', kind: 'building', startedAt: YESTERDAY, status: 'running', agents: [agent] }
  const m = stage.stageModel({ now: NOW, columns: 140, maxRows: 12, motion: 'off', refusal, run })
  assert.match(m.refusal.text, /^yesterday 21:38 ⊘ VBW refused/)
  assert.equal(m.rows[0].time, 'yesterday 21:38')
})

test('the Workflow run card and the Now cards name the day of a run started yesterday', () => {
  const run = { kind: 'planning', status: 'running', startedAt: YESTERDAY }
  assert.equal(lines.workflowCard({ input: { name: 'vbw:planning' }, run, now: NOW }), 'VBW planning · started yesterday 21:38 · [p] watch live')
  const m = live.nowModel({ now: NOW, run: { kind: 'building', status: 'running', startedAt: YESTERDAY, agents: [{ id: 'a1', role: 'dev', state: 'working', startedAt: YESTERDAY }] } })
  assert.equal(m.columns[0].cards[0].at, 'yesterday 21:38')
})

test('/vbw-why says when the run started in local time with its day', () => {
  const l = lease('build', YESTERDAY, { session: 's1', files: [] })
  const s = cmd.whyText({ record: record({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: 's1' })
  assert.match(s.split('\n')[0], / since yesterday 21:38 \(1082 min ago\);/)
})
