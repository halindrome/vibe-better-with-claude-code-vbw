// What the VBW panel says (R51): turns the project record and its last `vbw next`
// into plain sentences, each with its technical term beside it. Pure: data in,
// rows out; it never changes its input and never throws.

import { stepWords, dayClock } from './panel-step.js'
import { REFUSED_MARK } from './panel-palette.js'

export const MIN_VERSION = '2.1.287'

// The dim one-word term under each of the Now tab's sentences ('milestone', 'session cost'):
// one switch, so the terms can go in one change.
export const SHOW_TERMS = true

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
const parts = (v) => {
  const m = typeof v === 'string' ? /^(\d+)\.(\d+)\.(\d+)/.exec(v) : null
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// Comms redraws forever before 2.1.290 when its tree changes height (fixed in 2.1.290).
export const COMMS_MIN_VERSION = '2.1.290'

// True when this Claude Code version has the panel (or, with `min`, that feature);
// anything unreadable counts as older.
export function supports(version, min = MIN_VERSION) {
  const v = parts(version)
  const m = parts(min)
  if (!v || !m) return false
  for (let i = 0; i < 3; i++) if (v[i] !== m[i]) return v[i] > m[i]
  return true
}

// '[14:20] ' before a sentence that has a start time ('[yesterday 14:20] ' on another day,
// dayClock's rule); the sentence alone without one.
const stamped = (ms, text, now) => (dayClock(ms, now) ? '[' + dayClock(ms, now) + '] ' + text : text)

const NEUTRAL = { id: 'neutral', text: 'No VBW project is open here yet.', term: 'no project' }

function doing(rec, now) {
  const l = rec.lease
  if (!isObj(l)) return { id: 'doing', text: 'VBW is idle: nothing is running.', term: 'idle' }
  const ms = now - Date.parse(l.started_at)
  const mins = Number.isFinite(ms) ? Math.floor(ms / 60000) : 0
  const since = mins >= 1 ? mins + ' min so far' : 'just started'
  const names = (Array.isArray(rec.plans) ? rec.plans : [])
    .filter((p) => isObj(p) && p.status === 'building').map((p) => p.title).filter(Boolean)
  const what = {
    plan: ['planning the work', 'plan'],
    build: ['building' + (names.length ? ': ' + names.join(', ') : ' the plan'), 'build'],
    qa: ['checking the results', 'QA'],
    fix: ['fixing what the checks found', 'fix'],
    map: ['reading the project to map it', 'map'],
  }[l.kind] || ['working', String(l.kind || 'run')]
  return { id: 'doing', text: 'VBW is ' + what[0] + ' (' + since + ').', term: what[1] }
}

// The command that carries each gate on (a gate not named here goes on with /vbw:vibe).
export const GATE_COMMANDS = { approve: '/vbw:approve', accept: '/vbw:verify', convert: '/vbw:convert' }

const list = (a) => (Array.isArray(a) ? a.filter((x) => typeof x === 'string' && x).join(', ') : '')
// The files of a deviations gate's detail ({deviations: [{file, ...}]}).
const devFiles = (d) => (Array.isArray(d.deviations) ? d.deviations.filter(isObj).map((x) => x.file) : [])
const RUN_ACTIONS = new Set(['plan', 'build', 'qa', 'fix'])
const COMPACT_PCT = 85 // the context is this full: /compact before a run

// The gate in next.json as the need it makes: key, kind, the sentence Mission Control
// says, and the short phrase Comms puts after 'VBW needs you ·'.
function gateNeed(nx) {
  const d = isObj(nx.detail) ? nx.detail : {}
  // The kernel's since (R189): when VBW reached the gate, whichever session or restart reads it.
  const since = typeof nx.since === 'string' ? Date.parse(nx.since) : NaN
  const need = (key, text, what) => ({ key, kind: nx.action, text, what, ...(Number.isFinite(since) ? { at: since } : {}) })
  switch (nx.action) {
    case 'approve': {
      const f = list(d.files)
      if (f) return need('approve:' + f, 'Please approve the plan before VBW builds it.', 'test files changed since your approval: ' + f)
      if (d.changed === true) return need('approve:changed', 'Your plan changed since you approved it: please review the changes and approve it again.',
        'the plan changed since you approved it: review the changes, then approve it')
      return need('approve', 'Please approve the plan before VBW builds it.', 'the plan is ready: review it, then approve it to build')
    }
    case 'accept': { const r = list(d.requirements); return need('accept:' + r, 'Please check the result by hand: ' + r + '.', 'check by hand what only you can judge' + (r ? ': ' + r : '')) }
    case 'ship': return need('ship', 'The milestone is ready: your go-ahead to ship it is needed.', 'the milestone is proven and accepted: ready to ship')
    case 'spec': return need('spec', 'VBW needs you to say what to build: the requirements.', 'say what to build: the requirements')
    case 'escalate': { const f = list(d.fixes); return need('escalate:' + f, 'A decision is needed from you on ' + f + '.', 'the fix limit was reached' + (f ? ' for ' + f : '') + ': decide how to go on') }
    case 'unblock': { const p = list(d.plans); return need('unblock:' + p, 'Work is blocked and needs you' + (p ? ': ' + p : '') + '.', 'blocked' + (p ? ': ' + p : '') + ', VBW needs your help to go on') }
    case 'scope': return need('scope', 'Some changes went outside their planned files: your decision is needed.', 'commits changed files outside their plans: review them')
    case 'deviations': {
      const f = list(devFiles(d))
      return need('deviations:' + f, 'Files VBW built were changed outside VBW' + (f ? ': ' + f : '') + '. Keep the changes or restore them?', 'changed outside VBW' + (f ? ': ' + f : '') + ': keep the changes or restore them')
    }
    case 'milestone': return need('milestone', 'The milestone is shipped: say what to build next.', 'the milestone is shipped: choose what comes next')
    case 'convert': return need('convert', 'A VBW 1 plan is here: bring it into VBW 2 or start fresh.', 'a VBW 1 plan is here: bring it into VBW 2, or start fresh')
    default: return need('other:' + String(nx.action), 'VBW is waiting for you: run /vbw:vibe to see what for.', typeof nx.instruction === 'string' && nx.instruction ? nx.instruction : 'a decision is needed')
  }
}

// True when the record says the gate in next.json (written at `nextAt`, ms) is done.
// Any other record change (a parked idea) leaves it standing.
function answered(rec, nx, nextAt) {
  const rows = (k) => (Array.isArray(rec[k]) ? rec[k].filter(isObj) : [])
  if (nx.action === 'approve') {
    return Number.isFinite(nextAt) && rows('decisions').some((x) => typeof x.text === 'string' && x.text.startsWith('Contract approved') && Date.parse(x.at) > nextAt)
  }
  if (nx.action === 'ship') return rec.milestone.status === 'shipped'
  if (nx.action === 'accept') {
    const ids = isObj(nx.detail) && Array.isArray(nx.detail.requirements) ? nx.detail.requirements : []
    const mine = ids.map((id) => rows('requirements').find((r) => r.id === id))
    return mine.length > 0 && mine.every((r) => r && (r.status === 'accepted' || r.status === 'rejected'))
  }
  const ids = (key) => (isObj(nx.detail) && Array.isArray(nx.detail[key]) ? nx.detail[key] : [])
  const gone = (key, still) => ids(key).length > 0 && ids(key).every((id) => !rows(key).some((r) => r.id === id && r.status === still))
  const written = () => rows('requirements').some((r) => r.milestone === rec.milestone.id)
  switch (nx.action) {
    case 'milestone': return rec.milestone.status !== 'shipped' && rec.milestone.status !== 'parked'
    case 'spec': return written()
    case 'convert': return written() || Object.hasOwn(rec, 'converted') || (isObj(rec.project) && isObj(rec.project.legacy) && rec.project.legacy.choice === 'fresh')
    case 'unblock': return gone('plans', 'blocked')
    case 'escalate': return gone('fixes', 'escalated')
    case 'scope': return !(isObj(rec.evidence) && Array.isArray(rec.evidence.scope) && rec.evidence.scope.length > 0)
    // Each file is settled: a restore under way for it, or a decision after the gate that names it.
    case 'deviations': {
      const files = devFiles(isObj(nx.detail) ? nx.detail : {}).filter((f) => typeof f === 'string' && f)
      const restoring = (f) => rows('fixes').some((x) => x.restore === f && (x.status === 'open' || x.status === 'fixed'))
      const decided = (f) => Number.isFinite(nextAt) && rows('decisions').some((x) => Date.parse(x.at) > nextAt && [x.text, x.why].some((t) => typeof t === 'string' && t.includes(f)))
      return files.length > 0 && files.every((f) => restoring(f) || decided(f))
    }
    default: return false
  }
}

// The one thing VBW needs from the user now, or null: an open question, else a gate in
// next.json that the record has not answered, else /compact before a run when the
// context is 85% full. While a run holds the lease nothing is needed. `at` is when it
// was reached (ms; next.json's time, or the question's), null when unknown.
export function liveNeed(input) {
  const { record: rec, next: nx, nextAt, question, questionAt, health } = isObj(input) ? input : {}
  if (!isObj(rec) || !isObj(rec.milestone) || isObj(rec.lease)) return null
  const at = (t) => (Number.isFinite(t) ? t : null)
  if (isObj(question)) {
    return { key: 'question:' + (question.id ?? ''), kind: 'question', text: 'VBW has a question for you and is waiting for your answer.', what: 'a question is waiting for your answer', at: at(questionAt) }
  }
  if (!isObj(nx)) return null
  if (nx.gate === true) {
    if (answered(rec, nx, nextAt)) return null
    const g = gateNeed(nx)
    // Dated by the kernel's since; by when next.json was written only when there is none (an older kernel).
    return { ...g, at: Number.isFinite(g.at) ? g.at : at(nextAt) }
  }
  if (RUN_ACTIONS.has(nx.action) && isObj(health) && Number.isFinite(health.contextPct) && health.contextPct >= COMPACT_PCT) {
    return { key: 'compact', kind: 'compact', text: 'The context is nearly full: run /compact first, then VBW can start.', what: 'the context is nearly full: run /compact first', at: at(nextAt) }
  }
  return null
}

// The session cost as one small line; no number when there is none to show.
function costRow(cost) {
  return Number.isFinite(cost) && cost >= 0
    ? { id: 'cost', text: 'This session has cost $' + cost.toFixed(2) + ' so far.', term: 'session cost' }
    : { id: 'cost', text: 'The cost so far is not available.', term: 'cost, not available' }
}

// ', held by <name>' when another chat holds the run; '' otherwise (R192).
export const heldBy = (holder) => (isObj(holder) && holder.self === false && typeof holder.name === 'string' && holder.name ? ', held by ' + holder.name : '')

// A sentence as said: its first letter upper case, a full stop at its end.
const sentence = (t) => {
  const s = String(t).trim()
  return s ? s.charAt(0).toUpperCase() + s.slice(1) + (/[.!?]$/.test(s) ? '' : '.') : ''
}

// ---- The 'what's happening now' box (docs/panel.md, What's happening now) ----------------
// VBW's state as one sentence; the current step with when it started and (from the kernel's
// note, worded by panel-step.js) when it should end, and a done/total strip when the step has
// parts; when VBW needs you, the need's sentence, the command that answers it and since when
// it waits; the milestone's end with its basis (the kernel's road: the live note's, else the
// last `vbw next`'s); the session cost. Every time names its day when not today (dayClock).
// input: { record, need (panel-view.js liveNeed), proving, stamps ({ proving, need,
// 'estimate-milestone' }: ms), cost, step (the live note), holder, next, now }.
const needCommand = (need) => (need.kind === 'question' || need.kind === 'compact' ? null : GATE_COMMANDS[need.kind] || '/vbw:vibe')

function stepLine(name, at, step, now) {
  const words = step ? stepWords(step, now) : null
  const when = dayClock(at, now)
  const text = name ? 'Current step: ' + name + (when ? ', started at ' + when : '') + '.' : when ? 'Started at ' + when + '.' : null
  if (!text && !words) return null
  return { text, end: words ? (words.timed ? 'This step: ' + words.text : words.text) + '.' : null, at: num(at) ? at : null, timed: Boolean(words && words.timed) }
}

function milestoneOf(step, nx, stamp, now) {
  const road = isObj(step) && isObj(step.road) ? step.road : isObj(step) && step.road === null ? null : isObj(nx) && isObj(nx.road) ? nx.road : null
  if (!road) return null
  const basis = str(road.basis).trim().replace(/\.$/, '')
  if (typeof road.end !== 'string' || !Number.isFinite(Date.parse(road.end))) {
    return { text: 'No estimate yet' + (basis ? ': ' + basis : '') + '.', basis: null, known: false, term: 'estimate, no basis' }
  }
  const say = sentence(str(road.say))
  if (!say) return null
  const at = dayClock(stamp, now)
  return { text: (at ? '[' + at + '] ' : '') + say, basis: basis ? 'basis: ' + basis : null, known: true, term: 'estimate, approximate' }
}

const costOf = (cost) => (num(cost) && cost >= 0
  ? { text: 'This session has cost $' + cost.toFixed(2) + ' so far.', known: true, term: 'session cost' }
  : { text: 'The cost so far is not available.', known: false, term: 'cost, not available' })

const partsOf = (step) => (isObj(step) && isObj(step.parts) && Number.isInteger(step.parts.total) && step.parts.total > 0 && Number.isInteger(step.parts.done)
  ? { done: Math.max(0, Math.min(step.parts.done, step.parts.total)), total: step.parts.total } : null)

export const nowBoxModel = safe(({ record: rec, need, proving, stamps, cost, step, holder, next: nx, now }) => {
  if (!isObj(rec) || !isObj(rec.milestone)) return null
  const t = num(now) ? now : Date.now()
  const st = isObj(stamps) ? stamps : {}
  const note = isObj(step) ? step : null
  const base = { command: null, parts: null, milestone: milestoneOf(note, nx, st['estimate-milestone'], t), cost: costOf(cost) }
  const l = isObj(rec.lease) ? rec.lease : null
  if (l) {
    const plans = (Array.isArray(rec.plans) ? rec.plans : []).filter((p) => isObj(p) && p.status === 'building')
    const phases = [...new Set(plans.map((p) => p.phase).filter((x) => typeof x === 'string' && x))]
    const titles = plans.map((p) => p.title).filter(Boolean)
    const what = {
      plan: 'planning the work',
      build: 'building ' + (phases.length ? 'phase ' + phases.join(', ') : 'the plan') + (titles.length ? ' (' + titles.join(', ') + ')' : ''),
      qa: 'checking the results',
      fix: 'fixing what the checks found',
      map: 'reading the project to map it',
    }[l.kind] || 'working'
    return { ...base, state: { text: 'VBW is ' + what + heldBy(holder) + '.', need: false }, step: stepLine(note && str(note.doing), Date.parse(l.started_at), note, t), parts: partsOf(note) }
  }
  if (proving === true || (note && note.kind === 'proof')) {
    const at = num(st.proving) ? st.proving : note ? Date.parse(note.started_at) : NaN
    return { ...base, state: { text: 'VBW is proving the work: running its checks.', need: false }, step: stepLine(note && str(note.doing), at, note, t), parts: partsOf(note) }
  }
  if (isObj(need) && str(need.text)) {
    const since = num(st.need) ? st.need : need.at
    const when = dayClock(since, t)
    return { ...base, state: { text: need.text, need: true }, command: needCommand(need), step: when ? { text: 'Waiting since ' + when + '.', end: null, at: since, timed: false } : null }
  }
  return { ...base, state: { text: 'Nothing is running.', need: false }, step: null }
})

// The running step's time and the milestone's end are the kernel's, worded here; the
// panel works none out. The step's end comes from its note (panel-step.js); the road
// (R191) comes from the live step's note, else from the last `vbw next` (next.json).
// No road, or none at all, gives no milestone row.

function roadRow(step, nx, stamps, now) {
  const road = isObj(step) && isObj(step.road) ? step.road : isObj(step) && step.road === null ? null : isObj(nx) && isObj(nx.road) ? nx.road : null
  if (!road) return null
  if (typeof road.end !== 'string' || !Number.isFinite(Date.parse(road.end))) {
    const why = typeof road.basis === 'string' && road.basis.trim() ? road.basis.trim().replace(/\.$/, '') : ''
    return { id: 'estimate-milestone', text: 'No estimate yet' + (why ? ': ' + why : '') + '.', term: 'estimate, no basis' }
  }
  const say = sentence(road.say)
  return say ? { id: 'estimate-milestone', text: stamped(stamps['estimate-milestone'], say, now), term: 'estimate, approximate' } : null
}

function estimateRows(stamps, step, nx, now) {
  const r = roadRow(step, nx, stamps, now)
  return r ? [r] : []
}

// What panel.js dates before the view is drawn: the need and the rows of panelView that
// can carry a start time (the estimates), said as panelView says them with these stamps.
export function datedRows(input) {
  const { record: rec, next: nx, nextAt, question, questionAt, health, now } = isObj(input) ? input : {}
  if (!isObj(rec) || !isObj(rec.milestone) || !rec.milestone.id) return { rows: [], need: null }
  const step = isObj(input.step) ? input.step : null
  const stamps = isObj(input.stamps) ? input.stamps : {}
  return { need: liveNeed({ record: rec, next: nx, nextAt, question, questionAt, health }), rows: estimateRows(stamps, step, nx, Number.isFinite(now) ? now : Date.now()) }
}

// A refusal's text, short (design rule 4): its first line, and when that line names the
// run's files as a list ("... this run's files (a.js, b.js, ...): why"), the clause before
// the list, with the number of files kept apart. { clause, files } or null for no text.
const FILE_LIST = /^(.*?files) \(([^()]*)\)(?::|$)/
export function shortRefusal(text) {
  if (typeof text !== 'string') return null
  const first = (text.split('\n').find((l) => l.trim()) || '').trim()
  if (!first) return null
  const m = FILE_LIST.exec(first)
  const list = m ? m[2].split(',').map((f) => f.trim()).filter(Boolean) : []
  return list.length ? { clause: m[1], files: list.length } : { clause: first, files: 0 }
}
export const refusedBy = (r) => (typeof r.by === 'string' && r.by ? r.by + ': ' : '')

// A refusal as the Now tab says it: one short amber row, '[15:41] ⊘ VBW refused, dev P5.2:
// <first clause>', with `more` ('· 9 files in this run') when the clause left the run's
// file list out, and `full`, the whole text on one line, when there is more than the row
// says (shown on a press). Null for none.
export function refusalRow(r, now) {
  const s = isObj(r) ? shortRefusal(r.text) : null
  if (!s) return null
  const at = dayClock(r.at, now)
  const whole = r.text.split('\n').map((l) => l.trim()).filter(Boolean).join(' ')
  const text = (at ? '[' + at + '] ' : '') + REFUSED_MARK + ' VBW refused, ' + refusedBy(r) + s.clause
  return {
    id: 'refused:' + String(r.id), term: 'refused', files: s.files,
    more: s.files ? '· ' + s.files + (s.files === 1 ? ' file' : ' files') + ' in this run' : null,
    text, full: whole === s.clause ? null : whole,
  }
}

// The last run's refusals (panel-feed.js), newest five, each as refusalRow says it.
const REFUSALS_SHOWN = 5
const refusalRows = (list, now) => (Array.isArray(list) ? list : []).filter((r) => isObj(r) && typeof r.text === 'string' && r.text.trim())
  .slice(-REFUSALS_SHOWN).map((r) => refusalRow(r, now)).filter(Boolean)

export function panelView(input) {
  const { record: rec, next: nx, nextAt, question, questionAt, health, now, cost, proving } = isObj(input) ? input : {}
  const step = isObj(input) && isObj(input.step) ? input.step : null
  const stamps = isObj(input) && isObj(input.stamps) ? input.stamps : {}
  if (!isObj(rec) || !isObj(rec.milestone) || !rec.milestone.id) return { rows: [NEUTRAL], need: null, box: null }
  // Progress as the status line counts it: the current milestone's requirements proven or accepted.
  const rq = (Array.isArray(rec.requirements) ? rec.requirements : []).filter((r) => isObj(r) && r.milestone === rec.milestone.id)
  const done = rq.filter((r) => r.status === 'proven' || r.status === 'accepted').length
  const progress = rq.length === 0 ? 'No requirements are set yet.'
    : done + ' of ' + rq.length + (rq.length === 1 ? ' requirement' : ' requirements') + ' done.'
  const need = liveNeed({ record: rec, next: nx, nextAt, question, questionAt, health })
  const t = Number.isFinite(now) ? now : Date.now()
  return {
    need,
    box: nowBoxModel({ record: rec, need, proving: proving === true, stamps, cost, step, holder: input.holder, next: nx, now: t }),
    rows: [
      { id: 'milestone', text: 'Working on ' + rec.milestone.id + ': ' + (rec.milestone.title || 'untitled') + '.', term: 'milestone' },
      { id: 'progress', text: progress, term: 'requirements' },
      doing(rec, t),
      ...estimateRows(stamps, step, nx, t),
      costRow(cost),
      ...refusalRows(input.refusals, t),
      { id: 'need', text: need ? stamped(Number.isFinite(stamps.need) ? stamps.need : need.at, need.text, t) : 'VBW is not waiting on you.', term: 'your turn' },
    ],
  }
}
