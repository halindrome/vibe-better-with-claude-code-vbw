// The clone's own settings file (`<git common dir>/vbw/settings.json`, docs/config.md)
// as a session of the stand-in sees it: a git checkout at ROOT and a stand-in kernel
// whose `vbw config set sound VALUE` writes the file as the real one does. `kept` (a
// Map) holds the file across sessions, so a restart reads what the last one set.
// `refuse`: the kernel refuses every call with that reason. (Evidence level L1.)
import { mount, ROOT } from './fake-mod.mjs'

export const SETTINGS = ROOT + '/.git/vbw/settings.json'

export async function clonedMount(options = {}) {
  const kept = options.kept || new Map()
  const runs = []
  let h
  const kernel = (argv) => {
    runs.push(argv.slice(1))
    if (options.refuse) return { exitCode: 1, stdout: '', stderr: 'vbw: config refused: ' + options.refuse + '\n' }
    const [cmd, sub, key, value] = argv.slice(1)
    if (cmd === 'config' && sub === 'set' && key === 'sound') {
      let now = {}
      try {
        now = JSON.parse(kept.get(SETTINGS))
      } catch {
        now = {}
      }
      kept.set(SETTINGS, JSON.stringify({ ...now, sound: value }))
      h.write(SETTINGS, kept.get(SETTINGS))
      return { exitCode: 0, stdout: 'sound: ' + value + '\n', stderr: '' }
    }
    return { exitCode: 0, stdout: '', stderr: '' }
  }
  const files = { [ROOT + '/.git/HEAD']: 'ref: refs/heads/main\n', ...(kept.has(SETTINGS) ? { [SETTINGS]: kept.get(SETTINGS) } : {}), ...(options.files || {}) }
  const { kept: _k, refuse: _r, files: _f, ...rest } = options
  h = await mount({ ...rest, files, process: kernel })
  return { h, runs, kept }
}
