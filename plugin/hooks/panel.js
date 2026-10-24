// The VBW panel (R51, R53, R55; mods_4_vbw.md): a Claude Code mod that shows what
// VBW is doing. It reads the record, the last `vbw next`, the autonomous run, the
// clone's finished steps, the session's usage and this session's workflow files,
// all on one timer; it writes nothing itself (/vbw-todo hands its text to the
// kernel), and does nothing at all where it cannot run: Claude Code older than
// 2.1.287, or a folder that is not a VBW 2 project. Every hook is wrapped: an error
// here must never reach the user's session. Every function that takes `$` lives in
// this file (Claude Code follows `$` into this file's functions only); what is drawn
// is worked out by the pure modules: panel-stage.js (Comms), panel-sites.js (the
// one-line sites and rows), panel-pane.js (Mission Control), panel-view.js, and
// panel-candy.js (motion, sprites, celebrations), whose frames this file blits.
import { holderName, readRegistry, configDir } from './panel-sessions.js'
import { panelView, datedRows, liveNeed, supports, COMMS_MIN_VERSION } from './panel-view.js'
import * as sounds from './panel-sounds.js'
import { gatherRun, findRun } from './panel-feed.js'
import { stageModel, renderStage } from './panel-stage.js'
import { liveStep, dayClock } from './panel-step.js'
import { statusText, whyText, todoArgs } from './panel-commands.js'
import { renderPane } from './panel-pane.js'
import { freshKey } from './panel-next.js'
import { fresh as freshLook, freshArrive, freshSee } from './panel-candy.js'
import { READ_ARGV, settingArgv, settingsState, settingsSig } from './panel-settings.js'
import { stateColor } from './panel-palette.js'
import { SITES, turnPending } from './panel-sites.js'
import { motionOf, spriteFrame, encodeCells, confettiFrames, sweepFrames, wrappedModel, celebration } from './panel-candy.js'

const PANE = 'vbw-panel'
const TICK_MS = 2000
// The user's choice lives in Claude Code's per-user store, never in the project.
// A project holding .vbw/runtime/test-mode is a VBW test session (R64): it plays no
// audio and keeps its choices under test.* keys, never the user's.
const TEST_MARK = '/.vbw/runtime/test-mode'
// The store keys of the panel's choices. A real-app test session (TEST_MARK) keeps them
// under test keys of its own project, so it never touches the user's choices and one
// scenario's choices (a pane closed on purpose) never reach the next scenario's project.
const projectTag = (root) => {
  let h = 5381
  for (let i = 0; i < root.length; i++) h = ((h * 33) ^ root.charCodeAt(i)) >>> 0
  return h.toString(36)
}
const keys = (testRoot) => {
  const p = typeof testRoot === 'string' ? 'test.' + projectTag(testRoot) + '.' : ''
  return { closed: p + 'vbw-panel.closed', nextSeen: p + 'vbw-panel.next-seen', seen: p + 'vbw-panel.seen', needSeen: p + 'vbw-panel.need-seen', needNotified: p + 'vbw-panel.need-notified', helpersSeen: p + 'vbw-panel.helpers-seen', refusalsSeen: p + 'vbw-panel.refusals-seen' }
}
// The sound for a request for the user: the clone setting `sound` (docs/config.md) is
// `off`, `default` (any shipped voice) or a folder under assets/audio/; panel-sounds.js's
// soundFor picks the clip. With none shipped, the panel is silent.
const soundFor = sounds.soundFor
const pick = (st) => {
  const c = soundFor(st.soundChoice)
  return typeof c === 'string' ? { asset: c } : isObj(c) ? c : null
}
// The clone setting as the kernel defines it: a missing file or key, damaged JSON or a
// value that is not a string is `default`.
const soundChoice = (clone) => (isObj(clone) && typeof clone.sound === 'string' && clone.sound ? clone.sound : 'default')
const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
// VBW's workflows, as /vbw:vibe launches them (Workflow name 'vbw:<kind>').
const KINDS = ['planning', 'building', 'fixing', 'verifying', 'mapping', 'researching', 'investigating', 'tooling']
const kindOf = (name) => {
  const k = typeof name === 'string' ? name.replace(/^vbw[:-]/, '') : ''
  return KINDS.includes(k) ? k : null
}

// The motion level (mods_4_vbw.md §3.7, panel-candy.js): a test session is always
// still; else the record's `settings.motion`; else the interview level. The level
// is the one `vbw next` read (private or kept in the project) once the interview is
// done (before that, next fills a neutral level, which says nothing about the
// person), else the project's kept answers; unknown, calm.
const levelOf = (st) => {
  const p = isObj(st.next) && isObj(st.next.profile) ? st.next.profile : null
  if (p && p.interviewed === true) return p.level
  const pr = isObj(st.record) && isObj(st.record.project) ? st.record.project : null
  return pr && isObj(pr.interview) ? pr.interview.level : null
}
const motion = (st) => motionOf({ setting: isObj(st.record) && isObj(st.record.settings) ? st.record.settings.motion : null, level: levelOf(st), testMode: st.silent })
const FRAME_MS = 100 // 10 frames a second, while something moves
const AFTER_MS = 5000 // a celebration never drawn in this long is let go
const CONFETTI_ROWS = 3 // the height of the confetti burst in Comms
const CHEER_MS = 60000
// A sprite's cells, encoded once per role, pose and frame (every pose has 2 or 3).
const SPRITES = new Map()
const spriteCells = (role, pose, n) => {
  const k = role + ':' + pose + ':' + (n % 6)
  if (!SPRITES.has(k)) SPRITES.set(k, encodeCells(spriteFrame({ role, pose, frame: n })))
  return SPRITES.get(k)
}
// A celebration: its frames are made for the width of the site that first draws
// it, encoded once; the first is drawn, the rest are blitted.
const effect = (key, at, make) => ({ key, at, make, frames: null, i: 0, site: null })
const drawn = (fx, columns, site) => {
  if (!fx.frames) {
    const f = fx.make(Math.min(512, Math.floor(columns)))
    if (!f.length) return null
    Object.assign(fx, { cols: f[0].cols, rows: f[0].rows, frames: f.map(encodeCells) })
  }
  fx.site = site
  return fx.frames[Math.min(fx.i, fx.frames.length - 1)]
}

// Parse a project file; null when it is not a JSON object (half written, invalid).
function parse(text) {
  try {
    const v = JSON.parse(text)
    return isObj(v) ? v : null
  } catch {
    return null
  }
}

// What the panel knows: the last good state of its files, the live run, what is drawn, what is asked.
function fresh() {
  return {
    live: false, registered: false, born: {}, timer: null, busy: false, question: null, sound: true, soundChoice: 'default', soundSig: undefined, settingsPath: null, keys: keys(false), silent: false, wouldPlay: 0,
    record: null, next: null, history: null, cost: null, health: null, auto: null, stepsPath: null, steps: null, shown: '', seen: {}, sized: false,
    root: null, sessionId: null, holder: null, registry: null, stored: null, configDir: null, sessionDir: null, runRef: null, run: null, feed: {}, finder: {}, toolRuns: {}, leases: [],
    tab: 'now', phase: null, check: null, agent: null, suggested: null, before: null, memo: {}, notice: null,
    lastRec: null, crews: {}, anim: null, animBusy: false, frameNo: 0, commsId: null, nextFileAt: null, questionAt: null, helpersSeen: {}, refusalsSeen: {},
    sprites: null, burst: null, sweep: null, cheer: null, wrapped: null, nextSeen: null, nextAt: null, nextAnim: null,
    seenNext: null, needSeen: null, needNotified: null, proving: null, stamps: {}, stepNote: null, step: null, open: {},
    fresh: {}, settings: null,
  }
}

// What is true now, for every place that asks: next.json comes with the time it was
// written, so a gate is dated by the file and answered by the record that followed it.
// A message keeps the time it began saying what it says (st.stamps): the first pass
// reads the dated sentences bare, the second draws them all, each with its [HH:MM].
const STAMPED = ['estimate-milestone']
const bare = (t) => String(t).replace(/^\[\d\d:\d\d\] /, '')
function view(st, now) {
  const input = {
    record: st.record, next: st.next, nextAt: st.nextFileAt, question: st.question, questionAt: st.questionAt,
    health: st.health, now, cost: st.cost, steps: st.steps, step: st.step, proving: st.proving !== null, holder: st.holder,
    refusals: isObj(st.run) ? st.run.refusals : null,
  }
  const proving = st.proving && num(st.proving.at) ? st.proving.at : undefined
  const first = datedRows({ ...input, stamps: { proving } })
  const stamps = { proving }
  for (const id of STAMPED) {
    const row = first.rows.find((r) => r.id === id)
    const text = row ? bare(row.text) : null
    if (text === null || /^No (?:estimate|end time)/.test(text)) delete st.stamps[id]
    else {
      if (!st.stamps[id] || st.stamps[id].text !== text) st.stamps[id] = { text, at: now }
      stamps[id] = st.stamps[id].at
    }
  }
  // A need without a time of its own is dated by when it was first seen.
  const need = first.need
  if (need && !num(need.at)) {
    if (!st.stamps.need || st.stamps.need.text !== need.key) st.stamps.need = { text: need.key, at: now }
    stamps.need = st.stamps.need.at
  } else delete st.stamps.need
  return panelView({ ...input, stamps })
}

// The session cost moved while the open lease ran; null without both figures.
const openLease = (st) => {
  const l = st.leases[st.leases.length - 1]
  return l && l.costEnd === undefined ? l : null
}
const runCost = (st) => {
  const l = openLease(st)
  return l && num(l.costStart) && num(st.cost) ? st.cost - l.costStart : null
}

// Comms' model, for any width: what comms() draws and the redraw check compares.
// What the user has not seen yet (a recommendation, a needs-you line, a failed helper)
// is marked until it is pressed, opened, or its tab is opened.
const needNow = (st) => liveNeed({ record: st.record, next: st.next, nextAt: st.nextFileAt, question: st.question, questionAt: st.questionAt, health: st.health })
const needId = (n) => n.key + '@' + String(n.at)
// The fresh marks drawn (panel-candy.js): the recommendation's while it is unseen, dated by
// when the panel saw it arrive, and this session's finished runs and changed settings.
const freshMarks = (st) => {
  const key = freshKey(recOf(st))
  return key && unseenNext(st) ? { [key]: num(st.nextAt) ? st.nextAt : 0, ...st.fresh } : st.fresh
}
const unseenNext = (st) => {
  const rec = recOf(st)
  return isObj(rec) && typeof rec.at === 'string' && rec.at !== '' && rec.at !== st.seenNext
}
// A short message keeps the time it began saying what it says (st.stamps.comms): the
// same text keeps its time; new text, or text gone for longer than a few redraws, starts afresh.
const COMMS_GAP_MS = 10000
const commsStamp = (st, now) => (id, text) => {
  const c = isObj(st.stamps.comms) ? st.stamps.comms : (st.stamps.comms = {})
  const m = c[id]
  if (!isObj(m) || m.text !== text || now - m.seen > COMMS_GAP_MS) c[id] = { text, at: now, seen: now }
  else m.seen = now
  return c[id].at
}
// The refusals the agents of the last run reported (panel-feed.js); the newest one
// not yet seen goes on Comms until the Now tab is shown (seen(), 'refusals').
const runRefusals = (st) => (isObj(st.run) && Array.isArray(st.run.refusals) ? st.run.refusals.filter((r) => isObj(r) && typeof r.id === 'string') : [])
const refusalNow = (st) => runRefusals(st).filter((r) => !st.refusalsSeen[r.id]).reduce((a, r) => (!a || (num(r.at) ? r.at : 0) >= (num(a.at) ? a.at : 0) ? r : a), null)
const stage = (st, now, props) => {
  const need = needNow(st)
  return stageModel({
    refusal: refusalNow(st),
    stamp: commsStamp(st, now),
    run: st.run, next: st.next, step: st.step, now, health: st.health, cost: runCost(st), motion: motion(st),
    need, fresh: need !== null && needId(need) !== st.needSeen,
    seen: Object.keys(st.helpersSeen), born: st.born, columns: isObj(props) ? props.bodyColumns : undefined, maxRows: isObj(props) ? props.maxRows : undefined,
  })
}

// Read a file only when its size or time changed; keep the old state when it cannot be used,
// or drop it when `gone` and the file is gone.
async function refresh($, st, path, key, gone, timeKey) {
  let sig
  let at = null
  try {
    const f = await $.fs.stat(path)
    at = num(f.mtimeMs) ? f.mtimeMs : null
    sig = f.size + ':' + f.mtimeMs
  } catch {
    if (gone) st[key] = null
    if (gone && timeKey) st[timeKey] = null
    delete st.seen[path]
    return
  }
  if (st.seen[path] === sig) return
  st.seen[path] = sig
  let text
  try {
    text = await $.fs.read(path)
  } catch {
    return
  }
  const v = parse(text)
  if (v) {
    st[key] = v
    if (timeKey) st[timeKey] = at // the time stays with the contents it belongs to
  }
}

// Where this clone keeps steps.json: its git directory, also from a linked worktree
// (whose .git file names a directory with a `commondir` pointer). Null when unknown.
const norm = (p) => {
  const out = []
  for (const s of p.split('/')) {
    if (s === '..') out.pop()
    else if (s !== '' && s !== '.') out.push(s)
  }
  return '/' + out.join('/')
}
const place = (base, p) => norm(p.startsWith('/') ? p : base + '/' + p)

async function stepsPath($, root) {
  try {
    const dot = root + '/.git'
    if ((await $.fs.stat(dot)).kind === 'dir') return dot + '/vbw/steps.json'
    const m = /^gitdir:\s*(.+?)\s*$/m.exec(await $.fs.read(dot))
    if (!m) return null
    const dir = place(root, m[1])
    let common = dir
    try {
      const c = (await $.fs.read(dir + '/commondir')).trim()
      if (c) common = place(dir, c)
    } catch {
      // not a linked worktree: this is the git directory
    }
    return common + '/vbw/steps.json'
  } catch {
    return null
  }
}

// This session's folder, where Claude Code writes its workflow runs: the Claude
// config folder `dir` (as tools/resolve-claude-dir.sh finds it), the project's folder
// (its path, every other character a dash) and the session id. Null when unknown.
// The project of a session started in DIR, found as the kernel finds it (vbw_git_root):
// the nearest folder at or above DIR that holds .git (a folder, or the file of a linked
// worktree or a submodule), never above /; DIR itself when none does (hooks/project.sh).
async function projectOf($, dir) {
  let d = dir.replace(/\/+$/, '')
  for (;;) {
    if (await $.fs.exists(d + '/.git')) return d || '/'
    const i = d.lastIndexOf('/')
    if (i < 0) return dir
    d = d.slice(0, i)
  }
}

function sessionDir(dir, root, id) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]+$/.test(id)) return null
  return dir ? dir + '/projects/' + root.replace(/[^A-Za-z0-9]/g, '-') + '/' + id : null
}

// Who holds the open run: Claude Code's list of chats and what `vbw run start` stored
// (.vbw/runtime/holder.json), read on the tick only while a lease is open; the list
// alone also while the Sessions tab is shown.
async function readHolder($, st) {
  const lease = isObj(st.record) && isObj(st.record.lease) ? st.record.lease : null
  if (!lease && st.tab !== 'sessions') {
    st.holder = null
    st.registry = null
    return
  }
  const registry = await readRegistry($, st.configDir)
  st.registry = registry
  if (!lease) {
    st.holder = null
    return
  }
  await refresh($, st, st.root + '/.vbw/runtime/holder.json', 'stored', true)
  st.holder = holderName({ lease, registry, stored: isObj(st.stored) ? st.stored : null, sessionId: st.sessionId })
}

// The session cost so far, the context fill and the weekly limit: numbers, or null
// when they cannot be read (never a guess).
async function readUsage($, st) {
  try {
    const u = await $.session.usage()
    const usd = isObj(u) && isObj(u.cost) ? u.cost.usd : null
    st.cost = num(usd) ? usd : null
    const ctx = isObj(u) && isObj(u.context) ? u.context.percent : null
    const week = isObj(u) && Array.isArray(u.rateLimits) ? u.rateLimits.find((r) => isObj(r) && r.kind === 'seven_day') : null
    st.health = num(ctx) || (week && num(week.percentUsed)) ? { contextPct: num(ctx) ? ctx : null, weekPct: week && num(week.percentUsed) ? week.percentUsed : null } : null
  } catch {
    st.cost = null
    st.health = null
  }
}

// A proof is running in this session while its mark exists (the kernel removes it when
// the proof ends); the mark's time is when it began.
async function readProving($, st) {
  try {
    const f = st.sessionId ? await $.fs.stat(st.root + '/.vbw/runtime/proving.' + st.sessionId) : null
    st.proving = f ? { at: num(f.mtimeMs) ? f.mtimeMs : null } : null
  } catch {
    st.proving = null
  }
}

// Each lease (one VBW run) with the session cost when it opened and when it closed.
function trackLeases(st) {
  const l = isObj(st.record) && isObj(st.record.lease) ? st.record.lease : null
  const key = l ? String(l.run ?? '') + '@' + String(l.started_at ?? '') : null
  const open = openLease(st)
  if (open && open.key !== key) {
    open.costEnd = st.cost
    st.fresh = freshArrive(st.fresh, 'timeline:run:' + open.key, 0) // drawn as the word alone: no motion, no time
  }
  if (key && (!open || open.key !== key)) {
    const at = Date.parse(l.started_at)
    st.leases.push({ key, kind: String(l.kind || 'run'), startedAt: Number.isFinite(at) ? at : null, costStart: st.cost })
  }
}

// The reads panel-feed.js makes (list, stat, read and the clock), spelled here:
// Claude Code follows `$` into this file's functions only.
function reads($) {
  return {
    fs: { read: (p) => $.fs.read(p), list: (p) => $.fs.list(p), stat: (p) => $.fs.stat(p) },
    clock: { now: () => $.clock.now() },
  }
}

// The live run: the one this session launched, else (after a reload, while a lease
// is open) the newest VBW run still going in this session's folder.
async function feed($, st) {
  if (!st.sessionDir) return
  const io = reads($)
  const ended = !st.run || st.run.status !== 'running'
  if ((!st.runRef || ended) && isObj(st.record) && isObj(st.record.lease)) {
    const found = await findRun(io, st.finder, st.sessionDir)
    const kind = found && kindOf(found.kind)
    if (kind && (!st.runRef || found.runId !== st.runRef.runId)) st.runRef = { runId: found.runId, kind }
  }
  if (st.runRef) st.run = await gatherRun(io, st.feed, { sessionDir: st.sessionDir, ...st.runRef })
  // Each crew this session saw, for Wrapped's agent count.
  if (isObj(st.run) && typeof st.run.runId === 'string' && Array.isArray(st.run.agents)) {
    st.crews[st.run.runId] = { startedAt: st.run.startedAt, agents: st.run.agents.map((a) => (isObj(a) ? a.id : null)) }
  }
}

// The runs this session saw, for Wrapped: each lease with what it cost (an open one
// up to now), each workflow crew with its agents.
const runsSeen = (st) => [
  ...st.leases.map((l) => {
    const end = l.costEnd === undefined ? st.cost : l.costEnd
    return { startedAt: l.startedAt, cost: num(l.costStart) && num(end) ? end - l.costStart : null }
  }),
  ...Object.values(st.crews),
]

// What a change of the record earns (panel-candy.js): a phase passing QA, confetti
// in Comms (full motion); all checks green, the sweep over Proof (full) and a
// line in Comms (full and calm); a ship, the pane on VBW Wrapped (any motion:
// it is information). The first snapshot is not news.
// The proof's own time (when it was recorded, its day named when not today), else now.
const proofTime = (st, now) => {
  const ev = isObj(st.record) && isObj(st.record.evidence) ? st.record.evidence : null
  const at = ev ? Date.parse(ev.at) : NaN
  return dayClock(Number.isFinite(at) ? at : now, now)
}
async function celebrate($, st, now) {
  const before = st.lastRec
  if (before === st.record) return
  st.lastRec = st.record
  const c = celebration({ before, after: st.record })
  const m = motion(st)
  if (c === 'qa-pass' && m === 'full') st.burst = effect('vbw-confetti', now, (w) => confettiFrames({ cols: w, rows: CONFETTI_ROWS, seed: now }))
  if (c === 'all-green' && m !== 'off') st.cheer = { text: (proofTime(st, now) ? '[' + proofTime(st, now) + '] ' : '') + '✓ All checks pass', until: now + CHEER_MS }
  if (c === 'all-green' && m === 'full') st.sweep = effect('vbw-sweep', now, (w) => sweepFrames({ cols: w }))
  if (c === 'shipped') {
    st.wrapped = wrappedModel({ record: st.record, runs: runsSeen(st), steps: st.steps })
    if (st.wrapped) {
      st.tab = 'wrapped'
      await open($)
    }
  }
}

// Repaint by blit (no redraw): the crew's sprites while the run works and Comms
// shows them, and a celebration's frames once drawn; the loop stops when nothing moves.
async function paint($, requestId, key, cells) {
  try {
    const r = await $.ui.blit({ requestId, key, cells })
    return !(isObj(r) && r.deny)
  } catch {
    return false
  }
}

function still(st) {
  if (st.anim && st.anim.cancel) st.anim.cancel()
  st.anim = null
}

function animate($, st) {
  if (!st.anim) st.anim = $.clock.every(FRAME_MS, () => frame($, st))
}

async function frame($, st) {
  if (st.animBusy) return
  st.animBusy = true
  try {
    const n = ++st.frameNo
    if (st.sprites && !(motion(st) === 'full' && isObj(st.run) && st.run.status === 'running')) st.sprites = null
    for (const s of st.sprites || []) {
      if (!(await paint($, st.commsId, s.key, spriteCells(s.role, s.pose, n)))) {
        st.sprites = null
        break
      }
    }
    for (const k of ['burst', 'sweep']) {
      const fx = st[k]
      if (!fx || !fx.site) continue
      fx.i++
      if (fx.i >= fx.frames.length || !(await paint($, fx.site, fx.key, fx.frames[fx.i]))) {
        st[k] = null
        $.ui.invalidate('ui.render')
      }
    }
    if (!st.sprites && !(st.burst && st.burst.site) && !(st.sweep && st.sweep.site)) still(st)
  } catch {
    still(st)
  } finally {
    st.animBusy = false
  }
}

// Everything the panel shows, read afresh: each file only when it changed, never written.
async function gather($, st) {
  const root = st.root
  await refresh($, st, root + '/.vbw/record.json', 'record')
  await refresh($, st, root + '/.vbw/runtime/next.json', 'next', false, 'nextFileAt')
  await readProving($, st)
  await refresh($, st, root + '/.vbw/runtime/step.json', 'stepNote', true)
  st.step = liveStep(st.stepNote, st.record, st.sessionId)
  if (st.sessionId) await refresh($, st, root + '/.vbw/runtime/auto.' + st.sessionId + '.json', 'auto', true)
  if (st.stepsPath) {
    await refresh($, st, st.stepsPath, 'history')
    st.steps = isObj(st.history) && Array.isArray(st.history.steps) ? st.history.steps : null
  }
  await readSound($, st)
  await readUsage($, st)
  await readHolder($, st)
  trackLeases(st)
  await feed($, st)
}

// The sound choice, from the clone's settings.json in the git directory (only the kernel
// changes it: `vbw config set sound`); a damaged or missing file reads as `default`.
async function readSound($, st) {
  if (!st.settingsPath) return
  let sig = null
  try {
    const f = await $.fs.stat(st.settingsPath)
    sig = f.size + ':' + f.mtimeMs
  } catch {
    sig = null
  }
  if (sig !== st.soundSig) {
    st.soundSig = sig
    let v = null
    try {
      v = sig === null ? null : JSON.parse(await $.fs.read(st.settingsPath))
    } catch {
      v = null
    }
    st.soundChoice = soundChoice(v)
  }
  st.sound = st.soundChoice !== 'off'
}

// Call the user, once: the needs-you sound (`clip`) and a native notification (`text`), both
// only while the sound is on, the notification only while motion is not off, neither in a
// test session. Claude Code has no notification setting of VBW's own: `motion` is the
// switch (docs/panel.md). A missing player or $.ui.notify is silent.
async function call($, st, text, clip) {
  if (!st.sound) return
  if (st.silent) {
    if (clip) st.wouldPlay++
    return
  }
  if (clip) {
    try {
      await $.audio.play(clip)
    } catch {
      // no file or no player: nothing to say
    }
  }
  if (!text || motion(st) === 'off') return
  try {
    await $.ui.notify(text, { title: 'VBW' })
  } catch {
    // no notifications here: nothing to show instead
  }
}

// The need now standing, marked as notified (kept in the user's store, so a restart does
// not raise it again): true when it had not been notified yet.
async function firstCall($, st, need) {
  const id = needId(need)
  if (id === st.needNotified) return false
  st.needNotified = id
  await keep($, st.keys.needNotified, id)
  return true
}

// VBW starts waiting for the person (the needs-you line appears): one notification, once
// per need, never on a redraw. A question has its own call, with Claude Code's menu.
async function noteNeed($, st) {
  const need = needNow(st)
  if (!need || need.kind === 'question') return
  if (await firstCall($, st, need)) await call($, st, need.text, null)
}

// Claude Code's question menu just opened: one clip, and one notification naming what VBW
// needs (the need standing besides the question, else just a question) unless that need
// was already notified when it appeared.
async function callForQuestion($, st) {
  const need = liveNeed({ record: st.record, next: st.next, nextAt: st.nextFileAt, health: st.health })
  const text = need ? ((await firstCall($, st, need)) ? need.text : null) : 'VBW has a question for you.'
  await call($, st, text, pick(st))
}

// An approve gate puts /vbw:approve in the prompt's suggestion, once; the person sends it.
async function suggest($, st) {
  const need = liveNeed({ record: st.record, next: st.next, nextAt: st.nextFileAt })
  const key = need && need.kind === 'approve' ? 'approve' : null
  if (key === st.suggested) return
  st.suggested = key
  if (!key) return
  try {
    await $.prompt.suggest({ text: '/vbw:approve' })
  } catch {
    // no prompt box: nothing to suggest into
  }
}

const cheering = (st, now) => (st.cheer && st.cheer.until > now ? st.cheer.text : null)
const recOf = (st) => (isObj(st.record) ? st.record.recommendation : undefined)
const signature = (st, v, now) => JSON.stringify([v, st.sound, recOf(st), unseenNext(st), st.needSeen,  freshLook({ marks: freshMarks(st), key: freshKey(recOf(st)), motion: motion(st), now }), settingsSig(st.settings, now), Object.keys(st.fresh), stage(st, now), st.run, st.auto, st.leases.length, st.tab, st.phase, st.check, st.agent, st.open, st.tab === 'sessions' ? st.registry : null,
  cheering(st, now), !!st.burst, !!st.sweep])

// Remember when each agent first showed; at full motion a new row flashes for a
// second, and one short timer redraws Comms when the flash is over.
async function noteBorn($, st, now) {
  const fresh = (isObj(st.run) && Array.isArray(st.run.agents) ? st.run.agents : []).filter((a) => isObj(a) && typeof a.id === 'string' && a.id && !(a.id in st.born))
  for (const a of fresh) st.born[a.id] = now
  if (fresh.length && motion(st) === 'full') $.clock.after(1050, () => redrawIfChanged($, st).catch(() => {}))
}

// A recommendation with a written time not seen before (kept in the user's store, so
// a restart does not replay it) starts the What's next motion: one redraw per frame
// until it is seen (panel-candy.js fresh), only with full motion.
async function noteRecommendation($, st, now) {
  const rec = recOf(st)
  const at = isObj(rec) && typeof rec.at === 'string' && rec.at ? rec.at : null
  if (!at || at === st.nextSeen) return
  st.nextSeen = at
  st.nextAt = now
  try {
    await $.store.set(st.keys.nextSeen, at)
  } catch {
    // it may move again after a restart
  }
  await call($, st, 'There is a new recommendation for what to build next: ' + String(rec.top && rec.top.text ? rec.top.text : 'see What\'s next') + '.', null)
  if (motion(st) !== 'full' || st.nextAnim) return
  st.nextAnim = $.clock.every(FRAME_MS, async () => {
    try {
      const t = await $.clock.now()
      await redrawIfChanged($, st, false, t)
      if ((!unseenNext(st) || motion(st) !== 'full') && st.nextAnim) {
        st.nextAnim.cancel()
        st.nextAnim = null
      }
    } catch {
      // the next tick draws it
    }
  })
}

// Ask for a redraw when what is shown changed (`force`: in any case). `at`: the moment, when
// the caller has just read the clock for it.
async function redrawIfChanged($, st, force, at) {
  const now = num(at) ? at : await $.clock.now()
  await noteBorn($, st, now)
  const v = view(st, now)
  await suggest($, st)
  const sig = signature(st, v, now)
  if (sig === st.shown && !force) return
  st.shown = sig
  $.ui.invalidate('ui.render') // Claude Code drops a redraw that names nothing
}

async function tick($, st) {
  if (st.busy) return
  st.busy = true
  try {
    await gather($, st)
    const now = await $.clock.now()
    await celebrate($, st, now)
    await noteRecommendation($, st, now)
    await noteNeed($, st)
    for (const k of ['burst', 'sweep']) if (st[k] && !st[k].site && now - st[k].at > AFTER_MS) st[k] = null
    await redrawIfChanged($, st, false, now)
  } catch {
    // keep the last good state
  } finally {
    st.busy = false
  }
}

// Switch the sound: the kernel keeps the choice (`vbw config set sound off|default`), the
// panel reads it back and redraws. Null when it changed, else the kernel's refusal, and the
// sound stays as it was.
async function setSound($, st, on) {
  let refusal = null
  try {
    const r = await $.process.run([$.plugin.root + '/bin/vbw', 'config', 'set', 'sound', on ? 'default' : 'off'], { cwd: st.root })
    if (isObj(r) && r.exitCode === 0) {
      st.soundChoice = on ? 'default' : 'off'
      st.sound = on
      st.soundSig = undefined
      await readSound($, st)
    } else refusal = String((isObj(r) && (r.stderr || r.stdout)) || '').trim().split('\n')[0] || 'vbw config failed'
  } catch {
    refusal = 'VBW could not run vbw config here'
  }
  try {
    await redrawIfChanged($, st)
  } catch {
    // the next tick draws it
  }
  return refusal
}

// A quarter of the terminal, never under 40 columns (R82).
const quarter = (terminal) => Math.max(40, Math.round(terminal / 4))
const cols = (n) => typeof n === 'number' && Number.isFinite(n) && n > 0

// Once a session, on the first drawing as a dock, ask for a quarter of the terminal
// unless the pane already has it. The terminal is the conversation beside the pane
// plus the pane plus 1 (Claude Code 2.1.291). A width the user dragged is kept by
// Claude Code, which ignores this request; it is never asked again nor stored.
async function size($, st, e) {
  if (st.sized || !isObj(e.props) || e.props.placement !== 'dock') return
  const beside = isObj(e.viewport) ? e.viewport.columns : null
  const pane = e.props.bodyColumns
  if (!cols(beside) || !cols(pane)) return
  st.sized = true
  const want = quarter(beside + pane + 1)
  if (pane !== want) await open($, { columns: want })
}

async function open($, extra) {
  try {
    await $.ui.open({ id: PANE, title: 'VBW', ...extra })
  } catch {
    // where Claude Code keeps the pane closed, it stays closed
  }
}

// The person opened it: remembered, so later sessions open it by themselves.
async function openByPerson($, st, extra) {
  try {
    await $.store.set(st.keys.closed, false)
  } catch {
    // the panel still opens
  }
  await open($, extra)
}

// The user has seen these: the recommendation (kept in the user's store, so a restart
// keeps it seen) and the needs-you line (until the gate changes).
async function seen($, st, what) {
  for (const tab of ['timeline', 'settings']) if (what.includes(tab)) st.fresh = freshSee(st.fresh, tab + ':')
  if (what.includes('need')) {
    const n = needNow(st)
    if (n) {
      st.needSeen = needId(n)
      await keep($, st.keys.needSeen, st.needSeen)
    }
  }
  if (what.includes('refusals')) {
    const fresh = runRefusals(st).filter((r) => !st.refusalsSeen[r.id])
    if (fresh.length) {
      for (const r of fresh) st.refusalsSeen[r.id] = true
      await keep($, st.keys.refusalsSeen, Object.keys(st.refusalsSeen).slice(-100))
    }
  }
  const rec = recOf(st)
  if (what.includes('next') && isObj(rec) && typeof rec.at === 'string' && rec.at) {
    st.seenNext = rec.at
    await keep($, st.keys.seen, rec.at)
  }
}

// Keep one seen mark in the user's store; on failure it stays seen for this session.
async function keep($, key, value) {
  try {
    await $.store.set(key, value)
  } catch {
    // it stays seen for this session
  }
}

// A failed helper counts as seen once the user opens it: only while it is failed, so a
// card opened while the helper worked cannot hide its later failure from Comms.
async function seeHelper($, st, id) {
  const rn = st.run
  const a = isObj(rn) && Array.isArray(rn.agents) ? rn.agents.find((x) => isObj(x) && x.id === id) : null
  if (!a || a.state !== 'failed' || st.helpersSeen[id]) return
  st.helpersSeen[id] = true
  await keep($, st.keys.helpersSeen, Object.keys(st.helpersSeen).slice(-100))
}

// What a press asks for (panel-stage.js and the Mission Control views): fill the
// prompt (never send it, decision Q1), open Mission Control on a tab, or choose what
// a tab shows. Anything else is ignored.
async function act($, st, a) {
  try {
    if (!isObj(a)) return
    if (typeof a.fill === 'string') {
      await $.prompt.fill({ text: a.fill })
      if (a.seen === 'next') {
        await seen($, st, ['next'])
        await redrawIfChanged($, st, true)
      }
      return
    }
    if (a.open === 'mission') {
      st.tab = typeof a.tab === 'string' ? a.tab : 'now'
      if (st.tab === 'now') await seen($, st, ['next', 'need', 'refusals'])
      if (st.tab === 'sessions') await readHolder($, st)
      if (st.tab === 'timeline' || st.tab === 'settings') await seen($, st, [st.tab])
      if (st.tab === 'settings') await settings($, st, null)
      if (typeof a.agent === 'string') {
        st.agent = a.agent
        await seeHelper($, st, a.agent) // opened in Mission Control: a failed helper counts as seen
      }
      await openByPerson($, st, { focus: true })
    } else if (typeof a.select === 'string') {
      st.agent = st.agent === a.select ? null : a.select
      await seeHelper($, st, a.select) // pressing a failed helper's card opens it, selecting or not
    }
    else if (a.tab === 'plan' && typeof a.phase === 'string') st.phase = a.phase
    else if (typeof a.check === 'string') st.check = st.check === a.check ? null : a.check
    // Show or hide one thing a press opens in place (a refusal's whole text, a plan's files).
    else if (typeof a.toggle === 'string') st.open = { ...st.open, [a.toggle]: !st.open[a.toggle] }
    else if (isObj(a.setting)) await settings($, st, a.setting)
    else if (typeof a.show === 'string') {
      st.tab = a.show
      if (a.show === 'now') await seen($, st, ['next', 'need', 'refusals'])
      if (a.show === 'sessions') await readHolder($, st) // shown at once, not at the next tick
      if (a.show === 'timeline' || a.show === 'settings') await seen($, st, [a.show])
      if (a.show === 'settings') await settings($, st, null) // read at once, not at the next tick
    }
    else return
    await redrawIfChanged($, st, true)
  } catch {
    // the press does nothing
  }
}

// The Settings tab (panel-settings.js): `choice` ({ key, value }) runs the kernel's own
// command for it, then the tab reads `vbw config` and `vbw statusline status` again; a change
// that took is fresh on the tab, and its ✓ saved flash is redrawn away after about 2 s.
async function settings($, st, choice) {
  const run = async (argv) => {
    try {
      return await $.process.run([$.plugin.root + '/bin/vbw', ...argv], { cwd: st.root })
    } catch {
      return null
    }
  }
  const argv = choice ? settingArgv(choice) : null
  if (choice && !argv) return
  const result = argv ? await run(argv) : null
  const reads = []
  for (const r of READ_ARGV) reads.push(await run(r))
  const now = await $.clock.now()
  st.settings = settingsState({ before: st.settings, choice, result, reads, now })
  if (result && result.exitCode === 0) {
    st.fresh = freshArrive(st.fresh, 'settings:' + choice.key, now)
    if (choice.key === 'sound') await readSound($, st)
    $.clock.after(2100, () => redrawIfChanged($, st).catch(() => {}))
  }
}

// /vbw-todo: the text (or the selection) parked by the kernel's `vbw todo add`.
async function todo($, st, args) {
  let selection = null
  if (!String(args ?? '').trim()) {
    try {
      selection = await $.ui.selection()
    } catch {
      // no selection to take
    }
  }
  const t = todoArgs({ args, selection })
  if (!t.argv) return t.message
  try {
    const r = await $.process.run([$.plugin.root + '/bin/vbw', ...t.argv], { cwd: st.root })
    const out = String((r.exitCode === 0 ? r.stdout : r.stderr || r.stdout) || '').trim()
    return out || (r.exitCode === 0 ? 'Parked.' : 'vbw todo failed (exit ' + r.exitCode + ').')
  } catch {
    return 'VBW could not run vbw todo here.'
  }
}

// What the instant commands read: the gathered state, never a fresh turn.
async function facts($, st) {
  let now = Date.now()
  try {
    now = await $.clock.now()
  } catch {
    // the machine's clock will do
  }
  return { record: st.record, next: st.next, nextAt: st.nextFileAt, health: st.health, now, sessionId: st.sessionId, holder: st.holder }
}

const COMMANDS = [
  ['vbw-panel', 'Open Mission Control'],
  ['vbw-sound', "Turn the 'needs you' sound on or off"],
  ['vbw-status', 'VBW status, at once and free'],
  ['vbw-why', 'Who holds the VBW run, since when, and what blocks it'],
  ['vbw-todo', 'Park an idea for later (vbw todo)'],
]

// Answer a drawing from what a site says (panel-sites.js): null draws the engine's;
// { props } the engine's, rewritten; { tree } that tree; { text, dim } one line in
// the row's place; { line, below } one VBW line above (or below) the engine's own,
// which stays in the tree exactly once.
async function answer($, e, next, out) {
  if (!isObj(out)) return next(e)
  if (out.props) return next({ ...e, props: { ...e.props, ...out.props } })
  if (out.tree) return out.tree
  let ui
  try {
    ui = $.ui.resolve(e)
  } catch {
    return next(e)
  }
  if (out.text) return h(ui.Text, { dimColor: out.dim, wrap: 'truncate-end' }, out.text)
  const line = h(ui.Text, { key: 'vbw-line', dimColor: true, wrap: 'truncate-end' }, out.line)
  const engine = await next(e)
  return h(ui.Box, { flexDirection: 'column' }, ...(out.below ? [engine, line] : [line, engine]))
}

// A site's drawing: nothing of VBW outside a VBW project or on any error.
async function draw($, st, e, next) {
  if (!st.live) return next(e)
  let out = null
  try {
    if (e.component === 'AbovePrompt') out = st.comms ? await comms($, st, e) : null
    else {
      if (e.component === 'TurnDuration' && turnPending(st, e)) await refresh($, st, st.root + '/.vbw/record.json', 'record')
      out = SITES[e.component](st, e, await $.clock.now())
    }
  } catch {
    out = null
  }
  return answer($, e, next, out)
}

// Comms (panel-stage.js): the crew while a run works, the needs-you line when VBW
// needs the person; yields to a survey.
// Above it, a celebration: the all-green line and the confetti burst. The sprites
// and the confetti drawn here are what the frame loop blits.
async function comms($, st, e) {
  const p = isObj(e.props) ? e.props : {}
  st.sprites = null
  if (p.hasSurvey) return null
  const now = await $.clock.now()
  const ui = $.ui.resolve(e)
  // A celebration takes its rows from the room Claude Code gives (maxRows): the line
  // needs 3 rows, the confetti 4 more, and the crew or the needs-you line keeps the rest.
  const room = Number.isInteger(p.maxRows) && p.maxRows > 0 ? p.maxRows : 8
  const cheer = room >= 3 ? cheering(st, now) : null
  const fx = room - (cheer ? 1 : 0) >= 7 ? st.burst : null
  const spare = room - (cheer ? 1 : 0) - (fx ? CONFETTI_ROWS : 0)
  const m = stage(st, now, { ...p, maxRows: spare })
  const tree = m ? renderStage(ui, m, (a) => act($, st, a)) : null
  st.commsId = e.requestId
  if (tree && m.sprites && ui.Raster) st.sprites = m.rows.map((r) => ({ key: 'vbw-sprite-' + r.id, role: r.role, pose: r.pose }))
  const top = []
  if (cheer) top.push(h(ui.Text, { key: 'vbw-cheer', color: stateColor('done'), wrap: 'truncate-end' }, cheer))
  const cells = fx && ui.Raster ? drawn(fx, cols(p.bodyColumns) ? p.bodyColumns : 80, e.requestId) : null
  if (cells) top.push(h(ui.Raster, { key: fx.key, columns: fx.cols, rows: fx.rows, cells }))
  if (st.sprites || cells) animate($, st)
  if (!top.length) return tree ? { tree } : null
  return { tree: h(ui.Box, { flexDirection: 'column' }, ...top, ...(tree ? [tree] : [])) }
}

// Start the panel once the session's folder is a VBW project: at session start,
// and again on a prompt, a question or a workflow while it is not (a first
// session's /vbw:vibe sets the project up mid-session). No timer before that.
async function begin($, st) {
  if (st.live || st.unsupported === true) return
  try {
    await start($, st)
  } catch (err) {
    // A failure while starting (a store not ready yet) leaves nothing half-started: no
    // timer, not live, so the next prompt, question or workflow starts it again.
    st.live = false
    if (st.timer && st.timer.cancel) st.timer.cancel()
    st.timer = null
    throw err
  }
}
async function start($, st) {
  if (st.unsupported !== false) {
    const ver = await $.session.version()
    const v = isObj(ver) ? ver.version : ver
    st.unsupported = !supports(v)
    if (st.unsupported) return
    st.comms = supports(v, COMMS_MIN_VERSION)
  }
  const dir = await $.session.root()
  if (typeof dir !== 'string') return
  const root = await projectOf($, dir)
  if (!(await $.fs.exists(root + '/.vbw/record.json'))) return
  st.live = true
  st.root = root
  st.silent = await $.fs.exists(root + TEST_MARK)
  st.keys = keys(st.silent ? root : null)
  st.stepsPath = await stepsPath($, root)
  st.settingsPath = st.stepsPath ? st.stepsPath.replace(/steps\.json$/, 'settings.json') : null
  try {
    st.sessionId = await $.session.id()
  } catch {
    st.sessionId = null
  }
  // The config folder holds this session's folder and the list of chats: found once.
  st.configDir = await configDir($)
  // Claude Code names the session's folder after the folder the session started in.
  st.sessionDir = sessionDir(st.configDir, dir, st.sessionId)
  await gather($, st)
  st.lastRec = st.record
  const stored = await $.store.get(st.keys.nextSeen)
  st.nextSeen = typeof stored === 'string' ? stored : null
  const kept = await $.store.get(st.keys.seen)
  st.seenNext = typeof kept === 'string' ? kept : null
  const needKept = await $.store.get(st.keys.needSeen)
  st.needSeen = typeof needKept === 'string' ? needKept : null
  const helpersKept = await $.store.get(st.keys.helpersSeen)
  if (Array.isArray(helpersKept)) for (const id of helpersKept) if (typeof id === 'string') st.helpersSeen[id] = true
  const refusalsKept = await $.store.get(st.keys.refusalsSeen)
  if (Array.isArray(refusalsKept)) for (const id of refusalsKept) if (typeof id === 'string') st.refusalsSeen[id] = true
  const notified = await $.store.get(st.keys.needNotified)
  st.needNotified = typeof notified === 'string' ? notified : null
  const now = await $.clock.now()
  await noteRecommendation($, st, now)
  await noteNeed($, st)
  const v0 = view(st, now)
  await suggest($, st)
  st.shown = signature(st, v0, now)
  if (st.timer && st.timer.cancel) st.timer.cancel()
  st.timer = $.clock.every(TICK_MS, () => tick($, st))
  if (!st.registered) for (const [name, description] of COMMANDS) $.command.register({ name, description, immediate: true })
  st.registered = true
  if ((await $.store.get(st.keys.closed)) !== true) await open($)
}
async function wake($, st) {
  try {
    await begin($, st)
  } catch {
    // the panel stays out of the way
  }
}

// A gating hook that fails is skipped by Claude Code and its `.catch` is asked. Ours let the
// event go on as if the panel were not there, which is also what Claude Code does without one;
// a command that fails says so in plain words instead of "unknown command". Claude Code names
// the failed hook itself, so nothing is logged here. None of them throws.
const passOn = ($, e, next) => next(e)
const failedText = (name) => '/' + name + ' did not work just now. The rest of VBW is not affected.'

export function register(on) {
  const st = fresh()

  on('session.start', async ($, e, next) => {
    const out = await next(e)
    await wake($, st)
    return out
  })

  on('command.run', { command: 'vbw-panel' }, async ($, e, next) => {
    if (!st.live) return next(e)
    const w = isObj(e) && isObj(e.presentation) ? e.presentation.columns : null
    await openByPerson($, st, cols(w) ? { columns: quarter(w), focus: true } : { focus: true })
    return { text: 'Mission Control is open.' }
  }).catch(() => ({ text: failedText('vbw-panel') }))

  on('command.run', { command: 'vbw-sound' }, async ($, e, next) => {
    if (!st.live) return next(e)
    const word = String(e.args ?? '').trim().toLowerCase()
    const refused = word === '' || word === 'on' || word === 'off' ? await setSound($, st, word === '' ? !st.sound : word === 'on') : null
    return { text: (refused ? 'VBW could not change the sound: ' + refused + '. ' : '') + "The 'needs you' sound is " + (st.sound ? 'on' : 'off') + '.' }
  }).catch(() => ({ text: failedText('vbw-sound') }))

  on('command.run', { command: 'vbw-status' }, async ($, e, next) => {
    if (!st.live) return next(e)
    return { text: statusText(await facts($, st)) }
  }).catch(() => ({ text: failedText('vbw-status') }))

  on('command.run', { command: 'vbw-why' }, async ($, e, next) => {
    if (!st.live) return next(e)
    return { text: whyText(await facts($, st)) }
  }).catch(() => ({ text: failedText('vbw-why') }))

  on('command.run', { command: 'vbw-todo' }, async ($, e, next) => {
    if (!st.live) return next(e)
    return { text: await todo($, st, e.args) }
  }).catch(() => ({ text: failedText('vbw-todo') }))

  // Remember a close made by the user only; every close is passed on.
  on('ui.close', async ($, e, next) => {
    if (st.live && isObj(e) && e.id === PANE && isObj(e.origin) && e.origin.kind === 'person') {
      try {
        await $.store.set(st.keys.closed, true)
      } catch {
        // the close still goes through
      }
    }
    return next(e)
  }).catch(passOn)

  // A question to the user is a need while it is open.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (!st.live) await wake($, st)
    if (!st.live) return next(e)
    st.question = { id: String(Date.now()) + Math.random() }
    st.questionAt = await $.clock.now()
    try {
      await callForQuestion($, st)
      await redrawIfChanged($, st)
    } catch {
      // the next tick draws it
    }
    try {
      return await next(e)
    } finally {
      st.question = null
      st.questionAt = null
      try {
        await redrawIfChanged($, st)
      } catch {
        // nothing to redraw
      }
    }
  }).catch(async ($, e, next) => {
    // The question went on without the panel noticing its end: it is no longer open as far as the panel knows.
    st.question = null
    st.questionAt = null
    try {
      await redrawIfChanged($, st)
    } catch {
      // the next tick draws it
    }
    return next(e)
  })

  // A VBW workflow launched by this session (main loop): its run id and folder
  // come back in the launch's result; the timer reads the run from there.
  on('tool.call', { tool: 'Workflow' }, async ($, e, next) => {
    if (!st.live) await wake($, st)
    const out = await next(e)
    try {
      const r = isObj(out) && isObj(out.result) ? out.result : null
      const kind = kindOf(e.name)
      if (!st.live || e.agentId || !r || !kind || typeof r.runId !== 'string' || !/^wf_[A-Za-z0-9_-]+$/.test(r.runId)) return out
      const m = typeof r.transcriptDir === 'string' ? /^(\/.+)\/subagents\/workflows\/[^/]+\/?$/.exec(r.transcriptDir) : null
      if (m) st.sessionDir = m[1]
      st.runRef = { runId: r.runId, kind }
      st.run = null
      if (typeof e.tool_use_id === 'string') st.toolRuns[e.tool_use_id] = r.runId
    } catch {
      // the run is found by its lease instead
    }
    return out
  }).catch(passOn)

  // The record as a turn found it: the turn receipt says what moved.
  on('prompt.submit', async ($, e, next) => {
    if (!st.live) await wake($, st)
    if (st.live) st.before = st.record
    return next(e)
  }).catch(passOn)

  // Mission Control: drawn as Claude Code's own pane example does, from $.ui.resolve(e)
  // and h(). Only this pane's drawings reach here.
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (!st.live) return next(e)
    try {
      await size($, st, e)
    } catch {
      // the width stays as Claude Code placed it
    }
    try {
      const now = await $.clock.now()
      const v = view(st, now)
      const width = isObj(e.props) && cols(e.props.bodyColumns) ? e.props.bodyColumns : 50
      const ui = $.ui.resolve(e)
      const cells = st.sweep && st.tab === 'proof' && ui.Raster ? drawn(st.sweep, width, PANE) : null
      if (cells) animate($, st)
      const sweep = cells ? { cols: st.sweep.cols, cells } : null
      return renderPane(ui, { st, v, now, width, sweep, registry: st.registry, stored: st.stored, holder: st.holder, recommendation: recOf(st), fresh: freshMarks(st), motion: motion(st), wrapped: st.wrapped, scroll: isObj(e.props) ? e.props.scroll : null, portrait: $.plugin.root + '/assets/portrait.png' }, {
        act: (a) => act($, st, a),
        sound: () => setSound($, st, !st.sound),
      })
    } catch (err) {
      // Never an empty pane with nothing said (T160): one dim line with the reason.
      try {
        const { Text } = $.ui.resolve(e)
        const reason = String(err && err.message ? err.message : err).split('\n')[0].replace(/\s+/g, ' ').trim().slice(0, 120)
        return h(Text, { key: 'could-not-draw', dimColor: true, wrap: 'truncate' }, 'Mission Control could not draw: ' + (reason || 'unknown reason'))
      } catch {
        return next(e)
      }
    }
  })

  // Every other place VBW draws, each hook matched to its site (render from memory).
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'Spinner' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'InfoNotice' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'TurnDuration' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'Workflow' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'Bash' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'Edit' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'MultiEdit' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'Write' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'task-notification' } } }, async ($, e, next) => draw($, st, e, next))
}
