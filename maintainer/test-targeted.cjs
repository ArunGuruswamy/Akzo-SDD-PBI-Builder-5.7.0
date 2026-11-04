'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const P=require('./src/core.js'),shared=require('./fixtures/readiness-cases.cjs');
const {DirectoryHandle,FileHandle}=require('./fixtures/fs-handles.cjs');
const assets=JSON.parse(require('node:fs').readFileSync(path.join(__dirname,'src/assets.json'),'utf8'));

async function fixture(t){
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'akzo-targeted-'));
 t.after(()=>fs.rm(dir,{recursive:true,force:true}));
 const root=new DirectoryHandle(dir),folder='playbook/pbis/'+shared.PBI;
 await fs.mkdir(path.join(dir,'.git'));
 const {cases}=await shared.load(P),c=JSON.parse(JSON.stringify(cases.find(x=>x.name==='fully approved PBI may be finalized')));
 c.state.status='Ready for Review';c.state.approvals={user:{status:'pending'}};
 c.docs.draft=c.docs.refined.replace(/^Status:.*$/m,'Status: Ready for Review');c.docs.refined=null;
 await shared.writeCase(P,root,folder,c);
 await P.write(root,folder+'/pbi.json',JSON.stringify({number:'305974',title:'Measurement',description:'Original intake',acceptanceCriteria:'Original user criteria',wizard:{step:'source-access',status:'draft',note:'Keep original note'}}));
 return {dir,root,folder,c};
}
async function externalFixture(t){
 const f=await fixture(t),s=f.c.state;
 for(let i=1;i<=5;i++)if(!s.decisions.some(d=>d.id==='DEC-'+i))s.decisions.push({id:'DEC-'+i,pbi:s.pbi,status:'approved',decision:'Preserved decision '+i,evidence:'User supplied answer '+i});
 const gaps=['Color Measurement Service contract','Created By/Created On persistence','Instrument metadata resolution','DAB authorization policy and effective identity','Transaction and idempotency guarantees']
  .map((description,i)=>({id:'EXT-'+(i+1),classification:'EXTERNAL_DEPENDENCY',description,owner:i===3?'DAB security owner':'External dependency owner',readinessRefs:['BR-1']}));
 s.rules[0].gaps=gaps.map(g=>({id:g.id,description:g.description,status:'open',impact:'BLOCKING'}));
 s.analysis={gaps,requirementsComplete:true};
 await P.write(f.root,f.folder+'/pbi-state.json',JSON.stringify(s,null,2));
 return {...f,gaps};
}
async function packageFor(dir){
 const pkg=path.join(dir,'package');await fs.mkdir(pkg);
 await fs.copyFile(path.join(__dirname,'installer/Install-PBIBuilder.ps1'),path.join(pkg,'Install-PBIBuilder.ps1'));
 await fs.writeFile(path.join(pkg,'pbi-builder-bundle.json'),JSON.stringify(P.bundle(assets)));
 await fs.writeFile(path.join(pkg,'Akzo-SDD-PBI-Builder.html'),'<html></html>');
 return pkg;
}
function ps(pkg,dir,action,folder){
 const env={...process.env,USERPROFILE:dir};delete env.PSExecutionPolicyPreference;
 const r=cp.spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-File',path.join(pkg,'Install-PBIBuilder.ps1'),'-RepoPath',dir,'-Action',action,...(folder?['-Pbi',folder]:[]),'-Json'],{encoding:'utf8',env,timeout:120000});
 assert.ifError(r.error);assert.ok([0,3].includes(r.status),r.stdout+r.stderr);return JSON.parse(r.stdout.trim());
}

test('canonical mirrors repair drift, preserve intake, decisions and history, and are idempotent',async t=>{
 const {root,folder,c,dir}=await fixture(t),decisions=JSON.stringify(c.state.decisions),request=await P.read(root,folder+'/REQUEST.md');
 const intake=JSON.parse(await P.read(root,folder+'/pbi.json'));
 await P.write(root,folder+'/DRAFT-PBI.md','# Draft\nStatus: Development-Ready\n\n## Acceptance criteria\n\nWrong mirrored criterion\n\n## Reviewer notes\n\nKeep authored notes.\n');
 const sync=await P.synchronizePbi(root,folder);
 assert.ok(sync.changed.includes('DRAFT-PBI.md'));
 assert.equal(JSON.stringify(sync.state.decisions),decisions);
 assert.equal(await P.read(root,folder+'/REQUEST.md'),request);
 const saved=JSON.parse(await P.read(root,folder+'/pbi.json'));for(const key of ['description','acceptanceCriteria'])assert.deepEqual(saved[key],intake[key]);
 assert.equal(saved.wizard.note,intake.wizard.note);assert.notEqual(saved.wizard.status,'draft');assert.equal(saved.wizard.step,'review');
 const draft=await P.read(root,folder+'/DRAFT-PBI.md');assert.ok(draft.includes('Keep authored notes.'));assert.ok(!draft.includes('Wrong mirrored criterion'));
 for(const a of c.state.acceptanceCriteria)assert.ok(draft.includes(a.criterion.replace(/\r?\n/g,'<br>')));
 assert.equal(sync.report.issues.some(i=>/^DOC_/.test(i.code)),false);
 assert.ok((await fs.readdir(path.join(dir,folder,'history'))).length>0);
 const warm=await P.measure(()=>P.synchronizePbi(root,folder));assert.deepEqual(warm.result.changed,[]);assert.equal(warm.metrics.writes,0);
});

test('five external gaps present an interactive conditional choice, generate only after selection, and resume to owner action',async t=>{
 const {root,folder,c,gaps}=await externalFixture(t),approved=JSON.stringify(c.state.decisions);
 let run=await P.advanceWorkflow(root,folder);
 assert.equal(run.next.action,'ASK_DECISION',JSON.stringify(run.next));assert.equal(run.next.decision.recommended,'A');assert.equal(run.next.gaps.length,5);
 assert.equal(run.report.finalAllowed,false);assert.equal(JSON.stringify(run.state.decisions),approved);
 const selected=P.recordWorkflowChoice(run.state,{option:'A',by:'User'});
 await P.write(root,folder+'/pbi-state.json',JSON.stringify(selected.state,null,2));
 run=await P.advanceWorkflow(root,folder);
 assert.equal(run.next.action,'ASK_DECISION');assert.equal(run.next.conditional,true);assert.equal(run.next.finalAllowed,false);assert.ok(run.next.decision.options[0].text.includes('authorization'));
 assert.equal(run.state.analysis.conditionalPlan.verificationTasks.length,5);
 assert.ok((await P.read(root,folder+'/DRAFT-PBI.md')).includes('CONDITIONAL working draft only'));
 assert.equal(JSON.stringify(run.state.decisions),approved);
 for(const name of ['PBI-CDMS.md','PBI-DAB.md','PBI-UI.md','REFINED-PBI.md'])assert.equal(await P.read(root,folder+'/'+name),null);
 const resumed=await P.advanceWorkflow(root,folder);
 assert.equal(resumed.next.conditional,true);assert.equal(resumed.state.analysis.workflowChoices.length,1);
 assert.ok(resumed.report.issues.some(i=>i.code==='EVIDENCE_GAP'));assert.equal(resumed.state.rules[0].gaps.length,5);
 assert.equal(resumed.state.approvals.user.status,'pending');
 assert.deepEqual(resumed.state.analysis.gaps,gaps);
 const priorFingerprint=resumed.state.analysis.workflow.inputFingerprint;
 await P.write(root,folder+'/DRAFT-PBI.md',(await P.read(root,folder+'/DRAFT-PBI.md'))+'\n## Reviewer note\n\nA new supplied observation.\n');
 const changed=await P.advanceWorkflow(root,folder);
 assert.notEqual(changed.state.analysis.workflow.inputFingerprint,priorFingerprint);
});

test('conditional generation refuses missing requirements, unselected choices and uncovered readiness blockers',async t=>{
 const {root,folder,gaps}=await externalFixture(t);
 await assert.rejects(P.generateConditionalPbi(root,folder,{gaps,requirementsComplete:true}),/not authorized/);
 let raw=JSON.parse(await P.read(root,folder+'/pbi-state.json'));
 raw=P.recordWorkflowChoice(raw,{option:'A'}).state;
 await P.write(root,folder+'/pbi-state.json',JSON.stringify(raw));
 await assert.rejects(P.generateConditionalPbi(root,folder,{gaps,requirementsComplete:false}),/not authorized/);
 await assert.rejects(P.generateConditionalPbi(root,folder,{gaps:[],requirementsComplete:true}),/not authorized/);
});

test('persistent workflow detects unchanged automatic work, bounds history and applies custom/evidence responses once',()=>{
 const action={action:'AUTO_CONTINUE',stage:'IMPLEMENTATION_ANALYSIS',reason:'Investigate saved source',next:'Read the next relevant file'};
 let progress=P.recordWorkflowProgress({pbi:'305974'},action,'same');
 progress=P.recordWorkflowProgress(JSON.parse(JSON.stringify(progress.state)),action,'same');
 assert.equal(progress.next.action,'ASK_DECISION');assert.equal(progress.next.decision.allowCustom,true);
 for(let i=0;i<50;i++)progress=P.recordWorkflowProgress(progress.state,action,'new-'+i);
 assert.equal(progress.state.analysis.workflow.transitions.length,32);
 const gap={id:'EXT-1',description:'External service',classification:'EXTERNAL_DEPENDENCY'};
 let state=P.recordWorkflowChoice({pbi:'305974'},{option:'D',custom:'Ask the service owner'}).state;
 state=P.completeWorkflowChoice(state,'WF-1');
 const next=P.workflowNextAction({state,gaps:[gap],readiness:{computedStatus:'Needs Evidence',issues:[]}});
 assert.equal(next.action,'BLOCKED_EXTERNAL');assert.ok(next.decision);
 state=P.recordWorkflowChoice({pbi:'305974'},{option:'B'}).state;state=P.completeWorkflowChoice(state,'WF-1');
 assert.equal(state.analysis.externalEvidenceRequested,true);
 assert.equal(P.workflowNextAction({state,gaps:[gap],readiness:{computedStatus:'Needs Evidence',issues:[]}}).action,'BLOCKED_EXTERNAL');
 const conditional=P.workflowNextAction({state:{analysis:{conditionalPbiGenerated:true}},gaps:[gap],requirementsComplete:true,implementationPlanComplete:true,
  readiness:{computedStatus:'Draft',issues:[{code:'MISSING_COVERAGE',ref:'BR-1/negative'}]}});
 assert.equal(conditional.conditional,true);assert.ok(conditional.decision);assert.equal(conditional.remainingIssues[0].code,'MISSING_COVERAGE');
 assert.throws(()=>P.workflowNextAction({maxAutoSteps:100}),/budget/);
});

test('evidence rejects missing or unsafe dependencies, dependency-set edits, recorded revisions and repository moves',async t=>{
 const {root}=await fixture(t);
 await P.write(root,'src/A.cs','class A {}');await P.write(root,'src/B.cs','class B {}');
 await P.write(root,'.git/HEAD','a'.repeat(40));
 const entries=[
  {id:'missing',path:'src/A.cs',dependsOn:['src/Missing.cs']},
  {id:'unsafe',path:'src/A.cs',dependsOn:['../External.cs']},
  {id:'set',path:'src/A.cs',dependsOn:['src/B.cs']},
  {id:'revision',path:'src/A.cs',revision:'main abc'},
  {id:'commit',path:'src/A.cs',repositoryCommit:'a'.repeat(40)}
 ];
 await P.write(root,P.KNOWLEDGE,JSON.stringify({schemaVersion:1,entries}));
 let r=await P.refreshEvidence(root);assert.deepEqual(r.stale,['missing','unsafe']);
 const index=JSON.parse(await P.read(root,P.KNOWLEDGE));index.entries[2].dependsOn=[];index.entries[3].revision='main def';
 await P.write(root,P.KNOWLEDGE,JSON.stringify(index));await P.write(root,'.git/HEAD','b'.repeat(40));
 r=await P.refreshEvidence(root);assert.deepEqual(r.stale,['missing','unsafe','set','revision','commit']);assert.deepEqual(r.reusable,[]);
 assert.equal((await P.refreshEvidence(root)).written,false);
});

test('PowerShell and JavaScript synchronize identical mirrors and readiness without changing decisions',async t=>{
 const a=await externalFixture(t),b=await fs.mkdtemp(path.join(os.tmpdir(),'akzo-sync-ps-'));
 t.after(()=>fs.rm(b,{recursive:true,force:true}));
 a.c.state.acceptanceCriteria[0].criterion+='\nMeasurement Date & Time\nCreated By\nCreated On';
 await P.write(a.root,a.folder+'/pbi-state.json',JSON.stringify(a.c.state));
 await fs.cp(a.dir,b,{recursive:true});const pkg=await packageFor(a.dir);
 const js=await P.synchronizePbi(a.root,a.folder),powershell=ps(pkg,b,'SyncPbi',a.folder);
 assert.deepEqual(powershell.report,js.report);
 assert.equal(js.report.issues.some(i=>i.code==='DOC_CONTENT_MISMATCH'),false);
 assert.deepEqual(powershell.state.decisions,js.state.decisions);
 for(const file of ['DRAFT-PBI.md','EVIDENCE.md','DECISION-LOG.md','OPEN-QUESTIONS.md'])assert.equal(await fs.readFile(path.join(b,a.folder,file),'utf8'),await P.read(a.root,a.folder+'/'+file),file);
 assert.deepEqual(ps(pkg,b,'SyncPbi',a.folder).changed,[]);
});

test('PowerShell and JavaScript freshness agree on all dependency invalidations',async t=>{
 const a=await fixture(t),b=await fs.mkdtemp(path.join(os.tmpdir(),'akzo-fresh-ps-'));
 t.after(()=>fs.rm(b,{recursive:true,force:true}));
 await P.write(a.root,'src/A.cs','class A {}');await P.write(a.root,'src/B.cs','class B {}');
 await P.write(a.root,'.git/HEAD','b'.repeat(40));
 await P.write(a.root,P.KNOWLEDGE,JSON.stringify({schemaVersion:1,entries:[
  {id:'missing',path:'src/A.cs',dependsOn:['src/Absent.cs']},
  {id:'invalid',path:'src/A.cs',dependsOn:['../External.cs']},
  {id:'changed-set',path:'src/A.cs',dependsOn:[],dependencyHashes:{'src/B.cs':'old'}},
  {id:'revision',path:'src/A.cs',revision:'new',fingerprintedRevision:'old'},
  {id:'commit',path:'src/A.cs',repositoryCommit:'a'.repeat(40)},
  {id:'new-dependency',path:'src/A.cs',sha256:await P.hash('class A {}'),dependsOn:['src/B.cs']},
  {id:'mixed-invalid-missing',path:'src/Missing.cs',dependsOn:['../External.cs']}]}));
 await fs.cp(a.dir,b,{recursive:true});const pkg=await packageFor(a.dir);
 assert.deepEqual(ps(pkg,b,'RefreshEvidence'),await P.refreshEvidence(a.root));
 assert.deepEqual(JSON.parse(await fs.readFile(path.join(b,P.KNOWLEDGE),'utf8')),JSON.parse(await P.read(a.root,P.KNOWLEDGE)));
 assert.equal(ps(pkg,b,'RefreshEvidence').written,false);
});

test('operational workflow progress does not invalidate review snapshots; material evidence still does in both checkers',async t=>{
 const {root,dir,folder}=await fixture(t),pkg=await packageFor(dir);
 await P.synchronizePbi(root,folder);
 const before=await P.reviewFingerprint(root,folder),state=JSON.parse(await P.read(root,folder+'/pbi-state.json'));
 const progress=P.recordWorkflowProgress(state,{action:'ASK_DECISION',stage:'FINAL_REVIEW'},'input');
 await P.write(root,folder+'/pbi-state.json',JSON.stringify(progress.state));
 assert.equal(await P.reviewFingerprint(root,folder),before);
 assert.deepEqual(ps(pkg,dir,'CheckPbi',folder),await P.checkPbi(root,folder));
 progress.state.evidence[0].summary+=' Material change';
 await P.write(root,folder+'/pbi-state.json',JSON.stringify(progress.state));
 assert.notEqual(await P.reviewFingerprint(root,folder),before);
});

test('host profiles retain VS Code native Custom Response and use separate conservative Visual Studio instructions',()=>{
 const files=ide=>P.setupFiles({projectName:'Host',ide,role:'other',sources:{}},assets,'HTML').files;
 const code=files('vscode')[P.AGENT],vs=files('visualstudio')[P.AGENT];
 assert.match(code,/tools:.*vscode\/askQuestions/);assert.match(code,/VS Code profile: preserve native vscode\/askQuestions and free-text Custom Response/);
 assert.match(vs,/Visual Studio profile: no native question tool has been verified/);assert.doesNotMatch(vs,/tools:.*(?:vscode\/askQuestions|execute)/);
 for(const agent of [code,vs]){
  assert.ok(agent.slice(agent.indexOf('## Workflow router'),agent.indexOf('## Source access before analysis')).length<3500);
  assert.match(agent,/analysis\.workflow/);assert.match(agent,/-Action SyncPbi/);
 }
});

test('synchronization refuses a concurrent edit and restores earlier documents on write failure',async t=>{
 const {root,folder,dir}=await fixture(t),draft=await P.read(root,folder+'/DRAFT-PBI.md'),raw=await P.read(root,folder+'/pbi-state.json');
 const create=FileHandle.prototype.createWritable;let injected=false;
 FileHandle.prototype.createWritable=async function(){
  if(!injected&&this.path.includes(path.sep+'history'+path.sep)){
   injected=true;await fs.writeFile(path.join(dir,folder,'DRAFT-PBI.md'),'Concurrent reviewer edit');
  }
  return create.call(this);
 };
 try{await assert.rejects(P.synchronizePbi(root,folder),/changed/);}
 finally{FileHandle.prototype.createWritable=create;}
 assert.equal(await P.read(root,folder+'/DRAFT-PBI.md'),'Concurrent reviewer edit');assert.equal(await P.read(root,folder+'/pbi-state.json'),raw);
 await P.write(root,folder+'/DRAFT-PBI.md',draft);let failed=false;
 FileHandle.prototype.createWritable=async function(){
  if(!failed&&this.path===path.join(dir,folder,'EVIDENCE.md')){failed=true;throw Error('Injected mirror write failure');}
  return create.call(this);
 };
 try{await assert.rejects(P.synchronizePbi(root,folder),/Previously touched files were restored/);}
 finally{FileHandle.prototype.createWritable=create;}
 assert.equal(await P.read(root,folder+'/DRAFT-PBI.md'),draft);assert.equal(await P.read(root,folder+'/pbi-state.json'),raw);
});
