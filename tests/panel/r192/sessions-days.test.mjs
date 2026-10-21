// R192 (L1) regression: the Sessions tab names another day like the rest of the
// panel, and one chat with two files in Claude Code's list shows once, newest.
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, ROOT } from '../helpers/fake-mod.mjs'

const S = await import(pathToFileURL(PLUGIN + '/hooks/panel-sessions.js').href)
process.env.TZ = 'Europe/Zurich' // not UTC, so local time is proven
const DAY = 86400000
const NOW = Date.parse('2026-10-19T12:00:00Z') // a Monday, 14:00 in Zurich
const e = (over) => JSON.stringify({ sessionId: 'a', cwd: ROOT, name: 'x', status: 'idle', updatedAt: NOW, ...over })
const model = (texts) => S.sessionsModel({ registry: S.registryEntries(texts), root: ROOT, sessionId: 'me', lease: null, stored: null, now: NOW, width: 80 })

test('today is bare HH:MM, yesterday and older days are named', () => {
  const m = model([e({ sessionId: 'a', updatedAt: NOW }), e({ sessionId: 'b', updatedAt: NOW - DAY }), e({ sessionId: 'c', updatedAt: NOW - 3 * DAY })])
  const last = Object.fromEntries(m.rows.map((r) => [r.id, r.last]))
  assert.equal(last.a, '14:00')
  assert.equal(last.b, 'yesterday 14:00')
  assert.equal(last.c, 'Friday 14:00')
})

test('two files of one session id give one row, the newest', () => {
  const texts = [e({ name: 'old', updatedAt: NOW - 5000 }), e({ name: 'new', updatedAt: NOW }), e({ sessionId: 'b', updatedAt: NOW - 9000 })]
  const m = model(texts)
  assert.deepEqual(m.rows.map((r) => r.id + '/' + r.name), ['a/new', 'b/x'])
})
