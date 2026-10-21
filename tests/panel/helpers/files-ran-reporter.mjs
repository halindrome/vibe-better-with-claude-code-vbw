// A node:test reporter for tests/panel-suite.bats: prints one "FILE <path>" line per
// test file that reported at least one test, and one "TESTS <n>" line with the
// number of passing tests, so the suite can compare the files node ran with the
// files on disk.
export default async function* filesRan(source) {
  const files = new Set();
  let passed = 0;
  for await (const event of source) {
    if (event.type === 'test:pass' || event.type === 'test:fail') {
      if (event.data.file) files.add(event.data.file);
      if (event.type === 'test:pass' && event.data.details?.type !== 'suite') passed += 1;
    }
  }
  for (const f of [...files].sort()) yield `FILE ${f}\n`;
  yield `TESTS ${passed}\n`;
}
