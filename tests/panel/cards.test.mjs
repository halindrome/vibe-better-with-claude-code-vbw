// R85: in Mission Control's Now tab, each helper of the running workflow is one
// crew row whose role word is drawn in its role's colour and whose state shows as
// a coloured mark and word (running, failed, quiet), so two helpers of different
// roles never look the same. Finished helpers leave the crew at once (design
// 2.1.11: the crew folds into Now; Timeline keeps the history). Pure: nowModel
// and renderNow, no Claude Code needed (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']

const agent = (over = {}) => ({
  id: 'a1', role: 'dev', label: 'P6.7', state: 'working', activity: { kind: 'tool', text: 'editing app-topbar.tsx' },
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents, over = {}) => ({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 600 * S, endedAt: null, status: 'running', agents, ...over })
const draw = (r) => live.renderNow(UI, live.nowModel({ run: deepFreeze(r), now: NOW }))
const texts = (node) => {
  const out = []
  walk(node, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const row = (tree, id) => find(tree, (n) => n.type === 'Box' && n.props.key === 'crew:' + id)
const roleOf = (tree, id) => texts(row(tree, id))[0].props.color

test('each row draws its role word in its role colour', () => {
  const tree = draw(run(ROLES.map((role) => agent({ id: role, role }))))
  for (const role of ROLES) {
    assert.equal(roleOf(tree, role), P.roleColor(role), role)
    assert.ok(texts(row(tree, role))[0].text.startsWith(role), role)
  }
})

test('two helpers of different roles never get the same colour, whatever their state', () => {
  for (const state of ['working', 'failed', 'quiet']) {
    const tree = draw(run(ROLES.map((role) => agent({ id: role, role, state }))))
    assert.equal(new Set(ROLES.map((r) => roleOf(tree, r))).size, ROLES.length, state)
  }
})

test('a row shows its state as a mark and a word in the state colour; a done helper has no row', () => {
  const cases = { working: 'running', failed: 'failed', quiet: 'quiet' }
  for (const [state, name] of Object.entries(cases)) {
    const tree = draw(run([agent({ state, activity: null })]))
    const mark = texts(row(tree, 'a1')).find((t) => t.text === P.STATE_MARKS[name] + ' ')
    assert.ok(mark, state + ' row carries ' + P.STATE_MARKS[name])
    assert.equal(mark.props.color, P.stateColor(name), state)
    assert.ok(texts(row(tree, 'a1')).some((t) => t.text.includes(P.STATE_WORDS[name])), state + ' row says ' + P.STATE_WORDS[name])
  }
  assert.equal(row(draw(run([agent({ state: 'done' })])), 'a1'), undefined)
})

test('a run that was stopped leaves no row for what it cut off', () => {
  assert.equal(row(draw(run([agent()], { status: 'stopped', endedAt: NOW - 60 * S })), 'a1'), undefined)
})

test('the colour tells the role and the mark tells the state: they do not mix up', () => {
  const tree = draw(run([agent({ id: 'a', role: 'qa', state: 'failed' }), agent({ id: 'b', role: 'dev', state: 'working' })]))
  assert.equal(roleOf(tree, 'a'), P.roleColor('qa'))
  assert.equal(roleOf(tree, 'b'), P.roleColor('dev'))
  assert.equal(texts(row(tree, 'a')).find((t) => t.text === '✗ ').props.color, P.stateColor('failed'))
  assert.equal(texts(row(tree, 'b')).find((t) => t.text === '● ').props.color, P.stateColor('running'))
})

test('an unknown role is drawn in the neutral grey and does not crash rendering', () => {
  const tree = draw(run([agent({ id: 'x', role: 'mystery' }), agent({ id: 'y', role: undefined, state: 'weird' })]))
  assert.equal(roleOf(tree, 'x'), P.NEUTRAL)
  assert.equal(roleOf(tree, 'y'), P.NEUTRAL)
})

test('with colour off the state is still carried by the mark and the word', () => {
  const tree = draw(run([agent({ id: 'w', activity: null }), agent({ id: 'f', state: 'failed' }), agent({ id: 'q', state: 'quiet' })]))
  const plain = (id) => texts(row(tree, id)).map((t) => t.text).join('')
  assert.match(plain('w'), /● running/)
  assert.match(plain('f'), /✗ failed/)
  assert.match(plain('q'), /… quiet/)
})
