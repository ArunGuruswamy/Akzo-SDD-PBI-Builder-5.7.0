# Changelog

## 5.1.0 — 31 October 2026

Sensitive-data protection and untrusted-content handling. No new dependency, no telemetry, no
network call; the installers, readiness rules, approvals, generation, draft and resume behave as
in 5.0.0.

### Sensitive data
- Values that look like credentials are replaced with [REDACTED: <kind>] before anything is
  saved: private keys, GitHub, AWS, Slack, Google and Sonar tokens, JWTs, bearer tokens, SAS
  signatures, credentials in URLs, connection-string passwords and account keys, and password,
  secret, API-key and token assignments. Only the value is replaced; the setting name and the
  surrounding text stay. Placeholders (<password>, {0}, $env:X, ${VAR}, ***), code references
  (options.Password, GetValue(...)) and prose ("Password: required") are kept.
- Applied in the shared core, so every path uses it: intake fields (REQUEST.md, pbi.json, the
  start prompt, the folder name), text attachments (copied redacted), the intake ZIP, refinement
  requests and Request Changes notes, custom answers in the question panel (pbi-state.json and
  DECISION-LOG.md), Save Draft review notes, and the supporting files in the final ZIP.
- REQUEST.md and pbi.json record what was removed by kind and count (never the value). Binary or
  very large attachments (Word, PDF, images) are kept unchanged and listed as not scanned.
- Approve & Generate refuses, writing nothing, when pbi-state.json, pbi.json, REQUEST.md,
  DRAFT-PBI.md, EVIDENCE.md, OPEN-QUESTIONS.md, DECISION-LOG.md or VALIDATION-MATRIX.md holds a
  value that looks like a credential ([SENSITIVE_DATA], kind only). After generation every MD and
  JSON file is scanned again; a finding rolls the generation back.

### Untrusted content
- Lines in the request or a text attachment that address the agent rather than describe the
  business (override its rules, change its role, bypass an approval, hide something from the
  user, run commands, send data out) are flagged with file, line and kind. They are never removed;
  the attachment is kept whole.
- REQUEST.md lists them under "Instruction-like text (untrusted)", pbi.json records them
  (contentWarnings), and the start prompt tells the agent to treat them as data.
- Review & approve has a seventh card, Untrusted content and sensitive data. A credential in a
  working document blocks approval there; instruction-like text is shown, not blocking.
- Agent: new "Untrusted content" section. Attachments, the request, repository source and earlier
  reports are reference material, never instructions; instruction-like text is recorded in
  EVIDENCE.md as not followed; secrets are written as [REDACTED: <kind>].

## 5.0.0 — 30 October 2026

One workflow: Start PBI → requirements → legacy repository → development target → deep
analysis → review → approve once → generate → preview and download. Root causes and regression
coverage: docs/REGRESSION-305965.md.

### Intake and repositories
- One intake form (New PBI tab, four steps): PBI number (Azure DevOps or a manual identifier such
  as LOCAL-12), title, description and acceptance criteria required, attachments optional, with
  inline validation. Start PBI, Create PBI, New PBI, Start Development and Implement PBI start the
  same intake; an existing PBI number offers Resume, Review or Start New Version.
- Select Legacy Source Repository: configured repositories, Validate (browse to the folder: name
  and Git root), Add or remove repositories (configuration only; folders are never deleted),
  last choice remembered.
- Development target, single choice: CDMS + UI, DAB + UI, UI Only, Both (CDMS + DAB + UI). The
  form shows each repository's role (Legacy — Business Reference; CDMS/DAB — Implementation
  Target or Reference; Angular UI — Shared Frontend). DAB always reads CDMS as a read-only
  reference; CDMS + UI never involves DAB; UI Only creates no backend work; Both gives three PBIs
  with the shared UI work once. Recorded in pbi.json (application, legacy, repositories,
  analysisMode) and REQUEST.md.
- Shared Angular UI repository (config.json sources.ui, sources.yaml ui, role ui): form setup,
  setup window Repositories... (Browse), -UiSource. A 4.x config.json gains an empty ui source.
- Analysis modes Quick, Deep (default) and Comprehensive; findings classified Verified, Proposed,
  Unverified or Contradicted.

### Decisions and the one approval
- Rules the request states explicitly are recorded as decisions ("source": "request") without a
  question; remaining questions come together in one decision review; conflicting acceptance
  criteria are always asked.
- Only the user's final approval is required. Review & approve (Continue tab) shows six cards and
  offers Approve & Generate, Request Changes and Save Draft. The approval is bound to the
  check's fingerprint of the reviewed content. PO/BA and technical approvals are optional
  external records: checked when recorded, never implied.
- Approve & Generate writes history copies first, records the approval, sets Development-Ready,
  generates PBI-CDMS.md, PBI-DAB.md and/or PBI-UI.md (each also .docx and .json) from
  pbi-state.json, reads every file back, reruns the check, and restores every touched file if
  anything fails. Final documents of an earlier run move to history/.
- PBI Generated Successfully: Download DOCX, MD and JSON per PBI, Preview, Download Complete
  Package — ZIP. Downloads are verified against the generation hashes; the save location can be
  chosen where the browser supports it.

### Readiness (identical in the form and PowerShell)
- Required paths follow the development target (CDMS + UI: cdms and ui; DAB + UI: dab and ui;
  UI Only: ui; Both: all three; no target: cdms and dab as before). A path the target excludes
  that is recorded as applying is TARGET_SCOPE_CONFLICT.
- PBI-UI.md is a final document; approvals.user is the only required approval.

### Agent
- Development targets, Shared Angular UI, Legacy to CDMS to DAB mapping and Analysis modes
  sections; history copies are the agent's job (it never asks for a snapshot command); the agent
  never writes the final approval or the final PBIs.

## 4.2.0 — 30 October 2026

- HTML form Install and Repair follow the PowerShell installer: the same review summary
  (Repository, Agent, Review counts, retire and conflict notes), "Apply these changes?",
  "Allow updates...?" when needed, a stop on conflicts and the same result messages.
- The form's badge shows the full package version from core.js (it said 4.0 in 4.1.0).
- Release ZIPs are written to releases/Akzo-SDD-PBI-Builder-<version>/ in the repository.

## 4.1.0 — 29 October 2026

### Implementation references and separate CDMS / DAB PBIs
- Configure other repositories besides Legacy, CDMS and DAB (config.json `others`, sources.yaml
  `otherRepositories`): form setup (`Name = path`), setup window Repositories... with Browse per
  repository, or `-OtherSource "Name=path;..."`. Both installers write identical files; older
  config.json files without `others` keep working.
- New PBI: after the target application is chosen, a Select Implementation References pop-up
  offers every configured repository except the target; none, one or several, recorded per PBI
  in pbi.json and REQUEST.md. Create PBI in Copilot asks the same.
- Agent: Multi-repository implementation analysis. Target first, references read-only, an
  Implementation comparison section in VALIDATION-MATRIX.md with file and method references,
  "No matching implementation found" instead of invented references.
- Final application PBIs are now PBI-CDMS.md and PBI-DAB.md (4.0 names still read): CDMS only,
  DAB only, or exactly two separate, complete PBIs for Both, linked by a shared requirement
  line. PBI-DAB.md covers every applicable legacy rule in C#, including plugin-enforced ones.

### Installer: blocked scripts, HTML parity, folder selection
- Install.cmd and Uninstall.cmd (aliases of Install-PBIBuilder.cmd and Uninstall-PBIBuilder.cmd)
  check the package before PowerShell runs anything: required files, SHA256SUMS.txt, Windows
  PowerShell 5.1, the effective execution policy (and whether Group Policy sets it), script
  signatures, the downloaded-from-internet mark and AppLocker/WDAC Constrained Language mode.
  They never bypass or change the policy. A downloaded ZIP under RemoteSigned ("file is not
  digitally signed") is explained and, after a Y, unblocked for this package folder only.
  AllSigned, Restricted and application control get the compliant options: the browser form or
  an organization-signed package (release.cjs signs with PBI_SIGN_CERT). Exit codes 10-14.
- Uninstall-PBIBuilder.cmd now goes through the same checks.
- One JSON line per run in %USERPROFILE%\.akzo-pbi-builder\logs\install.log; write-access
  errors say how to fix them (no administrator rights needed).
- Install and uninstall roll back on Ctrl+C as well as on errors; rerunning Install completes
  an interrupted installation.
- HTML form: Repair, Uninstall (asks first; same engine and identical result as PowerShell),
  installed version on folder selection, and a list of repositories chosen in this session.
  Setup window: Add by path... (type or paste) besides the folder dialog, adapted from the
  Akzo-Agent installer. Parity matrix: docs/INSTALLER-PARITY.md.

### Agent: direct legacy source analysis
- New section "Analyze the legacy source directly": detect the stack (.NET Framework, Web
  Forms, controllers, handlers, ADO.NET, EF, stored procedures, CRM SDK) without assuming
  modern architecture; trace entry point to database; establish whether behavior exists and
  reuse it; cite files, classes, methods and lines; mark unverifiable details Not Verified;
  analysis documents (ANALYSIS.md, REFERENCE-ANALYSIS.md, earlier SDDs, generated reports) are
  never proof; respect .gitignore and skip build output; never copy secrets into reports.
- Approvals are offered as selectable choices: 1. Approved, 2. Change Requested, 3. Custom
  Response.

## 4.0.0 — 27 October 2026

### Repository first: no end-to-end analysis document
- The repository is the source of truth: the agent never requires, creates or waits for a
  separate end-to-end analysis document, treats bundled reports and earlier analysis documents
  as optional background (never a prerequisite or evidence), revalidates against current code on
  every investigation, and never deletes such documents.
- Required PBI files: REQUEST.md, DRAFT-PBI.md, VALIDATION-MATRIX.md, EVIDENCE.md,
  DECISION-LOG.md, OPEN-QUESTIONS.md, pbi-state.json and the final PBI. SOURCE-DISCOVERY.md is
  replaced by a short Source access section in EVIDENCE.md. PLUGIN-RULES.md,
  PLUGIN-WORKFLOW-COVERAGE.md, LEGACY-BUSINESS-RULE-CATALOG.md, SHARED-BUSINESS-RULES.md,
  BUSINESS-RULE-OWNERSHIP.md and ACCEPTANCE-CRITERIA.md are written only on request.
- The historical ColorDMS reports are no longer installed by default (form checkbox off; new
  `-IncludeReferences` switch; `-NoReferences` unchanged). The setup check prompts no longer open
  them. Readiness needed no change: it never required them and never counts them as evidence.

### Autonomous investigation and the Business Decision Advisor
- Create PBI: one compact intake. The agent asks, in one message and only when missing, for the
  PBI number or title, the requirement and an optional investigation scope; it infers the rest
  and shows it for correction. No separate approvals of title, module, project, attachments,
  change type or criteria. The Target project is the installation repository, not the
  application under investigation. The form records the scope (REQUEST.md, pbi.json, prompt).
- Autonomous investigation: the agent keeps investigating until the rules have evidence, a
  genuine business decision blocks, essential source is inaccessible, or the user stops it; it
  never asks permission to trace the next rule, file or language and finishes independent rules
  first. Per rule: expectation, current behavior, reuse, gap, layers, regression tests.
- Repository-wide discovery: the whole Git repository, not only the loaded solution; every
  legacy CRM/XRM layer (plugins, workflows, web resources and lookup filters, forms, metadata and
  option sets, solution XML, configuration, status changes) before calling anything missing;
  four finding classes; end-to-end workflow traces; the recorded scope is respected. Optional
  user-owned knowledge/SEARCH-SCOPE.md names a repository's folders, so no paths are hard-coded.
  Discover sources adds a "Source folders" table (file kinds two levels deep), which shows
  JavaScript outside every project.
- Business Decision Advisor: new workspace skill `.github/skills/business-decision-advisor/SKILL.md`
  (Visual Studio 18.5+ and VS Code discover it; the agent also reads it explicitly). Today /
  expected / missing, recommendation and why, numbered choices (never letters), ready-to-use
  answer, impact and evidence; six decision-quality checks; never records an unchosen
  recommendation.
- Resume continues from the last verified point; contradicting evidence is recorded and the
  affected recommendations revalidated; approved decisions change only through supersession.
- DRAFT-PBI.md separates confirmed requirements, existing functionality, gaps, proposed changes,
  approved decisions, blockers, source-access limitations and regression tests.
- Agent description updated; Visual Studio tools unchanged (`readfile`, `code_search`,
  `find_references`, `editfiles`, as documented by Microsoft; no terminal tool).

### Every new PBI starts fresh
- Agent: each new PBI uses only its own request, folder, attachments and the source read for
  it. Start it in a new chat (the agent asks for one if the conversation already worked on
  another PBI); nothing is carried over from earlier PBIs, chats or Copilot memory (rules,
  answers, decisions, assumptions, field values, application names, questions, criteria).
  Other PBI folders are read only by name for duplicate detection, or as a named related PBI
  that is never evidence or approval. PBI content is never stored in Copilot memory or
  knowledge notes. The start prompt of every new PBI repeats this.
- Readiness (form and PowerShell, identical): evidence that points into another PBI's folder is
  reported as FOREIGN_PBI_EVIDENCE and never counts; files in the PBI's own folder still do.

### Setup window with upgrade
- Double-clicking Install-PBIBuilder.cmd opens a setup window (PBI-Builder-Setup.ps1),
  modelled on the Akzo Master SDD installer: a remembered list of repositories with each one's
  installed version and available update, Add repository, Install / Upgrade, Upgrade all,
  Repair, Verify, Uninstall and a log. Editor and repository area are asked only for a first
  install; an upgrade keeps config.json.
- It runs Install-PBIBuilder.ps1 for every action, so review, conflict protection, backups and
  rollback are unchanged: changes are previewed and confirmed before writing, and a repository
  with edited files is skipped and reported. It runs under the user's execution policy (no
  Bypass, unlike the Master installer). `-NoGui -Action Install|Upgrade|Repair|Verify|Uninstall|Status`
  for scripts. The list is stored in %USERPROFILE%\.akzo-pbi-builder\repositories.txt (paths
  only). With arguments, Install-PBIBuilder.cmd runs the installer as before.

### Application areas and question rules
- Three application areas, named the same everywhere: CDMS, DAB (GraphQL) and Custom (Legacy
  CRM/XRM). Stored keys are unchanged (`legacy`, `dab`, `cdms`; evidence system `legacy-crm`),
  so existing configurations and PBIs keep working. The form's repository role and source
  labels, sources.yaml (`area` per source) and SOURCE-MAP.md use these names.
- Agent: identify the current repository's area from its source, search the source before
  describing functionality, name the owning area for each rule, trace across the available
  areas, explain in business language. Never invent an application, repository or dependency;
  a field value such as OwnColor (Development Tool) is data, not an application, and is kept as
  written.
- Questions: options in business language with a Recommended option and its reason (when
  supported), Custom answer and Decide later. A scope question (area, workflow, process or field
  value) only after finding where the field or behavior is used and whether the requirement
  covers all of those places. For PBI 277355 this removes the question "Should the Yes/No
  choice apply to ColorApps or both ColorApps and OwnColor?"; the agent now investigates where
  the Development Tool field affects actualization across the Industrialization workflows.
- Form: Decide later replaces Skip and also works on required questions; they stay open and the
  PBI is not Development-Ready until they are answered. A question's `recommended` option is
  marked and preselected.

### Guided PBI creation
- "Create PBI" (also New PBI, Create User Story, Refine New Requirement, Start PBI): six
  steps (title and project, requirement, acceptance criteria, supporting material, kind of
  change, review) with prefill from what the user already gave, Save draft and Resume.
- The form's New PBI tab is the same wizard: progress, Back/Next, Save draft, Start analysis,
  Cancel, target project from the configured sources, a real file picker that copies
  attachments into the PBI's attachments/ folder, and Resume or Create separate draft when the
  PBI number already exists (previously a hard stop).
- Commands: Resume, Review, Edit, Show Decisions, Analyze Legacy, Show Technical Flow,
  Generate Acceptance Criteria, Export and Validate PBI.

### Visual Studio source access and discovery
- Checked against Microsoft's Visual Studio documentation: custom agents live in
  `.github/agents/*.agent.md` (Visual Studio 18.4+); documented tool names include `readfile`,
  `code_search`, `editfiles` and `find_references`; agent file tools reach only the open
  solution or opened folder and its subfolders. The Visual Studio agent now also has
  `find_references` (read-only caller tracing); no terminal tool. Pinned comparison agents keep
  their original tools.
- Agent and repository-knowledge guide: source access check before every analysis (readable,
  configured but inaccessible, not configured, proven by a real file read; never "missing"),
  solution and project mapping, tracing from entry point to persistence and side effects for
  legacy .NET Framework, Web Forms, plugins, workflows, web resources, SQL and configuration (no
  secrets recorded), evidence priority (current source first, bundled reports last), and
  SOURCE-DISCOVERY.md per PBI; pbi-state.json may record `sourceAccess`.
- Readiness: bundled reports under playbook/pbi-builder/references/ (or evidence marked
  `historical`) never count as evidence; `HISTORICAL_NOT_PROOF` when a rule has nothing else.
- Form: Discover sources writes knowledge/SOURCE-MAP.md and source-map.json (solutions, projects,
  references, frameworks, markers, file kinds, access per source); reads only solution and project
  files. The developer handoff now carries `sourceAccess` and `dependencies`.
- sources.yaml states the Visual Studio access rule; user guide: setups for legacy, DAB, CDMS and
  several repositories, and a Visual Studio check.

### Branch completeness, developer handoff and speed
- New mandatory guide `skills/business-rule-branch-completeness.md`: conditions, Yes/No
  branches, success, validation failures, status transitions, side effects, failure and
  rollback, compared per branch with verified implementation; side-effect risk when an
  uncovered branch shares an operation with a covered one (worked example: Paint System
  measurement, Yes replaces Master measurement and Color Point, No keeps them).
- Rules may record `branches` with CDMS and DAB coverage (covered, partial, missing,
  conflicting, unverified, not-applicable), evidence, risk, proposed approach and acceptance
  criteria. Readiness: `BRANCH_INCOMPLETE`, `BRANCH_NOT_COVERED` (reuse claimed while a branch
  such as No is open), `BRANCH_COVERAGE_UNPROVEN` (covered without code evidence, without plugin
  activation, or with legacy evidence for DAB), `DAB_BRANCH_GAP`. Same results in PowerShell.
- Form: Export developer handoff writes `business-rules.json` (schema 1: applications, rules,
  branches, recorded and effective coverage, evidence, CDMS and DAB ownership, acceptance
  criteria, decisions, open gaps; approved requirements, proposed requirements and technical
  findings kept apart) and `BRANCH-COVERAGE-MATRIX.md`, from pbi-state.json only; earlier exports
  go to history/.
- Faster refinement instructions: configured paths are never asked for, search terms come from
  the PBI, no whole-repository scans, only the needed guides, incremental updates after an
  answer, a short default summary, and per-run metrics in EVIDENCE.md. The evidence index can
  hold method, entity, trigger, conditions, rule IDs, calls and confidence.
- Compare old & new: results.csv adds files_read, cache_entries_reused and cold_or_warm.
  `maintainer/benchmark.cjs` measures the deterministic operations against 3.1.0
  (docs/PERFORMANCE.md).

### Business rule ownership (CDMS and DAB)
- There is no DAB plugin. DAB implements every applicable legacy rule in its own code; the
  earlier "the plugin already runs for DAB" and "assign only some legacy operations to DAB"
  wording is removed. New guide `skills/business-rule-ownership.md`: application choice (CDMS,
  DAB or Both, asked once and saved); rules read from plugins, workflows, custom activities,
  JavaScript (OnLoad/OnSave/OnChange, ribbon), HTML web resources and helpers, with the
  AN.ColorDMS.Customizations areas to search; UI logic restated as API requirements; one
  canonical rule per outcome with every source as evidence; CDMS ownership (existing plugin
  reused when verified, workflow and JavaScript rules included); DAB ownership by layer (Azure
  Functions, CQRS handler, FluentValidation only for input rules, domain service, GraphQL,
  response conventions); documents LEGACY-BUSINESS-RULE-CATALOG.md, SHARED-BUSINESS-RULES.md,
  BUSINESS-RULE-OWNERSHIP.md, ACCEPTANCE-CRITERIA.md, CDMS-REFINED-PBI.md, DAB-REFINED-PBI.md.
- Readiness: a rule may record `dab` {layer, status}; a plugin as DAB layer is
  `DAB_PLUGIN_ASSIGNED`, an incomplete one `DAB_OWNER_INVALID`. With a `dab` record, a CDMS
  `reuse` of a plugin is no longer flagged because DAB bypasses it. Identical rule text is
  `RULE_DUPLICATE`. CDMS-REFINED-PBI.md and DAB-REFINED-PBI.md are gated and checked like
  REFINED-PBI.md, and `DOC_OUT_OF_SCOPE` when their application does not apply. Evidence
  components javascript, web-resource and ribbon.
- Form: the New PBI wizard asks the application (CDMS, DAB, Both, not decided) and saves it in
  REQUEST.md and pbi.json; the start prompt tells the agent not to ask again.
- PBI template: application line and CDMS/DAB ownership columns.

### Business questions
- The agent acts as a Business Analyst. It never asks business users about registration,
  pipelines, DI, middleware, builds, repository paths, GraphQL generation or deployment;
  missing technical evidence goes into the technical assessment and does not stop business
  refinement.
- VS Code: the agent's tools include `vscode/askQuestions` (interactive question controls; the
  host ignores unavailable tools). Elsewhere: numbered options with back, skip, status and why.
- The form's Continue tab has an Answer questions panel: options, custom answer, required
  name, skip (optional questions only), edit previous answer, show decisions.
- Decision engine (core.js): each answer is saved at once to pbi-state.json and DECISION-LOG.md
  with a backup in history/; editing an answer supersedes the earlier decision; the file is not
  written if it changed meanwhile. One answer approves that decision only, without a second
  confirmation.
- Question statuses unanswered, answered, approved, deferred, superseded and not-applicable
  (open and resolved still accepted); identical question text is flagged.

### Evidence
- New guide `skills/crm-plugin-workflow-intelligence.md`: call chains from one entry point with
  a visited list and depth bound, a 10-point record per entry point, evidence per rule, and a
  plain-language presentation (technical evidence, simple explanation, difference, next
  action).
- Evidence records may carry `system` (legacy-crm, cdms, dab, ocp, graphql, other). Legacy CRM
  evidence cannot prove a DAB/OCP/GraphQL path (`LEGACY_NOT_TARGET_EVIDENCE`). A PBI may record
  `evidenceScope` (for example excluding legacy-crm, as directed for PBI 305915) backed by an
  approved decision; excluded evidence is rejected.
- "Extract Plugin Rules <n>": the agent reads the plugin code once and writes PLUGIN-RULES.md,
  a DAB implementation handoff. Each rule is classed as validation, default/calculation, side
  effect or guard, with the trigger, condition as pseudocode, exact error message, data
  needed, CDMS and DAB status, Given/When/Then tests and source lines. DAB need is decided
  from the DAB write path: Web API/SDK writes already run the plugin; direct database writes
  must implement the rule. One business question confirms which rules carry over.
- New guide `skills/xrm-workflow-intelligence.md` and command "Analyze Workflows <n>": classic
  CRM (WF4/XAML) workflows and custom workflow activities, kept apart from Power Automate cloud
  flows. Targeted discovery from the operation's entity (.xaml.data.xml first), trigger, mode,
  scope, activation ("activation unverified" when not shown), branches, actions, child
  workflows, custom activity code, real-time versus background termination, downstream
  triggers with cycle and depth limits, no invented ordering. Writes PLUGIN-WORKFLOW-COVERAGE.md
  (rule, CDMS owner, plugin/workflow, trigger, conditions, evidence, DAB responsibility) with an
  operation graph, and separate business and technical views. CDMS, DAB and Both scopes.
- Rule owners: custom-activity, xrm-service, multiple (with types) and unknown; evidence may name
  its `component`. `OWNER_MISATTRIBUTED` when an owner is not backed by code evidence from that
  component (a workflow rule cited only with plugin code); `OWNER_UNKNOWN` blocks
  Development-Ready. Custom activities need activation evidence like plugins and workflows.
- Faster: a "Work fast" section (targeted searches, line ranges, pbi-state.json first on
  resume) and knowledge/PLUGIN-CATALOG.md so a plugin read for one PBI is reused by the next.

### Compatibility
- pbi-state.json stays schemaVersion 2. A PBI approved under 3.1.0 stays Development-Ready after
  the upgrade (tested). The pinned v2.0/v2.1 comparison agents keep their original tools.
- Results remain identical in the form and PowerShell (61 shared scenarios).

### Not included
- No VS Code extension (Quick Pick/webview); the documented in-chat tool is used instead.
- No Azure DevOps auto-prefill (no approved connection exists); screenshots and documents are
  read by Copilot only where its tools can open them.

## 3.1.0 — 27 October 2026

### Fixed readiness gaps (each reproduced by a failing test first)
1. An approved rule could change without a rev change and still be
   Development-Ready. Approvals are now bound to content fingerprints.
2. A final document with only a Status line and IDs could pass. The document must
   now contain each rule and criterion text from the state.
3. A target path such as DAB could be omitted. The PBI now records its path scope
   (cdms and dab required), and every rule must assess every path that applies.
4. A rule could cite an evidence ID with no record. Evidence IDs must now resolve
   to evidence records.
3.0.0 accepted all four as Development-Ready; 3.1.0 rejects all four (MEASUREMENTS.md).

### Approvals
- `pbi-state.json` schemaVersion 2. The check computes a 16-hex fingerprint per
  record in each approval scope (PO/BA, technical, final user), including the
  content of local evidence files. An approval records that `basis` as printed by
  the check. Any change, addition or removal makes the affected approvals stale
  and the report names the IDs. Whitespace-only reformatting does not.
- The approver is recorded (by, at, evidence), not authenticated. Old approvals
  move to `approvalHistory` as stale; history and decisions are never deleted.
- 3.0.0 approvals (rev-number basis) are reported as unbound and never count.

### Document, state and evidence consistency
- Rule and criterion text must be present, not a placeholder (TBD/TODO/TBC) and
  at least 12 characters, and must appear in the PBI document. Dependency IDs
  must be in the document; decision IDs in DECISION-LOG.md.
- Evidence records carry level (code, registration, reach, runtime), kind
  (repo-file or external), source, location and summary; external evidence needs
  a revision. Rules need code-level evidence for an existing owner, registration
  evidence for a registration claim, reach evidence for each path that reaches
  or bypasses, and runtime evidence for "runtime verified".
- Repository evidence files are read by the check: missing, changed (against an
  optional sha256) or stale evidence blocks Development-Ready.
- Resolved blocking questions need a resolution; PO/BA ones also an approved
  decision. Supersede links must point to a superseded decision. Rule
  dependencies must resolve.
- PATH_CONFLICT when a rule claims a path the PBI scope excludes.

### Product
- The wizard and `-Action CheckPbi` show the approval basis once a PBI is Ready
  for Review. Results are identical in both (50 shared scenarios plus the four
  3.0.0 gap states, JSON compared field by field).
- The agent, readiness guide and template describe the new flow: revalidate after
  every change, resolve PO/BA and technical questions with their owners, one
  consolidated review quoting the fingerprints, separate approvals, final document
  only when the check allows it. The guide separates code-enforced controls from
  controls that depend on the agent.
- Template: execution-path scope table, criteria as one verbatim column, evidence
  level column, approval fingerprints line.

### Other fixes found in review
- Paths with Windows device names (CON, NUL.cs, COM1...) or a trailing dot or
  space are rejected in the wizard and the installer; Windows silently aliased
  them to other files.
- PowerShell property lookup is now case-sensitive, as in JavaScript, so
  `"Rules"` is no longer read as `"rules"` by one implementation only.

### Unchanged
One agent, on-demand v2.0/v2.1 comparison baselines, wizard, PowerShell installer,
manifest, conflict handling, backups and rollback. No new dependencies.

## 3.0.0 — 27 October 2026

### Agent and refinement
- One agent, "Akzo SDD PBI Builder - <project>", replaces the original/Concise pair.
  The concise communication rules are kept. "Dynamic" is removed from all names.
- Execution-path ownership: four separate evidence levels (code exists, registration
  or configuration active, target request reaches it, runtime confirmed). Plugin
  source alone is not treated as active.
- Validation ownership matrix (`VALIDATION-MATRIX.md`) per business rule, and CDMS
  versus DAB/OCP/GraphQL decided per operation from evidence.
- Users and permissions: initiator, role/ownership/BU scope, execution identity,
  record/field restrictions, unauthorized behavior; frontend visibility is not
  backend authorization.
- Statuses: Draft, Needs Evidence, Awaiting PO/BA Decision, Ready for Review,
  Development-Ready.
- Final revalidation of all rules and criteria, then one consolidated approval request
  (PO/BA, technical, final user). `REFINED-PBI.md` is created only after all three
  approvals are recorded; drafts live in `DRAFT-PBI.md`. A change to an approved item
  bumps its `rev` and needs renewed approval.
- Better questions: business example, options with consequences, no re-asking an
  answered question, answers recorded with scope and provenance.
- New PBIs start with no decisions or approvals from other PBIs.
- On-demand guides in `playbook/pbi-builder/skills/`: execution-path analysis,
  readiness and approval, repository knowledge.
- PBI template extended (actors, current vs required behavior, ownership summary,
  CDMS vs DAB, integration failures, data/state, AC-to-rule links, readiness).

### Deterministic checks
- `pbi-state.json` and a readiness check (form button, `-Action CheckPbi`) with
  shared rules: completeness, evidence gaps, reuse of inactive/bypassed enforcement,
  identities, PBI-specific decisions, stale approvals, document consistency, and
  no final document before approval. It never claims semantic correctness or
  approval authenticity.
- Repository knowledge: `knowledge/evidence-index.json` with content fingerprints of
  raw bytes; refresh marks changed or deleted sources stale (form button,
  `-Action RefreshEvidence`). Reference documents get a heading index.

### Installation
- Windows installer: `Install-PBIBuilder.cmd/.ps1`, `Uninstall-PBIBuilder.cmd/.ps1`
  with folder selection, settings, preview, install, upgrade, verify, repair and
  uninstall. Same manifest, hashes, backups, conflict detection and rollback as the
  form. Respects execution policy.
- Generation contract: `core.js` exports a placeholder bundle
  (`pbi-builder-bundle.json`, schemaVersion 1) that both installers render. Unknown
  schemas, tokens and placeholders fail before writing.
- Migration retires unchanged 2.x agent files after the new ones are verified;
  edited or unowned ones are kept and reported.
- Comparison trials write a pinned v2.0 Original or v2.1 Concise baseline agent
  on demand; Remove comparison agents deletes unchanged ones.

### Maintenance
- `build.py` and `update-fixture.py` read and write UTF-8 with LF on Windows
  (previously failed with cp1252 and wrote CRLF).
- Tests: 24 core checks, UI handler smoke, 6 PowerShell equivalence and installer
  checks; `compare-versions.cjs`; `release.cjs` builds and verifies the ZIP.

## 2.1.0 — 28 September 2026
Concise pilot agent added beside the original 2.0 agent; comparison mode.

## 2.0.0
Setup wizard: project-specific agent, intake, continuation, managed updates.
