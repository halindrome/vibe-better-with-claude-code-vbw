// Mission Control's Settings tab: every setting `vbw config set` accepts (and rigor,
// the sound and the status line), each as one row `name  value  [controls]`, changed by
// a press. The kernel is the only reader and writer: the values are `vbw config`'s own
// lines and `vbw statusline status`'s, a press runs `vbw config set KEY VALUE` (or
// `vbw config rigor MODE`, `vbw statusline on|off`), and the tab is read again after
// it. A change flashes `✓ saved` for about 2 s; a refusal shows the kernel's own words
// in amber under its row and the value stays. panel.js runs the commands through `$`;
// everything here is pure: values in, values or trees out, never throws.

import { SOUNDS } from './panel-sounds.js'
import { ACCENT, NEED, roleColor, stateColor, STATE_MARKS } from './panel-palette.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const str = (x) => (typeof x === 'string' && x !== '' ? x : null)

export const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
// The sound folders shipped under assets/audio/ (panel-sounds.js lists their files).
export const SOUND_FOLDERS = [...new Set(SOUNDS.map((p) => p.split('/')[2]).filter(Boolean))]
export const SAVED_MS = 2000

// The rows, in the order drawn. `choices`: the values a press can set; `number`: the
// step of its − and + and its bounds (the kernel's); `scope`: who shares the value.
const MODELS = ['opus', 'sonnet', 'haiku', 'default']
export const ROWS = [
  { key: 'profile', choices: ['quality', 'balanced', 'budget'] },
  ...ROLES.map((r) => ({ key: 'model.' + r, choices: r === 'qa' ? MODELS.filter((m) => m !== 'haiku') : MODELS, role: r })),
  { key: 'autonomy', choices: ['guided', 'balanced', 'hands-off'] },
  { key: 'autonomy_cap', number: { min: 1, max: 9999, step: 5, unset: 25 } },
  { key: 'rigor', choices: ['auto', 'express', 'standard', 'deep'] },
  { key: 'motion', choices: ['full', 'calm', 'off', 'default'] },
  { key: 'check_jobs', number: { min: 1, max: 64, step: 1 }, scope: 'this clone' },
  { key: 'command_timeout', number: { min: 1, max: 86400, step: 60, unset: 3600 }, unit: 's' },
  { key: 'check_budget', number: { min: 1, max: 86400, step: 10, unset: 120 }, unit: 's' },
  { key: 'sound', choices: ['off', ...SOUND_FOLDERS, 'default'], scope: 'this computer' },
  { key: 'statusline', choices: ['on', 'off'], scope: 'this computer' },
]
const rowOf = (key) => ROWS.find((r) => r.key === key) || null

// What panel.js runs to read the tab: `vbw config`, then `vbw statusline status`.
export const READ_ARGV = [['config'], ['statusline', 'status']]

// The argv (after the vbw path) a press asks for, or null when the key or value is not one a
// row offers: nothing is run that the tab does not draw.
export function settingArgv(choice) {
  try {
    if (!isObj(choice) || typeof choice.key !== 'string') return null
    const row = rowOf(choice.key)
    const v = typeof choice.value === 'number' ? String(choice.value) : choice.value
    if (!row || typeof v !== 'string') return null
    if (row.choices && !row.choices.includes(v)) return null
    if (row.number && !(v === 'default' || (/^\d+$/.test(v) && Number(v) >= row.number.min && Number(v) <= row.number.max))) return null
    if (row.key === 'rigor') return ['config', 'rigor', v]
    if (row.key === 'statusline') return ['statusline', v]
    return ['config', 'set', row.key, v]
  } catch {
    return null
  }
}

// `vbw config`'s lines as { key: { value, note } }: 'profile: balanced',
// 'check_jobs: 6 (default: ...)', 'command_timeout: 3600 seconds', 'model.dev: sonnet',
// and the machine limit line as the note of check_jobs.
export function parseConfig(text) {
  const out = {}
  for (const line of String(typeof text === 'string' ? text : '').split('\n')) {
    const m = /^([a-z_.]+): (.*)$/.exec(line.trim())
    if (!m) continue
    if (m[1] === 'machine limit') continue
    const [, key, rest] = m
    const num = /^(\d+)\b\s*(.*)$/.exec(rest)
    out[key] = num ? { value: num[1], note: num[2].replace(/^\((.*)\)$/, '$1') } : { value: rest.trim(), note: '' }
  }
  const limit = /^machine limit: (\d+)\b/m.exec(String(text || ''))
  if (limit && out.check_jobs) out.check_jobs.limit = 'machine limit ' + limit[1]
  return out
}

// `vbw statusline status`'s first line: on, off, or another status line.
function parseStatusline(text) {
  const line = String(typeof text === 'string' ? text : '').split('\n')[0].trim()
  const m = /^(on|off):\s*(.*)$/.exec(line)
  if (m) return { value: m[1], note: m[2] }
  return line ? { value: 'other', note: line } : null
}

const firstLine = (r) => {
  const t = isObj(r) ? String(r.stderr || r.stdout || '').trim() : ''
  return t.split('\n').map((l) => l.trim()).filter(Boolean)[0] || 'VBW refused the change (exit ' + (isObj(r) ? r.exitCode : '?') + ').'
}

// The tab's state after a read (and a press): before, the earlier state or null; choice, the
// pressed { key, value } or null; result, what running settingArgv(choice) gave ({ exitCode,
// stdout, stderr }, null when it could not run); reads, the results of READ_ARGV in order.
export function settingsState(input) {
  try {
    const { before, choice, result, reads, now } = isObj(input) ? input : {}
    const prev = isObj(before) ? before : {}
    const [cfg, line] = Array.isArray(reads) ? reads : []
    const ok = (r) => isObj(r) && r.exitCode === 0
    const values = ok(cfg) ? parseConfig(cfg.stdout) : isObj(prev.values) ? prev.values : null
    const status = ok(line) || (isObj(line) && str(line.stdout)) ? parseStatusline(line.stdout) : prev.statusline || null
    const state = {
      values, statusline: status, at: Number.isFinite(now) ? now : null,
      error: ok(cfg) ? null : values ? prev.error || null : 'VBW could not read the settings here' + (isObj(cfg) ? ': ' + firstLine(cfg) : '.'),
      saved: null, refused: null,
    }
    if (isObj(choice) && typeof choice.key === 'string') {
      if (ok(result)) state.saved = { key: choice.key, at: state.at }
      else state.refused = { key: choice.key, text: isObj(result) ? firstLine(result) : 'VBW could not run the change here.' }
    } else {
      // A read with no press keeps a refusal on screen until the next press; the flash runs out by itself.
      state.refused = isObj(prev.refused) ? prev.refused : null
      state.saved = isObj(prev.saved) ? prev.saved : null
    }
    return state
  } catch {
    return { values: null, statusline: null, at: null, error: 'VBW could not read the settings here.', saved: null, refused: null }
  }
}

const flashing = (s, now) => isObj(s) && isObj(s.saved) && Number.isFinite(s.saved.at) && Number.isFinite(now) && now - s.saved.at < SAVED_MS
// What the redraw check compares: the state and whether the flash still shows.
export const settingsSig = (s, now) => [isObj(s) ? s.values : null, isObj(s) ? s.statusline : null, isObj(s) ? s.refused : null, isObj(s) ? s.error : null, flashing(s, now) ? s.saved.key : null]

// settingsModel({ settings, record, now }) -> { rows: [{ key, value, note, mine, choices|number,
// saved, refused }], error, reading }. `record` only says which models the user set (record.settings.models,
// read-only); every value is the kernel's.
export function settingsModel(input) {
  try {
    const { settings, record, now } = isObj(input) ? input : {}
    const s = isObj(settings) ? settings : null
    if (!s || !isObj(s.values)) return { rows: [], error: s && s.error ? s.error : null, reading: !s || !s.error }
    const mine = isObj(record) && isObj(record.settings) && isObj(record.settings.models) ? record.settings.models : {}
    const rows = []
    for (const r of ROWS) {
      const got = r.key === 'statusline' ? s.statusline : s.values[r.key]
      if (!isObj(got)) continue // a setting this kernel does not report has no row
      const value = String(got.value)
      const n = r.number && /^\d+$/.test(value) ? Number(value) : r.number && r.number.unset ? r.number.unset : null
      rows.push({
        key: r.key, value: value === 'null' && r.number ? 'not set' : value,
        note: [r.key === 'check_jobs' ? got.limit : null, r.scope ? r.scope : null].filter(Boolean).join(' · '),
        mine: Boolean(r.role && str(mine[r.role])), role: r.role || null,
        ...(r.choices ? { choices: r.choices } : {}),
        ...(r.number ? { number: { ...r.number, at: n } } : {}),
        unit: r.unit || '',
        saved: flashing(s, now) && s.saved.key === r.key,
        refused: isObj(s.refused) && s.refused.key === r.key ? s.refused.text : null,
      })
    }
    return { rows, error: s.error || null, reading: false }
  } catch {
    return { rows: [], error: 'VBW could not read the settings here.', reading: false }
  }
}

// One row: the name, the value (the current choice in the accent), its note dim, then its
// controls (a Select where the surface draws one, else a Button per choice; − and + and
// default for a number), the ✓ saved flash, and under it the kernel's refusal in amber.
export function renderSettings(ui, model, act) {
  const { Box, Text, Button, Select } = isObj(ui) ? ui : {}
  const m = isObj(model) ? model : { rows: [] }
  const press = (key, value) => () => { if (typeof act === 'function') act({ setting: { key, value: String(value) } }) }
  if (!Array.isArray(m.rows) || !m.rows.length) {
    return h(Box, { key: 'settings', flexDirection: 'column' },
      m.error ? h(Text, { key: 'settings-error', color: NEED }, m.error) : h(Text, { key: 'settings-reading', dimColor: true }, 'Reading the settings…'))
  }
  const nameW = Math.max(...m.rows.map((r) => r.key.length)) + 2
  const done = stateColor('done')
  const kids = m.rows.map((r) => {
    let controls
    if (r.choices && Select) {
      controls = [h(Select, { key: 'select-' + r.key, options: r.choices.map((c) => ({ value: c, label: c })), value: r.choices.includes(r.value) ? r.value : undefined, onSelect: (v) => press(r.key, v)() })]
    } else if (r.choices) {
      controls = r.choices.map((c) => h(Button, { key: 'set-' + r.key + '-' + c, label: c, ...(c === r.value ? { variant: 'primary' } : { dimColor: true }), onPress: press(r.key, c) }))
    } else {
      const n = r.number
      const at = Number.isFinite(n.at) ? n.at : n.min
      controls = [
        h(Button, { key: 'set-' + r.key + '-down', label: '−', onPress: press(r.key, Math.max(n.min, at - n.step)) }),
        h(Button, { key: 'set-' + r.key + '-up', label: '+', onPress: press(r.key, Math.min(n.max, at + n.step)) }),
        ...(r.key === 'autonomy_cap' ? [] : [h(Button, { key: 'set-' + r.key + '-default', label: 'default', dimColor: true, onPress: press(r.key, 'default') })]),
      ]
    }
    const value = r.value + (r.number && r.unit && /^\d+$/.test(r.value) ? ' ' + r.unit : '')
    return h(Box, { key: 'setting:' + r.key, flexDirection: 'column' },
      h(Box, { key: 'line', flexDirection: 'row', flexWrap: 'wrap', columnGap: 1 },
        h(Text, { key: 'name', ...(r.role ? { color: roleColor(r.role) } : {}) }, r.key.padEnd(nameW - 1)),
        h(Text, { key: 'value', bold: true, color: ACCENT }, value),
        r.mine ? h(Text, { key: 'mine', dimColor: true }, '(set by you)') : null,
        r.note ? h(Text, { key: 'note', dimColor: true }, r.note) : null,
        r.saved ? h(Text, { key: 'saved', color: done }, STATE_MARKS.done + ' saved') : null),
      h(Box, { key: 'controls', flexDirection: 'row', flexWrap: 'wrap', columnGap: 1, marginLeft: 2 }, ...controls),
      r.refused ? h(Text, { key: 'refused', color: NEED }, r.refused) : null)
  })
  if (m.error) kids.push(h(Text, { key: 'settings-error', color: NEED }, m.error))
  return h(Box, { key: 'settings', flexDirection: 'column' }, ...kids)
}
