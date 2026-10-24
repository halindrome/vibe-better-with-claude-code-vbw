// Mission Control's live tabs (mods_4_vbw.md §3.3): Now (the crew: one row per
// helper at work), Timeline (agent lanes on the run clock, past steps as
// a sparkline against the R58 median) and the Now box's drawing (its model is panel-view.js's). Pure:
// the run model in, plain models out, trees built with h(); never throws.

import { estimate, MIN_STEPS } from './panel-estimate.js'
import { stepWords } from './panel-step.js'
import { newMark } from './panel-next.js'
import { roleColor, stateColor, ACCENT, NEED, PROGRESS, ESTIMATE, STATE_MARKS, STATE_WORDS } from './panel-palette.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
const str = (x) => (typeof x === 'string' ? x : '')
const safe = (fn) => (input) => {
  try {
    return fn(isObj(input) ? input : {})
  } catch {
    return null
  }
}

const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
const STATES = ['working', 'done', 'failed', 'quiet', 'cut']
// A card's working state is the palette's running; the rest share their names.
const paletteState = (state) => (state === 'working' ? 'running' : state)
// A run kind and the step kind its finished leases are recorded under (steps.json).
const STEP_KIND = { planning: 'plan', building: 'build', verifying: 'qa', fixing: 'fix', mapping: 'map' }
const BARS = '▁▂▃▄▅▆▇█'

const roleOf = (a) => (ROLES.includes(a.role) ? a.role : 'agent')
const titleOf = (a) => [str(a.role) || 'agent', str(a.label)].filter(Boolean).join(' ')
const agentsOf = (run) =>
  run.agents.filter((a) => isObj(a) && typeof a.id === 'string')
    .map((a, i) => ({ a, i })).sort((x, y) => (num(x.a.startedAt) ? x.a.startedAt : 0) - (num(y.a.startedAt) ? y.a.startedAt : 0) || x.i - y.i)
    .map((x) => x.a)
const validRun = (run) => isObj(run) && Array.isArray(run.agents)

// 45 s, 3 min 12 s, 10 min.
export function duration(ms) {
  const s = Math.max(0, Math.round((num(ms) ? ms : 0) / 1000))
  if (s < 60) return s + ' s'
  const m = Math.floor(s / 60)
  return s % 60 ? m + ' min ' + (s % 60) + ' s' : m + ' min'
}

function tokens(n) {
  if (!num(n) || n < 0) return null
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M tokens'
  if (n >= 1000) return Math.round(n / 1000) + 'k tokens'
  return n + ' tokens'
}

// The state an agent shows: what was still going when the run ended (stopped, failed or
// completed) is cut off; a run still working never shows a card as ended.
function stateOf(a, run) {
  const s = STATES.includes(a.state) ? a.state : 'quiet'
  const ended = str(run.status) !== '' && run.status !== 'running'
  return ended && (s === 'working' || s === 'quiet') ? 'cut' : s
}

// The crew of the Now tab (2.1.11: Team folds into Now): one row per helper still at
// work, `role label  ● doing · 2 min 10 s`, the longest-running first. A finished
// helper leaves at once (Timeline keeps the history); a failed one stays first, in
// red with its reason, until it is seen (opened or pressed), as on Comms. When the run
// has ended only those failures stay. `width` (columns) cuts the doing text, never the
// name, the mark or the time.
const crewState = (a, running) => {
  const s = STATES.includes(a.state) ? a.state : 'quiet'
  if (s === 'failed') return 'failed'
  return running && s !== 'done' && s !== 'cut' ? s : null
}

export const nowModel = safe(({ run, now, selected, seen, motion, width }) => {
  if (!validRun(run)) return null
  const opened = new Set(Array.isArray(seen) ? seen : [])
  const t = num(now) ? now : Date.now()
  const running = str(run.status) === '' || run.status === 'running'
  const agents = agentsOf(run)
  const row = (a) => {
    const state = crewState(a, running)
    const p = paletteState(state)
    const act = isObj(a.activity) && str(a.activity.text) ? a.activity.text : ''
    const doing = state === 'failed' ? str(a.result) || STATE_WORDS.failed : state === 'quiet' ? STATE_WORDS.quiet : act || STATE_WORDS[p]
    const start = num(a.startedAt) ? a.startedAt : t
    const end = state === 'failed' && num(a.endedAt) ? a.endedAt : t
    return {
      id: a.id, title: titleOf(a), role: roleOf(a), roleColor: roleColor(roleOf(a)), state,
      mark: STATE_MARKS[p], word: STATE_WORDS[p], stateColor: stateColor(p),
      doing, tool: state === 'working' && Boolean(act) && a.activity.kind === 'tool', elapsed: duration(end - start),
      selected: a.id === selected, action: { select: a.id }, fresh: state === 'failed', motion,
    }
  }
  const rows = agents.filter((a) => {
    const s = crewState(a, running)
    return s !== null && !(s === 'failed' && opened.has(a.id))
  }).map(row)
  // Failures first (they wait for you), then the longest-running first (agentsOf orders by start).
  rows.sort((x, y) => (x.state === 'failed' ? 0 : 1) - (y.state === 'failed' ? 0 : 1))
  const sel = agents.find((a) => a.id === selected)
  const detail = sel ? {
    id: sel.id, label: titleOf(sel), role: roleOf(sel), model: str(sel.model) || null,
    activity: isObj(sel.activity) && str(sel.activity.text) ? sel.activity.text : null,
    result: str(sel.result) || null,
    elapsed: num(sel.startedAt) ? duration((num(sel.endedAt) ? sel.endedAt : t) - sel.startedAt) : null,
  } : null
  const end = num(run.endedAt) ? run.endedAt : t
  const header = { kind: str(run.kind) || 'run', status: str(run.status) || 'running', elapsed: num(run.startedAt) ? duration(end - run.startedAt) : null, done: agents.filter((a) => a.state === 'done').length }
  return { header, rows, started: agents.length > 0, width: num(width) && width > 0 ? Math.floor(width) : null, detail }
})

// The parts strip: one cell a part (scaled to `room` cells when there are more), done in the
// progress colour, the rest dim, then 'N of M done'.
function partsStrip(ui, parts, room) {
  const cellsWide = Math.max(1, Math.min(parts.total, room))
  const done = Math.round((parts.done / parts.total) * cellsWide)
  return h(ui.Box, { key: 'parts', flexDirection: 'row' },
    h(ui.Text, { key: 'done', color: PROGRESS }, '▰'.repeat(done)),
    h(ui.Text, { key: 'left', dimColor: true }, '▱'.repeat(cellsWide - done)),
    h(ui.Text, { key: 'figure' }, ' ' + parts.done + ' of ' + parts.total + ' done'))
}

// options: { width (the pane's columns), labels (the dim one-word terms; true unless false) }.
export function renderNowBox(ui, box, options) {
  if (!isObj(box) || !isObj(box.state)) return null
  const o = isObj(options) ? options : {}
  const labels = o.labels !== false
  const inner = Math.max(10, (num(o.width) ? Math.floor(o.width) : 50) - 4)
  const figure = box.parts ? (' ' + box.parts.done + ' of ' + box.parts.total + ' done').length : 0
  const term = (t, key) => (labels && t ? h(ui.Text, { key, dimColor: true }, t) : null)
  return h(ui.Box, { key: 'now-box', flexDirection: 'column', borderStyle: 'round', paddingX: 1, marginBottom: 1 },
    h(ui.Text, { key: 'state', bold: true, color: box.state.need ? NEED : undefined }, String(box.state.text)),
    box.command ? h(ui.Text, { key: 'command' }, 'Type ' + box.command + '.') : null,
    box.step && box.step.text ? h(ui.Text, { key: 'step' }, String(box.step.text)) : null,
    box.parts ? partsStrip(ui, box.parts, Math.min(40, inner - figure)) : null,
    box.step && box.step.end ? h(ui.Text, { key: 'end', color: box.step.timed ? ESTIMATE : undefined }, String(box.step.end)) : null,
    box.milestone ? h(ui.Text, { key: 'milestone', color: box.milestone.known ? ESTIMATE : undefined }, box.milestone.text) : null,
    box.milestone && box.milestone.basis ? h(ui.Text, { key: 'basis', dimColor: true }, box.milestone.basis) : null,
    box.milestone ? term(box.milestone.term, 'milestone-term') : null,
    h(ui.Text, { key: 'cost', color: box.cost.known ? ACCENT : undefined }, box.cost.text),
    term(box.cost.term, 'cost-term'))
}

// Past steps of this run's kind as bars, the median (R58, via estimate) and the bar nearest it.
function sparkOf(steps, kind, now) {
  const secs = steps.filter((s) => isObj(s) && s.kind === kind && num(s.seconds) && s.seconds > 0).slice(-20).map((s) => s.seconds)
  if (!secs.length) return null
  const lo = Math.min(...secs)
  const hi = Math.max(...secs)
  const bars = secs.map((s) => BARS[hi === lo ? 3 : Math.round(((s - lo) / (hi - lo)) * 7)]).join('')
  let median = null
  let mark = null
  if (secs.length >= MIN_STEPS) {
    const e = estimate({ steps, lease: { kind, started_at: new Date(now).toISOString() }, now })
    median = e.step && e.step.state === 'approx' ? e.step.seconds : null
  }
  if (median !== null) {
    mark = 0
    secs.forEach((s, i) => { if (Math.abs(s - median) < Math.abs(secs[mark] - median)) mark = i })
  }
  return { bars, median, mark, kind }
}

// The time left is the kernel's note, worded as everywhere else (panel-step.js); the Timeline works none out.
function leftOf(run, step, now) {
  if (num(run.endedAt) || !isObj(step)) return null
  const words = stepWords(step, now)
  return words ? words.text : null
}

export const timelineModel = safe(({ run, now, steps, step, width }) => {
  if (!validRun(run)) return null
  const t = num(now) ? now : Date.now()
  const w = num(width) ? Math.max(10, Math.floor(width)) : 40
  const start = num(run.startedAt) ? run.startedAt : t
  const end = num(run.endedAt) ? run.endedAt : t
  const span = Math.max(1, end - start)
  const col = (ms) => Math.min(w, Math.max(0, ((ms - start) / span) * w))
  const lanes = agentsOf(run).map((a) => {
    const a0 = num(a.startedAt) ? a.startedAt : start
    const a1 = num(a.endedAt) ? a.endedAt : end
    const from = Math.min(w - 1, Math.floor(col(a0)))
    return {
      id: a.id, name: titleOf(a), role: roleOf(a), color: roleColor(roleOf(a)), state: stateOf(a, run),
      from, to: Math.max(from + 1, Math.ceil(col(a1))), seconds: Math.max(0, Math.round((a1 - a0) / 1000)), slow: false,
    }
  })
  if (lanes.length > 3) {
    const slow = new Set(lanes.slice().sort((x, y) => y.seconds - x.seconds).slice(0, 3).map((l) => l.id))
    for (const l of lanes) l.slow = slow.has(l.id)
  }
  const history = Array.isArray(steps) ? steps : []
  const kind = STEP_KIND[run.kind] || str(run.kind)
  return { width: w, lanes, spark: sparkOf(history, kind, t), left: leftOf(run, step, t) }
})

// ---- Renders: ui = $.ui.resolve(e); `act` receives a card's action when it is pressed.

const NO_RUN = 'No VBW workflow runs in this session right now.'
const empty = (ui, text) => h(ui.Box, { flexDirection: 'column' }, h(ui.Text, { dimColor: true }, text))

const cells = (x) => [...x].length
const cutTo = (x, n) => (cells(x) <= n ? x : n <= 0 ? '' : [...x].slice(0, n - 1).join('') + '…')

// What a helper does: a tool intention is its verb in the role colour and the object
// dimmed; a failure is red, anything else dimmed whole. Cut to `room` cells.
function doingLine(ui, r, room) {
  const text = cutTo(r.doing, room)
  if (r.state === 'failed') return [h(ui.Text, { key: 'doing', color: r.stateColor }, text)]
  const i = r.tool ? text.indexOf(' ') : -1
  if (!r.tool) return [h(ui.Text, { key: 'doing', dimColor: true }, text)]
  if (i < 0) return [h(ui.Text, { key: 'doing', color: r.roleColor }, text)]
  return [h(ui.Text, { key: 'verb', color: r.roleColor }, text.slice(0, i)), h(ui.Text, { key: 'object', dimColor: true }, text.slice(i))]
}

// The crew: the header line, then one row per helper; a press on a row selects it.
export function renderNow(ui, model, act) {
  if (!isObj(model) || !Array.isArray(model.rows)) return empty(ui, NO_RUN)
  const hd = model.header || {}
  const header = [hd.kind, hd.status, hd.elapsed, hd.done ? hd.done + ' done' : ''].filter(Boolean).join(' · ')
  const nameW = Math.min(16, Math.max(0, ...model.rows.map((r) => cells(r.title))))
  const row = (r) => {
    const name = cutTo(r.title, nameW).padEnd(nameW) + '  '
    const tail = ' · ' + r.elapsed
    const room = model.width ? model.width - cells(name) - 2 - cells(tail) - (r.fresh ? 4 : 0) : Infinity
    return h(ui.Box, { key: 'crew:' + r.id, flexDirection: 'row' },
      h(ui.Button, { key: 'crew-name:' + r.id, plain: true, onPress: () => { if (typeof act === 'function') act(r.action) } },
        h(ui.Text, { color: r.roleColor, bold: r.selected }, name)),
      h(ui.Text, { key: 'mark', color: r.stateColor }, r.mark + ' '),
      ...doingLine(ui, r, room),
      h(ui.Text, { key: 'time', dimColor: true }, tail),
      r.fresh ? newMark(ui.Text, r.motion) : null)
  }
  const d = model.detail
  const detail = isObj(d)
    ? h(ui.Box, { flexDirection: 'column', marginTop: 1 },
      h(ui.Text, { bold: true, color: roleColor(d.role) }, d.label),
      h(ui.Text, null, 'Model: ' + (d.model || 'not known')),
      d.elapsed ? h(ui.Text, null, 'Elapsed: ' + d.elapsed) : null,
      d.activity ? h(ui.Text, null, 'Doing: ' + d.activity) : null,
      d.result ? h(ui.Text, null, 'Result: ' + d.result) : null)
    : null
  const none = model.started ? 'No helper is at work right now.' : 'No helper has started yet.'
  return h(ui.Box, { flexDirection: 'column' },
    h(ui.Text, { bold: true }, header),
    ...(model.rows.length ? model.rows.map(row) : [h(ui.Text, { dimColor: true }, none)]),
    detail)
}

// A refusal row of the Now tab (panel-lines.js refusalRow): the short amber line, then
// dimmed `· N files in this run`, then [ show ] when there is more to read; `open`, the
// whole text under it and [ hide ]. A press asks act({ toggle: id }) (panel.js keeps st.open[id]); the term under it.
export function renderRefusal(ui, row, open, act) {
  if (!isObj(row) || !str(row.text)) return null
  const press = () => { if (typeof act === 'function') act({ toggle: row.id }) }
  return h(ui.Box, { key: row.id, flexDirection: 'column', marginBottom: 1 },
    h(ui.Box, { key: 'line', flexDirection: 'row' },
      h(ui.Text, { key: 'text', color: NEED }, row.text),
      row.more ? h(ui.Text, { key: 'more', dimColor: true }, ' ' + row.more) : null,
      row.full ? h(ui.Text, { key: 'gap' }, ' ') : null,
      row.full ? h(ui.Button, { key: 'show:' + row.id, label: open ? 'hide' : 'show', onPress: press }) : null),
    open && row.full ? h(ui.Text, { key: 'full', color: NEED }, row.full) : null,
    h(ui.Text, { key: 'term', dimColor: true }, str(row.term) || 'refused'))
}

export function renderTimeline(ui, model) {
  if (!isObj(model) || !Array.isArray(model.lanes)) return empty(ui, NO_RUN)
  const nameW = Math.min(16, Math.max(4, ...model.lanes.map((l) => l.name.length)))
  const lane = (l) =>
    h(ui.Box, { key: 'lane:' + l.id, flexDirection: 'row' },
      h(ui.Text, { color: l.color }, l.name.slice(0, nameW).padEnd(nameW + 1)),
      h(ui.Text, { color: l.slow ? stateColor('running') : l.color, bold: l.slow }, ' '.repeat(l.from) + '█'.repeat(l.to - l.from)),
      h(ui.Text, { dimColor: !l.slow }, ' ' + duration(l.seconds * 1000)))
  const sp = model.spark
  const spark = isObj(sp)
    ? h(ui.Box, { flexDirection: 'column', marginTop: 1 },
      h(ui.Text, null, sp.bars),
      sp.mark !== null ? h(ui.Text, { dimColor: true }, ' '.repeat(sp.mark) + '▲ median ' + duration(sp.median * 1000)) : null,
      h(ui.Text, { dimColor: true }, 'past ' + sp.kind + ' steps'))
    : null
  return h(ui.Box, { flexDirection: 'column' },
    ...(model.lanes.length ? model.lanes.map(lane) : [h(ui.Text, { dimColor: true }, 'No agents have started yet.')]),
    spark,
    model.left ? h(ui.Text, null, model.left) : null)
}
