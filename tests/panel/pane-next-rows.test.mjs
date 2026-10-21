// T160 (L1, the stand-in for Claude Code's mods API, whose h() lets a Button hold
// only strings and Text): the Now tab of a shipped milestone with a What's next
// recommendation that has rows draws the whole pane (tab row and each row), a
// pressed row fills the prompt with its command and never sends it, and a pane
// that cannot draw says so in one dim line instead of staying empty.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, find, collect, dimTexts } from './helpers/fake-mod.mjs'

const REC = {
  at: '2026-10-09T10:00:00Z',
  top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most this month.', size: 'small', source: 'T4' },
  runners: [{ text: 'Gift cards', size: 'large', source: 'T9' }, { text: 'Dark mode', size: 'medium' }],
}
const shipped = () => record({
  milestone: { id: 'M9', title: 'Live VBW panel', status: 'shipped' },
  shipped: [{ id: 'M9', title: 'Live VBW panel', at: '2026-10-08T10:00:00Z' }],
  recommendation: REC,
})

async function session(rec, options = {}) {
  const h = await mount(options)
  h.project(rec, next())
  await h.start()
  await h.advance(4000)
  return h
}

test('shipped milestone with a recommendation: the Now tab draws the tab row and each What\'s next row', async () => {
  const h = await session(shipped())
  const all = await h.text()
  for (const re of [/Refunds for paid orders/, /Gift cards/, /Dark mode/, /Customers ask for it most/]) assert.match(all, re)
  const labels = collect(await h.render())
  assert.ok(labels.includes('Plan'), 'the tabs draw: ' + labels.slice(0, 8).join(' | '))
  assert.deepEqual(h.errors, [])
})

test('pressing a What\'s next row fills the prompt with its command and sends nothing', async () => {
  const h = await session(shipped())
  const b = find(await h.render(), (n) => n.type === 'Button' && n.children.some((c) => c.type === 'Text' && /Refunds/.test(c.children.join(''))))
  assert.ok(b, 'a Button holds the top pick')
  await b.props.onPress({ surface: 'terminal' })
  await h.settle()
  const fills = h.callsOf('prompt.fill')
  assert.equal(fills.length, 1)
  assert.match(fills[0][0].text, /^\/vbw:vibe .*T4/)
  assert.equal(h.count('prompt.submit'), 0)
})

test('a pane that cannot draw says so in one dim line, never an empty pane', async () => {
  const h = await session(shipped(), { brokenBox: true })
  const tree = await h.render()
  assert.notDeepEqual(tree, { type: 'engine', ref: 'default' })
  const line = dimTexts(tree).join('\n')
  assert.match(line, /^Mission Control could not draw: /)
  assert.match(line, /holds strings and Text, not <Box>/)
  assert.doesNotMatch(line, /\n.*\n/)
})
