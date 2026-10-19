// Comms (mods_4_vbw.md §3.1, §3.2, §3.8; R189): what the strip above the prompt
// shows. When VBW needs the person, one amber line, 'HH:MM ⚑ VBW needs you ·
// <what>', with no button: the `need` comes from panel-view.js (liveNeed) and
// leaves with the gate. While a VBW workflow runs, the helpers still at work: one
// row each (a finished one leaves at once and is counted in the top line's
// 'N done'; a failed one stays as a red ✗ row until it is seen). With full
// motion and room, a pixel figure for at most 3 working helpers
// (panel-candy.js; panel.js animates them). Rows beyond the room fold into
// one '+N more · [m] Mission Control' line. Otherwise nothing: the hint line
// already says what comes next.
// In little room the order is: the needs-you line, then the helper line while
// helpers work, then the step line. With one row left the helper line is the only
// one and carries the step's time words after its own parts; with two, the helper
// line and the step line; with the step line alone only when no helper works.
// Pure: data in, a model out (stageModel), a tree out (renderStage). No `$`,
// never changes its input, never throws.
import { poseOf, spriteFrame, encodeCells } from './panel-candy.js'
import { newMark } from './panel-next.js'
import { stepWords } from './panel-step.js'
import { roleColor as colorOfRole, stateColor, STATE_MARKS, NEED, ACCENT } from './panel-palette.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
const str = (x) => (typeof x === 'string' ? x : '')
const len = (s) => [...s].length

// Cut a line to `n` cells, marking the cut with an ellipsis.
const cut = (s, n) => (len(s) <= n ? s : n <= 0 ? '' : [...s].slice(0, n - 1).join('') + '…')
const pad = (s, n) => s + ' '.repeat(Math.max(0, n - len(s)))
const padStart = (s, n) => ' '.repeat(Math.max(0, n - len(s))) + s

const QUIET_MS = 45000
const FLASH_MS = 1000 // a new row shows inverted this long (full motion only)
const SPRITES = 3 // pixel figures at most, at full motion; the rest are text rows
const SPIN = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
// A workflow follows these steps of `vbw next`: the moment health nudges matter.
const RUNS = new Set(['plan', 'build', 'qa', 'fix'])
const STARTS_RUN = new Set(['approve', 'escalate', 'unblock', ...RUNS])

// 604 s -> 10m04s; an hour or more -> 1h02m.
function clock(ms) {
  const s = Math.max(0, Math.floor((num(ms) ? ms : 0) / 1000))
  const two = (n) => String(n).padStart(2, '0')
  if (s >= 3600) return Math.floor(s / 3600) + 'h' + two(Math.floor((s % 3600) / 60)) + 'm'
  return Math.floor(s / 60) + 'm' + two(s % 60) + 's'
}

// A moment as the local HH:MM; '' when it is not a moment.
const hhmm = (ms) => {
  if (!num(ms)) return ''
  const d = new Date(ms)
  return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
}

const tokens = (t) => {
  if (!num(t) || t < 0) return ''
  if (t >= 1e6) return (t / 1e6).toFixed(1) + 'M'
  return t >= 1000 ? Math.round(t / 1000) + 'k' : String(Math.round(t))
}

// --- the needs-you line --------------------------------------------------------

// `need` is { key, what, at } (panel-view.js liveNeed): the line is 'HH:MM ⚑ VBW needs you · <what>'.
// A need not yet seen (`fresh`) carries the mark after its text, which keeps its columns.
function needOf(need, columns, fresh, motion) {
  if (!isObj(need) || !str(need.what)) return null
  const time = hhmm(need.at)
  const mark = fresh === true
  return { key: str(need.key), text: cut((time ? time + ' ' : '') + '⚑ VBW needs you · ' + need.what, mark ? columns - 4 : columns), fresh: mark, motion }
}

// The weekly-limit line, only when a workflow is next.
function health(hl, action) {
  const out = []
  if (!isObj(hl) || !STARTS_RUN.has(action)) return out
  if (num(hl.weekPct) && hl.weekPct >= 80) {
    const w = Math.round(hl.weekPct)
    const per = num(hl.weekPerRun) && hl.weekPerRun > 0 ? 'a run like this used about ' + Math.round(hl.weekPerRun) + '% last time' : 'a long run may reach it'
    out.push({ text: 'Weekly limit ' + w + '%: ' + per + '.', color: NEED })
  }
  return out
}

// --- the step -------------------------------------------------------------------

// The running step, one line: what it is doing and its end time in the panel's
// wording ('proving 12 of 40 checks · about 8 min, until around 14:26'). '' with no
// step (the note went, or was never live), so the line goes at the next refresh.
function stepOf(step, words, columns) {
  if (!isObj(step) || !words) return ''
  const doing = str(step.doing) || str(step.kind)
  return cut((doing ? doing + ' · ' : '') + words.text, columns)
}

// --- the crew ----------------------------------------------------------------

// One helper as Comms shows it: a working or quiet one, or a failed one. A finished one has no row.
function rowOf(a, now, motion, born) {
  const role = str(a.role) || 'agent'
  const roleColor = colorOfRole(role)
  const start = num(a.startedAt) ? a.startedAt : now
  const end = num(a.endedAt) ? a.endedAt : null
  const base = { id: str(a.id), role, roleColor, label: str(a.label), time: hhmm(a.startedAt), elapsed: clock((end ?? now) - start), tokens: tokens(a.tokens), spin: '', button: null }
  if (a.state === 'failed') {
    return { ...base, glyph: STATE_MARKS.failed, glyphColor: stateColor('failed'), activity: str(a.result) || 'failed', activityColor: stateColor('failed'),
      button: { label: 'details', action: { open: 'mission', tab: 'now', agent: str(a.id) } } }
  }
  const age = isObj(born) && num(born[base.id]) ? now - born[base.id] : -1
  const flash = motion === 'full' && age >= 0 && age < FLASH_MS ? { flash: true } : {}
  const seen = num(a.lastSeenAt) ? a.lastSeenAt : start
  if (a.state === 'quiet' || now - seen >= QUIET_MS) {
    return { ...base, ...flash, glyph: STATE_MARKS.quiet, glyphColor: stateColor('quiet'), quiet: true, activity: 'quiet ' + clock(now - seen), activityColor: stateColor('quiet') }
  }
  const act = isObj(a.activity) ? a.activity : null
  const said = act && str(act.text) && act.kind === 'text'
  const text = act && str(act.text) ? (said ? '"' + act.text + '"' : act.text) : 'working'
  const step = motion === 'off' ? 0 : Math.floor(now / (motion === 'calm' ? 1000 : 250))
  return { ...base, ...flash, glyph: STATE_MARKS.running, glyphColor: stateColor('running'), activity: text, activityColor: undefined, intent: !said, spin: motion === 'off' ? '·' : SPIN[step % SPIN.length] }
}

const ROLE_W = 9
const LABEL_W = 10

// Fit each row to the columns: the activity takes what the fixed cells leave;
// when too narrow, elapsed and tokens go first, then the start time, then the label shrinks.
function fit(rows, columns, full) {
  const lw = Math.min(LABEL_W, Math.max(0, ...rows.map((r) => len(r.label))))
  return rows.map((r) => {
    // A figure takes 4 more columns than the dot, and is the row's only motion.
    const fixed = 2 + ROLE_W + 1 + 2 + (r.pose ? 4 : 0) + (r.spin ? 2 : 0) + (r.button ? len(r.button.label) + 6 : 0)
    const t = r.time
    const tails = [...(full && t ? ['  ' + t + '  ' + padStart(r.elapsed, 6) + '  ' + padStart(r.tokens, 4)] : []), ...(t ? ['  ' + t] : [])]
    const tail = tails.find((x) => columns - fixed - lw - len(x) >= 8) || ''
    const w = Math.max(0, Math.min(lw, columns - fixed - 8))
    const room = Math.max(0, columns - fixed - w - len(tail))
    return { ...r, label: pad(cut(r.label, w), w), activity: cut(r.activity, room), elapsed: tail.includes(r.elapsed) ? r.elapsed : '', tokens: tail.includes(r.elapsed) ? r.tokens : '', tail }
  })
}

// The crew: the helpers still at work, the failures not yet seen. Null when there is nothing to draw.
function crewOf(rn, now, columns, maxRows, motion, cost, born, seen, stepLine, timeWords) {
  const running = rn.status === 'running'
  const ended = num(rn.endedAt) ? rn.endedAt : null
  const agents = rn.agents.filter((a) => isObj(a) && typeof a.id === 'string' && a.id)
  const unseen = (a) => a.state === 'failed' && !seen.has(a.id)
  let rows = agents.filter((a) => (running ? a.state !== 'done' && (a.state !== 'failed' || unseen(a)) : unseen(a))).map((a) => rowOf(a, now, motion, born))
  if (!running && !rows.length) return null
  const doneAll = agents.filter((a) => a.state === 'done').length
  const kind = str(rn.kind) || 'run'
  const time = clock((ended ?? now) - (num(rn.startedAt) ? rn.startedAt : now))
  const status = running || !str(rn.status) ? '' : rn.status
  const button = { key: 'p', label: 'Mission Control', action: { open: 'mission' } }
  const room = columns - len(button.label) - 6
  if (maxRows < 4) {
    const working = agents.filter((a) => a.state === 'working' || a.state === 'quiet').length
    const parts = ['VBW ▸ ' + kind, status, working ? working + ' working' : '', doneAll ? doneAll + ' done' : '', time, timeWords].filter(Boolean)
    return { kind: 'crew', mode: 'line', header: { text: cut(parts.join(' · '), room), button }, rows: [], more: 0, ...(stepLine ? { step: stepLine } : {}) }
  }
  let failedKey = false
  rows = rows.map((r) => {
    if (!r.button) return r
    const b = { ...r.button, ...(failedKey ? {} : { key: 'd' }) }
    failedKey = true
    return { ...r, button: { key: b.key, label: b.label, action: b.action } }
  })
  const full = maxRows >= 8
  const avail = maxRows - 1
  // Figures: 3 rows a helper, for at most 3 working helpers, when they all fit with the other rows.
  const live = rows.filter((r) => !r.quiet && r.glyph === STATE_MARKS.running).length
  let figures = motion === 'full' && full && running ? Math.min(SPRITES, live) : 0
  while (figures > 0 && rows.length + 2 * figures > avail) figures--
  let more = 0
  if (rows.length > avail) {
    more = rows.length - (avail - 1)
    rows = rows.slice(0, avail - 1)
  }
  if (figures > 0) {
    const byId = new Map(agents.map((a) => [a.id, a]))
    let n = 0
    rows = rows.map((r) => (n < figures && !r.quiet && r.glyph === STATE_MARKS.running && ++n ? { ...r, spin: '', pose: poseOf(byId.get(r.id).activity, 'working') } : r))
  }
  const price = full && num(cost) && cost >= 0 ? '≈$' + cost.toFixed(2) + ' this run' : ''
  const parts = ['VBW ▸ ' + kind, status, str(rn.phase), doneAll ? doneAll + ' done' : '', time]
  if (price) parts.push(price)
  const model = { kind: 'crew', mode: full ? 'full' : 'compact', header: { text: cut(parts.filter(Boolean).join(' · '), room), ...(price ? { cost: price } : {}), button }, rows: fit(rows, columns, full), more }
  const withStep = stepLine ? { ...model, step: stepLine } : model
  return figures > 0 ? { ...withStep, sprites: true } : withStep
}

// --- the model ---------------------------------------------------------------

// What Comms shows, top down: the needs-you line (`need`), then the crew while a
// workflow runs (and failures not yet seen after it), else a health nudge
// before a workflow. Null when there is nothing to say.
export function stageModel(input) {
  try {
    if (!isObj(input)) return null
    const { run: rn, next: nx, health: hl, cost, motion, born } = input
    const now = num(input.now) ? input.now : Date.now()
    const columns = num(input.columns) && input.columns > 0 ? Math.floor(input.columns) : 80
    const maxRows = num(input.maxRows) && input.maxRows > 0 ? Math.floor(input.maxRows) : 8
    const need = needOf(input.need, columns, input.fresh, motion)
    // The needs-you line comes first; the step line takes the next row when there is one.
    const left = maxRows - (need ? 1 : 0)
    const words = left >= 1 && isObj(input.step) ? stepWords(input.step, now) : null
    const stepText = stepOf(input.step, words, columns)
    const seen = new Set(Array.isArray(input.seen) ? input.seen.filter((x) => typeof x === 'string') : [])
    if (left >= 1 && isObj(rn) && Array.isArray(rn.agents) && rn.agents.some((a) => isObj(a) && typeof a.id === 'string' && a.id)) {
      // One row left: the helper line carries the step's time words, the step line gives way.
      const crew = left === 1
        ? crewOf(rn, now, columns, 1, motion, cost, born, seen, '', words && words.timed ? words.text : '')
        : crewOf(rn, now, columns, left - (stepText ? 1 : 0), motion, cost, born, seen, stepText, '')
      if (crew) return need ? { ...crew, need } : crew
    }
    if (stepText) return { kind: 'step', step: stepText, ...(need ? { need } : {}), lines: [] }
    const action = isObj(nx) && typeof nx.action === 'string' ? nx.action : ''
    const lines = health(hl, action).slice(0, Math.max(0, need ? left : maxRows - 1)).map((l) => ({ ...l, text: cut(l.text, columns) }))
    if (need) return { kind: 'need', need, lines }
    if (RUNS.has(action) && lines.length) return { kind: 'nudge', title: cut('VBW · before the ' + action + ' run', columns), lines }
    return null
  } catch {
    return null
  }
}

// --- the tree ----------------------------------------------------------------

// Draw the model with the elements of $.ui.resolve(e). `onAction(action)` is
// called on a press; without it, Buttons carry no onPress (the plugin's
// ui.press hook answers them by key).
export function renderStage(ui, model, onAction) {
  try {
    if (!isObj(ui) || !isObj(model)) return null
    const { Box, Text, Button } = ui
    const button = (b, id) => h(Button, {
      key: 'vbw-stage-' + id, label: b.label, hotkey: b.key,
      ...(typeof onAction === 'function' ? { onPress: () => onAction(b.action) } : {}),
    })
    const needText = (n) => h(Text, { key: 'need', color: NEED, bold: true, wrap: 'truncate-end' }, String(n.text))
    const needLine = isObj(model.need)
      ? [model.need.fresh ? h(Box, { key: 'need-row', flexDirection: 'row' }, needText(model.need), newMark(Text, model.need.motion)) : needText(model.need)]
      : []
    const notes = (model.lines || []).map((l, i) => h(Text, { key: 'line-' + i, color: l.color, wrap: 'truncate-end' }, String(l.text)))
    const stepRow = typeof model.step === 'string' && model.step ? [h(Text, { key: 'step', wrap: 'truncate-end' }, model.step)] : []
    if (model.kind === 'step') return h(Box, { flexDirection: 'column' }, ...needLine, ...stepRow)
    if (model.kind === 'need') return h(Box, { flexDirection: 'column' }, ...needLine, ...notes)
    if (model.kind === 'nudge') return h(Box, { flexDirection: 'column' }, h(Text, { key: 'title', color: NEED, wrap: 'truncate-end' }, String(model.title)), ...notes)
    if (model.kind !== 'crew' || !isObj(model.header) || !Array.isArray(model.rows)) return null
    const head = String(model.header.text)
    const price = typeof model.header.cost === 'string' && model.header.cost && head.endsWith(model.header.cost) ? model.header.cost : ''
    const header = h(Box, { key: 'header', flexDirection: 'row', justifyContent: 'space-between' },
      h(Box, { flexDirection: 'row' },
        h(Text, { bold: true, wrap: 'truncate-end' }, price ? head.slice(0, head.length - price.length) : head),
        ...(price ? [h(Text, { bold: true, color: ACCENT, wrap: 'truncate-end' }, price)] : [])),
      button(model.header.button, 'mission'))
    // A tool call is its verb (role colour) and its object (dim), cut as one phrase.
    const intent = (r) => {
      const at = r.intent ? r.activity.search(/\s/) : -1
      if (at < 0) return [h(Text, { color: r.intent ? r.roleColor : r.activityColor, wrap: 'truncate-end' }, r.activity)]
      return [h(Text, { color: r.roleColor }, r.activity.slice(0, at)), h(Text, { dimColor: true, wrap: 'truncate-end' }, r.activity.slice(at))]
    }
    const sprite = (r) => h(ui.Raster, {
      key: 'vbw-sprite-' + r.id, columns: 5, rows: 3, cells: encodeCells(spriteFrame({ role: r.role, pose: r.pose, frame: 0 })),
    })
    const rows = model.rows.map((r) => h(Box, { key: 'agent-' + r.id, flexDirection: 'row' },
      model.sprites === true && r.pose && ui.Raster ? sprite(r) : h(Text, { color: r.glyphColor }, r.glyph),
      h(Text, { color: r.roleColor, ...(r.flash ? { inverse: true } : {}) }, ' ' + pad(r.role, ROLE_W) + ' '),
      h(Text, { color: r.roleColor, ...(r.flash ? { inverse: true } : {}) }, r.label + '  '),
      ...(r.spin ? [h(Text, { color: r.roleColor }, r.spin + ' ')] : []),
      ...intent(r),
      ...(r.tail ? [h(Text, { dimColor: true }, r.tail)] : []),
      ...(r.button ? [h(Text, null, '  '), button(r.button, 'details-' + r.id)] : [])))
    const fold = model.more ? [h(Box, { key: 'more', flexDirection: 'row', columnGap: 1 },
      h(Text, { dimColor: true }, '+' + model.more + ' more ·'), button({ key: 'm', label: 'Mission Control', action: { open: 'mission' } }, 'more'))] : []
    return h(Box, { flexDirection: 'column' }, ...needLine, header, ...stepRow, ...rows, ...fold)
  } catch {
    return null
  }
}
