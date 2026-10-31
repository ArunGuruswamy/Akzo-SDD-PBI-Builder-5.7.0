'use strict';
const $=id=>document.getElementById(id), assets=JSON.parse($('assets').textContent);
let root=null, config=null, originalHTML='', pbiItems=[], busy=false;
function msg(s,error=false){$('message').textContent=s;$('message').classList.toggle('error',error);$('message').style.display='block';}
function tab(name){for(const b of document.querySelectorAll('nav button'))b.setAttribute('aria-selected',String(b.dataset.tab===name));for(const p of document.querySelectorAll('.panel'))p.classList.toggle('active',p.id===name);}
for(const b of document.querySelectorAll('nav button'))b.onclick=()=>tab(b.dataset.tab);
function action(id,fn){$(id).onclick=async()=>{if(busy)return;busy=true;const buttons=[...document.querySelectorAll('button')];const prior=buttons.map(b=>b.disabled);buttons.forEach(b=>b.disabled=true);try{await fn();}catch(e){msg(e.name==='AbortError'?'Cancelled. No action was completed.':e.message,true);}finally{buttons.forEach((b,i)=>b.disabled=prior[i]||!!b.dataset.blocked);busy=false;}};}
function getConfig(){return PBI.normalizeConfig({projectName:$('projectName').value,ide:$('ide').value,role:$('role').value,includeReferences:$('includeReferences').checked,sources:{legacy:$('legacyPath').value,dab:$('dabPath').value,cdms:$('cdmsPath').value,ui:$('uiPath').value},others:otherRepos()});}
function otherRepos(){return $('otherRepos').value.split(/\r?\n/).filter(l=>l.trim()).map(l=>{const i=l.indexOf('=');if(i<1)throw Error('Write each other repository as Name = path: '+l.trim());return {name:l.slice(0,i).trim(),path:l.slice(i+1).trim()};});}
function fill(c){$('projectName').value=c.projectName;$('ide').value=c.ide;$('role').value=c.role;$('includeReferences').checked=c.includeReferences;for(const key of ['legacy','dab','cdms','ui'])$(key+'Path').value=c.sources[key]==='.'?'':c.sources[key]||'';$('otherRepos').value=(c.others||[]).map(o=>o.name+' = '+o.path).join('\n');previewName();}
function previewName(){$('agentPreview').textContent='Akzo SDD PBI Builder - '+($('projectName').value.trim()||'your project');for(const key of ['legacy','dab','cdms','ui']){$(key+'Path').disabled=$('role').value===key;$(key+'Path').placeholder=$('role').value===key?'Current repository (registered as .)':'Optional repository path';}}
$('projectName').oninput=previewName;$('role').onchange=previewName;
function needRoot(){if(!root)throw Error('Choose the project folder first. If folder access is unavailable, use Download ZIP.');}
function needConfig(){if(!config)throw Error('Install the PBI Builder first, select a project that has it installed, or load its config.json for ZIP-only use.');return config;}
async function activeConfig(){needRoot();const raw=await PBI.read(root,PBI.CONFIG);if(!raw)throw Error('This selected project is not installed. Complete Project setup first.');return PBI.normalizeConfig(JSON.parse(raw));}
async function solutions(dir,prefix='',depth=0){const items=[];if(depth>2)return items;for await(const [name,h]of dir.entries()){if(h.kind==='file'&&/\.slnx?$/i.test(name))items.push(prefix+name);else if(h.kind==='directory'&&!['.git','.vs','node_modules','bin','obj','packages','playbook'].includes(name)){items.push(...await solutions(h,prefix+name+'/',depth+1));}if(items.length>=30)break;}return items.slice(0,30);}
const sessionRepos=[];
action('pick',async()=>{
 if(!window.showDirectoryPicker)throw Error('Folder access is unavailable in this browser. Open the downloaded HTML in desktop Edge or Chrome, or use Download setup ZIP.');
 const selected=await window.showDirectoryPicker({mode:'readwrite',id:'akzo-pbi-project'});
 let i=-1;for(const [n,h]of sessionRepos.entries())if(await h.isSameEntry(selected))i=n;
 if(i<0){sessionRepos.push(selected);const sel=$('recentRepos');if(sessionRepos.length===1)sel.replaceChildren();sel.add(new Option(selected.name,String(sessionRepos.length-1)));i=sessionRepos.length-1;}
 $('recentRepos').value=String(i);await openRoot(selected);
});
$('recentRepos').onchange=()=>{const h=sessionRepos[+$('recentRepos').value];if(h&&!busy)openRoot(h).catch(e=>msg(e.message,true));};
async function openRoot(selected){root=selected;config=null;pbiItems=[];$('rootConfirmed').checked=false;$('displayPath').value='';$('allowUpdates').checked=false;$('review').replaceChildren();$('promptOutput').classList.add('hidden');$('comparisonOutput').classList.add('hidden');$('existingPbi').replaceChildren(new Option('Find PBIs in this project',''));$('pbiDetails').textContent='';$('manualPbi').value='';
 const current=await PBI.read(root,PBI.CONFIG);
 if(current){config=PBI.normalizeConfig(JSON.parse(current));fill(config);}else fill({projectName:root.name,ide:'visualstudio',role:'legacy',includeReferences:false,sources:{legacy:'',dab:'',cdms:'',ui:''}});
 let installed='';try{installed=JSON.parse(await PBI.read(root,PBI.MANIFEST)||'{}').packageVersion||'';}catch{installed='unreadable';}
 $('versionBadge').textContent='PBI Builder · '+PBI.VERSION+(installed&&installed!==PBI.VERSION?' · installed '+installed:'');
 $('connectedName').textContent=root.name;$('connectedDetail').textContent=(installed?'Installed: '+installed+(installed===PBI.VERSION?' (up to date). ':'; this file installs '+PBI.VERSION+'. '):'')+(current?'Existing setup loaded. Review setup to upgrade, or use New PBI or Continue PBI.':'Folder selected. Review project settings and install the PBI Builder.');
 let git=false;try{await root.getDirectoryHandle('.git');git=true;}catch(e){if(e.name==='TypeMismatchError')git=true;else if(e.name!=='NotFoundError')throw e;}
 $('rootConfirmed').checked=git;
 const found=await solutions(root);$('solutions').textContent=(git?'Git root marker found. ':'No Git root marker found; confirm this is the correct root. ')+(found.length?'Solutions found (up to 3 folder levels):\n'+found.join('\n'):'No solution found within 3 folder levels. Open the repository folder in VS Code, or locate the correct Visual Studio solution.');
 const old=await PBI.read(root,'.github/agents/akzo-sdd-pbi.agent.md');
 msg((current?'Existing setup loaded.':'Project selected: '+root.name)+(old?'\nAn earlier PBI Builder agent exists. It will be preserved; choose the new project-specific agent name after installation.':''));
}
// Same as Install-PBIBuilder.ps1 -Action Repair: installed settings, updates allowed, edited files never overwritten.
action('repair',async()=>{const c=await activeConfig();const rows=await PBI.plan(root,PBI.setupFiles(c,assets,originalHTML).files,true);renderReview(rows);await applySetup(c,rows,true);});
// Same review, questions and messages as Show-Plan and Invoke-Install in Install-PBIBuilder.ps1.
function planText(c,rows){const counts={};rows.forEach(r=>counts[r.state]=(counts[r.state]||0)+1);return 'Repository: '+root.name+'\nAgent: '+c.agentName+'\nReview: '+Object.entries(counts).map(([k,v])=>v+' '+k).join(', ')+(counts.retire?'\nretire: unchanged earlier-version files are backed up, then removed after the new files are verified.':'')+(counts['retire-conflict']?'\nretire-conflict: edited or unowned earlier-version files are kept. Delete them yourself, or change their name: line to keep a personal copy.':'')+(counts.conflict?'\nconflict: these files differ from the installed record and are never overwritten. Restore or move them, then rerun.':'');}
async function applySetup(c,rows,allow){const plan=planText(c,rows);
 if(rows.some(r=>r.state==='conflict'))throw Error(plan+'\nResolve the conflicts above, then rerun.');
 if(!confirm(plan+'\n\nApply these changes?')){msg('Cancelled. Nothing was changed.');return false;}
 if(!allow&&rows.some(r=>r.state==='update'||r.state==='retire'))allow=confirm('Allow updates to previously installed files and retirement of unchanged earlier-version files, with backups?');
 const r=await PBI.apply(root,rows,allow);config=c;$('connectedDetail').textContent='Installed: '+c.agentName;
 msg('Setup complete: '+r.written+' files saved.'+(r.backups.length?'\nBackups: '+PBI.BASE+'/backups/':'')+(r.retired.length?'\nRetired: '+r.retired.join(', '):'')+(r.kept.length?'\nKept (edited or unowned; review and remove yourself): '+r.kept.join(', '):'')+'\nOpen this repository in '+(c.ide==='vscode'?'VS Code':'Visual Studio')+' and select '+c.agentName+' in Copilot Chat.');return true;}
// Same as Install-PBIBuilder.ps1 -Action Uninstall: unchanged installed files are backed up, then removed.
action('uninstall',async()=>{needRoot();let c=null;try{c=await activeConfig();}catch{}const rows=await PBI.uninstallPlan(root,c);renderReview(rows);
 if(!confirm('Remove the PBI Builder from '+root.name+'?\n\nRemoved (backed up first): '+rows.filter(r=>r.state==='remove').length+' unchanged files.\nKept: playbook/pbis (your PBIs and decisions), knowledge notes, backups and every file you edited.'))return msg('Cancelled. Nothing was changed.');
 const r=await PBI.uninstall(root,rows);config=null;$('connectedDetail').textContent='Not installed.';msg('Uninstalled '+r.removed.length+' files. Backups: '+r.backup+(r.kept.length?'\nKept because they were edited: '+r.kept.join(', '):''));});
function renderReview(rows){const table=document.createElement('table'),head=document.createElement('tr');for(const s of ['Action','File']){const th=document.createElement('th');th.textContent=s;head.append(th);}table.append(head);for(const row of rows){const tr=document.createElement('tr'),state=document.createElement('td'),path=document.createElement('td');state.textContent=row.state;state.className='tag '+row.state;path.textContent=row.path;tr.append(state,path);table.append(tr);}$('review').replaceChildren(table);}
async function getSetupPlan(){needRoot();if(!$('rootConfirmed').checked)throw Error('Confirm that the selected folder is the application repository root.');const entered=$('displayPath').value.trim().replace(/[\\/]+$/, '');if(entered&&entered.split(/[\\/]/).pop().toLowerCase()!==root.name.toLowerCase())throw Error('The pasted path ends in a different folder name. Select the intended repository or correct the display path. The browser-selected folder is the actual destination.');const c=getConfig();const {files}=PBI.setupFiles(c,assets,originalHTML);const rows=await PBI.plan(root,files,true);renderReview(rows);return {c,rows};}
action('preview',async()=>{const {c,rows}=await getSetupPlan();msg(planText(c,rows)+'\nPreview only. No files written.',rows.some(r=>r.state==='conflict'));});
action('install',async()=>{const {c,rows}=await getSetupPlan();if(!await applySetup(c,rows,$('allowUpdates').checked))return;showPrompt('Check the setup in Copilot','playbook/pbi-builder/',`Check this PBI Builder setup. Read ${PBI.BASE}/config.json and ${PBI.BASE}/sources.yaml. Read one relevant application source file and give its path as evidence. Report missing sources. Do not modify files.`,false);});
function download(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);}
action('setupZip',async()=>{const {config:c,files}=PBI.setupFiles(getConfig(),assets,originalHTML),map={};for(const [p,t]of Object.entries(files))map[p]=await PBI.hash(t);files[PBI.MANIFEST]=JSON.stringify({schemaVersion:1,packageVersion:PBI.VERSION,files:map},null,2)+'\n';download(PBI.zip(files),'Akzo-PBI-Setup-'+c.projectName.replace(/[^a-zA-Z0-9_-]/g,'-')+'.zip');config=c;msg('Setup ZIP prepared. This does not install files. Extract it and copy its CONTENTS into the intended repository root, comparing existing files first. Then open the application and select '+c.agentName+'.');});
action('verify',async()=>{needRoot();const raw=await PBI.read(root,PBI.MANIFEST);if(!raw)throw Error('No PBI Builder installation record found in this folder.');const m=JSON.parse(raw);if(m.schemaVersion!==1||!m.files||typeof m.files!=='object')throw Error('Unrecognized installation record.');const results=[];let bad=0;for(const [p,h]of Object.entries(m.files)){const txt=await PBI.read(root,p);const ok=txt!==null&&await PBI.hash(txt)===h;if(!ok)bad++;results.push((txt===null?'MISSING':ok?'OK':'CHANGED')+'  '+p);}msg(results.join('\n')+'\n\n'+(bad?'Review missing/changed files.':'All recorded files match.')+' This does not verify Copilot discovery, source access or AI output.',bad>0);});
$('importConfig').onchange=async e=>{if(busy)return;try{const file=e.target.files[0];if(!file)return;const c=PBI.normalizeConfig(JSON.parse(await file.text()));root=null;config=c;fill(c);$('rootConfirmed').checked=false;$('solutions').textContent='';$('connectedName').textContent=c.projectName+' (ZIP-only mode)';$('connectedDetail').textContent='Settings loaded. Files and installation have not been checked.';$('existingPbi').replaceChildren(new Option('Enter the existing folder below',''));$('pbiDetails').textContent='';$('promptOutput').classList.add('hidden');$('comparisonOutput').classList.add('hidden');msg('Settings loaded. Use Download intake ZIP or Download refinement ZIP, then extract into the same repository before sending the prompt.');}catch(e){msg('Cannot load config: '+e.message,true);}};
let step=1,draftFolder='',draftAttachments=[],currentQ=null,lastAnswered='';
const STEPS=['Requirements','Legacy repository','Development target','Review & start'],TARGET_KEYS=['cdms','dab','ui','both'],MODE_KEYS=['quick','deep','comprehensive'];
const APP_LABEL=PBI.APPLICATIONS;
const CHANGE_LABEL={new:'A new feature',enhance:'Enhances existing functionality',fix:'Fixes an existing issue',migrate:'Migrates legacy functionality',unsure:'Not sure'};
function target(){return TARGET_KEYS.find(k=>$('target-'+k).checked)||'unsure';}
function setTarget(v){for(const k of TARGET_KEYS)$('target-'+k).checked=k===v;}
function mode(){return MODE_KEYS.find(k=>$('mode-'+k).checked)||'deep';}
function setMode(v){for(const k of MODE_KEYS)$('mode-'+k).checked=k===(MODE_KEYS.includes(v)?v:'deep');}
function picked(){return [...($('attachments').files||[])];}
function intake(draft=false){const ac=$('acceptanceCriteria').value;return {title:$('pbiTitle').value,description:$('pbiDescription').value,number:$('pbiNumber').value,project:$('customProject').value.trim()||$('targetProject').value,application:target(),legacy:$('legacyRepo').value||undefined,references:pbiRefs.slice(),analysisMode:mode(),acMode:ac.trim()||!draft?'enter':'skip',acceptanceCriteria:ac,changeType:$('changeType').value,notes:$('pbiNotes').value,scope:$('pbiScope').value,attachments:picked().map(f=>f.name),businessReason:$('businessReason').value,businessExample:$('businessExample').value,businessUnit:$('businessUnit').value,draft,step:STEPS[step-1],...(draftFolder?{folder:draftFolder,existingAttachments:draftAttachments}:{})};}
function fillProjects(){const sel=$('targetProject'),cur=sel.value,opts=[new Option(config?config.projectName+' (this repository)':'This repository',config?config.projectName:'')];
 if(config)for(const k of ['legacy','dab','cdms','ui'])if(config.sources[k]&&config.sources[k]!=='.'){const v=k.toUpperCase()+' repository ('+config.sources[k]+')';opts.push(new Option(v,v));}
 sel.replaceChildren(...opts);if(opts.some(o=>o.value===cur))sel.value=cur;}
// Legacy source repositories: the configured legacy source and every other configured repository.
function legacyOptions(){if(!config)return [];const o=[];if(config.sources.legacy)o.push({key:'legacy',name:'Custom (Legacy CRM/XRM)',path:config.sources.legacy});for(const x of config.others||[])o.push({key:x.name,name:x.name,path:x.path});return o;}
function remembered(){try{return localStorage.getItem('akzo-pbi-legacy')||'';}catch{return '';}}
function fillLegacy(){const sel=$('legacyRepo'),cur=sel.value||remembered(),o=legacyOptions();
 sel.replaceChildren(...(o.length?o.map(x=>new Option(x.name+' — '+(x.path==='.'?'this repository':x.path),x.key)):[new Option('No legacy repository configured: add one in Setup','')]));
 if(o.some(x=>x.key===cur))sel.value=cur;showLegacy();}
function showLegacy(){const x=legacyOptions().find(o=>o.key===$('legacyRepo').value);$('legacyInfo').textContent=x?'Repository: '+x.name+'\nLocation: '+(x.path==='.'?'this repository ('+(root?root.name:'.')+')':x.path)+' (relative to this repository)\nNot validated in this session. Validate checks the folder name and Git root.':'Configure the legacy repository in Setup, then return here.';}
$('legacyRepo').onchange=()=>{try{localStorage.setItem('akzo-pbi-legacy',$('legacyRepo').value);}catch{}showLegacy();};
action('validateLegacy',async()=>{const x=legacyOptions().find(o=>o.key===$('legacyRepo').value);if(!x)throw Error('Choose a configured legacy repository first.');if(!window.showDirectoryPicker)throw Error('Folder access is unavailable in this browser; the agent verifies access when it reads the source.');
 const d=await window.showDirectoryPicker({mode:'read',id:'akzo-pbi-legacy'}),want=x.path==='.'?(root?root.name:''):x.path.replace(/[\\/]+$/,'').split(/[\\/]/).pop();
 let git=false;try{await d.getDirectoryHandle('.git');git=true;}catch(e){if(e.name==='TypeMismatchError')git=true;}
 if(want&&d.name.toLowerCase()!==want.toLowerCase())throw Error('The selected folder "'+d.name+'" does not match the configured path '+x.path+'. Choose that folder, or correct the path in Setup.');
 $('legacyInfo').textContent='Repository: '+x.name+'\nLocation: '+x.path+'\nValidated: folder "'+d.name+'" found'+(git?' with a Git root.':', but no .git folder: confirm it is the repository root.');msg('Legacy repository validated. Nothing was read or changed.');});
function goRepos(){tab('setup');$('repoDetails').open=true;$('legacyPath').focus();msg('Add, correct or remove repositories under "Repositories and reference documents", then click Install / update to save them. Removing one only changes the configuration; its folder is never deleted.');}
action('manageRepos',goRepos);action('fixRepos',goRepos);
// Repository roles for the chosen target, from the same rules the agent follows (PBI.TARGETS).
function showRoles(){const t=PBI.TARGETS[target()];if(!t||!t.implement.length){$('repoRoles').textContent='Choose a target to see each repository\'s role.';return;}const c=config,leg=legacyOptions().find(o=>o.key===$('legacyRepo').value);
 const role=(k,use)=>k==='legacy'?'Legacy — Business Reference':k==='ui'?'Angular UI — Shared Frontend':(k==='cdms'?'CDMS':'DAB')+(use==='implement'?' — Implementation Target':' — Reference (read-only)');
 const path=k=>k==='legacy'&&leg?leg.path:c?c.sources[k]:'';
 $('repoRoles').textContent=[...t.reference.map(k=>[k,'reference']),...t.implement.map(k=>[k,'implement'])].map(([k,use])=>role(k,use)+': '+(path(k)?path(k)==='.'?'this repository':path(k):'not configured — use Correct repository paths')).join('\n')+'\nAnalysis order: '+t.order;}
for(const k of TARGET_KEYS)$('target-'+k).onchange=()=>{showRefs();showRoles();$('targetError').textContent='';};
function reviewText(){const d=intake(true),files=[...draftAttachments.map(a=>a.name),...d.attachments],desc=d.description.trim(),leg=legacyOptions().find(o=>o.key===d.legacy);
 return ['PBI number: '+(d.number.trim()||'(missing, required)'),'PBI title: '+(d.title.trim()||'(missing, required)'),'Description: '+(desc?desc.slice(0,600)+(desc.length>600?' …':''):'(missing, required)'),'Acceptance criteria: '+(d.acceptanceCriteria.trim()?d.acceptanceCriteria.trim().split(/\r?\n/).length+' line(s), kept as entered':'(missing, required)'),'Attachments: '+(files.join(', ')||'None'),
  'Legacy repository: '+(leg?leg.name+' ('+leg.path+')':'(not selected)'),'Development target: '+APP_LABEL[d.application],$('repoRoles').textContent,'Analysis mode: '+PBI.ANALYSIS_MODES[d.analysisMode],'Additional implementation references: '+refText(),'Target project: '+(d.project||'This repository'),'Kind of change: '+(CHANGE_LABEL[d.changeType]||'Not sure')+(d.notes.trim()?'\nNotes: '+d.notes.trim():'')].join('\n');}
function showStep(n){step=Math.max(1,Math.min(STEPS.length,n));STEPS.forEach((_,i)=>{$('step'+(i+1)).classList.toggle('hidden',i+1!==step);const l=$('stepLabel'+(i+1));l.setAttribute('aria-current',i+1===step?'step':'false');l.classList.toggle('done',i+1<step);});$('wizardProgress').textContent='Step '+step+' of '+STEPS.length+' · '+STEPS[step-1];
 if(step===2)fillLegacy();if(step===3)showRoles();if(step===STEPS.length){fillProjects();$('reviewSummary').textContent=reviewText();}}
// Inline validation: each required field shows its own message; returns the first invalid step or 0.
function fieldError(id,text){$(id).setAttribute('aria-invalid',text?'true':'false');$(id+'Error').textContent=text;return !!text;}
function invalidStep(upTo){let bad=0;
 if(upTo>=1){const e=[fieldError('pbiNumber',$('pbiNumber').value.trim()?(/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/.test($('pbiNumber').value.trim())?'':'Use the Azure DevOps number or letters, digits, dots, dashes and underscores.'):'Enter the PBI number.'),fieldError('pbiTitle',$('pbiTitle').value.trim()?'':'Enter the PBI title.'),
   fieldError('pbiDescription',$('pbiDescription').value.trim()?'':'Describe the requirement.'),fieldError('acceptanceCriteria',$('acceptanceCriteria').value.trim()?'':'Enter the acceptance criteria.')];if(e.some(Boolean))bad=bad||1;}
 if(upTo>=2&&fieldError('legacyRepo',$('legacyRepo').value?'':'Choose the legacy source repository, or add one in Setup.'))bad=bad||2;
 if(upTo>=3){$('targetError').textContent=target()==='unsure'?'Choose what you are developing this PBI for.':'';if(target()==='unsure')bad=bad||3;}
 return bad;}
$('wizardNext').onclick=()=>{if(step===2&&!$('legacyRepo').options?.length)fillLegacy();const bad=invalidStep(step);if(bad===step){msg('Complete the highlighted fields to continue.',true);return;}showStep(step+1);};
$('wizardBack').onclick=()=>showStep(step-1);
$('attachments').onchange=()=>{$('attachmentList').textContent=[...draftAttachments.map(a=>a.name+' (already saved)'),...picked().map(f=>f.name+' ('+Math.max(1,Math.ceil(f.size/1024))+' KB)')].join('\n');};
$('wizardCancel').onclick=()=>{for(const id of ['pbiTitle','pbiNumber','customProject','pbiScope','pbiDescription','acceptanceCriteria','pbiNotes','businessReason','businessExample','businessUnit'])$(id).value='';$('attachments').value='';$('changeType').value='unsure';setTarget('');setMode('deep');pbiRefs=[];showRefs();draftFolder='';draftAttachments=[];$('attachmentList').textContent='';showStep(1);msg('Cleared. Nothing was saved.');};
// Additional implementation references: configured repositories the target does not already use; none, one or several.
let pbiRefs=[];
function refOptions(){let c=config;if(!c)try{c=getConfig();}catch{c=PBI.normalizeConfig({projectName:'x',role:'other'});}return PBI.referenceOptions(c,target());}
function refText(){const o=refOptions();return pbiRefs.map(k=>(o.find(x=>x.key===k)||{label:k}).label).join(', ')||'none selected';}
function showRefs(){const o=refOptions();pbiRefs=pbiRefs.filter(k=>o.some(x=>x.key===k));$('refSummary').textContent='Additional implementation references: '+refText();}
function openRefs(){const list=$('refList');list.replaceChildren(...refOptions().map(o=>{const l=document.createElement('label'),b=document.createElement('input');b.type='checkbox';b.value=o.key;b.checked=pbiRefs.includes(o.key);const t=document.createElement('span');t.textContent=o.label;l.append(b,t);return l;}));const d=$('refDialog');if(d.showModal&&!d.open)d.showModal();}
$('chooseRefs').onclick=openRefs;
$('refOk').onclick=()=>{pbiRefs=[...$('refList').children].map(l=>l.children[0]).filter(b=>b&&b.checked).map(b=>b.value);const d=$('refDialog');if(d.close)d.close();showRefs();};
showStep(1);
function showPrompt(title,folder,prompt,zipOnly){$('promptOutput').classList.remove('hidden');$('outputTitle').textContent=title;$('outputWhere').textContent=(zipOnly?'ZIP prepared for: ':'Saved in: ')+folder;$('promptText').value=prompt;$('outputInstruction').textContent=(zipOnly?'Extract this ZIP into the intended repository first. ':'')+'In Copilot Chat, select '+needConfig().agentName+', paste this prompt and click Send.';$('promptOutput').scrollIntoView({behavior:'smooth',block:'start'});}
async function createIntake(zipOnly,draft=false){const c=zipOnly?needConfig():await activeConfig();config=c;const files=picked(),data=intake(draft);
 if(!zipOnly&&!draftFolder){const existing=await PBI.listPbis(root),n=data.number.trim(),match=n&&existing.find(x=>x.number===n);
  if(match&&!$('separateDraft').checked){dupMatch={match,zipOnly,draft};$('dupText').textContent='PBI '+n+' is saved in '+match.folder+'. Resume it, review it, or start a new version in a new folder. Nothing has been saved yet.';const d=$('dupDialog');if(d.showModal&&!d.open)d.showModal();msg('PBI '+n+' already exists. Choose Resume, Review or Start New Version. Nothing was saved.');return;}}
 if(!zipOnly&&!draft&&(invalidStep(3)||!$('legacyRepo').value)){const bad=invalidStep(3)||2;showStep(bad);throw Error('Complete the required fields first. Nothing was saved.');}
 // Attachments are redacted and scanned by the core before anything is written.
 data.attachmentContent=await Promise.all(files.map(async f=>new Uint8Array(await f.arrayBuffer())));
 const result=PBI.newPbi(c,data),bytes=result.attachmentBytes;
 if(zipOnly){const all={...result.files};result.attachments.forEach((p,i)=>{all[p]=bytes[i];});download(PBI.zip(all),'PBI-'+(result.request.number||'new')+'-intake.zip');}
 else{if(draftFolder){// Updating a saved draft: earlier versions of its intake files go to history/.
   for(const f of ['REQUEST.md','pbi.json','START-PROMPT.txt']){const old=await PBI.read(root,result.folder+'/'+f);if(old!==null)await PBI.write(root,result.folder+'/history/'+f.replace(/(\.[^.]+)$/,'.'+Date.now()+'$1'),old);}
   for(const [p,t] of Object.entries(result.files))await PBI.write(root,p,t);}
  else await PBI.apply(root,await PBI.plan(root,result.files));
  for(const [i,p] of result.attachments.entries())await PBI.write(root,p,bytes[i]);}
 if(draft&&!zipOnly){draftFolder=result.folder;draftAttachments=result.request.attachments;$('attachments').value='';$('attachments').onchange();}else{draftFolder='';draftAttachments=[];}
 showPrompt(draft?'Draft saved':'Start this PBI in Copilot',result.folder,result.prompt,zipOnly);
 msg((zipOnly?'Intake ZIP prepared. It does not contain an AI-refined PBI. Extract it before sending the prompt.':draft?'Draft saved in '+result.folder+'. Resume it later with “Resume draft in New PBI” on the Continue tab, or “Resume PBI” in Copilot.':'Intake saved'+(result.attachments.length?' with '+result.attachments.length+' attachment(s)':'')+'. Copy the prompt below into the selected PBI Builder agent.')+protection(result));}
function protection(r){return (r.redactions.length?'\nSensitive values replaced with [REDACTED] before saving: '+r.redactions.map(f=>f.kind+' ('+f.count+')').join(', ')+'.':'')+(r.warnings.length?'\nInstruction-like text flagged as untrusted (kept, listed in REQUEST.md): '+r.warnings.length+' line(s).':'');}
let dupMatch=null;
function closeDup(){const d=$('dupDialog');if(d.close)d.close();const m=dupMatch;dupMatch=null;return m;}
action('dupResume',async()=>{const m=closeDup();if(!m)return;await refreshPbis();$('existingPbi').value=m.match.folder;$('existingPbi').onchange();const raw=await PBI.read(root,m.match.folder+'/pbi.json');let draft=false;try{draft=JSON.parse(raw||'{}').wizard?.status==='draft';}catch{}
 if(draft)await $('loadDraft').onclick();else{tab('continue');msg('Selected '+m.match.folder+' in Continue PBI. Describe what to continue, or use Review & approve.');}});
action('dupReview',async()=>{const m=closeDup();if(!m)return;await refreshPbis();$('existingPbi').value=m.match.folder;$('existingPbi').onchange();tab('continue');await loadReview();});
action('dupNew',async()=>{const m=closeDup();if(!m)return;$('separateDraft').checked=true;await createIntake(m.zipOnly,m.draft);});
$('dupCancel').onclick=()=>{closeDup();msg('Cancelled. Nothing was saved.');};
action('saveNew',()=>createIntake(false));action('saveDraft',()=>createIntake(false,true));action('newZip',()=>createIntake(true));
async function refreshPbis(){needRoot();config=await activeConfig();pbiItems=await PBI.listPbis(root);const select=$('existingPbi');select.replaceChildren(new Option(pbiItems.length?'Choose a PBI':'No saved PBIs found',''));for(const item of pbiItems)select.add(new Option((item.number?item.number+' · ':'')+item.title+' ['+item.folder.split('/').pop()+']',item.folder));$('pbiDetails').textContent='';msg(pbiItems.length+' PBI folders found.');}
action('refresh',refreshPbis);
$('existingPbi').onchange=()=>{const item=pbiItems.find(x=>x.folder===$('existingPbi').value);$('pbiDetails').textContent=item?item.folder+'\nDocuments present: '+(item.present.join(', ')||'Intake metadata only')+(item.metadataWarning?'\n'+item.metadataWarning:'')+'\nFile presence does not prove business approval.':'';};
async function createRefinement(zipOnly){config=zipOnly?needConfig():await activeConfig();const folder=zipOnly?($('existingPbi').value||$('manualPbi').value.trim()):$('existingPbi').value;if(!folder)throw Error(zipOnly?'Select or enter the existing PBI folder.':'Find and select an existing PBI first.');if(!zipOnly&&!(await PBI.listPbis(root)).some(x=>x.folder===folder))throw Error('The selected PBI is no longer available. Refresh the list.');const result=PBI.refinePbi(folder,$('changes').value);if(zipOnly)download(PBI.zip(result.files),'PBI-refinement.zip');else await PBI.apply(root,await PBI.plan(root,result.files));showPrompt('Continue this PBI in Copilot',result.folder,result.prompt,zipOnly);msg(zipOnly?'Refinement ZIP prepared. Extract it into the same repository before sending the prompt.':'Refinement brief saved. Existing PBI documents have not been changed by the form.');}
action('saveRefine',()=>createRefinement(false));
action('loadDraft',async()=>{config=await activeConfig();const folder=selectedPbi(),raw=await PBI.read(root,folder+'/pbi.json');if(!raw)throw Error('This PBI has no saved intake (pbi.json). Continue it in Copilot instead.');const r=JSON.parse(raw);
 if(r.wizard?.status!=='draft')throw Error('This PBI was already sent for analysis. Continue or refine it instead; its original request is kept unchanged.');
 const v=(id,x)=>{$(id).value=typeof x==='string'?x:'';};v('pbiTitle',r.title);v('pbiNumber',r.number);v('pbiDescription',r.description);v('acceptanceCriteria',r.acceptanceCriteria);v('pbiNotes',r.notes);v('pbiScope',r.scope);v('businessReason',r.businessReason);v('businessExample',r.businessExample);v('businessUnit',r.businessUnit);
 $('changeType').value=CHANGE_LABEL[r.changeType]?r.changeType:'unsure';setTarget(r.application);setMode(r.analysisMode);fillLegacy();if(r.legacy?.key&&legacyOptions().some(o=>o.key===r.legacy.key))$('legacyRepo').value=r.legacy.key;pbiRefs=Array.isArray(r.references)?r.references.map(String):[];showRefs();
 draftFolder=folder;draftAttachments=Array.isArray(r.attachments)?r.attachments:[];tab('new');showStep(1);
 if([...$('targetProject').children].some(o=>o.value===r.project))$('targetProject').value=r.project;else v('customProject',r.project===config.projectName?'':r.project);
 $('attachments').value='';$('attachments').onchange();showStep(Math.max(1,STEPS.indexOf(r.wizard.step)+1));msg('Draft loaded from '+folder+'. Saving updates this folder; earlier versions go to its history folder.');});
async function stateOf(folder){const raw=await PBI.read(root,folder+'/pbi-state.json');if(raw===null)throw Error('This PBI has no pbi-state.json yet. Start the analysis in Copilot first.');try{return JSON.parse(raw);}catch{throw Error('pbi-state.json is not valid JSON. Ask the agent to repair it.');}}
async function loadQuestion(id){needRoot();const s=await stateOf(selectedPbi()),p=PBI.questionProgress(s),q=id?(s.questions||[]).find(x=>x&&x.id===id):p.next;
 if(!q){currentQ=null;$('questionBox').classList.add('hidden');return 'No unresolved business questions: '+p.answered+' of '+p.total+' answered'+(p.deferred.length?'; decide later: '+p.deferred.join(', '):'')+'.';}
 currentQ=q;$('questionBox').classList.remove('hidden');
 $('questionProgress').textContent=(id?'Editing your answer to ':'Question '+(p.answered+1)+' of '+p.total+' · ')+q.id+(q.blocking===true?' · required':' · optional');
 $('questionText').textContent=q.question||'(no question text recorded)';$('questionWhy').textContent=[q.why,q.example&&'Example: '+q.example].filter(Boolean).join('\n')||'Not recorded.';
 const opts=(Array.isArray(q.options)?q.options:[]).filter(o=>o&&o.key).map(o=>new Option(o.key+'. '+o.text+(q.recommended===o.key?' (recommended)':''),o.key));$('answerOption').replaceChildren(...opts,new Option('Custom answer','custom'));
 $('answerOption').value=q.answer?.option||(opts.some(o=>o.value===q.recommended)?q.recommended:opts[0]?opts[0].value:'custom');$('customAnswer').value=q.answer?.option==='custom'?q.answer.text:'';return '';}
action('loadQuestions',async()=>{const info=await loadQuestion();msg(info||'Choose an answer, or enter a custom one, and submit.');});
action('submitAnswer',async()=>{if(!currentQ)throw Error('Load the questions first.');const id=currentQ.id,r=await PBI.recordAnswer(root,selectedPbi(),id,{option:$('answerOption').value,custom:$('customAnswer').value,by:$('answeredBy').value});lastAnswered=id;
 const info=await loadQuestion();msg('Saved '+r.decision.id+' for '+id+(r.decision.supersedes?' (replaces '+r.decision.supersedes+')':'')+'. '+info);});
action('skipQuestion',async()=>{if(!currentQ)throw Error('Load the questions first.');const id=currentQ.id,req=currentQ.blocking===true;await PBI.recordSkip(root,selectedPbi(),id);const info=await loadQuestion();msg(id+' set to decide later'+(req?'; it is required, so the PBI is not Development-Ready until it is answered':'')+'. '+info);});
action('editPrevious',async()=>{needRoot();const p=PBI.questionProgress(await stateOf(selectedPbi())),prev=lastAnswered||p.answeredQuestions.filter(q=>q.answeredAt).sort((a,b)=>String(a.answeredAt).localeCompare(String(b.answeredAt))).map(q=>q.id).pop();
 if(!prev)throw Error('No answered question to edit yet.');await loadQuestion(prev);msg('Change the answer and submit. The earlier decision is kept as superseded.');});
action('showDecisions',async()=>{needRoot();const d=PBI.questionProgress(await stateOf(selectedPbi())).decisions;msg(d.length?d.map(x=>x.id+' · '+(x.status||'?')+(x.supersedes?' · replaces '+x.supersedes:'')+(x.decision?'\n  '+x.decision:'')+(x.evidence?'\n  '+x.evidence:'')).join('\n'):'No decisions recorded for this PBI yet.');});action('refineZip',()=>createRefinement(true));
action('copyPrompt',async()=>{try{await navigator.clipboard.writeText($('promptText').value);msg('Prompt copied. Paste it into your project’s PBI Builder in Copilot Chat.');}catch{$('promptText').focus();$('promptText').select();msg('Automatic clipboard access is unavailable. The prompt is selected: press Ctrl+C to copy.');}});
$('versionBadge').textContent='PBI Builder · '+PBI.VERSION;
document.addEventListener('DOMContentLoaded',()=>{originalHTML='<!doctype html>\n'+document.documentElement.outerHTML;previewName();if(!window.showDirectoryPicker)msg('Folder access is not available here. Open this downloaded file in desktop Edge or Chrome, or use the ZIP fallback.',true);});

async function createComparison(zipOnly){
 const c=zipOnly?needConfig():await activeConfig();
 if(!zipOnly&&!(await PBI.read(root,PBI.AGENT)))throw Error('Install the version '+PBI.VERSION+' setup first so the current agent is available.');
 config=c;
 const result=PBI.comparison(c,{title:$('comparisonTitle').value,description:$('comparisonDescription').value},$('comparisonBaseline').value);
 if(zipOnly)download(PBI.zip(result.files),'Akzo-PBI-'+result.id+'.zip');
 else await PBI.apply(root,await PBI.plan(root,result.files));
 $('comparisonOutput').classList.remove('hidden');
 $('comparisonWhere').textContent=result.reportFolder;
 $('comparisonNext').textContent=zipOnly?'ZIP prepared only. Extract it into the project with version '+PBI.VERSION+' installed before sending these prompts. It includes the baseline agent.':'Both original requests and the '+PBI.BASELINES[result.baseline].label+' baseline agent are saved. Start separate new chats and use the exact agent names below. Remove comparison agents after the trial.';
 for(const r of result.runs){$(r.profile+'Name').textContent=r.agentName;$(r.profile+'Prompt').value=r.prompt;}
 msg(zipOnly?'Comparison ZIP prepared. No AI tasks have run.':'Comparison ready. No AI tasks have run and no savings have been measured.');
 $('comparisonOutput').scrollIntoView({behavior:'smooth',block:'start'});
}
action('saveComparison',()=>createComparison(false));
action('comparisonZip',()=>createComparison(true));
async function copyComparison(profile){const el=$(profile+'Prompt');try{await navigator.clipboard.writeText(el.value);msg('Prompt copied. Start a new Copilot chat and select '+$(profile+'Name').textContent+'.');}catch{el.focus();el.select();msg('Press Ctrl+C to copy the selected prompt.');}}
action('copyBaseline',()=>copyComparison('baseline'));
action('copyCurrent',()=>copyComparison('current'));
action('cleanupComparison',async()=>{needRoot();const r=await PBI.cleanupComparison(root,await activeConfig());msg((r.removed.length?'Removed: '+r.removed.join(', '):'No unchanged comparison agents found.')+(r.kept.length?'\nKept because they were edited: '+r.kept.join(', '):'')+'\nTrial folders and results are kept.');});
function selectedPbi(){const folder=$('existingPbi').value||$('manualPbi').value.trim();if(!folder)throw Error('Find and select an existing PBI first.');return folder;}
action('exportHandoff',async()=>{needRoot();const r=await PBI.exportHandoff(root,selectedPbi()),h=r.handoff;msg('Wrote '+r.files.join(' and ')+'\nReadiness: '+r.report.computedStatus+' · rules: '+h.rules.length+' · branches: '+h.rules.reduce((n,x)=>n+x.branches.length,0)+' · open gaps: '+h.gaps.length+'\nGive business-rules.json to the development agent. Earlier exports were copied to history/.');});
action('checkReadiness',async()=>{needRoot();const r=await PBI.checkPbi(root,selectedPbi());msg('Readiness for '+r.pbi+'\nComputed status: '+r.computedStatus+(r.claimedStatus?' (claimed: '+r.claimedStatus+')':'')+'\nFinal PBIs allowed: '+(r.finalAllowed?'yes':'no')+'\n\n'+(r.issues.map(x=>'['+x.cap+'] '+x.code+' '+x.ref+': '+x.message).join('\n')||'No issues found.')+(PBI.READINESS.statuses.indexOf(r.computedStatus)>=3?'\n\nApproval basis (the final approval is recorded by Review & approve; give the agent a block only for an external PO/BA or technical approval it records):\n'+Object.entries(r.review).map(([k,v])=>k+' (fingerprint '+v.fingerprint+'): '+JSON.stringify(v.basis)).join('\n'):'')+'\n\nThis checks completeness and consistency only, not business correctness or who approved.',!r.finalAllowed);});
action('discoverSources',async()=>{needRoot();const m=await PBI.discoverSources(root,needConfig());msg(['Wrote '+PBI.SOURCE_MAP.replace('source-map.json','SOURCE-MAP.md')+' ('+m.filesScanned+' files scanned'+(m.truncated?', stopped early':'')+').','Solutions: '+m.solutions.length+' · projects: '+m.projects.length,...m.sources.map(s=>s.key+': '+s.status+(s.checkedFile?' (read '+s.checkedFile+')':s.reason?' ('+s.reason+')':''))].join('\n'),m.sources.some(s=>s.status==='configured-inaccessible'));});
action('refreshEvidence',async()=>{needRoot();const r=await PBI.refreshEvidence(root);msg(r.checked||r.skipped.length?'Checked '+r.checked+' evidence entries. Newly fingerprinted: '+r.fingerprinted.length+'. Stale: '+(r.stale.join(', ')||'none')+'.'+(r.skipped.length?' Outside this repository (not fingerprinted): '+r.skipped.join(', ')+'.':'')+(r.written?' Index updated.':' No changes.'):'No evidence index found at '+PBI.KNOWLEDGE+'. The agent creates it when it records reusable knowledge.',r.stale.length>0);});

// ---- Review & approve: one final approval, generation and downloads ----
let reviewing=null;
const DOC_LABEL={'PBI-CDMS.md':'CDMS backend PBI','PBI-DAB.md':'DAB backend PBI','PBI-UI.md':'Shared Angular UI PBI','REFINED-PBI.md':'Refined PBI'};
function card(title,text,cls){const sec=document.createElement('section'),h=document.createElement('h4'),p=document.createElement('p');h.textContent=title;p.textContent=text;if(cls)p.className=cls;sec.append(h,p);return sec;}
async function loadReview(){needRoot();const folder=selectedPbi(),r=await PBI.checkPbi(root,folder,true),cr=await PBI.contentReview(root,folder);
 // A credential in a working document blocks approval; instruction-like text is shown, never removed.
 const blockers=[...PBI.approvalBlockers(r),...cr.blocking.map(s=>({code:'SENSITIVE_DATA',ref:s.path,message:s.kind+' ('+s.count+'). Ask the agent to replace it with [REDACTED: '+s.kind+'].'}))];
 let st={},req={};try{st=JSON.parse(await PBI.read(root,folder+'/pbi-state.json')||'{}')||{};}catch{}try{req=JSON.parse(await PBI.read(root,folder+'/pbi.json')||'{}')||{};}catch{}
 const L=x=>Array.isArray(x)?x.filter(y=>y&&typeof y==='object'):[],codes=new Set(r.issues.map(i=>i.code)),t=PBI.TARGETS[req.application]||PBI.TARGETS.unsure,applies=k=>st.paths?.[k]?.applies===true;
 const reqIssues=r.issues.filter(i=>/^(NO_RULES|NO_ACS|CONTENT_MISSING|MISSING_COVERAGE|AC_|RULE_INCOMPLETE)/.test(i.code));
 const ev=L(st.evidence),lv=['code','registration','reach','runtime'].map(l=>ev.filter(e=>e.level===l).length+' '+l).join(', ');
 const owned=k=>L(st.rules).filter(x=>x.paths?.[k]&&x.paths[k].status!=='not-applicable').length;
 const q=L(st.questions),open=q.filter(x=>x.blocking===true&&!['resolved','answered','approved','not-applicable','superseded'].includes(x.status));
 reviewing={folder,req,st,check:r,blockers};
 $('reviewCards').replaceChildren(
  card('PBI',(req.number?'PBI '+req.number+' · ':'')+(req.title||st.pbi||folder)+'\n'+folder+'\nDevelopment target: '+(PBI.APPLICATIONS[req.application]||'Not recorded')),
  card('Requirements and acceptance criteria',L(st.rules).length+' business rules · '+L(st.acceptanceCriteria).length+' acceptance criteria\n'+(reqIssues.length?'Incomplete: '+reqIssues.map(i=>i.code+' '+i.ref).join(', '):'Complete: every rule has its required criteria.'),reqIssues.length?'bad':'good'),
  card('Repository analysis','Legacy: '+(req.legacy?req.legacy.name+' ('+req.legacy.path+')':'not recorded')+'\nAnalysis mode: '+(PBI.ANALYSIS_MODES[req.analysisMode]||'Deep')+'\nPaths in scope: '+(Object.keys(st.paths||{}).filter(applies).join(', ')||'none')+'\nEvidence: '+ev.length+' records ('+lv+')'),
  card('Implementation approach',(t.implement.length?t.implement.map(k=>(k==='ui'?'Shared Angular UI':k.toUpperCase())+': '+(applies(k)?owned(k)+' rule(s)':'not applying ('+(st.paths?.[k]?.reason||'no reason')+')')).join('\n')+'\nDeliverables: '+t.documents.filter(n=>applies({'PBI-CDMS.md':'cdms','PBI-DAB.md':'dab','PBI-UI.md':'ui'}[n])).join(', '):'No development target recorded: one REFINED-PBI.md.')),
  card('Business decisions',L(st.decisions).filter(d=>d.status==='approved').length+' approved decision(s)\n'+(open.length?'Open blocking questions: '+open.map(x=>x.id).join(', '):'No open blocking questions')+(q.some(x=>x.status==='deferred')?'\nDecide later: '+q.filter(x=>x.status==='deferred').map(x=>x.id).join(', '):''),open.length?'bad':'good'),
  card('Untrusted content and sensitive data',(cr.secrets.length?'Values that look like credentials: '+cr.secrets.map(s=>s.path+': '+s.kind+' ('+s.count+')').join(', '):'No credentials detected.')+'\n'+(cr.instructions.length?'Instruction-like text (untrusted, not followed):\n'+cr.instructions.slice(0,8).map(w=>'- '+w.source+':'+w.line+' '+w.kind+': "'+w.text+'"').join('\n')+(cr.instructions.length>8?'\n… and '+(cr.instructions.length-8)+' more':''):'No instruction-like text detected.')+(cr.unscanned.length?'\nNot scanned (binary or large): '+cr.unscanned.join(', '):''),cr.blocking.length||cr.instructions.length?'bad':'good'),
  card('Technical readiness','Status: '+r.computedStatus+'\n'+(blockers.length?blockers.map(i=>'['+i.code+'] '+i.ref+': '+i.message).join('\n'):'No blockers. Your approval is the only step left.'+(codes.has('APPROVAL_STALE')?' The earlier approval is stale because the content changed.':'')),blockers.length?'bad':'good'));
 $('approveBox').classList.remove('hidden');$('approveGenerate').dataset.blocked=blockers.length?'1':'';$('approveGenerate').disabled=blockers.length>0;
 msg(blockers.length?'Not ready for approval: '+blockers.length+' blocker(s) are listed under Technical readiness. Request Changes sends them to the agent.':'Ready for your approval. Approve & Generate records it and generates the final PBIs.',blockers.length>0);}
action('loadReview',loadReview);
function needReview(){if(!reviewing||reviewing.folder!==selectedPbi())throw Error('Review the selected PBI first.');return reviewing;}
action('approveGenerate',async()=>{const v=needReview();if(v.blockers.length)throw Error('Resolve the blockers under Technical readiness first.');if(!$('approverName').value.trim())throw Error('Enter your name to approve.');
 const r=await PBI.approveAndGenerate(root,v.folder,$('approverName').value);await refreshPbis();$('existingPbi').value=v.folder;await loadReview();showDone(r,v.req);});
action('requestChanges',async()=>{const v=needReview(),note=$('reviewNote').value.trim();if(!note)throw Error('Describe the changes you request.');
 const result=PBI.refinePbi(v.folder,'Change requested at Review & approve:\n'+note+(v.blockers.length?'\n\nOpen blockers:\n'+v.blockers.map(i=>'['+i.code+'] '+i.ref+': '+i.message).join('\n'):''));await PBI.apply(root,await PBI.plan(root,result.files));
 showPrompt('Request changes in Copilot',result.folder,result.prompt,false);msg('Change request saved. Nothing was approved. Send the prompt to the agent, then review again.');});
action('saveReviewDraft',async()=>{const v=needReview(),path=v.folder+'/history/REVIEW-'+new Date().toISOString().replace(/[-:TZ.]/g,'')+'.md';
 await PBI.write(root,path,PBI.redactSecrets('# Review saved as draft (not approved)\n\nReviewer: '+($('approverName').value.trim()||'not given')+'\n\n'+[...$('reviewCards').children].map(x=>'## '+x.children[0].textContent+'\n\n'+x.children[1].textContent).join('\n\n')+'\n\n## Note\n\n'+($('reviewNote').value.trim()||'None')+'\n').text);
 msg('Saved as draft in '+path+'. Nothing was approved.');});
async function saveFile(blob,name){if(window.showSaveFilePicker){try{const h=await window.showSaveFilePicker({suggestedName:name}),w=await h.createWritable();await w.write(blob);await w.close();msg('Saved '+name+'.');return;}catch(e){if(e.name==='AbortError'){msg('Download cancelled.');return;}throw e;}}download(blob,name);msg('Downloaded '+name+'.');}
// Every download is read back from the generated file and checked against the hash recorded at generation.
async function generated(name){const x=done.files.find(f=>f.name===name);if(!x)throw Error('Not generated: '+name);const b=await PBI.readBytes(root,x.path);if(b===null||await PBI.hashBytes(b)!==x.sha256)throw Error(name+' is missing or changed since it was generated. Generate again from Review & approve.');return b;}
const MIME={md:'text/markdown',json:'application/json',docx:'application/vnd.openxmlformats-officedocument.wordprocessingml.document'};
let done=null;
function showDone(r,req){done=r;const list=$('doneList');
 $('doneSummary').textContent=(req.number?'PBI '+req.number+' · ':'')+(req.title||r.folder)+'\nStatus: '+r.check.computedStatus+' · '+r.documents.length+' PBI(s) generated and verified.';
 list.replaceChildren(...r.documents.map(doc=>{const row=document.createElement('div'),t=document.createElement('strong');row.className='doc-row';t.textContent=(DOC_LABEL[doc]||doc)+' ('+doc+')';row.append(t);const base=doc.replace(/\.md$/,'');
  for(const [kind,label] of [['docx','Download DOCX'],['md','Download MD'],['json','Download JSON'],['preview','Preview']]){const b=document.createElement('button');b.className='secondary';b.textContent=label;
   b.onclick=async()=>{try{if(kind==='preview'){const p=$('donePreview');p.textContent=new TextDecoder().decode(await generated(doc));p.classList.remove('hidden');return;}const n=base+'.'+kind;await saveFile(new Blob([await generated(n)],{type:MIME[kind]}),n);}catch(e){msg(e.message,true);}};row.append(b);}
  return row;}));
 $('donePath').textContent='Saved in '+r.folder+' in the selected repository. Browsers cannot open File Explorer; open this folder from your editor.';$('donePreview').classList.add('hidden');
 const d=$('doneDialog');if(d.showModal&&!d.open)d.showModal();msg('PBI generated successfully: '+r.documents.join(', ')+' (with DOCX and JSON). Every file was verified.');}
action('downloadAll',async()=>{if(!done)throw Error('Generate the final PBIs first.');const files={};
 for(const x of done.files)files[x.name]=await generated(x.name);
 for(const n of ['REQUEST.md','pbi.json','pbi-state.json','DRAFT-PBI.md','DECISION-LOG.md','EVIDENCE.md','VALIDATION-MATRIX.md','OPEN-QUESTIONS.md']){const b=await PBI.readBytes(root,done.folder+'/'+n);if(b!==null)files['supporting/'+n]=PBI.cleanAttachment(n,b).bytes;}
 await saveFile(PBI.zip(files),done.folder.split('/').pop()+'-final-pbis.zip');});
$('doneClose').onclick=()=>{const d=$('doneDialog');if(d.close)d.close();};
