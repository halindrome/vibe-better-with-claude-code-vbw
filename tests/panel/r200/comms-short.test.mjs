// R200, phase P159 (evidence level L1: the stand-in for Claude Code's mods API,
// a VBW build run written as Claude Code writes it, ../r189/helpers/crew.mjs,
// and the model of Ink's layout in ../r189/helpers/screen.mjs). In a short
// window Claude Code gives Comms one or two rows. The 2.0.40 panel L3 run
// (2026-10-19, 200x24) showed only the step line, 'building P1.1 · No end time
// yet: ...', and no 'VBW ▸' helper line while one helper worked: the step line
// took the one row. The order in little room is the needs-you line, then the
// helper line while helpers work, then the step line. With one row and no
// needs-you line the helper line shows and carries the step's time after its
// own parts ('VBW ▸ build · 1 working · 0m30s · about 12 min, until around
// 14:20'), cut to the width with the Mission Control button kept; with two
// rows the helper line and the step line; with three or more rows as before
// (the header, the helper rows, the step line); a needs-you line with one row
// shows alone; the step line alone shows only when no helper works (a proof);
// and Comms never draws more rows than Claude Code gives it.
// Times are local to Europe/Zurich (UTC+01:00, +02:00 in summer), so a UTC clock shows.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, PLUGIN, ROOT, T0 } from '../helpers/fake-mod.mjs'
import { TICK, writeCrew, endRun, working, building } from '../r189/helpers/crew.mjs'
import { screen, widest, hhmm } from '../r189/helpers/screen.mjs'

process.env.TZ = 'Europe/Zurich'

const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)

const NOTE = ROOT + '/.vbw/runtime/step.json'
const GIT = ROOT + '/.git/HEAD'
const S = 1000
const MIN = 60 * S
// building() launches the run and lets one refresh pass; the clock then stands at T0 + TICK.
const NOW = T0 + TICK
const END = NOW + 12 * MIN
const AT = hhmm(END)
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }

// The kernel's step note of the build run, as the 2.0.40 capture had it: no end time yet.
const note = (over = {}) => ({
  kind: 'build', run: 'build-1', session: 'sess-1', pid: null, started_at: iso(T0), ids: ['P1.1'],
  doing: 'building P1.1', parts: { done: 0, total: 1 }, proof: null, first_end: null, end: null, late: false, ...over,
})
const timed = () => note({ first_end: iso(END), end: iso(END) })
const proofNote = () => note({ kind: 'proof', run: null, pid: process.pid, ids: [], doing: 'proving 3 of 9 checks', parts: { done: 3, total: 9 }, proof: { done: 3, total: 9 }, first_end: iso(END), end: iso(END) })

// A build run with its crew at work and the step note written before the run is launched.
const crewed = (n, crew = working(1)) => building(crew, { profile: 'balanced', motion: 'calm' }, { files: { [GIT]: 'ref: refs/heads/main\n', [NOTE]: JSON.stringify(n) } })
// A session with no run: the record as it stands, the next step, and a note when given.
async function idle(rec, nx, n) {
  const h = await mount({ env: { HOME: '/home/u' }, files: { [GIT]: 'ref: refs/heads/main\n', ...(n ? { [NOTE]: JSON.stringify(n) } : {}) } })
  h.project(rec, nx)
  await h.start()
  await h.advance(TICK)
  return h
}
const comms = (h, rows, columns = 80) => h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: rows, bodyColumns: columns })
const lines = async (h, rows, columns = 80) => screen(await comms(h, rows, columns), columns)
const helperLine = (l) => l.startsWith('VBW ▸')

test("the 2.0.40 capture: one working helper and a step note with no end time draw, at 1 row, one line starting 'VBW ▸'; at 2 and 3 rows the helper line is there too", async () => {
  const { h } = await crewed(note())
  const one = await lines(h, 1)
  assert.equal(one.length, 1, JSON.stringify(one))
  assert.ok(helperLine(one[0]), 'the one row is not the helper line: ' + one[0])
  assert.match(one[0], /\b1 working\b/)
  assert.match(one[0], /Mission Control/)
  assert.doesNotMatch(one[0], /No end time/, 'a note with no end time adds nothing to the one line')
  const two = await lines(h, 2)
  assert.equal(two.length, 2, JSON.stringify(two))
  assert.ok(helperLine(two[0]), two[0])
  assert.match(two[1], /building P1\.1 · No end time yet/)
  const three = await lines(h, 3)
  assert.ok(three.length <= 3, JSON.stringify(three))
  assert.ok(helperLine(three[0]), three[0])
  assert.ok(three.some((l) => /building P1\.1 · No end time yet/.test(l)), JSON.stringify(three))
  assert.deepEqual(h.errors, [])
})

test("with one row and no needs-you line the helper line carries the step's time after its own parts, cut to the width with the Mission Control button kept", async () => {
  const { h } = await crewed(timed())
  const wide = await lines(h, 1, 100)
  assert.equal(wide.length, 1, JSON.stringify(wide))
  assert.match(wide[0], new RegExp('^VBW ▸ \\w+ · 1 working · \\d+m\\d\\ds · about 12 min, until around ' + AT.replace(':', '\\:')), wide[0])
  assert.match(wide[0], /Mission Control/)
  assert.ok(widest(screen(await comms(h, 1, 100), Infinity)) <= 100)
  const narrow = await lines(h, 1, 40)
  assert.equal(narrow.length, 1, JSON.stringify(narrow))
  assert.ok(helperLine(narrow[0]), narrow[0])
  assert.match(narrow[0], /Mission Control/, 'the button went with the cut: ' + narrow[0])
  assert.ok(widest(screen(await comms(h, 1, 40), Infinity)) <= 40, 'wider than 40: ' + narrow[0])
})

test('with two rows the helper line and the step line show', async () => {
  const { h } = await crewed(timed())
  const two = await lines(h, 2)
  assert.equal(two.length, 2, JSON.stringify(two))
  assert.ok(helperLine(two[0]), two[0])
  assert.ok(two[1].includes('building P1.1 · about 12 min, until around ' + AT), two[1])
})

test('with three or more rows Comms draws as before: the header first, the step line, and from 8 rows the helper rows', async () => {
  const { h } = await crewed(timed())
  for (const rows of [3, 4]) {
    const few = await lines(h, rows)
    assert.ok(few.length <= rows, rows + ' rows: ' + JSON.stringify(few))
    assert.ok(helperLine(few[0]), rows + ' rows: ' + few[0])
    assert.ok(few.some((l) => l.includes('building P1.1 · about 12 min, until around ' + AT)), rows + ' rows: no step line in ' + JSON.stringify(few))
  }
  const many = await lines(h, 8)
  assert.ok(many.length <= 8, '8 rows: ' + JSON.stringify(many))
  assert.ok(helperLine(many[0]), '8 rows: ' + many[0])
  assert.ok(many.some((l) => /\bdev\b.*P142\.1/.test(l)), '8 rows: no helper row in ' + JSON.stringify(many))
  assert.ok(many.some((l) => l.includes('building P1.1 · about 12 min, until around ' + AT)), '8 rows: no step line in ' + JSON.stringify(many))
})

test('a needs-you line with one row shows the needs-you line alone; with two rows the step line follows it', async () => {
  const h = await idle(record(), next({ action: 'approve', gate: true }), proofNote())
  const one = await lines(h, 1)
  assert.equal(one.length, 1, JSON.stringify(one))
  assert.match(one[0], /⚑ VBW needs you/)
  assert.doesNotMatch(one[0], /VBW ▸|proving/)
  const two = await lines(h, 2)
  assert.equal(two.length, 2, JSON.stringify(two))
  assert.match(two[0], /⚑ VBW needs you/)
  assert.match(two[1], /^proving 3 of 9 checks · /)
})

test('the order in little room is the needs-you line, then the helper line while helpers work, then the step line', () => {
  const agent = { id: 'a1', role: 'dev', label: 'P1.1', state: 'working', activity: { kind: 'tool', text: 'editing greet.sh' }, startedAt: NOW - 20 * S, endedAt: null, lastSeenAt: NOW - S, tokens: 1000, result: null }
  const run = { runId: 'wf_1', kind: 'build', phase: 'Build', startedAt: NOW - 30 * S, endedAt: null, status: 'running', agents: [agent] }
  const need = { key: 'k', what: 'approve the plan', at: NOW }
  const draw = (maxRows) => {
    const model = stage.stageModel({ run, step: timed(), need, now: NOW, columns: 100, maxRows })
    assert.ok(model, maxRows + ' rows: Comms has nothing to show')
    return screen(stage.renderStage(UI, model), 100)
  }
  const three = draw(3)
  assert.equal(three.length, 3, JSON.stringify(three))
  assert.match(three[0], /⚑ VBW needs you · approve the plan/)
  assert.ok(helperLine(three[1]), three[1])
  assert.ok(three[2].includes('building P1.1 · about 12 min, until around ' + AT), three[2])
  const two = draw(2)
  assert.equal(two.length, 2, JSON.stringify(two))
  assert.match(two[0], /⚑ VBW needs you/)
  assert.ok(two[1].startsWith('VBW ▸ build · 1 working · 0m30s · about 12 min, until around ' + AT), 'the one row left is not the helper line with the step time: ' + two[1])
  const one = draw(1)
  assert.equal(one.length, 1, JSON.stringify(one))
  assert.match(one[0], /⚑ VBW needs you/)
})

test('the step line alone (no helper line) shows only when no helper works: a proof, or a run whose helpers are all done', async () => {
  const proving = await idle(record(), next({ action: 'prove' }), proofNote())
  const alone = await lines(proving, 1)
  assert.equal(alone.length, 1, JSON.stringify(alone))
  assert.ok(alone[0].startsWith('proving 3 of 9 checks · about 12 min, until around ' + AT), alone[0])
  const { h, at } = await crewed(timed())
  writeCrew(h, at, [{ n: 'P142.1', state: 'done' }])
  endRun(h, at)
  await h.advance(TICK)
  const done = await lines(h, 1)
  assert.equal(done.length, 1, JSON.stringify(done))
  assert.ok(!helperLine(done[0]), 'no helper works, yet the helper line shows: ' + done[0])
  assert.match(done[0], /^building P1\.1 · /)
})

test('Comms never draws more rows than Claude Code gives it: with a live step note at 1, 2, 3, 4 and 8 rows at 80 and 40 columns the row count is held and no line is wider', async () => {
  const { h } = await crewed(timed(), working(3))
  for (const columns of [80, 40]) {
    for (const rows of [1, 2, 3, 4, 8]) {
      const tree = await comms(h, rows, columns)
      const drawn = screen(tree, columns)
      assert.ok(drawn.length <= rows, columns + 'x' + rows + ': ' + drawn.length + ' rows: ' + JSON.stringify(drawn))
      assert.ok(widest(screen(tree, Infinity)) <= columns, columns + 'x' + rows + ': ' + widest(screen(tree, Infinity)) + ' columns')
      assert.ok(drawn.length >= 1 && helperLine(drawn[0]), columns + 'x' + rows + ': the helper line is missing: ' + JSON.stringify(drawn))
    }
  }
  assert.deepEqual(h.errors, [])
})
