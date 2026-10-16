// R190, phase P146 (evidence level L1): the 9 October list's P9 as D406 and D418
// replaced it. Everything a user can see calls the strip above the prompt
// 'Comms' and the side panel 'Mission Control': the panel's drawings, its
// buttons, its instant commands and their descriptions, the plugin's skills
// and agents, docs/ and README.md. None of them says 'Telemetry', 'the
// band' or '/vbw-telemetry'; no /vbw-telemetry command exists, and /vbw-panel
// opens Mission Control. The CHANGELOG is history and is not read.
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { mount, record, next, lease, walk, PLUGIN, T0 } from '../helpers/fake-mod.mjs'
import { working, building } from '../r189/helpers/crew.mjs'
import { textOf } from '../r189/helpers/screen.mjs'

const REPO = path.resolve(PLUGIN, '..')
const OLD = /telemetry|\bthe band\b|\bband above the prompt\b/i
const TABS = ['now', 'plan', 'proof', 'timeline', 'decisions', 'team', 'costs']

// Every text file under a folder, skipping pictures and sounds.
function files(dir) {
  const out = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) out.push(...files(p))
    else if (!/\.(png|jpe?g|gif|mp3|wav|ico)$/i.test(e.name)) out.push(p)
  }
  return out
}

test('no skill, agent, docs page or README calls the strip or the pane by an old or proposed name', () => {
  const read = [...files(path.join(PLUGIN, 'skills')), ...files(path.join(PLUGIN, 'agents')), ...files(path.join(REPO, 'docs')), path.join(REPO, 'README.md')]
  assert.ok(read.some((p) => p.endsWith(path.join('skills', 'panel', 'SKILL.md'))), 'the panel skill is not among the files read')
  assert.ok(read.some((p) => p.endsWith(path.join('docs', 'panel.md'))), 'docs/panel.md is not among the files read')
  const hits = []
  for (const p of read) {
    fs.readFileSync(p, 'utf8').split('\n').forEach((l, i) => {
      if (OLD.test(l)) hits.push(path.relative(REPO, p) + ':' + (i + 1) + ': ' + l.trim())
    })
  }
  assert.deepEqual(hits, [])
})

test('no /vbw-telemetry command exists; /vbw-panel is described as opening Mission Control and opens it', async () => {
  const h = await mount()
  h.project(record(), next())
  await h.start()
  const commands = h.callsOf('command.register').map(([c]) => c)
  assert.ok(commands.length > 0, 'no command was registered')
  for (const c of commands) {
    assert.doesNotMatch(c.name, OLD, c.name)
    assert.doesNotMatch(String(c.description), OLD, c.name + ': ' + c.description)
  }
  const panel = commands.find((c) => c.name === 'vbw-panel')
  assert.ok(panel, 'no /vbw-panel command')
  assert.match(panel.description, /Mission Control/)
  const opens = h.opens.length
  const out = await h.cmd('vbw-panel')
  assert.ok(h.opens.length > opens, '/vbw-panel opened nothing')
  assert.match(String(out && out.text), /Mission Control/)
  const before = h.errors.length
  const told = await h.cmd('vbw-telemetry')
  assert.equal(h.errors.length, before)
  assert.equal(h.opens.length, opens + 1, '/vbw-telemetry opened the pane')
  assert.ok(!(told && /Mission Control|Telemetry/i.test(String(told.text))), 'the panel answered /vbw-telemetry')
})

test('nothing the panel draws, on Comms or on any Mission Control tab, says an old name', async () => {
  const words = []
  const take = (tree) => walk(tree, (n) => {
    if (n.type === 'Text') words.push(textOf(n))
    if (n.type === 'Button' && n.props.label !== undefined) words.push(String(n.props.label))
  })
  const { h } = await building(working(5), { profile: 'balanced', motion: 'full' })
  take(await h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 6, bodyColumns: 100 }))
  for (const tab of TABS) {
    await h.press('tab-' + tab)
    take(await h.render())
  }
  const g = await mount()
  g.project(record({ lease: lease('build', T0) }), next({ action: 'approve', gate: true }))
  await g.start()
  await g.advance(4000)
  g.project(record(), next({ action: 'approve', gate: true }))
  await g.advance(2000)
  take(await g.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100 }))
  take(await g.render())
  assert.ok(words.some((w) => /Mission Control/.test(w)), 'Mission Control is not named anywhere it is drawn')
  assert.deepEqual(words.filter((w) => OLD.test(w)), [])
})
