// Mission Control (mods_4_vbw.md §3.3): the pane, six tabs as buttons across the
// top in whole rows (a name is never split, no row is wider than the pane; the fewest rows
// win, then the full names over the short ones, then the portrait), after the VBW portrait
// where the terminal draws images and it costs the tabs nothing (§3.7). Now opens
// with the panel's own sentences and its sound switch above the live workflow (the
// crew); Plan holds the milestone's decisions, Timeline each run's time and cost, and
// Settings every setting, changed by a press (panel-settings.js); the views are those of panel-mission-live.js,
// panel-mission-record.js, panel-runs.js and panel-sessions.js.
// At ship the pane shows VBW Wrapped (panel-candy.js) until a tab is chosen; the
// all-green sweep crosses the top of Proof. Pure over the state panel.js gathered:
// no `$` here; presses go to `on.act(action)` and the sound switch to `on.sound()`.
import { nowModel, timelineModel, renderNow, renderTimeline, renderNowBox, renderRefusal } from './panel-mission-live.js'
import { planModel, proofModel, renderPlan, renderProof } from './panel-mission-record.js'
import { settingsModel, renderSettings } from './panel-settings.js'
import { runsModel, renderRuns } from './panel-runs.js'
import { sessionsModel, renderSessions } from './panel-sessions.js'
import { renderNext } from './panel-next.js'
import { renderWrapped } from './panel-candy.js'
import { NEED, PROGRESS, ESTIMATE, ACCENT } from './panel-palette.js'
import { SHOW_TERMS } from './panel-view.js'

// The head: the portrait's PORTRAIT_DRAWN_ROWS rows or the tab rows, whichever are more, and the gap
// under them. A short pane (fewer than PORTRAIT_ROWS) drops the portrait, and gets a gap
// under the tabs only with room to spare.
const PORTRAIT_ROWS = 8
const GAP_ROWS = 6
// Where Claude Code reports no height (inline, the main screen) the pane is at most this tall.
const FIXED_ROWS = 30
const PORTRAIT_COLS = 6
const PORTRAIT_DRAWN_ROWS = 3
// Claude Code draws a button as '[ ' + label + ' ]' (a hotkey button as '[k] ' + label): 4 cells
// around the label. The tab buttons sit one cell apart.
const BUTTON_CHROME = 4
const TAB_GAP = 1

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
export const TABS = [['now', 'Now'], ['plan', 'Plan'], ['proof', 'Proof'], ['timeline', 'Timeline'], ['sessions', 'Sessions'], ['settings', 'Settings']]
// The tab labels where they save a row: one row from 52 columns (the full names need 65), two
// rows below 38.
export const SHORT = { now: 'Now', plan: 'Plan', proof: 'Proof', timeline: 'Time', sessions: 'Sess', settings: 'Set' }

// The tabs packed in order into whole rows: each row holds as many whole buttons as fit (first-fit
// in order gives the fewest rows) and a name is never split; a width narrower than one button still
// gives one button per row. -> arrays of names.
export function tabRows(names, width) {
  const rows = []
  let used = 0
  for (const name of names) {
    const w = [...name].length + BUTTON_CHROME
    if (rows.length && used + TAB_GAP + w <= width) { rows[rows.length - 1].push(name); used += TAB_GAP + w } else { rows.push([name]); used = w }
  }
  return rows
}

// The head's layout: every candidate (the full names or SHORT, with the portrait, its columns taken
// from the width, or without) ranked by the fewest rows, then the full names over SHORT, then the
// portrait over none: the portrait never costs a row or a full name.
export function layout(width, portraitWanted) {
  const found = []
  for (const portrait of portraitWanted ? [true, false] : [false]) {
    for (const short of [false, true]) {
      const rows = tabRows(TABS.map(([id, name]) => (short ? SHORT[id] : name)), width - (portrait ? PORTRAIT_COLS : 0))
      found.push({ portrait, short, rows, rank: [rows.length, short ? 1 : 0, portrait ? 0 : 1] })
    }
  }
  return found.sort((a, b) => a.rank[0] - b.rank[0] || a.rank[1] - b.rank[1] || a.rank[2] - b.rank[2])[0]
}

// The head as drawn: the layout with each row's tabs as [id, label], worked out again only
// when the width or the portrait's wish changes (a pane redraws at one width for long).
let laidOut = null
function headAt(width, portraitWanted) {
  if (!laidOut || laidOut.width !== width || laidOut.portraitWanted !== portraitWanted) {
    const lay = layout(width, portraitWanted)
    const idOf = (label) => TABS.find(([i, name]) => (lay.short ? SHORT[i] : name) === label)[0]
    laidOut = { width, portraitWanted, portrait: lay.portrait, rows: lay.rows.map((names) => names.map((label) => [idOf(label), label])) }
  }
  return laidOut
}

// --- how many rows a drawing takes ----------------------------------------------
// A model of Ink's layout (a Box stacks or sets side by side, a Text wraps or is cut),
// enough to know whether Mission Control fits the fixed height. { w, h }: the widest
// line and the rows. Never throws; an unknown element takes no room.
const int = (x) => (Number.isInteger(x) ? x : 0)
const wide = (s) => [...s].length
const textOf = (n) => (typeof n === 'string' || typeof n === 'number' ? String(n) : n && typeof n === 'object' ? (n.children || []).map(textOf).join('') : '')

function measure(node, cols) {
  if (typeof node === 'string' || typeof node === 'number') return measure({ type: 'Text', props: {}, children: [String(node)] }, cols)
  if (Array.isArray(node)) return { w: Math.max(0, ...node.map((n) => measure(n, cols).w)), h: node.reduce((n, c) => n + measure(c, cols).h, 0) }
  if (!node || typeof node !== 'object') return { w: 0, h: 0 }
  const p = node.props || {}
  if (p.display === 'none') return { w: 0, h: 0 }
  let m
  switch (node.type) {
    case 'Text': {
      const cut = /^truncate/.test(String(p.wrap || ''))
      m = { w: 0, h: 0 }
      for (const line of textOf(node).split('\n')) {
        const n = wide(line)
        if (!Number.isFinite(cols) || cut || n <= cols) m = { w: Math.max(m.w, Math.min(n, cols)), h: m.h + 1 }
        else m = { w: cols, h: m.h + Math.ceil(n / Math.max(1, cols)) }
      }
      break
    }
    case 'Raster': case 'Image': m = { w: int(p.columns), h: int(p.rows) }; break
    case 'Button': {
      const label = p.label === undefined || p.label === null ? [] : [{ type: 'Text', props: {}, children: [' '.repeat(BUTTON_CHROME) + String(p.label)] }]
      m = setBeside([...label, ...(node.children || [])], cols, { columnGap: 1 })
      break
    }
    default: m = boxOf(node, cols)
  }
  const top = int(p.marginTop ?? p.marginY ?? p.margin)
  const bottom = int(p.marginBottom ?? p.marginY ?? p.margin)
  return { w: m.w, h: Math.max(0, m.h + top + Math.max(0, bottom)) }
}

const flexible = (c) => Boolean(c) && typeof c === 'object' &&
  ((c.type === 'Box' && (c.props || {}).flexWrap === 'wrap') || (c.type === 'Text' && !/^truncate/.test(String((c.props || {}).wrap || ''))))

// Children side by side: as wide as they are, the ones that can wrap sharing what the rest leave.
function setBeside(children, cols, p) {
  const gap = int(p.columnGap ?? p.gap)
  const kids = children.filter((c) => measure(c, Infinity).h > 0)
  let blocks = kids.map((c) => measure(c, Infinity))
  if (p.flexWrap === 'wrap' && Number.isFinite(cols)) {
    let h = 0
    let w = 0
    let used = 0
    let rowH = 0
    for (const b of blocks) {
      if (rowH && used + gap + b.w > cols) { h += rowH; used = 0; rowH = 0 }
      used += (rowH ? gap : 0) + b.w
      rowH = Math.max(rowH, b.h)
      w = Math.max(w, used)
    }
    return { w: Math.min(w, cols), h: h + rowH }
  }
  const gaps = gap * Math.max(0, blocks.length - 1)
  const flex = kids.map(flexible)
  if (Number.isFinite(cols) && blocks.reduce((n, b) => n + b.w, 0) + gaps > cols && flex.some(Boolean)) {
    const fixed = blocks.reduce((n, b, i) => n + (flex[i] ? 0 : b.w), 0) + gaps
    const share = Math.max(1, Math.floor((cols - fixed) / flex.filter(Boolean).length))
    blocks = kids.map((c, i) => (flex[i] ? measure(c, share) : blocks[i]))
  }
  return { w: Math.min(blocks.reduce((n, b) => n + b.w, 0) + gaps, Number.isFinite(cols) ? cols : Infinity), h: Math.max(0, ...blocks.map((b) => b.h)) }
}

function boxOf(node, cols) {
  const p = node.props || {}
  const kids = node.children || []
  const border = p.borderStyle ? 1 : 0
  const px = int(p.paddingX ?? p.padding)
  const py = int(p.paddingY ?? p.padding)
  const inner = Number.isFinite(cols) ? Math.max(1, cols - 2 * border - 2 * px) : Infinity
  let m
  if (p.flexDirection === 'column' || p.flexDirection === 'column-reverse') {
    const gap = int(p.rowGap ?? p.gap)
    const parts = kids.map((c) => measure(c, inner))
    m = { w: Math.max(0, ...parts.map((b) => b.w)), h: parts.reduce((n, b, i) => n + b.h + (i && gap ? gap : 0), 0) }
  } else m = setBeside(kids, inner, p)
  m = { w: m.w + 2 * px + 2 * border, h: m.h + 2 * py + 2 * border }
  if (Number.isFinite(cols) && border) m.w = cols
  if (Number.isInteger(p.height) && p.height >= 0) m.h = p.height
  return m
}

// The colour of a sentence's key value; a sentence with no value in it stays plain.
function tint(r, need) {
  if (String(r.id).startsWith('refused:')) return NEED // a refusal: amber, beside its ⊘ mark and word
  switch (r.id) {
    case 'need': return need ? NEED : undefined
    case 'progress': return /^No requirements/.test(String(r.text)) ? undefined : PROGRESS
    case 'estimate-milestone': return /^No (?:estimate|end time)/.test(String(r.text)) ? undefined : ESTIMATE
    case 'cost': return /not available/.test(String(r.text)) ? undefined : ACCENT
    default: return undefined
  }
}

// What the box already says: what VBW is doing, the milestone's end, the cost, and a need
// (its sentence is the box's state).
const IN_BOX = (v) => new Set(['doing', 'estimate-milestone', 'cost', ...(v.need ? ['need'] : [])])

// The box (panel-view.js nowBoxModel, drawn by panel-mission-live.js renderNowBox), the crew
// slot under it, the panel's sentences (panel-view.js), each with its term in small text
// while SHOW_TERMS holds, a refusal as its short row (open while st.open holds its id), and
// the sound switch.
function summary(ui, v, st, on, crewRows, width, act) {
  const { Box, Text, Button } = ui
  const boxed = v.box ? IN_BOX(v) : new Set()
  const open = isObj(st.open) ? st.open : {}
  const box = v.box ? [renderNowBox(ui, v.box, { width, labels: SHOW_TERMS })] : []
  const rows = [...box, ...crewRows, ...v.rows.filter((r) => !boxed.has(r.id)).map((r) =>
    String(r.id).startsWith('refused:') ? renderRefusal(ui, r, open[r.id] === true, act)
      : h(Box, { key: r.id, flexDirection: 'column', marginBottom: 1 },
        h(Text, { color: tint(r, v.need) }, String(r.text)),
        SHOW_TERMS ? h(Text, { dimColor: true }, String(r.term)) : null))]
  // panel.js keeps st.sound from the kernel's `sound` setting and on.sound() sets it (off or default).
  rows.push(
    h(Box, { key: 'sound', flexDirection: 'row', marginBottom: 1 },
      h(Text, null, 'Sound is ' + (st.sound ? 'on' : 'off') + '. '),
      h(Button, { key: 'sound-toggle', label: st.sound ? 'Turn off' : 'Turn on', onPress: () => on.sound() })))
  return rows
}

const marksOf = (input) => (isObj(input.fresh) ? input.fresh : {})

function body(ui, input, tab, act) {
  const { st, now, width, registry, stored } = input
  const rec = st.record
  const marks = marksOf(input)
  switch (tab) {
    // Plan: the phases, the chosen one's work, then the milestone's decisions (the record ties a decision to no phase).
    case 'plan': return renderPlan({ ...ui, Input: undefined }, planModel({ record: rec, phase: st.phase, open: st.open, now }), act, width - 4) // Ask is not wired yet
    case 'proof': return renderProof(ui, proofModel({ record: rec, selected: st.check, open: st.open, now }), act, width - 4)
    // Timeline: the live run's agents on its clock, then every run of the session with its time and cost.
    case 'timeline': return h(ui.Box, { key: 'timeline-tab', flexDirection: 'column' },
      renderTimeline(ui, timelineModel({ run: st.run, now, steps: st.steps, step: st.step, width: width - 4 })),
      renderRuns(ui, runsModel({ runs: st.leases, steps: st.steps, sessionCost: st.cost, now, width: Math.max(20, width - 4), fresh: marks, motion: input.motion })))
    case 'sessions': return renderSessions(ui, sessionsModel({ registry, root: st.root, sessionId: st.sessionId, lease: isObj(rec) ? rec.lease : null, stored, now, width: Math.max(10, width - 4), plans: isObj(rec) ? rec.plans : null }))
    case 'settings': return renderSettings(ui, settingsModel({ settings: st.settings, record: rec, now, fresh: marks, motion: input.motion }), act)
    default: return null
  }
}

// The Now tab's crew slot, right under the box (Lane B draws the rows: panel-mission-live.js
// renderNow). The box already says that nothing runs; "no workflow runs here" is only news
// while a run is held.
function crew(ui, { st, now, motion, width }, act) {
  const rec = st.record
  const model = nowModel({ run: st.run, now, selected: st.agent, seen: Object.keys(st.helpersSeen || {}), motion, width: Math.max(10, width - 2) })
  return model || (isObj(rec) && isObj(rec.lease)) ? [h(ui.Box, { key: 'crew', flexDirection: 'column', marginBottom: 1 }, renderNow(ui, model, act))] : []
}

// input: { st, v, now, width, portrait (a PNG's path, or null), wrapped (the
// Wrapped model, or null), sweep ({ cols, cells } of the sweep's frame, or null) }.
export function renderPane(ui, input, on) {
  const { Box, Button, Image, Raster, Text } = ui
  const { st, v } = input
  const act = (a) => on.act(a)
  const wrapped = st.tab === 'wrapped' && input.wrapped ? input.wrapped : null
  const tab = wrapped ? 'wrapped' : TABS.some(([id]) => id === st.tab) ? st.tab : 'now'
  const sc = input.scroll
  const rows = sc && Number.isInteger(sc.bodyRows) ? sc.bodyRows : 0
  // The portrait goes when the room is short or costs the tabs a row or a full name.
  const width = Number.isFinite(input.width) ? input.width : 50
  const wanted = Boolean(Image) && typeof input.portrait === 'string' && (rows < 1 || rows >= PORTRAIT_ROWS)
  const lay = headAt(width, wanted)
  const withPortrait = lay.portrait
  const tabs = h(Box, { key: 'tabs', flexDirection: 'column' },
    ...lay.rows.map((row, r) => h(Box, { key: 'tab-row-' + r, flexDirection: 'row', columnGap: TAB_GAP, flexShrink: 0 },
      ...row.map(([id, label]) => h(Button, { key: 'tab-' + id, label, ...(id === tab ? { variant: 'primary' } : { dimColor: true }), onPress: () => act({ show: id }) })))))
  const portrait = withPortrait
    ? [h(Image, { key: 'vbw-portrait', source: { file: input.portrait, format: 'png' }, columns: PORTRAIT_COLS, rows: PORTRAIT_DRAWN_ROWS, alt: 'VBW' })] : []
  const gap = rows < 1 || withPortrait || rows >= GAP_ROWS
  const headRows = Math.max(withPortrait ? PORTRAIT_DRAWN_ROWS : 0, lay.rows.length) + (gap ? 1 : 0)
  const head = h(Box, { key: 'head', flexDirection: 'row', ...(gap ? { marginBottom: 1 } : {}) }, ...portrait, tabs)
  const sweep = tab === 'proof' && Raster && input.sweep ? [h(Raster, { key: 'vbw-sweep', columns: input.sweep.cols, rows: 1, cells: input.sweep.cells })] : []
  const view = wrapped ? renderWrapped(ui, wrapped) : body(ui, { ...input, width }, tab, act)
  const upNext = tab === 'now' ? [renderNext(ui, { recommendation: input.recommendation, width: input.width, motion: input.motion, fresh: marksOf(input), now: input.now }, act)] : []
  const content = [...(tab === 'now' ? summary(ui, v, st, on, crew(ui, { ...input, width }, act), width, act) : []), ...upNext, ...sweep, view]
  if (rows < 1) {
    // No height reported: one fixed height at most, ending with how much is left out.
    const tall = measure(h(Box, { flexDirection: 'column' }, ...content), width).h
    if (headRows + tall <= FIXED_ROWS) return h(Box, { flexDirection: 'column' }, head, ...content)
    const room = FIXED_ROWS - headRows - 1
    return h(Box, { flexDirection: 'column' }, head,
      h(Box, { key: 'body', flexDirection: 'column', overflow: 'hidden', height: room }, h(Box, { key: 'body-rows', flexDirection: 'column', flexShrink: 0 }, ...content)),
      h(Text, { key: 'more', dimColor: true, wrap: 'truncate-end' }, '+' + (tall - room) + ' more · open Mission Control'))
  }
  // The tabs are a fixed head; everything under them is one clipped body, shifted by the scroll offset.
  const off = Number.isInteger(sc.offset) && sc.offset > 0 ? sc.offset : 0
  const inner = h(Box, { key: 'body-rows', flexDirection: 'column', flexShrink: 0, marginTop: -off }, ...content)
  // A pane shorter than its head clips the head to the reported rows: never more rows than Claude Code gives.
  const top = headRows > rows ? h(Box, { key: 'head-clip', flexDirection: 'column', overflow: 'hidden', height: rows }, head) : head
  return h(Box, { flexDirection: 'column' }, top,
    h(Box, { key: 'body', flexDirection: 'column', overflow: 'hidden', height: Math.max(0, rows - headRows) }, inner))
}
