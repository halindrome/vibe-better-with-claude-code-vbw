// Mission Control's Timeline, under the lanes of the live run: every VBW run of this
// session as one row, its time bar beside its cost bar, each to one scale, then the
// session total. A run's time is its finished steps' seconds (steps.json) or, while it
// is open, the clock since it started; its cost is the session cost added while its
// lease was open, so "about". Pure: values in, trees out; no `$`, never throws.

import { duration } from './panel-mission-live.js'
import { ACCENT } from './panel-palette.js'
import { newMark } from './panel-next.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
const str = (x) => (typeof x === 'string' && x !== '' ? x : null)
const usd = (x) => '$' + x.toFixed(2)
const cents = (x) => Math.round(x * 1e4) / 1e4

// The run id of a lease panel.js tracked: its own, else the part of its key before '@'.
const runIdOf = (l) => str(l.run) || (str(l.key) ? l.key.split('@')[0] : null)

// runs: panel.js's leases [{ key, kind, startedAt, costStart, costEnd? }]; the last one
// without costEnd is open. -> { rows: [{ name, open, seconds, cost, time, money, timeBar,
// costBar }], kinds, session, width }.
export function runsModel(input) {
  try {
    const { runs, steps, sessionCost, now, width, fresh, motion } = isObj(input) ? input : {}
    const marks = isObj(fresh) ? fresh : {}
    const list = (Array.isArray(runs) ? runs : []).filter((l) => isObj(l) && str(l.kind))
    const session = num(sessionCost) ? sessionCost : null
    const history = (Array.isArray(steps) ? steps : []).filter((s) => isObj(s) && num(s.seconds) && s.seconds >= 0)
    const seen = {}
    const rows = list.map((l, i) => {
      const open = l.costEnd === undefined && i === list.length - 1
      const id = runIdOf(l)
      const own = id ? history.filter((s) => s.run === id) : []
      const seconds = open && num(l.startedAt) && num(now) ? Math.max(0, Math.round((now - l.startedAt) / 1000))
        : own.length ? own.reduce((n, s) => n + s.seconds, 0) : null
      const end = num(l.costEnd) ? l.costEnd : open ? session : null
      const cost = num(l.costStart) && num(end) && end >= l.costStart ? cents(end - l.costStart) : null
      seen[l.kind] = (seen[l.kind] || 0) + 1
      return {
        name: l.kind + ' ' + seen[l.kind], kind: l.kind, open, seconds, cost, fresh: str(l.key) ? Object.prototype.hasOwnProperty.call(marks, 'timeline:run:' + l.key) : false,
        time: seconds === null ? 'time unknown' : duration(seconds * 1000),
        money: cost === null ? 'cost unknown' : 'about ' + usd(cost),
      }
    })
    const w = num(width) ? Math.max(20, Math.floor(width)) : 60
    const nameW = Math.max(4, ...rows.map((r) => r.name.length))
    const timeW = Math.max(4, ...rows.map((r) => r.time.length))
    const moneyW = Math.max(4, ...rows.map((r) => r.money.length))
    // What is left after the name and the two figures goes to the two bars, half each.
    const bar = Math.max(1, Math.floor((w - nameW - timeW - moneyW - 4) / 2))
    const maxS = Math.max(0, ...rows.map((r) => r.seconds || 0))
    const maxC = Math.max(0, ...rows.map((r) => r.cost || 0))
    const scale = (v, max) => (max > 0 && v > 0 ? Math.max(1, Math.round((v / max) * bar)) : 0)
    for (const r of rows) {
      r.timeBar = scale(r.seconds, maxS)
      r.costBar = scale(r.cost, maxC)
    }
    const kinds = []
    for (const r of rows.filter((x) => x.cost !== null)) {
      let k = kinds.find((x) => x.kind === r.kind)
      if (!k) kinds.push((k = { kind: r.kind, runs: 0, cost: 0 }))
      k.runs++
      k.cost = cents(k.cost + r.cost)
    }
    kinds.sort((x, y) => y.cost - x.cost)
    return {
      rows, kinds, bar, widths: { name: nameW, time: timeW, money: moneyW }, motion,
      session: session === null ? 'The session cost is not available.' : 'This session: ' + usd(session),
    }
  } catch {
    return { rows: [], kinds: [], bar: 1, widths: { name: 4, time: 4, money: 4 }, session: 'The session cost is not available.' }
  }
}

// One row per run: name, time bar (the accent while it runs, dim once done) and its time,
// cost bar (the accent: the run's cost) and its cost; then the totals by kind, dim, and the
// session total.
export function renderRuns(ui, model) {
  const { Box, Text } = isObj(ui) ? ui : {}
  const m = isObj(model) && Array.isArray(model.rows) ? model : runsModel(null)
  const w = m.widths
  const pad = (s, n) => String(s).padEnd(n)
  const kids = [h(Text, { key: 'runs-title', bold: true }, 'Runs this session')]
  if (!m.rows.length) kids.push(h(Text, { key: 'runs-none', dimColor: true }, 'No VBW run has finished in this session yet.'))
  m.rows.forEach((r, i) => kids.push(h(Box, { key: 'run:' + i, flexDirection: 'row' },
    h(Text, { key: 'name' }, pad(r.name, w.name + 1)),
    h(Text, { key: 'time-bar', ...(r.open ? { color: ACCENT } : { dimColor: true }) }, pad('█'.repeat(r.timeBar), m.bar)),
    h(Text, { key: 'time', dimColor: true }, ' ' + pad(r.time, w.time + 1)),
    h(Text, { key: 'cost-bar', color: ACCENT }, pad('█'.repeat(r.costBar), m.bar)),
    h(Text, { key: 'cost', dimColor: true }, ' ' + r.money),
    r.fresh ? newMark(Text, m.motion) : null)))
  if (m.kinds.length > 1) {
    kids.push(h(Text, { key: 'runs-kinds', dimColor: true, wrap: 'truncate-end' },
      'by kind: ' + m.kinds.map((k) => k.kind + ' about ' + usd(k.cost) + ' (' + k.runs + (k.runs === 1 ? ' run' : ' runs') + ')').join(' · ')))
  }
  kids.push(h(Text, { key: 'runs-session', bold: true }, m.session))
  return h(Box, { key: 'runs', flexDirection: 'column', marginTop: 1 }, ...kids)
}
