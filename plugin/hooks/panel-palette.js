// D407: a role never wears a state colour (no green, red, amber or grey hue).
// The one palette of the VBW panel (R84): every part of the panel (Comms,
// Mission Control, Wrapped) takes its colours from here, so a role has one
// colour everywhere and a state has one colour everywhere. Colours are Ink
// names or #rrggbb strings; rgb() turns one into the number a Raster cell
// takes. Pure: values in, values out, never throws.

// Seven hues spread over the blue-to-pink arc (teal 176 to pink 329 degrees),
// all at a mid lightness so they read on dark and light terminals; teal is the
// brand kit's Proof Teal lifted, indigo the Contract Indigo lifted.
export const ROLE_COLORS = {
  architect: '#e060e0', lead: '#5f7bff', dev: '#1fbfb0', qa: '#ff6fb5',
  scout: '#3ab0ff', debugger: '#8a6bff', docs: '#c27aff',
}
export const STATE_COLORS = {
  running: '#ffaf00', done: 'green', failed: 'red', quiet: 'gray', cut: 'gray',
}
export const NEUTRAL = 'gray'
export const ACCENT = '#af87ff'
export const NEED = STATE_COLORS.running
export const PROGRESS = 'green'
export const ESTIMATE = '#ffaf00'

// A mark and a word per state, so the state reads with colour switched off.
export const STATE_MARKS = { running: '●', done: '✓', failed: '✗', quiet: '…', cut: '■' }
export const STATE_WORDS = { running: 'running', done: 'done', failed: 'failed', quiet: 'quiet', cut: 'cut off' }

const own = (o, k) => typeof k === 'string' && Object.prototype.hasOwnProperty.call(o, k)
export const roleColor = (role) => (own(ROLE_COLORS, role) ? ROLE_COLORS[role] : NEUTRAL)
export const stateColor = (state) => (own(STATE_COLORS, state) ? STATE_COLORS[state] : NEUTRAL)

// The pixel value of each Ink colour name the palette uses.
const NAMED = {
  magenta: 0xd75fd7, blue: 0x5f87ff, green: 0x5fd75f, yellow: 0xffd75f,
  cyan: 0x5fd7ff, red: 0xff5f5f, gray: 0x808080,
}
export function rgb(color) {
  if (typeof color === 'string' && /^#[0-9a-fA-F]{6}$/.test(color)) return parseInt(color.slice(1), 16)
  return own(NAMED, color) ? NAMED[color] : NAMED[NEUTRAL]
}
