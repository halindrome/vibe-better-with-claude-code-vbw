// R227 (D522): a gate the kernel raises with an action no gateNeed case names still asks
// the user. The default branch of gateNeed (plugin/hooks/panel-view.js) builds the need
// from the kernel's instruction: the generic sentence in the Now panel's 'your turn' row,
// where the empty-state text would stand, and the instruction as the short request Comms
// puts after 'VBW needs you ·'. Pinned so a later edit cannot drop that branch unnoticed.
// Pure data in, rows out: no Claude Code needed (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next } from './helpers/fake-mod.mjs'

const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const NOW = Date.parse('2026-10-30T15:00:00Z')
const row = (v, id) => v.rows.find((r) => r.id === id)
const INVENTED = { action: 'frobnicate', gate: true, instruction: 'Run vbw frob to go on', since: '2026-10-30T14:50:00Z' }

test('liveNeed on a gate whose action no case names: the generic sentence, and the request built from the instruction', () => {
  const need = view.liveNeed({ record: record(), next: next(INVENTED) })
  assert.ok(need, 'the gate makes a need')
  assert.equal(need.kind, 'frobnicate')
  assert.equal(need.key, 'other:frobnicate')
  assert.equal(need.text, 'VBW is waiting for you: run /vbw:vibe to see what for.')
  assert.equal(need.what, 'Run vbw frob to go on')
  assert.equal(need.at, Date.parse('2026-10-30T14:50:00Z'))
  // Without an instruction the request still says a decision is needed.
  const bare = view.liveNeed({ record: record(), next: next({ ...INVENTED, instruction: undefined }) })
  assert.equal(bare.what, 'a decision is needed')
})

test("the Now panel's 'your turn' row carries that request where the empty-state text would stand", () => {
  const v = view.panelView({ record: record(), next: next(INVENTED), now: NOW })
  const need = row(v, 'need')
  assert.equal(need.term, 'your turn')
  assert.match(need.text, /VBW is waiting for you: run \/vbw:vibe to see what for\./)
  assert.doesNotMatch(need.text, /not waiting on you|Nothing is needed/)
  assert.equal(v.box.state.need, true)
  assert.equal(v.box.state.text, 'VBW is waiting for you: run /vbw:vibe to see what for.')
  // No gate: the row is the empty state and the box needs nothing.
  const idle = view.panelView({ record: record(), next: next(), now: NOW })
  assert.equal(row(idle, 'need').text, 'VBW is not waiting on you.')
  assert.equal(idle.box.state.need, false)
})
