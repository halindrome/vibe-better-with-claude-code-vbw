// Mission Control's record views (mods_4_vbw.md §3.3): Plan, Proof, and the
// decisions under Plan. Each is a pure `xxxModel(input)` over the project record and a
// `renderXxx(ui, model, act)` drawn with the global h(); `act(action)` receives
// what a press asks for ({tab, phase}, {check}, {ask}). Never throws:
// odd input gives an empty model. No `$` here.

import { stateColor, STATE_MARKS } from './panel-palette.js'
import { dayTime } from './panel-sessions.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const arr = (x) => (Array.isArray(x) ? x.filter(isObj) : [])
const str = (x) => (typeof x === 'string' && x !== '' ? x : null)
const recOf = (input) => (isObj(input) && isObj(input.record) ? input.record : {})
const msId = (rec) => (isObj(rec.milestone) ? str(rec.milestone.id) : null)

// An argv as a shell would read it: words with anything unusual single-quoted.
export function argvText(argv) {
  if (!Array.isArray(argv)) return ''
  return argv.map((a) => {
    const s = String(a)
    return /^[\w@%+=:,./-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\\''") + "'"
  }).join(' ')
}

function scope(rec) {
  const id = msId(rec)
  const reqs = arr(rec.requirements).filter((r) => id && r.milestone === id)
  const reqIds = new Set(reqs.map((r) => r.id))
  return {
    id,
    reqs,
    phases: arr(rec.phases).filter((p) => id && p.milestone === id && str(p.id)),
    checks: arr(rec.checks).filter((c) => str(c.id) && reqIds.has(c.req)),
  }
}
const reqText = (rec, id) => {
  const r = arr(rec.requirements).find((x) => x.id === id)
  return r && str(r.text) ? id + ': ' + r.text : String(id ?? '')
}

// ---- Plan -------------------------------------------------------------------

// A plan's status as a palette state, with its own word.
const PLAN_STATE = { done: ['done', 'done'], building: ['running', 'building'], blocked: ['failed', 'blocked'], planned: ['open', 'planned'] }
const look = (state, word) => ({ state, mark: STATE_MARKS[state], word, color: stateColor(state) })
const planLook = (status) => look(...(PLAN_STATE[status] || PLAN_STATE.planned))

// A phase's state, derived as the record derives it (docs/record.md): passed by QA is done;
// a blocked plan blocks it; a building plan builds it; every plan done is built; else planned.
function phaseLook(phase, plans) {
  if (isObj(phase.qa) && phase.qa.result === 'pass') return look('done', 'done')
  if (plans.some((p) => p.status === 'blocked')) return look('failed', 'blocked')
  if (plans.some((p) => p.status === 'building')) return look('running', 'building')
  if (plans.length && plans.every((p) => p.status === 'done')) return look('done', 'built')
  return look('open', 'planned')
}

// A requirement's state: proven or accepted is done, failing or rejected failed; an open one
// builds while a plan of it builds.
function reqLook(r, building) {
  if (r.status === 'proven' || r.status === 'accepted') return look('done', r.status)
  if (r.status === 'failing' || r.status === 'rejected') return look('failed', r.status)
  return building.has(r.id) ? look('running', 'building') : look('open', 'open')
}

// planModel({ record, phase, open, now }): the milestone's phases as rows, the chosen phase
// expanded (its requirements, plans and checks), and the milestone's decisions. `open` holds
// the toggles panel.js keeps (a plan's files are shown while 'files:<plan id>' is on).
export function planModel(input) {
  const rec = recOf(input)
  const want = isObj(input) ? input.phase : null
  const open = isObj(input) && isObj(input.open) ? input.open : {}
  const now = isObj(input) && Number.isFinite(input.now) ? input.now : Date.now()
  const { phases } = scope(rec)
  const plans = arr(rec.plans).map((p) => ({ ...p, status: str(p.status) || 'planned' }))
  const pick = phases.find((p) => p.id === want)
    || phases.find((p) => !(isObj(p.qa) && p.qa.result === 'pass'))
    || phases[phases.length - 1] || null
  const rows = phases.map((p) => {
    const own = plans.filter((x) => x.phase === p.id)
    return {
      id: p.id, title: str(p.title) || '', active: !!pick && p.id === pick.id, press: { tab: 'plan', phase: p.id },
      done: own.filter((x) => x.status === 'done').length, total: own.length,
      strip: own.map((x) => ({ state: planLook(x.status).state, color: planLook(x.status).color })),
      ...phaseLook(p, own),
    }
  })
  let selected = null
  if (pick) {
    const reqs = Array.isArray(pick.reqs) ? pick.reqs : []
    const own = plans.filter((p) => p.phase === pick.id)
    const building = new Set(own.filter((p) => p.status === 'building').flatMap((p) => (Array.isArray(p.reqs) ? p.reqs : reqs)))
    selected = {
      id: pick.id,
      title: str(pick.title) || '',
      goal: str(pick.goal),
      reqs: reqs.map((id) => arr(rec.requirements).find((r) => r.id === id)).filter(Boolean)
        .map((r) => ({ id: r.id, text: str(r.text) || '', ...reqLook(r, building) })),
      plans: own.map((p) => {
        const files = Array.isArray(p.files) ? p.files.filter((f) => typeof f === 'string') : []
        return {
          id: String(p.id ?? ''), title: str(p.title) || '', status: p.status, note: p.status === 'blocked' ? str(p.note) : null,
          files, toggle: 'files:' + String(p.id ?? ''), filesOpen: open['files:' + String(p.id ?? '')] === true, ...planLook(p.status),
        }
      }),
      checks: arr(rec.checks).filter((c) => str(c.id) && reqs.includes(c.req))
        .map((c) => ({ id: c.id, req: c.req, command: argvText(c.run) })),
    }
  }
  const decisions = decisionsModel({ record: rec }).items.map((d) => ({ ...d, when: dayTime(Date.parse(d.at), now) }))
  return { milestone: scope(rec).id, phases: rows, selected, decisions, ask: { ask: true, placeholder: 'Ask about this plan' } }
}

// ---- Proof ------------------------------------------------------------------

const TAIL_LINES = 20
// A check cell is a palette state: its colour, and its mark and word for colour off.
const CELL_STATE = { passed: 'done', failing: 'failed', running: 'running', none: 'quiet' }
const CELL_WORD = { passed: 'passed', failing: 'failing', running: 'running', none: 'not run' }

export function checkDetail(record, id) {
  const rec = isObj(record) ? record : {}
  const c = arr(rec.checks).find((x) => x.id === id && str(x.id))
  if (!c) return null
  const ev = isObj(rec.evidence) && isObj(rec.evidence.checks) && isObj(rec.evidence.checks[id]) ? rec.evidence.checks[id] : {}
  const tail = typeof ev.tail === 'string' ? ev.tail.replace(/\n+$/, '').split('\n').slice(-TAIL_LINES).join('\n') : ''
  return {
    id,
    command: argvText(c.run),
    requirement: reqText(rec, c.req),
    status: str(ev.status),
    exit: Number.isInteger(ev.exit) ? ev.exit : null,
    seconds: Number.isFinite(ev.seconds) ? ev.seconds : null,
    at: isObj(rec.evidence) ? str(rec.evidence.at) : null,
    output: tail,
  }
}

export function proofModel(input) {
  const rec = recOf(input)
  const running = new Set(isObj(input) && Array.isArray(input.running) ? input.running : [])
  const { checks, reqs } = scope(rec)
  const proven = new Set(reqs.filter((r) => r.status === 'proven').map((r) => r.id))
  // With no evidence at all, a proven requirement still says its checks passed;
  // a check the last proof did not run is not run.
  const evc = isObj(rec.evidence) && isObj(rec.evidence.checks) ? rec.evidence.checks : null
  if (evc) proven.clear()
  const counts = { passed: 0, failing: 0, running: 0, none: 0 }
  const cells = checks.map((c) => {
    const st = evc && isObj(evc[c.id]) ? evc[c.id].status : null
    const state = running.has(c.id) ? 'running'
      : st === 'pass' ? 'passed'
      : st === 'fail' || st === 'timeout' ? 'failing'
      : !st && proven.has(c.req) ? 'passed' : 'none'
    counts[state]++
    const ps = CELL_STATE[state]
    return { id: c.id, state, color: stateColor(ps), mark: STATE_MARKS[ps], hover: c.id + ' · ' + CELL_WORD[state] + ' · ' + reqText(rec, c.req), press: { check: c.id } }
  })
  const sel = isObj(input) ? input.selected : null
  return { cells, counts, detail: sel ? checkDetail(rec, sel) : null }
}

// ---- Decisions ----------------------------------------------------------------

// Decisions carry no milestone: the current milestone's are those made after
// the previous milestone shipped (and, once it shipped, not after its own ship).
export function decisionsModel(input) {
  const rec = recOf(input)
  const id = msId(rec)
  const shipped = arr(rec.shipped).filter((s) => str(s.at))
  const own = shipped.find((s) => s.id === id)
  const before = shipped.filter((s) => s.id !== id).map((s) => s.at).sort()
  const from = before.length ? before[before.length - 1] : null
  const to = own ? own.at : null
  const items = !id ? [] : arr(rec.decisions)
    .filter((d) => str(d.text) && str(d.at) && (!from || d.at > from) && (!to || d.at <= to))
    .map((d, i) => {
      const q = /^(.+?\?)\s+(\S[\s\S]*)$/.exec(d.text)
      return {
        id: String(d.id ?? ''), question: q ? q[1] : null, answer: q ? q[2] : d.text,
        why: str(d.why), at: d.at, n: i,
      }
    })
    .sort((a, b) => (a.at === b.at ? b.n - a.n : a.at < b.at ? 1 : -1))
    .map(({ n, ...d }) => d)
  return { milestone: id, items }
}

// ---- Rendering ----------------------------------------------------------------

const call = (act, a) => () => { if (typeof act === 'function') act(a) }
const els = (ui) => (isObj(ui) ? ui : {})
const T = (ui, props, ...s) => h(els(ui).Text, props, ...s)
const col = (ui, props, ...kids) => h(els(ui).Box, { flexDirection: 'column', ...props }, ...kids)
const row = (ui, props, ...kids) => h(els(ui).Box, { flexDirection: 'row', ...props }, ...kids)
const btn = (ui, key, label, act, a, extra) => h(els(ui).Button, { key, label, onPress: call(act, a), ...extra })
const empty = (ui, text) => col(ui, null, T(ui, { dimColor: true }, text))
// Code or Markdown when the surface has them, else the same words as Text.
const code = (ui, source, language) => (els(ui).Code ? h(ui.Code, { source, ...(language ? { language } : {}), wrap: 'truncate-end' }) : T(ui, null, source))
const md = (ui, text) => (els(ui).Markdown ? h(ui.Markdown, { text }) : T(ui, null, text))

// A cut to n characters: a longer text ends with an ellipsis.
const cutTo = (s, n) => { const c = [...String(s)]; return c.length > Math.max(1, n) ? c.slice(0, Math.max(1, n) - 1).join('') + '…' : String(s) }
const STRIP_CELLS = 10
const STRIP_ORDER = ['done', 'running', 'failed', 'open']

// A phase's plans as a segmented strip, at most STRIP_CELLS cells: done, building, blocked,
// then planned (dim, a lighter block), each group in its state's colour.
function strip(ui, p) {
  const total = p.strip.length
  if (!total) return [T(ui, { key: 'strip', dimColor: true }, '·')]
  const scale = Math.min(1, STRIP_CELLS / total)
  const counts = STRIP_ORDER.map((s) => p.strip.filter((x) => x.state === s).length)
  let cells = counts.map((n) => (n ? Math.max(1, Math.round(n * scale)) : 0))
  while (cells.reduce((a, b) => a + b, 0) > STRIP_CELLS) cells[cells.indexOf(Math.max(...cells))]--
  return STRIP_ORDER.map((s, i) => (cells[i] ? T(ui, { key: 'strip-' + s, ...(s === 'open' ? { dimColor: true } : { color: stateColor(s) }) }, (s === 'open' ? '░' : '█').repeat(cells[i])) : null)).filter(Boolean)
}

// renderPlan(ui, model, act, width): the phases as whole rows (the title cut to the row, never
// wrapped), the chosen phase's requirements, plans (files a press away) and checks, then the
// milestone's decisions, dim, newest first.
export function renderPlan(ui, model, act, width) {
  const m = isObj(model) ? model : {}
  const w = Number.isFinite(width) ? Math.max(20, Math.floor(width)) : 60
  if (!Array.isArray(m.phases) || !m.phases.length) return empty(ui, 'No phases are planned yet.')
  const rows = m.phases.map((p) => {
    const figure = p.done + '/' + p.total
    const stateText = p.mark + ' ' + p.word
    const cells = Math.min(STRIP_CELLS, Math.max(1, p.strip.length))
    // Room for the label: the row less the button's chrome, the strip, the figure, the state and the gaps.
    const room = w - 4 - cells - figure.length - stateText.length - 3
    return row(ui, { key: 'plan-row-' + p.id, columnGap: 1 },
      btn(ui, 'plan-' + p.id, cutTo(p.id + (p.title ? ' ' + p.title : ''), room), act, p.press, p.active ? { variant: 'primary' } : { dimColor: true }),
      row(ui, { key: 'strip' }, ...strip(ui, p)),
      T(ui, { key: 'figure', dimColor: true }, figure),
      T(ui, { key: 'state', color: p.color }, stateText))
  })
  const kids = [col(ui, { key: 'plan-phases', marginBottom: 1 }, ...rows)]
  const s = m.selected
  if (isObj(s)) {
    kids.push(T(ui, { bold: true }, s.id + ' ' + s.title))
    if (s.goal) kids.push(md(ui, s.goal))
    if (s.reqs.length) {
      kids.push(T(ui, { dimColor: true }, 'Requirements'))
      for (const r of s.reqs) {
        kids.push(row(ui, { key: 'req-' + r.id, columnGap: 1 },
          T(ui, { key: 'id' }, r.id), T(ui, { key: 'state', color: r.color }, r.mark + ' ' + r.word),
          T(ui, { key: 'text', dimColor: true, wrap: 'truncate-end' }, r.text)))
      }
    }
    kids.push(T(ui, { dimColor: true }, 'Plans'))
    for (const p of s.plans) {
      kids.push(row(ui, { key: 'plan-' + p.id + '-row', flexWrap: 'wrap', columnGap: 1 },
        T(ui, { key: 'title' }, p.id + ' ' + p.title),
        T(ui, { key: 'state', color: p.color }, p.mark + ' ' + p.word + (p.note ? ': ' + p.note : '')),
        p.files.length ? btn(ui, 'files-' + p.id, p.files.length + (p.files.length === 1 ? ' file' : ' files'), act, { toggle: p.toggle }, { dimColor: !p.filesOpen }) : null))
      if (p.filesOpen) for (const f of p.files) kids.push(T(ui, { dimColor: true }, '  ' + f))
    }
    if (s.checks.length) {
      kids.push(T(ui, { dimColor: true }, 'Checks'))
      for (const c of s.checks) kids.push(T(ui, null, c.id + ' · ' + c.req), code(ui, c.command, 'bash'))
    }
    if (els(ui).Input && isObj(m.ask)) {
      kids.push(h(ui.Input, { key: 'plan-ask', placeholder: m.ask.placeholder, submitLabel: 'ask', onSubmit: (v) => call(act, { ask: String(v) })() }))
    }
  }
  const ds = Array.isArray(m.decisions) ? m.decisions : []
  kids.push(col(ui, { key: 'plan-decisions', marginTop: 1 }, T(ui, { dimColor: true, bold: true }, 'Decisions'),
    ...(ds.length ? ds.map((d) => col(ui, { key: 'decision-' + d.id, marginBottom: 1 },
      T(ui, { dimColor: true }, d.id + (d.when ? ' · ' + d.when : '')),
      T(ui, { dimColor: true }, (d.question ? d.question + ' ' : '') + d.answer),
      d.why ? T(ui, { dimColor: true, italic: true }, 'because ' + d.why) : null))
      : [T(ui, { dimColor: true }, 'No decisions recorded for this milestone yet.')])))
  return col(ui, null, ...kids)
}

export const PER_ROW = 20

export function renderProof(ui, model, act) {
  const m = isObj(model) ? model : {}
  const cells = Array.isArray(m.cells) ? m.cells : []
  if (!cells.length) return empty(ui, 'No checks are approved for this milestone yet.')
  const cell = (c) => h(els(ui).Box, { key: 'cell-' + c.id },
    T(ui, { color: c.color }, c.mark || STATE_MARKS.quiet),
    h(els(ui).Box, { position: 'absolute', top: 1, left: 0, display: 'none', hover: { display: 'flex' }, borderStyle: 'round' },
      T(ui, null, c.hover)))
  const rows = []
  for (let i = 0; i < cells.length; i += PER_ROW) {
    rows.push(row(ui, { key: 'proof-row-' + i / PER_ROW }, ...cells.slice(i, i + PER_ROW).map(cell)))
  }
  const k = isObj(m.counts) ? m.counts : {}
  const kids = [...rows, T(ui, { dimColor: true },
    (k.passed || 0) + ' passed · ' + (k.failing || 0) + ' failing · ' + (k.running || 0) + ' running · ' + (k.none || 0) + ' not run')]
  // Every check is a press away: the failing ones first, as the ones worth reading.
  const order = [...cells.filter((c) => c.state === 'failing'), ...cells.filter((c) => c.state !== 'failing')]
  kids.push(row(ui, { key: 'proof-press', flexWrap: 'wrap' }, ...order.map((c) =>
    btn(ui, 'check-' + c.id, c.id, act, c.press, { plain: true, dimColor: c.state !== 'failing' }))))
  const d = m.detail
  if (isObj(d)) {
    kids.push(T(ui, { bold: true }, d.id + ' · ' + d.requirement),
      T(ui, { dimColor: true }, d.status ? 'last run: ' + d.status + (d.exit !== null ? ' (exit ' + d.exit + ')' : '') : 'not run yet'),
      code(ui, d.command, 'bash'))
    if (d.output) kids.push(code(ui, d.output))
  }
  return col(ui, null, ...kids)
}
