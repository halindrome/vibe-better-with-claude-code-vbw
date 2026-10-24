// The panel module wired to its views (mods_4_vbw.md §2-§4): the run feed learns a
// VBW workflow from its Workflow tool call (or finds it after a reload) and reads it
// on the panel's timer; Comms, above the prompt, draws the crew, the one needs-you
// line and the nudges, with buttons that only fill or open; the pane is Mission Control
// with six tabs. Driven through the stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, collect, find, walk, ROOT, T0 } from './helpers/fake-mod.mjs'
import { screen, widest } from './r189/helpers/screen.mjs'
import { ENV, SESSION_DIR, RUN, RUN_DIR, ARCH, LEAD, writeRun, finish, launch, band } from './helpers/run.mjs'

const TEST_MODE = ROOT + '/.vbw/runtime/test-mode'
const approve = () => next({ action: 'approve', gate: true })

// WIDE: the six full tab names take one row beside the portrait at 80 columns.
const WIDE = { title: 'VBW', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} }
const wide = (h) => { const render = h.render; h.render = (extra = {}) => render({ props: WIDE, ...extra }); return h }
async function started(options = {}, rec = record(), nxt = next()) {
  const h = await mount({ env: ENV, ...options })
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return wide(h)
}
const texts = (tree) => collect(tree)
const text = (tree) => texts(tree).join('\n')
const buttons = (tree) => { const out = []; walk(tree, (n) => { if (n.type === 'Button') out.push(n) }); return out }
const press = async (h, tree, label) => {
  const b = buttons(tree).find((x) => x.props.label === label)
  assert.ok(b, 'no button ' + label + ' in ' + texts(tree).join(' | '))
  await b.props.onPress({ surface: 'terminal' })
  await h.settle()
}
const isEngine = (x, component) => x && x.type === 'engine' && x.ref === component

// ---- the run feed ----

test('a VBW workflow launched in this session shows its crew on Comms within 2 seconds', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
  const t = text(await band(h))
  assert.match(t, /VBW ▸ planning/)
  assert.match(t, /architect/)
  assert.match(t, /reading\s+spec\.md/)
  assert.match(t, /"Splitting R69 into two plans"/)
  assert.match(t, /Mission Control/)
  assert.deepEqual(h.errors, [])
})

test('a workflow that is not VBW\'s is not followed', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h, 'someone-else')
  await h.advance(4000)
  assert.ok(isEngine(await band(h), 'AbovePrompt'))
})

test('after a reload, a VBW run already going is found in the session folder, by the session id', async () => {
  const h = await mount({ env: ENV })
  h.project(record({ lease: lease('build', T0) }), next({ action: 'run' }))
  writeRun(h, T0)
  h.write(SESSION_DIR + '/workflows/scripts/building-' + RUN + '.js', 'export const meta = {}')
  await h.start()
  await h.advance(2000)
  assert.match(text(await band(h)), /VBW ▸ building/)
})

test('the Claude config folder follows CLAUDE_CONFIG_DIR when it is set', async () => {
  const h = await mount({ env: { HOME: '/nowhere', CLAUDE_CONFIG_DIR: '/home/u/.claude' } })
  h.project(record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, T0)
  h.write(SESSION_DIR + '/workflows/scripts/planning-' + RUN + '.js', 'export const meta = {}')
  await h.start()
  await h.advance(2000)
  assert.match(text(await band(h)), /architect/)
})

test('agent snippets come from the transcripts: no hook on every tool call or every streamed step (P2)', async () => {
  const h = await started()
  for (const x of h.handlers) {
    if (x.event === 'tool.call') assert.ok(x.matcher && x.matcher.tool, 'a tool.call hook without a tool matcher')
    assert.notEqual(x.event, 'turn.step')
    if (x.event === 'ui.render') assert.ok(x.matcher && x.matcher.component, 'a ui.render hook without a component matcher')
  }
})

test('a run that ends leaves Comms at the next redraw, and Mission Control says it ended', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now(), { journal: [{ type: 'result', agentId: ARCH, result: { summary: 'scope set' } }, { type: 'result', agentId: LEAD, result: { summary: 'planned' } }] })
  await launch(h)
  await h.advance(2000)
  finish(h, h.now() - 840000, 'completed')
  h.project(record(), next())
  await h.advance(2000)
  assert.ok(isEngine(await band(h), 'AbovePrompt'), 'no hold: Comms is empty at once')
  assert.match(text(await h.render()), /completed/)
})

// ---- Comms: the needs-you line ----

test('an approve gate is one needs-you line with no button: nothing on Comms fills or sends', async () => {
  const h = await started({}, record(), approve())
  const tree = await band(h)
  assert.match(text(tree), /^\d\d:\d\d ⚑ VBW needs you · /)
  assert.equal(buttons(tree).length, 0)
  assert.equal(h.count('prompt.fill'), 0)
  assert.equal(h.count('prompt.submit'), 0)
})

test('an approve gate suggests /vbw:approve once, however many ticks follow', async () => {
  const h = await started()
  h.project(undefined, approve())
  await h.advance(20000)
  assert.deepEqual(h.callsOf('prompt.suggest'), [[{ text: '/vbw:approve' }]])
  h.project(undefined, next({ action: 'accept', gate: true, detail: { requirements: ['R1'] } }))
  await h.advance(4000)
  assert.equal(h.count('prompt.suggest'), 1, 'only the approve gate is suggested')
})

test('a standing gate has no Later: the line stays, and comes back when the gate is raised again', async () => {
  const h = await started({}, record(), approve())
  assert.doesNotMatch(text(await band(h)), /Later/)
  await h.advance(10000)
  assert.match(text(await band(h)), /VBW needs you/, 'still standing for the same gate')
  h.project(undefined, next({ action: 'ship', gate: true }))
  await h.advance(2000)
  assert.match(text(await band(h)), /ready to ship/)
  h.project(undefined, next())
  await h.advance(2000)
  assert.ok(isEngine(await band(h), 'AbovePrompt'))
  h.project(undefined, approve())
  await h.advance(2000)
  assert.match(text(await band(h)), /VBW needs you/)
})

test('a survey wins over Comms: VBW yields', async () => {
  const h = await started({}, record(), approve())
  assert.ok(isEngine(await band(h, { hasSurvey: true }), 'AbovePrompt'))
})

test('health: a nearly full context is a needs-you line naming /compact, a weekly limit past 80% warns before a run', async () => {
  const usage = { cost: { usd: 2 }, context: { window: 200000, tokens: 180000, percent: 90 }, rateLimits: [{ kind: 'seven_day', percentUsed: 85 }] }
  const h = await started({ usage }, record(), next({ action: 'build', gate: false }))
  const tree = await band(h)
  assert.match(text(tree), /VBW needs you · .*\/compact/)
  assert.match(text(tree), /Weekly limit 85%/)
  assert.equal(buttons(tree).length, 0, 'no /compact button')
})

test('no usage figures: the needs-you line shows without health lines', async () => {
  const h = await started({ usageError: true }, record(), approve())
  const t = text(await band(h))
  assert.match(t, /VBW needs you/)
  assert.doesNotMatch(t, /Weekly|compact/)
})

// ---- motion ----

const spinOf = async (h) => {
  const tree = await band(h)
  const row = find(tree, (n) => n.props && n.props.key === 'agent-' + ARCH)
  return texts(row)
}

test('motion: calm by default (a spinner), off in a test session and when the record says off (a dot)', async () => {
  const calm = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(calm, calm.now())
  await launch(calm)
  await calm.advance(2000)
  assert.ok((await spinOf(calm)).some((t) => /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] $/.test(t)))

  for (const opts of [{ files: { [TEST_MODE]: '1' } }, {}]) {
    const settings = Object.keys(opts).length ? {} : { motion: 'off' }
    const h = await started(opts, record({ lease: lease('plan', T0), settings }), next({ action: 'run' }))
    writeRun(h, h.now())
    await launch(h)
    await h.advance(2000)
    assert.ok((await spinOf(h)).includes('· '), JSON.stringify(opts))
  }
})

// ---- Mission Control ----

const TABS = ['Now', 'Plan', 'Proof', 'Timeline', 'Sessions', 'Settings']

test('the pane is Mission Control: six tabs, Now first with the panel rows and the sound switch', async () => {
  const h = await started()
  const pane = await h.render()
  assert.deepEqual(buttons(pane).filter((b) => /^tab-/.test(b.props.key)).map((b) => b.props.label), TABS)
  const t = text(pane)
  assert.match(t, /Working on M9/)
  assert.match(t, /Sound is on/)
  assert.doesNotMatch(t, /No VBW workflow runs/, 'the box says nothing runs; the Now tab does not say it again')
})

test('the tabs sit in whole rows: at 80 columns the six full names on one row beside the portrait, at 60 the short names on one row beside it, at 50 the full names on two rows beside it, at 40 on two rows without it', async () => {
  const h = await started()
  const FULL = TABS
  const SHORT = ['Now', 'Plan', 'Proof', 'Time', 'Sess', 'Set']
  const at = async (columns) => {
    const pane = await h.render({ props: { title: 'VBW', isFocused: false, bodyColumns: columns, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} } })
    const lines = screen(pane, columns)
    const shown = lines.flatMap((l) => (l.match(/\[ [A-Za-z]+ \]/g) || []).map((b) => b.slice(2, -2)))
    const rows = lines.filter((l) => /\[ [A-Za-z]+ \]/.test(l)).length
    assert.ok(widest(lines) <= columns, columns + ' columns: a line is ' + widest(lines) + ' wide')
    assert.ok(lines.every((l) => !/\[ [A-Za-z]*$|^[A-Za-z]* \]/.test(l.replace(/\[ [A-Za-z]+ \]/g, ''))), columns + ' columns: a cut name in ' + JSON.stringify(lines.slice(0, 4)))
    return { shown, rows, portrait: find(pane, (n) => n.type === 'Image') }
  }
  const wide80 = await at(80)
  assert.deepEqual(wide80.shown, FULL)
  assert.equal(wide80.rows, 1)
  assert.ok(wide80.portrait, 'the portrait costs the tabs nothing at 80 columns')
  const mid = await at(50)
  assert.deepEqual(mid.shown, FULL)
  assert.equal(mid.rows, 2)
  assert.ok(mid.portrait, 'beside the portrait the full names still take two rows at 50 columns')
  const wide60 = await at(60)
  assert.deepEqual(wide60.shown, SHORT, 'one row of short names beats two rows of full ones')
  assert.equal(wide60.rows, 1)
  assert.ok(wide60.portrait, 'the portrait costs the short names nothing at 60 columns')
  const narrow = await at(40)
  assert.deepEqual(narrow.shown, FULL)
  assert.equal(narrow.rows, 2)
  assert.ok(!narrow.portrait, 'beside the portrait the full names would take three rows')
})

test('each tab draws its view, and the choice holds across redraws; the folded tabs keep their facts in their new homes', async () => {
  const h = await started({}, record({ settings: { profile: 'quality' }, decisions: [{ id: 'D1', text: 'Which db? sqlite', at: '2026-10-01T00:00:00Z' }] }))
  // Decisions under Plan, the cost per run and the session total (Costs) in Timeline.
  const want = { Plan: [/P44 Cost/, /sqlite/], Proof: [/No checks are approved/], Timeline: [/No VBW workflow runs/, /This session: \$1\.42/], Sessions: [/No other chats are open on this project/], Settings: [/Reading the settings/] }
  for (const [tab, res] of Object.entries(want)) {
    await press(h, await h.render(), tab)
    for (const re of res) assert.match(text(await h.render()), re, tab)
    await h.advance(4000)
    for (const re of res) assert.match(text(await h.render()), re, tab + ' after a tick')
  }
})

test('Now: pressing an agent card shows its detail', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
  await press(h, await h.render(), 'architect scope')
  assert.match(text(await h.render()), /Model: opus/)
})

test('a failed agent\'s details button opens Mission Control on that agent', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now(), { journal: [{ type: 'result', agentId: ARCH, error: 'Agent crashed' }] })
  await launch(h)
  await h.advance(2000)
  await press(h, await band(h), 'details')
  assert.match(text(await h.render()), /Result: Agent crashed/)
  await h.advance(2000)
  assert.doesNotMatch(text(await band(h)), /architect/, 'opened in Mission Control: the failure leaves Comms')
})

test('Timeline: each run costs the session cost moved while its lease was open', async () => {
  const h = await started({ usage: { cost: { usd: 1 } } })
  h.project(record({ lease: lease('plan', h.now()) }), next({ action: 'run' }))
  await h.advance(2000)
  h.setUsage({ cost: { usd: 3.5 } })
  h.project(record(), next())
  await h.advance(2000)
  await press(h, await h.render(), 'Timeline')
  const t = text(await h.render())
  assert.match(t, /plan 1/)
  assert.match(t, /about \$2\.50/)
})

test('the crew header shows the cost of the open run', async () => {
  const h = await started({ usage: { cost: { usd: 1 } } }, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  h.setUsage({ cost: { usd: 4.2 } })
  await h.advance(2000)
  assert.match(text(await band(h)), /≈\$3\.20 this run/)
})

test('the plan\'s Ask field is not drawn until it is wired', async () => {
  const h = await started()
  await press(h, await h.render(), 'Plan')
  assert.equal(find(await h.render(), (n) => n.type === 'Input'), undefined)
})

// ---- staying out of the way ----

test('outside a VBW project, or on an old Claude Code, Comms and the pane draw nothing of VBW', async () => {
  for (const opts of [{}, { version: '2.1.200' }]) {
    const h = await mount({ env: ENV, ...opts })
    if (opts.version) h.project(record(), approve())
    await h.start()
    await launch(h)
    await h.advance(4000)
    assert.ok(isEngine(await band(h), 'AbovePrompt'))
    assert.equal(h.count('prompt.suggest'), 0)
    assert.deepEqual(h.errors, [])
  }
})

test('outside the project it reads only this session\'s own folder and Claude Code\'s list of chats (R192), and never settings or credentials', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(6000)
  const paths = [...h.callsOf('fs.read'), ...h.callsOf('fs.stat'), ...h.callsOf('fs.exists'), ...h.callsOf('fs.list')].map((a) => a[0])
  for (const p of paths) {
    // the Claude config folder here is ~/.claude (~/.config/claude-code is only probed)
    const chats = '/home/u/.claude/sessions'
    assert.ok(p === ROOT || p.startsWith(ROOT + '/') || p.startsWith(SESSION_DIR) || p === '/home/u/.config/claude-code' || p === chats || p.startsWith(chats + '/'), 'outside: ' + p)
    assert.doesNotMatch(p, /credentials|settings\.json|\.ssh/)
  }
  assert.ok(paths.some((p) => p.startsWith(RUN_DIR)), 'the run was read')
})

// Claude Code before 2.1.290 redrew a band forever when its tree changed height
// (fixed in 2.1.290); the crew changes height as agents come and go.
test('Comms draws from Claude Code 2.1.290; on older versions it leaves the engine its own', async () => {
  const old = await started({ version: '2.1.289' }, record(), approve())
  assert.ok(isEngine(await band(old), 'AbovePrompt'))
  const now = await started({ version: '2.1.290' }, record(), approve())
  assert.match(text(await band(now)), /needs you/)
})

test('a proof running in this session (its mark in .vbw/runtime) is the state "proving", dated by the mark; it ends with the mark', async () => {
  const mark = ROOT + '/.vbw/runtime/proving.sess-1'
  const h = await started({}, record(), next({ action: 'prove' }))
  const box = async () => text(await h.render())
  assert.doesNotMatch(await box(), /proving/i)
  h.write(mark, '4242\n')
  await h.advance(2000)
  assert.match(await box(), /VBW is proving the work/)
  h.remove(mark)
  await h.advance(2000)
  assert.doesNotMatch(await box(), /proving/i)
})
