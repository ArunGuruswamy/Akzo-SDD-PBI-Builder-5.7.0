'use strict';
// 5.6.2 versus current on the same PBI 309446-shaped workspace (fixtures/pbi-309446-shape.cjs): Approve & Generate (approval to
// verified handoff), the Complete Package ZIP and Start Development. 5.6.2 is read from git (release commit b57f706), so nothing
// is vendored. Times are wall clock on this machine, medians of [runs] (default 5); counts come from PBI.measure().
const fs = require('node:fs/promises'), os = require('node:os'), path = require('node:path'), cp = require('node:child_process');
const P = require('./src/core.js'), F = require('./fixtures/pbi-309446-shape.cjs'), W = require('./fixtures/workspace.cjs'), { DirectoryHandle } = require('./fixtures/fs-handles.cjs');
const assets = JSON.parse(require('node:fs').readFileSync(path.join(__dirname, 'src/assets.json'), 'utf8'));
const runs = Number(process.argv[2]) || 5, median = a => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];
const SUPPORTING = ['REQUEST.md', 'pbi.json', 'pbi-state.json', 'DRAFT-PBI.md', 'DECISION-LOG.md', 'EVIDENCE.md', 'VALIDATION-MATRIX.md', 'OPEN-QUESTIONS.md'];

async function workspace(tmp, i) {
  const o = { feature: 'Measurement', entity: 'measurement' }, dir = path.join(tmp, 'ws' + i), { files, config } = await F.build(P, fs, path, dir, o), root = new DirectoryHandle(dir);
  await P.apply(root, await P.plan(root, P.setupFiles(config, assets, '<html></html>').files, true), true); await P.discoverSources(root, config);
  const made = P.newPbi(config, { number: '309446', title: 'Measurement validation', description: 'Validate measurements before saving', application: 'dab', legacy: 'legacy' });
  await P.apply(root, await P.plan(root, made.files));
  const folder = made.folder, state = await F.state(P, o, folder.split('/').pop(), files);
  await P.write(root, folder + '/pbi-state.json', JSON.stringify(state, null, 2)); await P.write(root, folder + '/DRAFT-PBI.md', W.draftDoc(state, state.status));
  await P.write(root, folder + '/DECISION-LOG.md', '# Decision log\n\nDEC-1 approved: stated in the original request.\n');
  await P.write(root, folder + '/attachments/measurement-rules.md', '# Measurement rules\nA measurement value must be positive.\n');
  for (const id of ['Q-1', 'Q-2', 'Q-3', 'Q-4', 'Q-5', 'Q-6']) await P.recordAnswer(root, folder, id, { option: 'A', by: 'Business analyst' });
  await P.synchronizePbi(root, folder);
  return { root, folder };
}
// The 5.6.2 form's Download Complete Package, as its ui.js did it (generated files checked against their hash, records under supporting/).
async function oldPackage(C, root, folder, files) {
  const out = {};
  for (const x of files) { const b = await C.readBytes(root, x.path); if (b === null || await C.hashBytes(b) !== x.sha256) throw Error('changed: ' + x.name); out[x.name] = b; }
  for (const n of SUPPORTING) { const b = await C.readBytes(root, folder + '/' + n); if (b !== null) out['supporting/' + n] = C.cleanAttachment(n, b).bytes; }
  return out;
}
async function measureVersion(label, C, tmp) {
  const rows = [];
  for (let i = 0; i < runs; i++) {
    const { root, folder } = await workspace(tmp, label + i), review = await C.checkPbi(root, folder, true);
    const approve = await C.measure(() => C.approveAndGenerate(root, folder, 'Benchmark approver', review.reviewedContent));
    let t = performance.now();
    const files = label === '5.6.2' ? await oldPackage(C, root, folder, approve.result.files) : await C.developmentPackage(root, folder, approve.result.files);
    const zip = new Uint8Array(await C.zip(files).arrayBuffer()), zipMs = performance.now() - t;
    let start = null;
    if (C.startDevelopment) { start = await C.measure(() => C.startDevelopment(root, folder)); }
    rows.push({ approveMs: approve.metrics.elapsedMs, fileOpens: approve.metrics.fileOpens, bytesRead: approve.metrics.bytesRead, writes: approve.metrics.writes, bytesWritten: approve.metrics.bytesWritten,
      generatedFiles: approve.result.files.length, zipMs, zipEntries: Object.keys(files).length, zipBytes: zip.length,
      startMs: start ? start.metrics.elapsedMs : null, startOpens: start ? start.metrics.fileOpens : null, startWrites: start ? start.metrics.writes : null,
      targets: start ? start.result.targets.length : 0, manifestFiles: start ? start.result.manifest.files.length : 0 });
  }
  const m = k => rows[0][k] === null ? null : median(rows.map(r => r[k]));
  return Object.fromEntries(Object.keys(rows[0]).map(k => [k, m(k)]));
}
(async () => {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'akzo-bench570-'));
  try {
    const oldFile = path.join(tmp, 'core-5.6.2.cjs');
    await fs.writeFile(oldFile, cp.execFileSync('git', ['show', 'b57f706:maintainer/src/core.js'], { cwd: __dirname, maxBuffer: 1 << 26 }));
    const Old = require(oldFile); if (Old.VERSION !== '5.6.2') throw Error('expected the 5.6.2 core, got ' + Old.VERSION);
    const before = await measureVersion('5.6.2', Old, tmp), after = await measureVersion(P.VERSION, P, tmp);
    console.log(JSON.stringify({ runs, fixture: 'PBI 309446 shape (DAB + UI, 6 answered questions, 1 attachment)', '5.6.2': before, [P.VERSION]: after }, null, 2));
  } finally { await fs.rm(tmp, { recursive: true, force: true }); }
})().catch(e => { console.error(e); process.exitCode = 1; });
