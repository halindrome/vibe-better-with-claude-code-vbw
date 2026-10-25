// What a drawing of the panel puts on the terminal, as lines of text: a model of
// how Ink lays out the trees VBW builds with h() (evidence level L1: a model, not
// Claude Code's own renderer). A Box sets its children side by side (Ink's
// default row; wrapping onto more lines with flexWrap 'wrap') or stacks them
// (flexDirection 'column'); margins, padding and a border take their rows and
// columns; a Box with a height shows exactly that many rows (a negative
// marginTop scrolls its content up). A Text is one line per line of its text
// when it truncates (cut to the width), else it wraps at the width it is given.
// A Button is its label in 4 cells of chrome ("[ label ]" with no hotkey, as
// Claude Code 2.1.302 draws a tab button; "[k] label" with a hotkey, the same 4
// cells of width), then its children on the same row; a plain Button is its children
// alone, drawn in the label's place, or with none its label without chrome. A Raster or an Image takes its rows and columns. Claude Code's own
// drawing (the stand-in's 'engine') is none of VBW's, so it takes no line.

const width = (s) => [...s].length
const pad = (s, n) => s + ' '.repeat(Math.max(0, n - width(s)))
const clip = (s, n) => (Number.isFinite(n) && width(s) > n ? [...s].slice(0, Math.max(0, n)).join('') : s)
const int = (x) => (Number.isInteger(x) ? x : 0)

// The words of a Text, nested Texts included.
export function textOf(node) {
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (!node || typeof node !== 'object') return ''
  return (node.children || []).map(textOf).join('')
}

function text(node, cols) {
  const truncate = /^truncate/.test(String((node.props || {}).wrap || ''))
  const out = []
  for (const raw of textOf(node).split('\n')) {
    if (!Number.isFinite(cols) || truncate || width(raw) <= cols) out.push(clip(raw, cols))
    else for (let i = 0; i < width(raw); i += Math.max(1, cols)) out.push([...raw].slice(i, i + Math.max(1, cols)).join(''))
  }
  return out
}

// Blocks of lines set side by side, each as wide as its widest line.
function zip(blocks, gap) {
  const rows = Math.max(0, ...blocks.map((b) => b.length))
  const widths = blocks.map((b) => Math.max(0, ...b.map(width)))
  const out = []
  for (let i = 0; i < rows; i++) out.push(blocks.map((b, j) => pad(b[i] || '', widths[j])).join(' '.repeat(gap)))
  return out
}

// A child Ink lets shrink by wrapping: a Box with flexWrap 'wrap', or a Text that wraps.
const flexible = (c) => Boolean(c) && typeof c === 'object' &&
  ((c.type === 'Box' && (c.props || {}).flexWrap === 'wrap') || (c.type === 'Text' && !/^truncate/.test(String((c.props || {}).wrap || ''))))

function row(children, cols, p) {
  const gap = int(p.columnGap ?? p.gap)
  const kids = children.filter((c) => draw(c, Infinity).length)
  let blocks = kids.map((c) => draw(c, Infinity))
  if (p.flexWrap !== 'wrap' || !Number.isFinite(cols)) {
    // Too wide for the row: the children that can wrap share what the others leave.
    const wide = (b) => Math.max(0, ...b.map(width))
    const gaps = gap * Math.max(0, blocks.length - 1)
    const flex = kids.map(flexible)
    if (Number.isFinite(cols) && blocks.reduce((n, b) => n + wide(b), 0) + gaps > cols && flex.some(Boolean)) {
      const fixed = blocks.reduce((n, b, i) => n + (flex[i] ? 0 : wide(b)), 0) + gaps
      const share = Math.max(1, Math.floor((cols - fixed) / flex.filter(Boolean).length))
      blocks = kids.map((c, i) => (flex[i] ? draw(c, share) : blocks[i]))
    }
    return zip(blocks, gap).map((l) => clip(l, cols))
  }
  const out = []
  let group = []
  let used = 0
  for (const b of blocks) {
    const w = Math.max(0, ...b.map(width))
    if (group.length && used + gap + w > cols) {
      out.push(...zip(group, gap))
      group = []
      used = 0
    }
    used += (group.length ? gap : 0) + w
    group.push(b)
  }
  if (group.length) out.push(...zip(group, gap))
  return out.map((l) => clip(l, cols))
}

function column(children, cols, p) {
  const gap = int(p.rowGap ?? p.gap)
  const out = []
  children.forEach((c, i) => {
    if (i && gap) out.push(...Array(gap).fill(''))
    out.push(...draw(c, cols))
  })
  return out
}

function box(node, cols) {
  const p = node.props || {}
  const kids = node.children || []
  const border = p.borderStyle ? 1 : 0
  const px = int(p.paddingX ?? p.padding)
  const py = int(p.paddingY ?? p.padding)
  const inner = Number.isFinite(cols) ? Math.max(1, cols - 2 * border - 2 * px) : Infinity
  let body = p.flexDirection === 'column' || p.flexDirection === 'column-reverse' ? column(kids, inner, p) : row(kids, inner, p)
  body = [...Array(py).fill(''), ...body.map((l) => ' '.repeat(px) + l), ...Array(py).fill('')]
  if (border) {
    const w = Number.isFinite(cols) ? Math.max(0, cols - 2) : Math.max(0, ...body.map(width)) + px
    const fill = Number.isFinite(cols) ? w : Math.max(w, ...body.map(width))
    body = ['╭' + '─'.repeat(fill) + '╮', ...body.map((l) => '│' + pad(l, fill) + '│'), '╰' + '─'.repeat(fill) + '╯']
  }
  if (Number.isInteger(p.height) && p.height >= 0) body = [...body.slice(0, p.height), ...Array(Math.max(0, p.height - body.length)).fill('')]
  return body
}

// A node as the lines it takes, its own margins included.
function draw(node, cols) {
  if (typeof node === 'string' || typeof node === 'number') return text({ props: {}, children: [String(node)] }, cols)
  if (!node || typeof node !== 'object') return []
  if (Array.isArray(node)) return node.flatMap((n) => draw(n, cols))
  const p = node.props || {}
  if (p.display === 'none') return []
  let out
  switch (node.type) {
    case 'engine': return []
    case 'Text': out = text(node, cols); break
    case 'Raster': out = Array.from({ length: int(p.rows) }, () => '▒'.repeat(int(p.columns))); break
    case 'Image': out = Array.from({ length: int(p.rows) }, () => '▓'.repeat(int(p.columns))); break
    case 'Button': {
      const kids = (node.children || []).filter((c) => c !== null && c !== undefined && c !== false)
      const chrome = (l) => (p.plain ? (p.hotkey ? p.hotkey + ': ' + l : l) : p.hotkey ? '[' + p.hotkey + '] ' + l : '[ ' + l + ' ]')
      const label = p.label === undefined || p.label === null || (p.plain && kids.length) ? [] : [{ type: 'Text', props: {}, children: [chrome(String(p.label))] }]
      out = row([...label, ...(node.children || [])], cols, { columnGap: 1 })
      break
    }
    default: out = box(node, cols)
  }
  const top = int(p.marginTop ?? p.marginY ?? p.margin)
  const bottom = int(p.marginBottom ?? p.marginY ?? p.margin)
  if (top < 0) out = out.slice(-top)
  else if (top > 0) out = [...Array(top).fill(''), ...out]
  if (bottom > 0) out = [...out, ...Array(bottom).fill('')]
  return out
}

// screen(tree, columns): the lines the tree takes in that many columns (Infinity:
// as wide as it wants). widest(lines): the widest line, in terminal cells.
export const screen = (tree, columns = Infinity) => draw(tree, columns).map((l) => l.replace(/\s+$/, ''))
export const widest = (lines) => Math.max(0, ...lines.map(width))

// The local time of a moment as HH:MM, as the panel shows it.
export function hhmm(ms) {
  const d = new Date(ms)
  return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
}
