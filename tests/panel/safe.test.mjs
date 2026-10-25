// R53: where the panel cannot run it does nothing at all: on Claude Code older
// than 2.1.287, outside a VBW project, and when Claude Code's own calls fail.
// No panel, no command, no timer, no error (L1, stand-in for the mods API).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, ROOT } from './helpers/fake-mod.mjs'

const NOTHING = ['command.register', 'clock.every', 'clock.after', 'ui.open', 'audio.play', 'ui.toast', 'ui.log', 'ui.status']

async function assertInert(h) {
  await h.start()
  await h.advance(10000)
  await h.cmd('vbw-panel')
  await h.cmd('vbw-sound', 'off')
  for (const name of NOTHING) assert.equal(h.count(name), 0, name + ' was called')
  assert.deepEqual(await h.render(), { type: 'engine', ref: 'default' }, 'no pane is drawn')
  assert.deepEqual(h.errors, [], 'no hook failed')
}

test('on Claude Code older than 2.1.287 the panel does nothing at all', async () => {
  for (const version of ['2.1.286', '2.0.5', '1.0.0']) {
    const h = await mount({ version })
    h.project(record(), next())
    await assertInert(h)
    assert.equal(h.count('fs.read'), 0, 'no project file was read on ' + version)
  }
})

test('a version that cannot be read is treated as one without mods', async () => {
  const h = await mount({ version: 'garbage' })
  h.project(record(), next())
  await assertInert(h)
})

test('on 2.1.287 and newer, in a VBW project, the panel starts', async () => {
  for (const version of ['2.1.287', '2.1.289', '2.2.0']) {
    const h = await mount({ version })
    h.project(record(), next())
    await h.start()
    assert.ok(h.count('command.register') >= 1, 'commands registered on ' + version)
    assert.ok(h.count('clock.every') >= 1, 'a refresh timer on ' + version)
  }
})

test('outside a VBW project (no .vbw folder) there is no panel, no command and no error', async () => {
  const h = await mount()
  h.write(ROOT + '/README.md', 'hello')
  await assertInert(h)
})

test('a folder with a VBW 1 plan but no VBW 2 record is not a VBW 2 project', async () => {
  const h = await mount()
  h.write(ROOT + '/.vbw-planning/STATE.md', 'old')
  await assertInert(h)
})

test('when Claude Code answers with failures the panel stays quiet', async () => {
  const h = await mount({ usageError: true })
  h.project(record(), next())
  await h.start()
  await h.advance(10000)
  await h.render()
  assert.deepEqual(h.errors, [])
})

test('garbage in the project files never makes a hook fail', async () => {
  for (const bad of ['{"phases": 7, "milestone": []}', '[]', '"x"', '\u0000\u0001', '{"lease": {"kind": 5}, "milestone": {"id": 1}}']) {
    const h = await mount()
    h.write(ROOT + '/.vbw/record.json', bad)
    h.write(ROOT + '/.vbw/runtime/next.json', bad)
    await h.start()
    await h.advance(6000)
    await h.render()
    assert.deepEqual(h.errors, [], JSON.stringify(bad))
  }
})

// A first session starts in a folder with no project; /vbw:vibe sets it up
// mid-session and asks its first question. No timer runs before the project exists
// (R53): the panel checks again on the hooks it already has.
test('a project set up during the session turns the panel on at the next question or prompt', async () => {
  const h = await mount()
  await h.start()
  await h.fire('prompt.submit', { text: '/vbw:vibe a greeting script' })
  await h.advance(4000)
  for (const name of NOTHING) assert.equal(h.count(name), 0, name + ' before the project exists')
  h.project(record(), next())
  await h.fire('tool.call', { tool: 'AskUserQuestion', questions: [{ question: 'Which?' }] }, async () => ({ result: 'x' }))
  await h.settle()
  assert.ok(h.count('command.register') >= 1, 'the commands are registered')
  assert.equal(h.count('clock.every') >= 1, true, 'the panel timer runs')
  assert.notDeepEqual(await h.render(), { type: 'engine', ref: 'default' }, 'the pane is drawn')
  assert.deepEqual(h.errors, [])
})

test('a prompt sent after the project appeared turns the panel on too', async () => {
  const h = await mount()
  await h.start()
  h.project(record(), next())
  await h.fire('prompt.submit', { text: 'carry on' })
  await h.settle()
  assert.ok(h.count('command.register') >= 1)
})

// Gating hooks (7.6): a hook that fails is skipped by Claude Code and its `.catch` is asked
// (`claude plugin validate` lists a gating hook without one). Every gating hook of the panel
// has a `.catch` that lets the event through, and answers a command in plain words; none throws.
const GATING = ['command.run', 'ui.close', 'tool.call', 'prompt.submit']

test('every gating hook has a .catch that lets the event through (a command answers in plain words) and never throws', async () => {
  const h = await mount()
  const gating = h.handlers.filter((x) => GATING.includes(x.event))
  assert.ok(gating.length >= 9, 'the panel registers its gating hooks (' + gating.length + ')')
  for (const x of gating) {
    const name = x.event + JSON.stringify(x.matcher ?? {})
    assert.equal(typeof x.catcher, 'function', name + ' has no .catch')
    const e = { id: 'vbw-panel', tool: 'AskUserQuestion', command: 'vbw-x' }
    const passed = []
    const next = Object.assign((e2) => { passed.push(e2); return Promise.resolve('beneath') }, { called: false, error: new Error('boom') })
    const answer = await x.catcher(h.$, e, next)
    if (x.event === 'command.run') {
      assert.match(String(answer && answer.text), /did not work|failed/i, name + ' answers in plain words')
      assert.equal(passed.length, 0, name)
    } else {
      assert.equal(answer, 'beneath', name + ' lets the event through')
      assert.deepEqual(passed, [e], name)
    }
  }
})

test('a question hook that fails does not leave Mission Control saying VBW has a question', async () => {
  const h = await mount()
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  h.fails.add('clock.now')
  let through = false
  await h.fire('tool.call', { tool: 'AskUserQuestion', questions: [{ question: 'Which?' }] }, async () => { through = true; return { result: 'x' } })
  h.fails.delete('clock.now')
  await h.advance(4000)
  assert.ok(h.errors.some((x) => x.event === 'tool.call'), 'the hook failed, as the test meant')
  assert.ok(through, 'the question itself went through')
  assert.doesNotMatch(await h.text(), /question for you/)
})

// A session started in a subfolder of a VBW project: the project is found the way the
// kernel finds it, the nearest folder up that holds .git (the git top), never a folder above it.
test('a session started in a subfolder of a VBW project turns the panel on, with the git top as the project', async () => {
  const h = await mount({ root: '/proj/Sub Folder' })
  h.write('/proj/.git/HEAD', 'ref: refs/heads/main\n')
  h.write('/proj/.vbw/record.json', record())
  h.write('/proj/.vbw/runtime/next.json', next())
  await h.start()
  await h.settle()
  assert.ok(h.count('command.register') >= 1, 'the commands are registered')
  assert.match(await h.text(), /Live VBW panel/)
  assert.deepEqual(h.errors, [])
})

test('a record above the git top is not the project: the panel stays off', async () => {
  const h = await mount({ root: '/proj/inner/sub' })
  h.write('/proj/inner/.git', 'gitdir: /proj/.git/modules/inner\n')
  h.write('/proj/.git/HEAD', 'ref: refs/heads/main\n')
  h.write('/proj/.vbw/record.json', record())
  await assertInert(h)
})
