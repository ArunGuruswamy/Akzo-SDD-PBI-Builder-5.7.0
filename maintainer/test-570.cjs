'use strict';
// 5.7.0: Approve & Generate ends in one development-ready package for the Akzo Master SDD agent (business-rules.json,
// BRANCH-COVERAGE-MATRIX.md and HANDOFF-MANIFEST.json beside the Refined PBIs), and Start Development hands it over.
// Real files and real Windows PowerShell; a PBI shaped like PBI 309446 (fixtures/pbi-309446-shape.cjs) plus independent fixtures.
// The Akzo Master SDD agent's own helper (akzo.ps1) runs only when its folder is found (AKZO_SDD_AGENT, else the sibling
// Akzo-SDD-Agent-v4.2.5-GitHub checkout). No IDE or Copilot session runs here: live agent invocation is not tested.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs/promises'), os = require('node:os'), path = require('node:path'), cp = require('node:child_process'), crypto = require('node:crypto');
const P = require('./src/core.js'), F = require('./fixtures/pbi-309446-shape.cjs'), W = require('./fixtures/workspace.cjs'), { DirectoryHandle } = require('./fixtures/fs-handles.cjs');
const assets = JSON.parse(require('node:fs').readFileSync(path.join(__dirname, 'src/assets.json'), 'utf8'));
const installer = require('node:fs').readFileSync(path.join(__dirname, 'installer/Install-PBIBuilder.ps1'), 'utf8');
const MANDATORY = ['Q-1', 'Q-2', 'Q-3', 'Q-4', 'Q-5', 'Q-6'], sha = b => crypto.createHash('sha256').update(b).digest('hex');
const REFINED_309446 = ['Refined-PBI-DAB.md', 'Refined-PBI-DAB.json', 'Refined-PBI-DAB.docx', 'Refined-PBI-UI.md', 'Refined-PBI-UI.json', 'Refined-PBI-UI.docx'];

// One workspace with a PBI. shape '309446': DAB + UI, CDMS a read-only reference, six mandatory questions. Otherwise an independent
// workspace PBI for `application`, keeping only the paths of `keep` (as test-560 does).
async function pbi(t, { shape = '309446', application = 'dab', keep = ['cdms', 'dab', 'ui'], attachment = true } = {}) {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'akzo-570-')); t.after(() => fs.rm(tmp, { recursive: true, force: true }));
  const o = { feature: 'Measurement', entity: 'measurement' }, dir = path.join(tmp, 'ws');
  const { files, config } = await F.build(P, fs, path, dir, o), root = new DirectoryHandle(dir);
  await P.apply(root, await P.plan(root, P.setupFiles(config, assets, '<html></html>').files, true), true);
  await P.discoverSources(root, config);
  const made = P.newPbi(config, { number: '309446', title: 'Measurement validation', description: 'Validate measurements before saving', application, legacy: 'legacy' });
  await P.apply(root, await P.plan(root, made.files));
  const folder = made.folder, name = folder.split('/').pop();
  let state;
  if (shape === '309446') state = await F.state(P, o, name, files);
  else {
    state = await W.stateFor(P, o, name, files);
    for (const k of ['cdms', 'dab', 'ui']) if (!keep.includes(k)) { state.paths[k] = { applies: false, reason: 'Not selected' }; for (const r of state.rules) { delete r.paths[k]; for (const b of r.branches || []) delete b[k]; } }
  }
  await P.write(root, folder + '/pbi-state.json', JSON.stringify(state, null, 2)); await P.write(root, folder + '/DRAFT-PBI.md', W.draftDoc(state, state.status));
  await P.write(root, folder + '/DECISION-LOG.md', '# Decision log\n\nDEC-1 approved: stated in the original request.\n');
  if (attachment) await P.write(root, folder + '/attachments/measurement-rules.md', '# Measurement rules\nA measurement value must be positive.\n');
  const pkg = path.join(tmp, 'package'); await fs.mkdir(pkg);
  await fs.writeFile(path.join(pkg, 'Install-PBIBuilder.ps1'), installer); await fs.writeFile(path.join(pkg, 'pbi-builder-bundle.json'), JSON.stringify(P.bundle(assets)));
  await fs.writeFile(path.join(pkg, 'Akzo-SDD-PBI-Builder.html'), '<html></html>');
  const env = { ...process.env, USERPROFILE: tmp }; delete env.PSExecutionPolicyPreference;
  const run = (...args) => { const r = cp.spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-File', path.join(pkg, 'Install-PBIBuilder.ps1'), '-RepoPath', dir, ...args], { encoding: 'utf8', env, timeout: 180000 }); assert.ifError(r.error); return { code: r.status, out: r.stdout, err: r.stderr, json: () => JSON.parse(r.stdout.trim()) }; };
  const questions = state.questions.filter(q => q.blocking).map(q => q.id);
  const w = { tmp, dir, root, folder, name, run, questions, read: n => P.read(root, folder + '/' + n), bytes: n => fs.readFile(path.join(dir, folder, n)), state: async () => JSON.parse(await P.read(root, folder + '/pbi-state.json')) };
  w.answer = async () => { for (const id of questions) await P.recordAnswer(root, folder, id, { option: 'A', by: 'Business analyst' }); await P.synchronizePbi(root, folder); };
  w.approveJs = async () => { await w.answer(); const review = await P.checkPbi(root, folder, true); return P.approveAndGenerate(root, folder, 'Product owner', review.reviewedContent); };
  w.approvePs = async () => { await w.answer(); const s = run('-Action', 'SyncPbi', '-Pbi', name, '-Json'); assert.equal(s.code, 0, s.err); const r = run('-Action', 'ApproveAndGenerate', '-Pbi', name, '-Approver', 'Product owner', '-ReviewedContent', s.json().report.reviewedContent); assert.equal(r.code, 0, r.err + r.out); return r; };
  w.listing = async () => (await fs.readdir(path.join(dir, folder))).filter(n => n !== 'history').sort();
  w.snapshot = async () => { const out = {}; for (const n of await w.listing()) { const p = path.join(dir, folder, n); if ((await fs.stat(p)).isFile()) out[n] = sha(await fs.readFile(p)); } return out; };
  return w;
}
const manifestOf = async w => JSON.parse(await w.read('HANDOFF-MANIFEST.json'));

for (const engine of ['JavaScript', 'PowerShell']) test(`309446 (DAB + UI), ${engine}: the Refined PBIs and the handoff come from one approved state`, async t => {
  const w = await pbi(t), before = await w.state();
  if (engine === 'JavaScript') { const r = await w.approveJs(); assert.equal(r.handoff.disposition, 'DEVELOPMENT_READY'); assert.deepEqual(r.files.map(f => f.name), [...REFINED_309446, 'business-rules.json', 'BRANCH-COVERAGE-MATRIX.md', 'HANDOFF-MANIFEST.json']); }
  else assert.match((await w.approvePs()).out, /Development handoff: DEVELOPMENT_READY, bound to this approval/);
  const state = await w.state(), m = await manifestOf(w), report = await P.checkPbi(w.root, w.folder);
  assert.equal(report.computedStatus, 'Development-Ready'); assert.deepEqual(report.issues, []);
  // Bound to the recorded approval; the manifest never lists (or hashes) itself.
  assert.equal(m.schema, 'akzo-pbi-handoff'); assert.equal(m.schemaVersion, 1); assert.deepEqual(m.producer, { name: 'Akzo SDD PBI Builder', version: P.VERSION }); assert.equal(m.disposition, 'DEVELOPMENT_READY'); assert.equal(m.status, 'Development-Ready');
  assert.deepEqual([m.approval.by, m.approval.at, m.approval.evidence, m.approval.reviewedContent], [state.approvals.user.by, state.approvals.user.at, state.approvals.user.evidence, state.approvals.user.basis.reviewedContent]);
  assert.equal(m.approval.fingerprint, report.review.user.fingerprint); assert.match(m.approval.fingerprint, /^[0-9a-f]{16}$/);
  assert.deepEqual(m.pbi, { id: w.name, number: '309446', title: 'Measurement validation', folder: w.folder, stateSchema: 2 });
  assert.deepEqual(m.files.map(f => f.path), [...REFINED_309446, 'business-rules.json', 'BRANCH-COVERAGE-MATRIX.md']);
  for (const f of m.files) { const b = await w.bytes(f.path); assert.equal(f.sha256, sha(b), f.path); assert.equal(f.bytes, b.length, f.path); }
  // business-rules.json (schema 2), the matrix and every Refined PBI JSON are byte for byte what the approved state gives, in both engines.
  const request = JSON.parse(await w.read('pbi.json')), h = P.handoff(state, report, request);
  assert.equal(await w.read('business-rules.json'), JSON.stringify(h, null, 2) + '\n'); assert.equal(await w.read('BRANCH-COVERAGE-MATRIX.md'), P.branchMatrix(h)); assert.equal(h.schemaVersion, 2);
  for (const d of P.finalDocuments(request, state, w.folder)) assert.equal(await w.read(d.name.replace(/\.md$/, '.json')), d.json, d.name + ' JSON');
  // EV-5 (CDMS reach) is cited by no rule once CDMS is only a reference, so there is nothing to re-check for it.
  assert.deepEqual(h.technicalRevalidation, ['EV-1', 'EV-2', 'EV-3', 'EV-4', 'EV-6', 'EV-7']); assert.deepEqual(h.questions.map(q => q.status), MANDATORY.map(() => 'answered'));
  assert.deepEqual(h.rules[0].evidence.map(e => e.repository), ['legacy', 'cdms', 'dab', 'ui']); assert.ok(h.decisions.every(d => typeof d.decision === 'string' || d.decision === null));
  const dabJson = JSON.parse(await w.read('Refined-PBI-DAB.json')); assert.equal(dabJson.pbi.originalAcceptanceCriteria, request.acceptanceCriteria); assert.deepEqual(Object.keys(dabJson.approval), ['user', 'poba', 'technical']); assert.ok(dabJson.openIssues.some(x => /informational evidence gap/.test(x)));
  // Every selected target, nothing for CDMS; DAB + UI implement, Legacy and CDMS are read-only references.
  assert.deepEqual(m.target, { key: 'dab', label: 'DAB + UI', implement: ['dab', 'ui'], reference: ['legacy', 'cdms'] });
  assert.deepEqual(m.documents, [{ area: 'dab', md: 'Refined-PBI-DAB.md', json: 'Refined-PBI-DAB.json', docx: 'Refined-PBI-DAB.docx', repository: 'DAB Repo' }, { area: 'ui', md: 'Refined-PBI-UI.md', json: 'Refined-PBI-UI.json', docx: 'Refined-PBI-UI.docx', repository: 'UI Repo' }]);
  assert.deepEqual(m.repositories.map(r => r.key + ':' + r.use), ['legacy:reference', 'cdms:reference', 'dab:implement', 'ui:implement']);
  assert.ok(!(await w.listing()).some(n => /CDMS/.test(n)), 'no CDMS document for a reference');
  // Evidence paths name the repository each source came from.
  assert.deepEqual(m.evidence.map(e => e.id + ':' + e.repository), ['EV-1:legacy', 'EV-2:cdms', 'EV-3:dab', 'EV-4:ui', 'EV-5:cdms', 'EV-6:dab', 'EV-7:ui']);
  assert.ok(m.evidence.every(e => /^[0-9a-f]{64}$/.test(e.sha256) && e.verification === 'VERIFIED'));
  // Answered questions stay answered; decisions and requirements as approved; the attachment is referenced with its hash.
  assert.deepEqual(m.questions.map(q => q.id + ':' + q.status), MANDATORY.map(id => id + ':answered')); assert.ok(m.questions.every(q => /^DEC-\d+$/.test(q.decisionRef)));
  assert.deepEqual(state.questions.map(q => q.status), MANDATORY.map(() => 'answered')); assert.deepEqual(state.questions.map(q => q.question), before.questions.map(q => q.question));
  assert.deepEqual(m.requirements, [{ id: 'BR-1', rev: 1, kind: 'approved-requirement' }, { id: 'BR-2', rev: 1, kind: 'approved-requirement' }]);
  assert.deepEqual(m.acceptanceCriteria, ['AC-1', 'AC-2', 'AC-3', 'AC-4']); assert.ok(m.decisions.every(d => d.status === 'approved'));
  assert.deepEqual(m.attachments, [{ path: 'attachments/measurement-rules.md', bytes: (await w.bytes('attachments/measurement-rules.md')).length, sha256: sha(await w.bytes('attachments/measurement-rules.md')) }]);
  // The other engine writes the same manifest, byte for byte, from the same state and Refined PBI files.
  const docFiles = m.files.filter(f => f.role === 'refined-pbi'), js = await P.handoffOutputs(w.root, w.folder, state, request, report, docFiles);
  assert.equal(await w.read('HANDOFF-MANIFEST.json'), js.files['HANDOFF-MANIFEST.json']);
  // Re-exporting from the form leaves the approved handoff exactly as it is, whichever engine approved.
  const rulesBytes = await w.bytes('business-rules.json'), exported = await P.exportHandoff(w.root, w.folder);
  assert.equal(exported.disposition, 'DEVELOPMENT_READY'); assert.deepEqual(await w.bytes('business-rules.json'), rulesBytes, 'unchanged content is not rewritten');
  // Both engines verify the package; Start Development reports the same targets in both and changes nothing.
  const v = await P.verifyHandoff(w.root, w.folder); assert.deepEqual([v.disposition, v.valid, v.problems], ['DEVELOPMENT_READY', true, []]);
  const snapshot = await w.snapshot(), stateRaw = await w.read('pbi-state.json');
  const ps = w.run('-Action', 'StartDevelopment', '-Pbi', w.name, '-Json'); assert.equal(ps.code, 0, ps.err); const p = ps.json();
  assert.deepEqual([p.status, p.disposition, p.valid, p.adopted, p.sddInstalled], ['READY', 'DEVELOPMENT_READY', true, false, false]);
  const s = await P.startDevelopment(w.root, w.folder, w.dir);
  assert.equal(s.source, path.join(w.dir, ...w.folder.split('/'))); assert.equal(p.source, s.source);
  assert.deepEqual(p.targets, s.targets.map(x => ({ document: x.document, target: x.target, repository: x.repository, area: x.area, command: x.command })));
  assert.deepEqual(p.references.map(r => r.key), ['legacy', 'cdms']); assert.deepEqual(s.references.map(r => r.key), ['legacy', 'cdms']);
  assert.equal(s.targets[0].command, `& "$env:USERPROFILE\\.akzo-agent\\modules\\investigate\\scripts\\akzo.ps1" pick -Source '${s.source}' -File 'Refined-PBI-DAB.md'`);
  assert.match(w.run('-Action', 'StartDevelopment', '-Pbi', w.name).out, /Disposition: DEVELOPMENT_READY[\s\S]*DAB \(GraphQL\) \(DAB Repo\): Refined-PBI-DAB\.md[\s\S]*Read-only references \(never changed\): Custom \(Legacy CRM\/XRM\), CDMS[\s\S]*not installed for this user[\s\S]*starts nothing/);
  assert.deepEqual(await w.snapshot(), snapshot, 'Start Development writes nothing'); assert.equal(await w.read('pbi-state.json'), stateRaw);
});

test('independent fixtures: every selected target gets its documents in the handoff, in both engines', async t => {
  for (const [application, keep, docs] of [['both', ['cdms', 'dab', 'ui'], ['Refined-PBI-CDMS.md', 'Refined-PBI-DAB.md', 'Refined-PBI-UI.md']], ['cdms-only', ['cdms'], ['Refined-PBI-CDMS.md']]]) {
    for (const engine of ['js', 'ps']) {
      const w = await pbi(t, { shape: 'workspace', application, keep, attachment: false });
      if (engine === 'js') await w.approveJs(); else await w.approvePs();
      const m = await manifestOf(w);
      assert.deepEqual(m.documents.map(d => d.md), docs, application + '/' + engine);
      assert.deepEqual(m.files.map(f => f.path), [...docs.flatMap(d => ['.md', '.json', '.docx'].map(x => d.replace(/\.md$/, x))), 'business-rules.json', 'BRANCH-COVERAGE-MATRIX.md'], application + '/' + engine);
      assert.deepEqual(m.repositories.filter(r => r.use === 'implement').map(r => r.key).sort(), keep.slice().sort(), application + '/' + engine);
      assert.deepEqual(m.attachments, []);
      const state = await w.state(), request = JSON.parse(await w.read('pbi.json')), report = await P.checkPbi(w.root, w.folder);
      assert.equal(await w.read('business-rules.json'), JSON.stringify(P.handoff(state, report, request), null, 2) + '\n', application + '/' + engine);
      for (const d of P.finalDocuments(request, state, w.folder)) assert.equal(await w.read(d.name.replace(/\.md$/, '.json')), d.json, application + '/' + engine + ' ' + d.name);
      assert.equal((await P.verifyHandoff(w.root, w.folder)).valid, true, application + '/' + engine);
      assert.equal(w.run('-Action', 'StartDevelopment', '-Pbi', w.name, '-Json').json().targets.length, docs.length, application + '/' + engine);
    }
  }
});

test('a PBI without a development target (REFINED-PBI.md) is approved in Chat as in the browser, with the same JSON', async t => {
  // 5.6.2's PowerShell approval failed here ("The property 'Count' cannot be found"); the browser engine handled it.
  const shared = require('./fixtures/readiness-cases.cjs'), { cases } = await shared.load(P), pending = cases.find(c => c.name.startsWith('pending approvals'));
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'akzo-570-')); t.after(() => fs.rm(tmp, { recursive: true, force: true }));
  const dir = path.join(tmp, 'repo'), root = new DirectoryHandle(dir), folder = 'playbook/pbis/' + shared.PBI;
  await fs.mkdir(path.join(dir, '.git'), { recursive: true }); await shared.writeCase(P, root, folder, pending); await fs.rm(path.join(dir, folder, 'REFINED-PBI.md'));
  const pkg = path.join(tmp, 'package'); await fs.mkdir(pkg);
  await fs.writeFile(path.join(pkg, 'Install-PBIBuilder.ps1'), installer); await fs.writeFile(path.join(pkg, 'pbi-builder-bundle.json'), JSON.stringify(P.bundle(assets))); await fs.writeFile(path.join(pkg, 'Akzo-SDD-PBI-Builder.html'), '<html></html>');
  const env = { ...process.env, USERPROFILE: tmp }; delete env.PSExecutionPolicyPreference;
  const run = (...a) => cp.spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-File', path.join(pkg, 'Install-PBIBuilder.ps1'), '-RepoPath', dir, ...a], { encoding: 'utf8', env, timeout: 180000 });
  const review = JSON.parse(run('-Action', 'CheckPbi', '-Pbi', shared.PBI, '-Json').stdout.trim());
  const r = run('-Action', 'ApproveAndGenerate', '-Pbi', shared.PBI, '-Approver', 'Product owner', '-ReviewedContent', review.reviewedContent); assert.equal(r.status, 0, r.stderr);
  const state = JSON.parse(await P.read(root, folder + '/pbi-state.json')), report = await P.checkPbi(root, folder), doc = P.finalDocuments({}, state, folder)[0];
  assert.equal(doc.name, 'REFINED-PBI.md'); assert.equal(await P.read(root, folder + '/REFINED-PBI.json'), doc.json, 'the same Refined PBI JSON as the browser');
  assert.match(await P.read(root, folder + '/REFINED-PBI.md'), /### BR-1[\s\S]*### BR-2/, 'a document without a target owns every rule');
  assert.equal(await P.read(root, folder + '/business-rules.json'), JSON.stringify(P.handoff(state, report, {}), null, 2) + '\n');
  const m = JSON.parse(await P.read(root, folder + '/HANDOFF-MANIFEST.json'));
  assert.equal(m.target, null); assert.deepEqual(m.documents, [{ area: null, md: 'REFINED-PBI.md', json: 'REFINED-PBI.json', docx: 'REFINED-PBI.docx', repository: null }]);
  assert.equal(await P.read(root, folder + '/HANDOFF-MANIFEST.json'), (await P.handoffOutputs(root, folder, state, {}, report, m.files.filter(f => f.role === 'refined-pbi'))).files['HANDOFF-MANIFEST.json']);
  assert.equal((await P.verifyHandoff(root, folder)).valid, true);
});

test('modification is detected by both engines and nothing is handed off', async t => {
  const w = await pbi(t); await w.approveJs();
  const refuse = async (problem, label) => {
    const v = await P.verifyHandoff(w.root, w.folder); assert.equal(v.disposition, 'STALE', label); assert.ok(v.problems.some(x => x.startsWith(problem)), label + ': ' + v.problems.join('; '));
    await assert.rejects(P.startDevelopment(w.root, w.folder), new RegExp('is STALE[\\s\\S]*Nothing was changed and nothing was started'), label);
    const p = w.run('-Action', 'StartDevelopment', '-Pbi', w.name, '-Json'); assert.equal(p.code, 3, label + ' ' + p.err);
    const j = p.json(); assert.deepEqual([j.status, j.disposition, j.targets], ['NOT_READY', 'STALE', []], label); assert.ok(j.problems.some(x => x.startsWith(problem)), label);
  };
  const keep = async (n, change, problem, label) => { const was = await w.read(n); await change(was); await refuse(problem, label); await P.write(w.root, w.folder + '/' + n, was); assert.equal((await P.verifyHandoff(w.root, w.folder)).valid, true, label + ' restored'); };
  await keep('Refined-PBI-DAB.md', was => P.write(w.root, w.folder + '/Refined-PBI-DAB.md', was + '\nUnreviewed extra scope.\n'), 'HANDOFF_FILE_CHANGED Refined-PBI-DAB.md', 'a Refined PBI edited after generation');
  // A forged manifest hash does not help: business-rules.json must still be what the approved state gives.
  const m0 = await w.read('HANDOFF-MANIFEST.json'), rules0 = await w.read('business-rules.json');
  {
    const forged = rules0.replace('with a clear message', 'silently'); assert.notEqual(forged, rules0); await P.write(w.root, w.folder + '/business-rules.json', forged);
    const m = JSON.parse(m0), f = m.files.find(x => x.path === 'business-rules.json'); f.sha256 = sha(Buffer.from(forged)); f.bytes = Buffer.byteLength(forged);
    await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', JSON.stringify(m, null, 2) + '\n');
    await refuse('HANDOFF_CONTENT_CHANGED business-rules.json', 'business-rules.json edited and its hash forged');
    await P.write(w.root, w.folder + '/business-rules.json', rules0); await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', m0);
  }
  for (const [bad, problem] of [['HANDOFF-MANIFEST.json', 'HANDOFF_PATH_UNSAFE'], ['../pbi.json', 'HANDOFF_PATH_UNSAFE'], ['history/x.md', 'HANDOFF_PATH_UNSAFE']]) {
    const m = JSON.parse(m0); m.files.push({ path: bad, role: 'x', target: null, bytes: 0, sha256: sha('') }); await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', JSON.stringify(m));
    await refuse(problem, 'manifest lists ' + bad);
  }
  { const m = JSON.parse(m0); m.files = m.files.filter(f => f.path !== 'Refined-PBI-UI.docx'); await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', JSON.stringify(m)); await refuse('HANDOFF_FILE_NOT_LISTED Refined-PBI-UI.docx', 'a target file left out'); }
  { const m = JSON.parse(m0); m.approval.by = 'Someone else'; await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', JSON.stringify(m)); await refuse('HANDOFF_APPROVAL_MISMATCH', 'another approval'); }
  // Fields without a hash of their own are re-derived too: the import document and the repository roles cannot be redirected.
  { const m = JSON.parse(m0); m.documents[0].md = 'DRAFT-PBI.md'; await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', JSON.stringify(m)); await refuse('HANDOFF_MANIFEST_CHANGED', 'the import redirected to the draft'); }
  { const m = JSON.parse(m0); m.repositories.find(r => r.key === 'cdms').use = 'implement'; await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', JSON.stringify(m)); await refuse('HANDOFF_MANIFEST_CHANGED', 'CDMS turned into an implementation target'); }
  await P.write(w.root, w.folder + '/HANDOFF-MANIFEST.json', m0); assert.equal((await P.verifyHandoff(w.root, w.folder)).valid, true);
  // A technical move between the two supported PBI roots changes no approved content: the handoff stays valid.
  const moved = path.join(w.dir, 'Source', ...w.folder.split('/')); await fs.cp(path.join(w.dir, w.folder), moved, { recursive: true });
  assert.deepEqual((await P.verifyHandoff(w.root, 'Source/' + w.folder)).problems, [], 'the same PBI under Source/playbook/pbis');
  await fs.rm(path.join(w.dir, 'Source'), { recursive: true, force: true });
  // Approved business content changed after approval: the existing approval process applies again; nothing is re-approved here.
  const s = await w.state(); s.rules[0].rule += ' within one second'; await P.write(w.root, w.folder + '/pbi-state.json', JSON.stringify(s, null, 2));
  const v = await P.verifyHandoff(w.root, w.folder); assert.equal(v.disposition, 'STALE'); assert.ok(v.report.issues.some(i => i.code === 'APPROVAL_STALE'));
  await assert.rejects(P.startDevelopment(w.root, w.folder), /is STALE[\s\S]*review the PBI again \(Review & approve\)/);
  assert.equal(w.run('-Action', 'StartDevelopment', '-Pbi', w.name, '-Json').json().disposition, 'STALE');
  assert.equal((await w.state()).approvals.user.status, 'approved', 'the earlier approval record is not touched');
});

test('drafts and conditional drafts cannot impersonate an approved PBI', async t => {
  const draft = await pbi(t);
  assert.deepEqual((await P.verifyHandoff(draft.root, draft.folder)).disposition, 'DRAFT');
  await assert.rejects(P.startDevelopment(draft.root, draft.folder), /is DRAFT[\s\S]*Finish the refinement/);
  // Conditional draft: business questions answered, technical dependencies still open (the workflow's own conditional generation).
  const c = await pbi(t); await c.answer();
  const s = await c.state(), gaps = ['Color Measurement Service contract', 'DAB authorization policy'].map((description, i) => ({ id: 'EXT-' + (i + 1), classification: 'EXTERNAL_DEPENDENCY', description, owner: 'External dependency owner', readinessRefs: ['BR-1'] }));
  s.rules[0].gaps = [...s.rules[0].gaps, ...gaps.map(g => ({ id: g.id, description: g.description, status: 'open', impact: 'BLOCKING' }))]; s.analysis = { ...(s.analysis || {}), gaps, requirementsComplete: true };
  await P.write(c.root, c.folder + '/pbi-state.json', JSON.stringify(s, null, 2));
  const generated = await P.generateConditionalPbi(c.root, c.folder, { gaps, requirementsComplete: true }); assert.equal(generated.state.analysis.conditionalPbiGenerated, true);
  assert.equal((await P.verifyHandoff(c.root, c.folder)).disposition, 'CONDITIONAL');
  const exported = await P.exportHandoff(c.root, c.folder); assert.equal(exported.disposition, 'CONDITIONAL'); assert.equal(await c.read('HANDOFF-MANIFEST.json'), null, 'a draft export writes no manifest');
  await assert.rejects(P.startDevelopment(c.root, c.folder), /is CONDITIONAL[\s\S]*resolve its dependencies/);
  // Copying an approved PBI's Refined PBIs and handoff into the conditional draft does not make it approved.
  const a = await pbi(t); await a.approveJs();
  for (const n of [...REFINED_309446, 'business-rules.json', 'BRANCH-COVERAGE-MATRIX.md', 'HANDOFF-MANIFEST.json']) await fs.copyFile(path.join(a.dir, a.folder, n), path.join(c.dir, c.folder, n));
  const v = await P.verifyHandoff(c.root, c.folder); assert.equal(v.valid, false); assert.notEqual(v.disposition, 'DEVELOPMENT_READY'); assert.ok(v.problems.includes('HANDOFF_APPROVAL_MISMATCH'), v.problems.join('; '));
  await assert.rejects(P.startDevelopment(c.root, c.folder), /Nothing was changed and nothing was started/);
  const p = c.run('-Action', 'StartDevelopment', '-Pbi', c.name, '-Json'); assert.equal(p.code, 3); assert.equal(p.json().status, 'NOT_READY'); assert.notEqual(p.json().disposition, 'DEVELOPMENT_READY');
});

// The browser engine with one injected write failure: HANDOFF-MANIFEST.json cannot be written.
class FailingDirectory extends DirectoryHandle {
  constructor(p, fail) { super(p); this.fail = fail; }
  async getDirectoryHandle(n, o) { const d = await super.getDirectoryHandle(n, o); return new FailingDirectory(d.path, this.fail); }
  async getFileHandle(n, o) { const h = await super.getFileHandle(n, o); if (n === this.fail && o?.create) h.createWritable = async () => { throw Error('disk full (injected)'); }; return h; }
}
test('a failed handoff write rolls the whole approval back, in both engines', async t => {
  const w = await pbi(t); await w.answer();
  const before = await w.snapshot(), review = await P.checkPbi(w.root, w.folder, true);
  await assert.rejects(P.approveAndGenerate(new FailingDirectory(w.dir, 'HANDOFF-MANIFEST.json'), w.folder, 'Product owner', review.reviewedContent), /Generation failed; nothing was approved\. Earlier files were restored\. disk full/);
  assert.deepEqual(await w.snapshot(), before, 'every file as before: no approval, no Refined PBI, no handoff');
  // PowerShell: a folder in the manifest's place makes its write fail after every other file was written.
  await fs.mkdir(path.join(w.dir, w.folder, 'HANDOFF-MANIFEST.json'));
  const s = w.run('-Action', 'SyncPbi', '-Pbi', w.name, '-Json').json(), after = await w.snapshot();
  const r = w.run('-Action', 'ApproveAndGenerate', '-Pbi', w.name, '-Approver', 'Product owner', '-ReviewedContent', s.report.reviewedContent);
  assert.equal(r.code, 2); assert.match(r.err, /Generation failed; earlier files were restored/);
  assert.deepEqual(await w.snapshot(), after); assert.equal((await w.state()).approvals.user.status, 'pending');
  await fs.rmdir(path.join(w.dir, w.folder, 'HANDOFF-MANIFEST.json'));
  await w.approveJs(); assert.equal((await P.verifyHandoff(w.root, w.folder)).valid, true, 'approving again afterwards works');
});

test('a PBI approved before 5.7 keeps its approval; Start Development creates its handoff without re-approval', async t => {
  const V53 = require('./fixtures/baseline-v5.3.0-core.cjs');
  for (const engine of ['js', 'ps']) {
    const w = await pbi(t, { shape: 'workspace', application: 'both', attachment: false }); await w.answer();
    const review = await V53.checkPbi(w.root, w.folder, true); await V53.approveAndGenerate(w.root, w.folder, 'Product owner', review.reviewedContent);
    const stateRaw = await w.read('pbi-state.json'), legacy = (await w.listing()).filter(n => /\.(md|json|docx)$/.test(n) && /PBI-(CDMS|DAB|UI)|REFINED/.test(n));
    assert.equal(await w.read('HANDOFF-MANIFEST.json'), null); assert.ok(legacy.length >= 3, legacy.join());
    assert.equal((await P.verifyHandoff(w.root, w.folder)).problems.join(), 'HANDOFF_MISSING');
    let docs;
    if (engine === 'js') { const s = await P.startDevelopment(w.root, w.folder); assert.equal(s.adopted, true); docs = s.targets.map(x => x.document); }
    else { const p = w.run('-Action', 'StartDevelopment', '-Pbi', w.name, '-Json'); assert.equal(p.code, 0, p.err); assert.equal(p.json().adopted, true); docs = p.json().targets.map(x => x.document); }
    assert.equal(await w.read('pbi-state.json'), stateRaw, engine + ': the 5.3.0 approval and every answer stay exactly as recorded');
    assert.ok(docs.every(d => legacy.includes(d)), engine + ': the documents keep their earlier names: ' + docs.join());
    const m = await manifestOf(w); assert.equal(m.approval.by, 'Product owner'); assert.equal((await P.verifyHandoff(w.root, w.folder)).valid, true);
    assert.equal((await P.startDevelopment(w.root, w.folder)).adopted, false, engine + ': created once');
  }
});

// The ZIP is read back by an independent reader (Windows PowerShell Expand-Archive), as release.cjs verifies the release ZIP.
test('Download Complete Package: one verified ZIP that matches the approved handoff', async t => {
  const w = await pbi(t), r = await w.approveJs();
  const started = performance.now(), files = await P.developmentPackage(w.root, w.folder, r.files), zip = Buffer.from(await P.zip(files).arrayBuffer()), ms = performance.now() - started;
  const zipPath = path.join(w.tmp, w.name + '-final-pbis.zip'), out = path.join(w.tmp, 'unzipped'); await fs.writeFile(zipPath, zip);
  const x = cp.spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', 'Expand-Archive -LiteralPath $env:ZIP -DestinationPath $env:OUT'], { encoding: 'utf8', env: { ...process.env, ZIP: zipPath, OUT: out } });
  assert.equal(x.status, 0, x.stderr);
  const names = Object.keys(files), m = JSON.parse(await fs.readFile(path.join(out, 'HANDOFF-MANIFEST.json'), 'utf8'));
  assert.deepEqual(names, [...REFINED_309446, 'business-rules.json', 'BRANCH-COVERAGE-MATRIX.md', 'HANDOFF-MANIFEST.json', 'attachments/measurement-rules.md',
    ...['REQUEST.md', 'pbi.json', 'pbi-state.json', 'DRAFT-PBI.md', 'DECISION-LOG.md', 'EVIDENCE.md', 'VALIDATION-MATRIX.md', 'OPEN-QUESTIONS.md'].map(n => 'supporting/' + n)]);
  for (const f of m.files) assert.equal(sha(await fs.readFile(path.join(out, f.path))), f.sha256, 'ZIP copy of ' + f.path);
  for (const a of m.attachments) assert.equal(sha(await fs.readFile(path.join(out, a.path))), a.sha256, 'ZIP copy of ' + a.path);
  for (const n of names) { assert.doesNotThrow(() => P.safePath(n)); assert.ok((await fs.stat(path.join(out, n))).size > 0, n + ' is not empty'); }
  assert.equal(new Set(names.map(n => sha(files[n]))).size, names.length, 'no duplicate file');
  t.diagnostic(`package: ${names.length} files, ${zip.length} bytes, assembled and zipped in ${ms.toFixed(1)} ms`);
  // A generated file changed after generation is refused, as the single downloads are.
  await P.write(w.root, w.folder + '/business-rules.json', '{}'); await assert.rejects(P.developmentPackage(w.root, w.folder, r.files), /business-rules\.json is missing or changed since it was generated/);
});

test('the installed agent hands an approved PBI over through StartDevelopment and never restarts refinement for it', () => {
  for (const ide of ['visualstudio', 'vscode']) {
    const f = P.setupFiles({ projectName: 'X', ide, role: 'dab', sources: {} }, assets, '').files, norm = s => s.replace(/\s+/g, ' ');
    const agent = norm(f[P.AGENT]), stage = norm(f[P.BASE + '/skills/stage-approval.md']);
    assert.match(agent, /Start PBI \(also Create PBI, New PBI, Create User Story, Refine New Requirement\): all start the same intake below\. Start Development <n> and Implement PBI <n> hand an approved PBI to the Akzo Master SDD agent \(stage-approval\.md\), never start a new intake/, ide);
    assert.doesNotMatch(agent, /New PBI, Start Development, Implement PBI/, ide + ': Start Development is no longer an intake command');
    for (const re of [/-Action StartDevelopment -Pbi <folder>/, /Do not run them yourself \(they write outside this repository\), and never say the SDD agent was started/,
      /When it reports STALE, CONDITIONAL or DRAFT, say so and continue that PBI at its current stage; never start a new intake, re-ask an answered question or approve on the user's behalf\./, /Without a PBI, ask which approved PBI to hand off\./])
      assert.match(stage, re, ide);
  }
});

// The golden package consumers test against (make-golden-package.cjs). Its bytes differ per generation (approval time, folder name);
// its contract must not: file names, schemas, keys, roles and status values. Expand-Archive reads it independently.
test('golden package (fixtures/golden): verified by its own manifest and matching the contract of a package generated now', async t => {
  const G = require('./make-golden-package.cjs'), tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'akzo-570-golden-')); t.after(() => fs.rm(tmp, { recursive: true, force: true }));
  const out = path.join(tmp, 'golden'), x = cp.spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', 'Expand-Archive -LiteralPath $env:ZIP -DestinationPath $env:OUT'], { encoding: 'utf8', env: { ...process.env, ZIP: G.GOLDEN, OUT: out } });
  assert.equal(x.status, 0, x.stderr + ' (regenerate with: node make-golden-package.cjs)');
  const list = async (d, rel = '') => (await Promise.all((await fs.readdir(path.join(d, rel), { withFileTypes: true })).map(e => e.isDirectory() ? list(d, rel + e.name + '/') : [rel + e.name]))).flat().sort();
  const read = n => fs.readFile(path.join(out, n), 'utf8'), m = JSON.parse(await read('HANDOFF-MANIFEST.json')), rules = JSON.parse(await read('business-rules.json'));
  assert.equal(m.producer.version, P.VERSION, 'the golden package is from this Builder version: run node make-golden-package.cjs for the release');
  for (const f of [...m.files, ...m.attachments]) assert.equal(sha(await fs.readFile(path.join(out, f.path))), f.sha256, 'golden ' + f.path);
  const fresh = await G.goldenPackage(), fm = JSON.parse(Buffer.from(fresh.files['HANDOFF-MANIFEST.json']).toString('utf8')), fr = JSON.parse(Buffer.from(fresh.files['business-rules.json']).toString('utf8'));
  const keys = o => o && typeof o === 'object' && !Array.isArray(o) ? Object.fromEntries(Object.keys(o).map(k => [k, keys(o[k])])) : Array.isArray(o) ? (o.length ? [keys(o[0])] : []) : typeof o;
  assert.deepEqual(await list(out), Object.keys(fresh.files).sort(), 'same package file names');
  assert.deepEqual(keys(m), keys(fm), 'same manifest structure'); assert.deepEqual(keys(rules), keys(fr), 'same business-rules.json structure');
  for (const [label, pick] of [['schema', o => [o.schema, o.schemaVersion, o.disposition, o.status, o.pbi.number, o.pbi.stateSchema]], ['target', o => o.target], ['repositories', o => o.repositories.map(r => r.key + ':' + r.use)],
    ['documents', o => o.documents.map(d => [d.area, d.md, d.json, d.docx])], ['file roles', o => o.files.map(f => f.path + ':' + f.role)], ['questions', o => o.questions.map(q => q.id + ':' + q.status)],
    ['requirements', o => o.requirements], ['evidence repositories', o => o.evidence.map(e => e.id + ':' + e.repository)]]) assert.deepEqual(pick(m), pick(fm), 'golden ' + label);
  assert.deepEqual([rules.schemaVersion, rules.technicalRevalidation, rules.questions.map(q => q.status)], [fr.schemaVersion, fr.technicalRevalidation, fr.questions.map(q => q.status)]);
});

const sddRoot = [process.env.AKZO_SDD_AGENT, path.resolve(__dirname, '../../Akzo-SDD-Agent-v4.2.5-GitHub')].find(d => d && require('node:fs').existsSync(path.join(d, 'copilot/modules/investigate/scripts/akzo.ps1')));
test('the Akzo Master SDD agent imports each target\'s Refined PBI from the folder and from the ZIP (its own helper, unmodified)', { skip: sddRoot ? false : 'Akzo Master SDD agent folder not found (set AKZO_SDD_AGENT)' }, async t => {
  const w = await pbi(t), r = await w.approveJs(), s = await P.startDevelopment(w.root, w.folder, w.dir), helper = path.join(sddRoot, 'copilot/modules/investigate/scripts/akzo.ps1');
  const zipPath = path.join(w.tmp, w.name + '-final-pbis.zip'); await fs.writeFile(zipPath, Buffer.from(await P.zip(await P.developmentPackage(w.root, w.folder, r.files)).arrayBuffer()));
  const env = { ...process.env, AKZO_AGENT_HOME: path.join(w.tmp, 'sdd-home') }; delete env.PSExecutionPolicyPreference;
  const pick = (...args) => { const x = cp.spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-File', helper, 'pick', ...args], { encoding: 'utf8', env, timeout: 180000 }); assert.equal(x.status, 0, x.stderr + x.stdout); return JSON.parse(x.stdout); };
  for (const target of s.targets) for (const source of [s.source, zipPath]) {
    const p = pick('-Source', source, '-File', target.document), first = (await fs.readFile(path.join(p.item.path, 'refined-pbi.md'), 'utf8')).split('\n')[0];
    assert.equal(p.status, 'PICKED'); assert.equal(p.builder.document, target.document); assert.equal(p.item.suggestedId, '309446');
    assert.equal(first, '# Measurement validation — Refined PBI: ' + { dab: 'DAB backend', ui: 'Shared Angular UI' }[target.target]);
    const supporting = p.supporting.map(x => x.name);
    for (const n of ['business-rules.json', 'BRANCH-COVERAGE-MATRIX.md', 'HANDOFF-MANIFEST.json', 'measurement-rules.md', 'pbi-state.json']) assert.ok(supporting.includes(n), target.document + ' from ' + path.basename(source) + ': ' + n);
    assert.deepEqual(p.builder.missingAttachments, []);
  }
  // Known SDD 4.2.5 gap (consumer update needed): without -File it does not know the 5.5+ Refined-PBI names and imports the draft.
  t.diagnostic('SDD 4.2.5 pick without -File imports: ' + pick('-Source', s.source).builder.document);
});
