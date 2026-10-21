// The panel's one helper for chats (R192): Claude Code's list of chats
// (<claude-config-dir>/sessions/*.json, read-only), and who holds the run in
// words. Names are untrusted text: escape sequences and control characters go,
// long names are cut with an ellipsis. Pure over its input except readRegistry,
// which reads through `$` and never throws.

import { ACCENT } from './panel-palette.js'

const isObj =(x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const NAME_MAX = 40
const ESC = String.fromCharCode(27) // the sequences are matched, never written out
const OSC = new RegExp(ESC + '\\][^\\u0007' + ESC + ']*(?:\\u0007|' + ESC + '\\\\)?', 'g')
const CSI = new RegExp(ESC + '\\[[0-?]*[ -/]*[@-~]', 'g')

// A text with its CSI and OSC escape sequences and every control character removed.
export function cleanName(s) {
  if (typeof s !== 'string') return ''
  return s
    .replace(OSC, '')
    .replace(CSI, '')
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, '')
    .trim()
}

// At most n characters: a longer text becomes its first n-1 and an ellipsis.
export function cutName(s, n) {
  const c = [...String(s)]
  return c.length > n ? c.slice(0, n - 1).join('') + '…' : String(s)
}

// The file texts that parse to an object with a string sessionId, newest updatedAt first.
export function registryEntries(texts) {
  if (!Array.isArray(texts)) return []
  const out = []
  for (const t of texts) {
    try {
      const v = JSON.parse(t)
      if (isObj(v) && typeof v.sessionId === 'string' && v.sessionId) out.push(v)
    } catch {
      // a malformed file is skipped
    }
  }
  const at = (e) => (Number.isFinite(e.updatedAt) ? e.updatedAt : -Infinity)
  return out.map((e, i) => ({ e, i })).sort((a, b) => (at(b.e) - at(a.e) || a.i - b.i)).map((x) => x.e)
}

// Claude Code's config folder, as tools/resolve-claude-dir.sh finds it; null when unknown.
export async function configDir($) {
  try {
    let dir = await $.env.get('CLAUDE_CONFIG_DIR')
    if (!dir) {
      const home = await $.env.get('HOME')
      if (!home) return null
      dir = (await $.fs.exists(home + '/.config/claude-code')) ? home + '/.config/claude-code' : home + '/.claude'
    }
    return dir.replace(/\/+$/, '')
  } catch {
    return null
  }
}

// The list of chats in the config folder `dir` (configDir, found once a session), newest
// first; [] when missing or unreadable.
export async function readRegistry($, dir) {
  try {
    if (typeof dir !== 'string' || !dir) return []
    const names = Object.values(await $.fs.list(dir + '/sessions'))
      .map((e) => (isObj(e) ? e.name : e)).filter((n) => typeof n === 'string' && /\.json$/.test(n))
    const texts = []
    for (const n of names) {
      try {
        texts.push(await $.fs.read(dir + '/sessions/' + n))
      } catch {
        // an unreadable file is skipped
      }
    }
    return registryEntries(texts)
  } catch {
    return []
  }
}

// The holder of the run: null without a session in the lease; else its display name
// (the list's current name, else the stored one, else 8 characters of the id), whether
// this chat holds it and whether a name is known.
export function holderName({ lease, registry, stored, sessionId } = {}) {
  if (!isObj(lease) || typeof lease.session !== 'string' || !lease.session) return null
  const self = sessionId === lease.session
  const listed = (Array.isArray(registry) ? registry : []).find((e) => isObj(e) && e.sessionId === lease.session)
  const fromList = listed ? cleanName(listed.name) : ''
  const fromStore = isObj(stored) && stored.session === lease.session ? cleanName(stored.session_name) : ''
  const name = fromList || fromStore
  return { name: cutName(name || lease.session.slice(0, 8), NAME_MAX), self, known: Boolean(name) }
}

const EMPTY = 'No other chats are open on this project'
const inside = (cwd, root) => typeof cwd === 'string' && typeof root === 'string' && root !== '' && (cwd === root || cwd.startsWith(root.replace(/\/+$/, '') + '/'))
const two = (n) => String(n).padStart(2, '0')
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
// 'HH:MM' on the local clock; another day is named as panel-step's times are
// ('yesterday 14:20', a weekday, 'tomorrow'); '' without a moment.
function hhmm(ms, now) {
  if (!Number.isFinite(ms)) return ''
  const d = new Date(ms)
  const days = Number.isFinite(now) ? Math.round((midnight(d) - midnight(new Date(now))) / 86400000) : 0
  const day = days === 0 ? '' : days === 1 ? 'tomorrow ' : days === -1 ? 'yesterday ' : DAY_NAMES[d.getDay()] + ' '
  return day + two(d.getHours()) + ':' + two(d.getMinutes())
}

// The Sessions tab: the chats of this project (cwd is the root or a folder under it),
// newest first, and the holder of the run, listed from the lease when no entry has it.
export function sessionsModel({ registry, root, sessionId, lease, stored, now, width, plans } = {}) {
  const room = Number.isInteger(width) && width > 1 ? width : 80
  const held = isObj(lease) && typeof lease.session === 'string' && lease.session ? lease.session : null
  const kind = held
    ? [String(lease.kind || 'run'), ...(Array.isArray(plans) ? plans : []).filter((p) => isObj(p) && p.status === 'building' && typeof p.id === 'string').map((p) => p.id)].join(' ')
    : ''
  // One row per session id: the newest updatedAt wins, as the kernel reads the list.
  const at = (e) => (Number.isFinite(e.updatedAt) ? e.updatedAt : -Infinity)
  const list = (Array.isArray(registry) ? registry : []).filter((e) => isObj(e) && typeof e.sessionId === 'string' && inside(e.cwd, root))
  const rows = list
    .filter((e, i) => list.findIndex((o) => o.sessionId === e.sessionId && at(o) > at(e)) < 0 && list.findIndex((o) => o.sessionId === e.sessionId && at(o) === at(e)) === i)
    .map((e) => ({
      id: e.sessionId,
      name: cutName(cleanName(e.name) || e.sessionId.slice(0, 8), room),
      state: typeof e.status === 'string' ? cleanName(e.status) : '',
      last: hhmm(e.updatedAt, now),
      resume: 'claude --resume ' + e.sessionId,
      self: e.sessionId === sessionId,
      holder: e.sessionId === held ? { kind } : null,
      closed: false,
    }))
  const empty = rows.some((r) => !r.self) ? null : EMPTY
  if (held && !rows.some((r) => r.id === held)) {
    const name = isObj(stored) && stored.session === held ? cleanName(stored.session_name) : ''
    rows.push({ id: held, name: cutName(name || held.slice(0, 8), room), state: '', last: '', resume: 'claude --resume ' + held, self: held === sessionId, holder: { kind }, closed: true })
  }
  return { rows, empty }
}

// Text only: no button and no input; the resume line is there to copy.
export function renderSessions(ui, model) {
  const { Box, Text } = ui
  const m = isObj(model) && Array.isArray(model.rows) ? model : { rows: [], empty: EMPTY }
  const kids = m.rows.map((r) => {
    const marks = []
    if (r.holder) marks.push(h(Text, { key: 'holder', color: ACCENT }, '● holds the run · ' + r.holder.kind))
    if (r.closed) marks.push(h(Text, { key: 'closed', dimColor: true }, 'closed or not seen'))
    if (r.self) marks.push(h(Text, { key: 'self', dimColor: true }, 'this chat'))
    return h(Box, { key: 'chat-' + r.id, flexDirection: 'column', marginBottom: 1 },
      h(Text, { bold: true }, r.name + (r.state ? ' · ' + r.state : '') + (r.last ? ' · last ' + r.last : '')),
      h(Text, { dimColor: true }, r.resume),
      ...marks)
  })
  if (m.empty) kids.push(h(Text, { key: 'empty' }, m.empty))
  return h(Box, { key: 'sessions', flexDirection: 'column' }, ...kids)
}
