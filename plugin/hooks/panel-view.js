// What the VBW panel says (R51): turns the project record and its last `vbw next`
// into plain sentences, each with its technical term beside it. Pure: data in,
// rows out; it never changes its input and never throws.

import { estimate } from './panel-estimate.js'

export const MIN_VERSION = '2.1.287'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
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

// A moment as the local clock reads it, 'HH:MM'; '' when there is no moment.
export function clock(ms) {
  if (typeof ms !== 'number' || !Number.isFinite(ms)) return ''
  const d = new Date(ms)
  return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
}
// '[14:20] ' before a sentence that has a start time; the sentence alone without one.
const stamped = (ms, text) => (clock(ms) ? '[' + clock(ms) + '] ' + text : text)

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

const list = (a) => (Array.isArray(a) ? a.filter((x) => typeof x === 'string' && x).join(', ') : '')
const RUN_ACTIONS = new Set(['plan', 'build', 'qa', 'fix'])
const COMPACT_PCT = 85 // the context is this full: /compact before a run

// The gate in next.json as the need it makes: key, kind, the sentence Mission Control
// says, and the short phrase Comms puts after 'VBW needs you ·'.
function gateNeed(nx) {
  const d = isObj(nx.detail) ? nx.detail : {}
  const need = (key, text, what) => ({ key, kind: nx.action, text, what })
  switch (nx.action) {
    case 'approve': {
      const f = list(d.files)
      return need('approve' + (f ? ':' + f : ''), 'Please approve the plan before VBW builds it.',
        f ? 'test files changed since your approval: ' + f : 'the plan is ready: review it, then approve it to build')
    }
    case 'accept': { const r = list(d.requirements); return need('accept:' + r, 'Please check the result by hand: ' + r + '.', 'check by hand what only you can judge' + (r ? ': ' + r : '')) }
    case 'ship': return need('ship', 'The milestone is ready: your go-ahead to ship it is needed.', 'the milestone is proven and accepted: ready to ship')
    case 'spec': return need('spec', 'VBW needs you to say what to build: the requirements.', 'say what to build: the requirements')
    case 'escalate': { const f = list(d.fixes); return need('escalate:' + f, 'A decision is needed from you on ' + f + '.', 'the fix limit was reached' + (f ? ' for ' + f : '') + ': decide how to go on') }
    case 'unblock': { const p = list(d.plans); return need('unblock:' + p, 'Work is blocked and needs you' + (p ? ': ' + p : '') + '.', 'blocked' + (p ? ': ' + p : '') + ', VBW needs your help to go on') }
    case 'scope': return need('scope', 'Some changes went outside their planned files: your decision is needed.', 'commits changed files outside their plans: review them')
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
  return false
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
  if (nx.gate === true) return answered(rec, nx, nextAt) ? null : { ...gateNeed(nx), at: at(nextAt) }
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

// The 'what's happening now' box: VBW's state as one plain sentence, the current step
// with the time it started, and the cost line. `proving` comes from panel.js (a proof
// is running with no lease); `stamps.proving` is when it began.
function nowBox(rec, need, proving, stamps, cost) {
  const l = isObj(rec.lease) ? rec.lease : null
  const cl = costRow(cost)
  if (l) {
    const plans = (Array.isArray(rec.plans) ? rec.plans : []).filter((p) => isObj(p) && p.status === 'building')
    const phases = [...new Set(plans.map((p) => p.phase).filter((x) => typeof x === 'string' && x))]
    const titles = plans.map((p) => p.title).filter(Boolean)
    const what = {
      plan: ['planning the work', 'planning'],
      build: ['building ' + (phases.length ? 'phase ' + phases.join(', ') : 'the plan') + (titles.length ? ' (' + titles.join(', ') + ')' : ''), 'building'],
      qa: ['checking the results', 'checking'],
      fix: ['fixing what the checks found', 'fixing'],
      map: ['reading the project to map it', 'mapping'],
    }[l.kind] || ['working', String(l.kind || 'run')]
    const at = Date.parse(l.started_at)
    return { state: { text: 'VBW is ' + what[0] + '.', term: 'state' }, step: Number.isFinite(at) ? { text: 'Current step: ' + what[1] + ', started at ' + clock(at) + '.', at } : null, cost: cl }
  }
  if (proving) {
    const at = stamps.proving
    return { state: { text: 'VBW is proving the work: running its checks.', term: 'state' }, step: Number.isFinite(at) ? { text: 'Current step: proving, started at ' + clock(at) + '.', at } : null, cost: cl }
  }
  if (need) {
    return { state: { text: 'VBW is waiting for you: ' + need.what + '.', term: 'state' }, step: Number.isFinite(need.at) ? { text: 'Waiting since ' + clock(need.at) + '.', at: need.at } : null, cost: cl }
  }
  return { state: { text: 'Nothing is running.', term: 'state' }, step: null, cost: cl }
}

const mins = (sec) => Math.max(1, Math.round(sec / 60))
const NO_BASIS = { text: 'No estimate yet: there are not enough finished steps to go on.', term: 'estimate, no basis' }

// Time left for the running step and for the milestone, never more exact than it is.
function estimateRows(rec, steps, phasesLeft, now, stamps) {
  const e = estimate({ steps, lease: isObj(rec.lease) ? rec.lease : null, phasesLeft, now })
  const row = (id, x, what) => {
    if (x.state === 'none') return { id, ...NO_BASIS }
    const text = x.state === 'longer' ? 'This step is taking longer than usual.' : 'About ' + mins(x.seconds) + ' min left in ' + what + '.'
    return { id, text: stamped(stamps[id], text), term: 'estimate, approximate' }
  }
  const rows = []
  if (e.step) rows.push(row('estimate-step', e.step, 'this step'))
  if (e.milestone && !(e.milestone.state === 'none' && rows.length && rows[0].term === NO_BASIS.term)) rows.push(row('estimate-milestone', e.milestone, 'the milestone'))
  return rows
}

export function panelView(input) {
  const { record: rec, next: nx, nextAt, question, questionAt, health, now, cost, steps, proving } = isObj(input) ? input : {}
  const stamps = isObj(input) && isObj(input.stamps) ? input.stamps : {}
  if (!isObj(rec) || !isObj(rec.milestone) || !rec.milestone.id) return { rows: [NEUTRAL], need: null, box: null }
  const ph = (Array.isArray(rec.phases) ? rec.phases : []).filter((p) => isObj(p) && p.milestone === rec.milestone.id)
  const phasesLeft = ph.filter((p) => !(isObj(p.qa) && p.qa.result === 'pass')).length
  // Progress as the status line counts it: the current milestone's requirements proven or accepted.
  const rq = (Array.isArray(rec.requirements) ? rec.requirements : []).filter((r) => isObj(r) && r.milestone === rec.milestone.id)
  const done = rq.filter((r) => r.status === 'proven' || r.status === 'accepted').length
  const progress = rq.length === 0 ? 'No requirements are set yet.'
    : done + ' of ' + rq.length + (rq.length === 1 ? ' requirement' : ' requirements') + ' done.'
  const need = liveNeed({ record: rec, next: nx, nextAt, question, questionAt, health })
  const t = Number.isFinite(now) ? now : Date.now()
  return {
    need,
    box: nowBox(rec, need, proving === true, stamps, cost),
    rows: [
      { id: 'milestone', text: 'Working on ' + rec.milestone.id + ': ' + (rec.milestone.title || 'untitled') + '.', term: 'milestone' },
      { id: 'progress', text: progress, term: 'requirements' },
      doing(rec, t),
      ...estimateRows(rec, Array.isArray(steps) ? steps : [], phasesLeft, t, stamps),
      costRow(cost),
      { id: 'need', text: need ? stamped(Number.isFinite(stamps.need) ? stamps.need : need.at, need.text) : 'Nothing is needed from you right now.', term: 'your turn' },
    ],
  }
}
