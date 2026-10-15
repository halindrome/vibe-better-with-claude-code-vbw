// A VBW build run with a crew of Dev helpers, written as Claude Code writes a
// workflow run (the files of ../../helpers/run.mjs), inside the stand-in of
// ../../helpers/fake-mod.mjs (evidence level L1).
import { mount, record, next, lease, ROOT, T0 } from '../../helpers/fake-mod.mjs'
import { line, usage, jsonl } from '../../helpers/feed-fs.mjs'
import { ENV, RUN_DIR, FINAL, launch } from '../../helpers/run.mjs'

export const TICK = 2000 // the panel's refresh interval
export const agentId = (c) => 'a' + c.n.replace(/\D/g, '')

// writeCrew(h, at, crew): crew is [{ n: 'P142.1', state: 'working' | 'done' | 'failed' }],
// every helper started 5 s before `at` and last seen editing src/a.js at `at`.
export function writeCrew(h, at, crew) {
  h.write(RUN_DIR + '/journal.jsonl', jsonl([
    { type: 'launched' },
    ...crew.map((c) => ({ type: 'started', agentId: agentId(c), label: 'dev ' + c.n, phase: 'Build' })),
    ...crew.filter((c) => c.state === 'done').map((c) => ({ type: 'result', agentId: agentId(c), result: 'done: ' + c.n })),
    ...crew.filter((c) => c.state === 'failed').map((c) => ({ type: 'result', agentId: agentId(c), error: 'tests failed in ' + c.n })),
  ]))
  for (const c of crew) {
    h.write(RUN_DIR + '/agent-' + agentId(c) + '.meta.json', { agentType: 'vbw:dev', description: 'dev ' + c.n, model: 'sonnet' })
    h.write(RUN_DIR + '/agent-' + agentId(c) + '.jsonl', jsonl([line.user(at - 5000), line.tool(at, 'Edit', { file_path: ROOT + '/src/a.js' }, usage(10, 20000, 100))]))
  }
}

// The run ends as Claude Code ends it: its final file.
export const endRun = (h, at) => h.write(FINAL, { workflowName: 'building', status: 'completed', startTime: at, durationMs: 4000, phases: [{ title: 'Build' }] })

// n working helpers, P142.1 to P142.n.
export const working = (n) => Array.from({ length: n }, (_, i) => ({ n: 'P142.' + (i + 1), state: 'working' }))

// A session in a build run launched by /vbw:vibe, its crew written and seen once.
export async function building(crew, settings, options = {}) {
  const h = await mount({ env: ENV, ...options })
  h.project(record({ lease: lease('build', T0), ...(settings ? { settings } : {}) }), next({ action: 'run' }))
  await h.start()
  await h.settle()
  const at = h.now()
  writeCrew(h, at, crew)
  await launch(h, 'vbw:building')
  await h.advance(TICK)
  return { h, at }
}
