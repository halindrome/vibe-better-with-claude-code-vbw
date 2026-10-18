// The panel's one helper for chats (R192): Claude Code's list of chats
// (<claude-config-dir>/sessions/*.json, read-only), and who holds the run in
// words. Names are untrusted text: escape sequences and control characters go,
// long names are cut with an ellipsis. Pure over its input except readRegistry,
// which reads through `$` and never throws.

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const NAME_MAX = 40

// A text with its CSI and OSC escape sequences and every control character removed.
export function cleanName(s) {
  if (typeof s !== 'string') return ''
  return s
    .replace(/\u001b\][^\u0007\u001b]*(?:\u0007|\u001b\\)?/g, '')
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, '')
    .trim()
}

// At most n characters: a longer text becomes its first n-1 and an ellipsis.
export function cutName(s, n) {
  const c = [...String(s)]
  return c.length > n ? c.slice(0, n - 1).join('') + '…' : String(s)
}

// The file texts that parse to an object with a string sessionId, newest updatedAt first.
export function registryEntries(texts) {
  if (!Array.isArray(texts)) return []
  const out = []
  for (const t of texts) {
    try {
      const v = JSON.parse(t)
      if (isObj(v) && typeof v.sessionId === 'string' && v.sessionId) out.push(v)
    } catch {
      // a malformed file is skipped
    }
  }
  const at = (e) => (Number.isFinite(e.updatedAt) ? e.updatedAt : -Infinity)
  return out.map((e, i) => ({ e, i })).sort((a, b) => (at(b.e) - at(a.e) || a.i - b.i)).map((x) => x.e)
}

// Claude Code's config folder, as tools/resolve-claude-dir.sh finds it; null when unknown.
export async function configDir($) {
  try {
    let dir = await $.env.get('CLAUDE_CONFIG_DIR')
    if (!dir) {
      const home = await $.env.get('HOME')
      if (!home) return null
      dir = (await $.fs.exists(home + '/.config/claude-code')) ? home + '/.config/claude-code' : home + '/.claude'
    }
    return dir.replace(/\/+$/, '')
  } catch {
    return null
  }
}

// The list of chats, newest first; [] when missing or unreadable.
export async function readRegistry($, root) {
  try {
    const dir = await configDir($)
    if (!dir) return []
    const names = Object.values(await $.fs.list(dir + '/sessions'))
      .map((e) => (isObj(e) ? e.name : e)).filter((n) => typeof n === 'string' && /\.json$/.test(n))
    const texts = []
    for (const n of names) {
      try {
        texts.push(await $.fs.read(dir + '/sessions/' + n))
      } catch {
        // an unreadable file is skipped
      }
    }
    return registryEntries(texts)
  } catch {
    return []
  }
}

// The holder of the run: null without a session in the lease; else its display name
// (the list's current name, else the stored one, else 8 characters of the id), whether
// this chat holds it and whether a name is known.
export function holderName({ lease, registry, stored, sessionId } = {}) {
  if (!isObj(lease) || typeof lease.session !== 'string' || !lease.session) return null
  const self = sessionId === lease.session
  const listed = (Array.isArray(registry) ? registry : []).find((e) => isObj(e) && e.sessionId === lease.session)
  const fromList = listed ? cleanName(listed.name) : ''
  const fromStore = isObj(stored) && stored.session === lease.session ? cleanName(stored.session_name) : ''
  const name = fromList || fromStore
  return { name: cutName(name || lease.session.slice(0, 8), NAME_MAX), self, known: Boolean(name) }
}
