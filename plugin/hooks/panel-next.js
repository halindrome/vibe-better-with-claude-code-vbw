// The Now tab's What's next section (R124, R125): the stored recommendation in
// vbw status order, a Suggest next button, and the fresh highlight (panel-candy.js) that marks a
// new recommendation. Pure: values in, trees out; no `$`, never throws.

import { ACCENT, ROLE_COLORS } from './panel-palette.js'
import { fresh } from './panel-candy.js'
import { dayClock } from './panel-step.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const str = (x) => typeof x === 'string' && x.trim() !== ''

export const TITLE = "What's next"
export const REQUEST = "/vbw:vibe what's next"

// nextModel(recommendation): { kind: 'none' } | { kind: 'empty', at } |
// { kind: 'pick', at, top: { text, reason, size, source }, runners: [{ text, size, source }] }.
// Any wrong type or missing field is 'none': a half-read pick is never shown.
export function nextModel(rec) {
  try {
    if (!isObj(rec) || !str(rec.at)) return { kind: 'none' }
    if (rec.empty === true) return { kind: 'empty', at: rec.at }
    const t = rec.top
    if (!isObj(t) || !str(t.text) || !str(t.reason) || !str(t.size) || !Array.isArray(rec.runners)) return { kind: 'none' }
    const runners = []
    for (const r of rec.runners.slice(0, 2)) {
      if (!isObj(r) || !str(r.text) || !str(r.size)) return { kind: 'none' }
      runners.push({ text: r.text, size: r.size, source: str(r.source) ? r.source : '' })
    }
    return { kind: 'pick', at: rec.at, top: { text: t.text, reason: t.reason, size: t.size, source: str(t.source) ? t.source : '' }, runners }
  } catch {
    return { kind: 'none' }
  }
}

// The local time of a stored moment as '[HH:MM]' ('[yesterday HH:MM]' on another day,
// dayClock's rule), or '' when it is not a time.
export function stamp(at, now) {
  const t = dayClock(Date.parse(at), now)
  return t ? '[' + t + ']' : ''
}

// What pressing a row puts in the prompt: its T or R id, else its text.
export const commandOf = (row) => '/vbw:vibe ' + (/^[TR]\d+$/.test(row.source) ? row.source : row.text)

// The section's lines before the width cut: [{ id, text, dim?, row? }]. A row
// is a pressable item { text, size, source, reason? }, drawn as one Button.
export function nextLines(model, now) {
  const m = isObj(model) ? model : { kind: 'none' }
  if (m.kind === 'empty') return [{ id: 'empty', text: 'the backlog is empty', dim: true }]
  if (m.kind !== 'pick') return [{ id: 'none', text: 'none yet', dim: true }]
  const out = [{ id: 'top', row: m.top, pick: true }]
  m.runners.forEach((r, i) => out.push({ id: 'runner' + i, row: r }))
  out.push({ id: 'at', text: (stamp(m.at, now) ? stamp(m.at, now) + ' ' : '') + 'written ' + m.at.slice(0, 10), dim: true })
  return out
}

const cut = (s, width) => {
  const cs = [...String(s)]
  const w = Number.isFinite(width) ? Math.max(1, Math.floor(width)) : 40
  return cs.length <= w ? cs.join('') : cs.slice(0, w - 1).join('') + '…'
}

const HIGHLIGHT = ROLE_COLORS.scout

// The title as Text pieces: one piece when still, else before / lit / after.
function titlePieces(Text, title) {
  const letters = [...TITLE]
  const whole = [h(Text, { key: 'title', bold: true, color: ACCENT }, TITLE)]
  if (title === null) return whole
  const from = Math.max(0, title - 1)
  const to = Math.min(letters.length, title + 2)
  if (from >= to) return whole
  const piece = (key, a, b, color) => (a < b ? h(Text, { key, bold: true, color }, letters.slice(a, b).join('')) : null)
  return [piece('t0', 0, from, ACCENT), piece('t1', from, to, HIGHLIGHT), piece('t2', to, letters.length, ACCENT)].filter(Boolean)
}

// The mark of a recommendation not yet seen: the word 'new'. Motion off draws
// the word alone; calm and full add a steady palette colour (the shimmer and
// pulse of fresh() come back at full motion until it is seen, and this mark stays).
export function newMark(Text, motion) {
  const props = { key: 'new', wrap: 'truncate' }
  if (motion === 'full' || motion === 'calm') Object.assign(props, { bold: true, color: ACCENT })
  return h(Text, props, ' new')
}

// The fresh key of a recommendation: 'now:next:' and when it was written.
export const freshKey = (rec) => (isObj(rec) && str(rec.at) ? 'now:next:' + rec.at : null)

// renderNext(ui, { recommendation, width, motion, fresh (the marks, panel-candy.js), now }, act) -> Box.
// A recommendation not yet seen shimmers and pulses at full motion, and is marked new, until seen.
export function renderNext(ui, input, act) {
  const { Box, Text, Button } = isObj(ui) ? ui : {}
  const { recommendation, width, motion, now } = isObj(input) ? input : {}
  const c = fresh({ marks: isObj(input) ? input.fresh : null, key: freshKey(recommendation), motion, now })
  const unseen = c.on
  const model = nextModel(recommendation)
  // A row pressed has been seen; Suggest next only fills the prompt.
  const press = (fill, seen) => () => { if (typeof act === 'function') act(seen ? { fill, seen: 'next' } : { fill }) }
  const lines = nextLines(model, now).map((l) => {
    if (!l.row) {
      const props = { key: l.id, wrap: 'truncate' }
      if (l.dim) props.dimColor = true
      return h(Text, props, cut(l.text, width))
    }
    const r = l.row
    const w = Number.isFinite(width) ? Math.max(1, Math.floor(width)) : 40
    // One Button, one line: '▸ item  [size]  reason'. Claude Code's h() lets a Button hold only
    // strings and Text (never a Box), so every piece is a Text inside it. The item takes what the
    // chip leaves; the reason, dim, sits on the line when it fits whole, else under it, cut.
    const chip = '  [' + r.size + ']'
    const item = cut(r.text, Math.max(1, w - 2 - [...chip].length))
    const left = w - 2 - [...item].length - [...chip].length - 2
    const beside = Boolean(r.reason) && [...r.reason].length <= left
    const itemProps = { key: 'item', wrap: 'truncate' }
    if (l.pick) Object.assign(itemProps, { bold: true, color: c.pulse === 2 ? HIGHLIGHT : ACCENT })
    return h(Box, { key: l.id, flexDirection: 'column' },
      h(Button, { key: 'item-button', plain: true, onPress: press(commandOf(r), true) },
        h(Text, { key: 'mark', wrap: 'truncate', ...(l.pick ? { color: ACCENT } : { dimColor: true }) }, '▸ '),
        h(Text, itemProps, item),
        h(Text, { key: 'chip', dimColor: true, wrap: 'truncate' }, chip),
        ...(beside ? [h(Text, { key: 'reason', dimColor: true, wrap: 'truncate' }, '  ' + r.reason)] : [])),
      ...(r.reason && !beside ? [h(Text, { key: 'reason', dimColor: true, wrap: 'truncate' }, cut('  ' + r.reason, w))] : []))
  })
  return h(Box, { key: 'whats-next', flexDirection: 'column', marginBottom: 1 },
    h(Box, { key: 'whats-next-title', flexDirection: 'row' }, ...titlePieces(Text, c.title), ...(unseen === true ? [newMark(Text, motion)] : [])),
    ...lines,
    h(Button, { key: 'suggest-next', label: 'Suggest next', onPress: press(REQUEST) }))
}
