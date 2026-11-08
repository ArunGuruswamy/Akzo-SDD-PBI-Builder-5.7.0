# Akzo SDD PBI Builder
## Application Performance and Quality Audit

Report date: 1 November 2026
Application version: 5.1.0
Repository: C:\src\Akzo-Pbi-Builder
Status: Analysis and recommendations only. Implementation requires approval.

## 1. Executive Summary

The builder is a functional offline intake, installation, validation, and artifact-generation utility, backed by an instruction-driven Copilot workflow. Prioritize approval integrity, repository isolation, UI handoff completeness, and recovery before optimizing AI prompts. Several defects were reproduced despite the existing core tests passing. No rewrite is justified.

The original audit did not change repository files, dependencies, or Git state. This document conversion adds report files only; it does not implement the recommendations.

The PBI Builder prepares requirements and handoff artifacts. It is not the Akzo Development Agent. Application implementation and Azure DevOps publishing remain outside the builder.

Most important findings:
- Approval fingerprints omit material inputs, and approval is not bound to the snapshot previously displayed to the user.
- Switching repositories retains draft state and can save a draft into the wrong repository.
- UI-only branch coverage can pass readiness while the handoff loses the UI application scope.
- The PowerShell installer follows junctions and can write outside the selected repository.
- A failed decision-log write can leave an approved decision in state without its log entry.
- PBI listing performs unnecessary document-content reads: 900 reads and 13.1 MB for 100 synthetic PBIs.

## 2. Architecture and Execution Flow

### 2.1 Architecture

The active repository root is C:\src\Akzo-Pbi-Builder. The audited source reports version 5.1.0.

maintainer/src/core.js combines JavaScript generation, agent and guide templates, readiness rules, hashing, filesystem operations, ZIP generation, and DOCX generation. maintainer/src/ui.js implements the vanilla browser interface; maintainer/src/shell.html supplies HTML and CSS. There are no third-party runtime dependencies or embedded AI engine.

maintainer/build.py embeds source and assets into the standalone HTML. PowerShell/.NET provides installation and WinForms setup; Node runs maintenance and tests. The generated agent has editor-specific read, search, and edit tools, eight workflow guides, and one Business Decision Advisor skill. These are generated definitions, not autonomous processes running inside the browser.

Sources: maintainer/src/core.js:4; maintainer/src/ui.js:1; maintainer/src/shell.html:1; maintainer/build.py:1; maintainer/src/core.js:2107 (templates).

### 2.2 End-to-End Flow

1. Open the standalone HTML.
2. Select the repository and load its configuration.
3. Install the generated customization files, if needed.
4. Capture the requirement, acceptance criteria, legacy source, and development target.
5. Save intake documents and attachments.
6. Manually send the prepared prompt to the selected Copilot agent.
7. The agent investigates source and writes draft, state, and evidence documents.
8. Answer genuine business questions and record decisions.
9. The browser checks readiness and presents a review.
10. The user approves; the builder generates Markdown, JSON, and DOCX artifacts and offers downloads.

Source investigation, business-rule extraction, and semantic correctness depend on Copilot following generated instructions, not executable analysis engines in the browser.

Sources: maintainer/src/core.js:253 (investigation instructions); maintainer/src/ui.js:121 (createIntake); maintainer/src/ui.js:207 (loadReview); maintainer/src/core.js:2759 (approveAndGenerate).

### 2.3 State, Caching, and Boundaries

State lives in repository JSON and Markdown files, with history and backups. Browser directory handles and active workflow state are session-local; only the legacy selection uses local storage. Knowledge reuse uses evidence hashes and agent-maintained notes.

The browser cannot silently select directories or authenticate Copilot. The generated agent's edit restrictions are instructions, not an operating-system sandbox. Approver identity is self-reported. PO/BA and technical sign-off remain organizational steps outside the required final user approval.

Sources: maintainer/src/ui.js:17,75; maintainer/src/core.js:611,1616,2437,2803.

## 3. Measured Performance and Verification

### 3.1 Measurement Conditions

Environment: Windows; AMD Ryzen 7 PRO 4750U; Node 26.5.1. Browser timings used integrated Chromium/Electron, not native Edge or Chrome. Synthetic files were isolated in temporary directories.

These are local observations under ordinary host load, not controlled production benchmarks. They do not establish full AI-driven workflow duration or performance on real CDMS, DAB, UI, or legacy repositories.

### 3.2 Results

- Browser startup: seven reloads; median DOMContentLoaded 122.2 ms and load 123.5 ms. No JavaScript errors or external resource requests were observed. OS-cold startup and native Edge startup were not measured.
- Intake plus text-attachment scanning: 42.3 ms median across seven runs, using a 1,083,000-byte synthetic attachment.
- List 100 PBIs: 3,440 ms median across three runs; 900 content reads and 13.1 MB read.
- Source discovery: 134.1 ms median across three runs; 930 synthetic files, 30 projects, and 31 content reads.
- Readiness with 60 rules and 240 criteria: current 346.5 ms versus frozen 3.1 baseline 173.0 ms, using seven-run medians. Current readiness with 240 branches measured 316.8 ms. Controlled profiling is needed before attributing the differences to a specific cause.
- Evidence refresh for 300 files: current first fingerprint 1,159.5 ms and unchanged refresh 992.3 ms; baseline 1,836.7 ms and 1,243.7 ms respectively. First fingerprint means the first index fingerprint, not a cold filesystem cache.
- Approve and generate: 203.9 ms median across seven runs; two rules, seven criteria, and three output formats. The last run performed 31 successful file reads.
- Handoff projection: 3.2 ms median for 240 branches.

The existing maintainer/benchmark.cjs was executed with its report write suppressed. The whole benchmark process used 33.7 seconds elapsed, 17.3 seconds CPU, and approximately 150 MiB peak RSS. These resource figures are not browser or individual-PBI consumption.

### 3.3 Existing Tests and Package Verification

- All 55 core checks passed in 10.9 seconds.
- The simulated-DOM UI suite passed in 0.7 seconds.
- The PowerShell suite passed its first four groups, then exceeded a 240-second harness limit. Subsequent full-suite validation was stopped without a usable completion result. Full PowerShell parity remains unverified.
- Shipped HTML and bundle matched the source.
- All 56 recorded package checksums matched.

Sources: maintainer/test-core.cjs:8; maintainer/test-ui.cjs:1; maintainer/test-ps.cjs:1; maintainer/benchmark.cjs:1.

### 3.4 Measurement Limits

Not measured: real CDMS/DAB/legacy searches, Copilot startup, per-PBI tool calls, tokens, credits, semantic drafting quality, human approval time, or complete AI-driven workflow duration. There is no basis for claiming an end-to-end speedup.

The generated comparison workflow provides manually populated metrics, not an automatic token or tool-call meter. Instruction sizes are bytes and words, not token measurements.

Source: maintainer/src/core.js:2166 (comparison metrics).

## 4. Prioritized Findings and Improvements

Findings are ordered by correctness/security impact, then measured performance opportunity. P1 means high priority; P2 means the next improvement tier. Effort and regression risk are qualitative: S = small, M = medium, H = high. Proposed benefits have not been achieved or benchmarked by an implementation.

### F01. P1 - Approval Does Not Cover Everything Reviewed or Generated

Source: maintainer/src/core.js:2444 (READINESS.scopes), maintainer/src/core.js:2759 (approveAndGenerate), and maintainer/src/ui.js:207 (loadReview).

Evidence and root cause: readiness scopes omit request content and source-access records. Changing both preserved the approval fingerprint and finalAllowed=true. approveAndGenerate also accepts no token identifying the earlier UI review snapshot. A changed title was generated successfully after review.

Impact: the user can approve or receive material that was not part of the reviewed content. Current validation of the latest state does not prove that the user saw that state.

Improvement: bind all material generation inputs to the displayed review; reject changed snapshots before writing. Include relevant request, attachment, target, source-access, and state inputs.

Expected benefit: prevent approval of unseen or materially changed content.

Effort: M. Regression risk: H, because existing approvals need migration or invalidation.

Verification: change each material input after review and confirm approval is refused; test concurrent changes. Mirror readiness rules in PowerShell and verify parity.

### F02. P1 - Cross-Repository Draft Leakage and Broken Duplicate Resume

Source: maintainer/src/ui.js:26 (openRoot), maintainer/src/ui.js:140 (dupResume), and maintainer/src/ui.js:7 (action).

Evidence and root cause: openRoot resets configuration but retains draft/form state. A reproduced repository switch saved repository A's draft into repository B. dupResume calls an action-wrapped handler while busy is already true, making saved-draft Resume a no-op.

Impact: wrong-repository writes, possible disclosure of requirement content, and failed recovery through the duplicate dialog.

Improvement: clear or explicitly scope all draft, question, review, and download state to its repository root. Invoke an underlying resume function rather than a guarded click handler.

Expected benefit: prevent cross-repository state leakage and restore Resume.

Effort: S-M. Regression risk: M.

Verification: add root-switch and duplicate-draft handler tests, including a destination containing an existing PBI with the same folder name.

### F03. P1 - UI Coverage Can Pass Without Verification

Source: maintainer/src/core.js:2430 (READINESS.branchApps), maintainer/src/core.js:2441 (evidence systems), and maintainer/src/core.js:2378 (handoff).

Evidence and root cause: branch checks cover only CDMS/DAB; evidence systems exclude ui. handoff exports only CDMS/DAB applications. A UI-only fixture with unverified branches passed readiness and produced an empty applications list, with no reported handoff gaps.

Impact: false completeness and missing frontend responsibilities in a developer handoff.

Improvement: carry UI consistently through evidence, branch validation, handoff, and guides.

Expected benefit: preserve UI scope and prevent unsupported coverage claims.

Effort: M. Regression risk: M-H.

Verification: add UI-only and combined golden-contract tests, including unverified and conflicting branches, and confirm UI evidence is represented correctly.

### F04. P1 - Installer Crosses Repository Boundaries Through Junctions

Source: maintainer/installer/Install-PBIBuilder.ps1:95 (Test-SafePath, Get-Full, and Write-Text).

Evidence and root cause: paths are validated lexically, but filesystem junctions are followed. A temporary .github junction caused installation to write an agent outside the selected repository, with exit code 0.

Impact: a pre-existing reparse point can redirect installation beyond the selected repository boundary.

Improvement: reject or explicitly validate reparse-point ancestry before reads, writes, and deletes, including backup and manifest paths.

Expected benefit: enforce the selected-repository filesystem boundary.

Effort: M. Regression risk: M for legitimate linked workspaces.

Verification: confirm outside sentinel files remain untouched during install, repair, and uninstall through junction-containing paths.

### F05. P1 - Multi-File Recovery and Concurrency Are Incomplete

Source: maintainer/src/core.js:2361 (updateQuestions), maintainer/src/ui.js:121 (createIntake), and maintainer/installer/PBI-Builder-Setup.ps1:42 (Save-Repos).

Evidence and root cause: updateQuestions writes state before its decision log, without rollback. An injected log failure left one approved decision in state and an unchanged log. createIntake saves attachments outside the intake transaction. Setup uses direct writes and an unlocked repository registry.

Impact: split state, incomplete intake, lost concurrent updates, and incomplete recovery after interruption. Existing exception rollback is useful but is not crash atomicity.

Improvement: apply existing backup/rollback conventions to complete write sets, compare every input, and add recoverable transaction markers and appropriate locking.

Expected benefit: consistent state and predictable recovery without a larger architectural rewrite.

Effort: M. Regression risk: M.

Verification: inject failure at every write, interrupt and restart, and test two writers against the same PBI and installer registry.

### F06. P2 - Final Artifacts Can Be Incomplete or Stale

Source: maintainer/src/core.js:2673 (finalDocuments) and maintainer/src/core.js:2666 (FINAL_NAMES).

Evidence and root cause: finalDocuments projects selected state fields rather than preserving the full draft. Markdown/DOCX omit branch risk, branch approach, and branch-only evidence citations. FINAL_NAMES retires Markdown only; obsolete JSON and DOCX files survived generation in the probe.

Impact: final formats differ in technical detail, and old deliverables can remain alongside current output.

Improvement: define one complete canonical artifact projection and retire every format together, with history.

Expected benefit: complete, consistent, current deliverables for downstream consumers.

Effort: M. Regression risk: M.

Verification: compare branch details and citations across formats; test transitions between every development target and check all obsolete formats are retired.

### F07. P2 - PBI Listing Reads Document Bodies Unnecessarily

Source: maintainer/src/core.js:2863 (listPbis); maintainer/src/ui.js:121 (createIntake) and :149 (createRefinement).

Evidence and root cause: listPbis calls read() for eight documents merely to establish presence. Creation and refinement invoke listing again. Measured cost was 900 reads and 3.44 seconds for 100 PBIs.

Impact: latency and unnecessary file-content processing increase with PBI count and document size.

Improvement: enumerate filenames, read intake metadata only, and validate the selected PBI directly where possible.

Expected benefit: reduced I/O. No wall-time improvement percentage has been measured.

Effort: S. Regression risk: L.

Verification: preserve legacy-folder discovery and malformed-metadata handling; benchmark 100 and 1,000 PBIs and count content reads and bytes.

### F08. P2 - Discovery Is Incomplete and Poorly Bounded

Source: maintainer/src/core.js:2897 (discoverSources), :2881 (SKIP_DIRS), and :2889 (parseProject).

Evidence and root cause: discovery omits UI and named repositories, ignores .gitignore, and lowercases directory names against a list containing TestResults. These issues were reproduced. The 60,000-file cap still entered 500 subsequent directories. Each file filters/sorts project candidates, and parseProject uses order-sensitive XML regexes.

Impact: incomplete access reporting, scanning of excluded output, and unnecessary work on large repositories. Project-reference parsing can miss valid XML layouts.

Improvement: use shared source keys, correct exclusions, propagate the global stop, index project ownership, and parse XML structurally.

Expected benefit: more accurate discovery with bounded traversal and improved scaling.

Effort: M. Regression risk: M.

Verification: test ignored trees, UI/named sources, XML attribute order, large/many-project trees, inaccessible roots, and global cap enforcement.

### F09. P2 - Repeated Validation and Hash Work Lacks Scoped Reuse

Source: maintainer/src/core.js:2508 (readiness), :2803 (refreshEvidence), and :2657 (checkPbi).

Evidence and root cause: readiness repeatedly searches arrays and serially fingerprints records. refreshEvidence hashes every entry, including repeated paths; checkPbi rehashes sources on each invocation. Warm refresh is not a content-read cache.

Impact: repeated CPU and I/O costs during reviews and refinements. External evidence still depends on agent-recorded revisions rather than local content verification.

Improvement: add ID/path maps and command-scoped immutable snapshots. Use measured, bounded concurrency where helpful. Retain fresh checks at approval boundaries; do not trust timestamps alone.

Expected benefit: eliminate duplicate work without weakening stale-evidence detection.

Effort: M. Regression risk: M-H.

Verification: test duplicate paths, uncommitted edits, deletion, and JS/PowerShell parity; benchmark before and after with identical inputs.

### F10. P2 - Instructions Are Large and Inconsistent

Source: maintainer/src/core.js:61 (AGENT_TEMPLATE), :915 (guided controls), :1035 (Related PBIs), and :1715 (Business Decision Advisor).

Evidence and root cause: the sample generated main agent was 37,152 bytes and 5,364 words. Agent plus guides/skill totaled 108,646 bytes. Guided controls require one question per call, while the advisor requests consolidated decisions. Related-PBI guidance encourages discovery/reuse inconsistent with the main fresh-PBI boundary. The advisor is requested before every question.

Impact: excess context and conflicting instructions can cause repeated reads, questions, or analysis. Actual token waste and behavioral impact were not measured.

Improvement: establish one authoritative rule per topic, reconcile conflicts, and load applicable guides once per relevant context.

Expected benefit: clearer execution and potentially lower repeated context loading; no token-saving percentage is claimed.

Effort: M. Regression risk: M for behavior changes.

Verification: equivalent real PBI trials, counting tool calls/tokens and checking missed rules, unsupported assumptions, repeated questions, and scope isolation.

### F11. P2 - Secret and Injection Protection Is Best-Effort

Source: maintainer/src/core.js:2242 (cleanAttachment), :2748 (contentReview), :596 (untrusted-content instructions), and maintainer/src/ui.js:121 (createIntake).

Evidence and root cause: binary and over-5-MB files remain unscanned; attachment secrets do not block contentReview. Intake buffers all attachments concurrently. Regex detection has false negatives. Resistance to prompt injection in repository content is primarily an agent instruction, not enforcement.

Impact: sensitive or instruction-like content can survive into stored material; large attachment sets can cause memory pressure. Plaintext files, clipboard use, and subsequent Copilot submission remain data-handling boundaries.

Improvement: add aggregate/per-file limits, bounded processing, explicit acknowledgement or rejection of unscanned material, and consistent export gates.

Expected benefit: clearer security limits, reduced accidental disclosure risk, and bounded attachment processing.

Effort: M. Regression risk: M for legitimate documents.

Verification: test size boundaries, binary formats, adversarial text, and synthetic credential variants without logging values.

### F12. P2 - Packaging and Verification Need Stronger Boundaries

Source: maintainer/release.cjs:11 (list) and maintainer/installer/Install-PBIBuilder.cmd:16 (checksum preflight).

Evidence and root cause: release packaging includes nearly everything outside a short exclusion list, including potential untracked/ignored sensitive files. Launcher checksums are optional and co-delivered, so they detect damage rather than trusted provenance.

Impact: future release contents can unintentionally include private workspace files; matching checksums alone do not establish publisher authenticity.

Improvement: use an explicit package allowlist and trusted signing/manifest verification for enterprise distribution. Preserve execution-policy compliance.

Expected benefit: controlled package contents and stronger provenance verification.

Effort: S-M. Regression risk: L-M.

Verification: test exclusion of synthetic private files, missing/tampered manifests, signed/unsigned packages, and execution-policy behavior.

### F13. P2 - Verification and Telemetry Gaps Conceal Regressions

Source: maintainer/test-core.cjs, maintainer/test-ui.cjs, maintainer/test-ps.cjs, and maintainer/src/core.js:2166 (comparison metrics).

Evidence and root cause: tests heavily assert generated wording and use simulated DOM. Parity cannot catch defects shared by both implementations. Comparison metrics are manually populated; automatic per-PBI agent telemetry does not exist.

Impact: passing tests do not establish native browser/editor integration, semantic quality, or actual efficiency.

Improvement: add the focused regressions above, independent artifact expectations, stage timings/read counters, and real-editor acceptance trials. Keep telemetry local and exclude content and secrets.

Expected benefit: measurable regressions and stronger confidence in complete workflows.

Effort: M. Regression risk: L.

Verification: validate reported counts against observed operations and complete native browser and editor trials.

## 5. Functional Capability Evaluation

PARTIAL includes implemented scaffolding with defects or instruction-dependent behavior; it does not mean the workflow is absent. IMPLEMENTED applies to the specifically described support, not a guarantee of semantic correctness.

### 1. PBI Number, Title, Description, and Acceptance Criteria

Status: IMPLEMENTED.
newPbi and wizard validation capture these fields. Text is trimmed and detected secrets are redacted, so this is not byte-for-byte preservation.
Sources: maintainer/src/core.js:2255; maintainer/src/ui.js:101.

### 2. CDMS-Only Selection

Status: PARTIAL.
TARGETS offers CDMS + UI, not a backend-only choice. State can exclude UI with a reason.
Source: maintainer/src/core.js:40.

### 3. DAB-Only Selection

Status: PARTIAL.
TARGETS offers DAB + UI, not a backend-only choice. State can exclude UI with a reason; DAB always references CDMS.
Source: maintainer/src/core.js:40.

### 4. UI-Only Selection

Status: PARTIAL.
Selection and a final document exist. Branch, evidence, discovery, and handoff defects remain.
Sources: maintainer/src/core.js:40,2378,2430,2897.

### 5. Combined Repository Analysis

Status: PARTIAL.
Repository roles and three-document generation exist; access and analysis coverage are not guaranteed.
Sources: maintainer/src/core.js:2276,2673.

### 6. Legacy CRM Comparison

Status: PARTIAL.
An explicit investigation workflow and CRM guide exist. Live accuracy and external-source access were not verified.
Sources: maintainer/src/core.js:281,1041.

### 7. Existing Implementation Reuse

Status: PARTIAL.
Investigation instructions, ownership records, and evidence caching support reuse. Correct identification of reusable behavior remains agent-dependent.
Sources: maintainer/src/core.js:281,1422,1616,2803.

### 8. Cross-Repository Impact Analysis

Status: PARTIAL.
Path/dependency records and multi-repository instructions exist. External access, semantic accuracy, and UI completeness remain limitations.
Sources: maintainer/src/core.js:392,2508,2378.

### 9. Missing Evidence Identification

Status: IMPLEMENTED structurally.
Readiness detects missing references, paths, activation evidence, and stale local files. It cannot discover business rules omitted from the state.
Source: maintainer/src/core.js:2538.

### 10. Business-Rule Extraction

Status: PARTIAL.
Guided analysis and CRM/XRM investigation instructions exist. Extraction is a Copilot task, not a deterministic browser function.
Sources: maintainer/src/core.js:976,1041,1187.

### 11. PBI Drafting and Refinement

Status: PARTIAL.
Guided analysis, state documents, and refinement briefs exist. Semantic drafting/refinement is performed by Copilot.
Sources: maintainer/src/core.js:976,2323.

### 12. User Approval and Revision

Status: PARTIAL.
Decision supersession and fingerprints exist, with reproduced binding and transaction gaps. Approver identity is self-reported, not authenticated.
Sources: maintainer/src/core.js:2338,2361,2444,2759.

### 13. Final Artifact Generation and Download

Status: PARTIAL.
Generation and verified downloads work. Projection and retirement defects remain.
Sources: maintainer/src/core.js:2673,2759; maintainer/src/ui.js:237.

### 14. Resume and Recovery

Status: PARTIAL.
Saved intake, state, and history exist. Duplicate Resume, root switching, interruption, and multi-file consistency have gaps.
Sources: maintainer/src/ui.js:26,140,151; maintainer/src/core.js:2361.

### 15. Secure Attachments and Credentials

Status: PARTIAL.
Redaction, warnings, CSP, and working-document gates exist. Unscanned content and plaintext storage remain limitations.
Sources: maintainer/src/core.js:2207,2242,2748; maintainer/src/shell.html:2.

### 16. Verified Versus Unverified Evidence

Status: PARTIAL.
Four evidence levels are explicit. External revisions are declarative, UI coverage is incomplete, and source-access records are not validated or bound to approval.
Sources: maintainer/src/core.js:626,2444,2508.

### 17. Development Agent Handoff Compatibility

Status: PARTIAL; consumer compatibility NOT VERIFIED.
exportHandoff generates structured rules and a branch matrix. No Development Agent implementation or consumer contract test was available. UI scope is currently lost.
Sources: maintainer/src/core.js:2378,2413.

## 6. Performance and Quality Scorecard

These are evidence-based engineering assessments, not benchmark-derived percentages. Unmeasured AI performance is explicitly excluded.

- Startup efficiency: 8/10. Warm browser startup was fast; OS-cold and native-browser startup remain unverified.
- Repository search efficiency: 4/10 for local discovery/retrieval. Coverage and repeated-I/O weaknesses are demonstrated; live Copilot search efficiency is unverified.
- Agent token efficiency: NOT VERIFIED. No measured per-PBI token usage or automatic token meter.
- PBI generation speed: 8/10 locally. Deterministic generation was fast on a small fixture; end-to-end AI duration is unverified.
- Architecture quality: 6/10. Small dependency footprint, but mixed concerns and duplicated JavaScript/PowerShell logic.
- Functional completeness: 6/10. Substantial workflow support with incomplete UI contracts and instruction-dependent capabilities.
- Reliability: 4/10. Reproduced approval, state-isolation, and recovery defects.
- Security: 5/10. Useful protections, but a junction boundary escape and content-scanning gaps remain.
- Test coverage and verification: 6/10. Passing core/UI suites, missed defects, and incomplete PowerShell/native-editor validation.
- Maintainability: 5/10. Large embedded templates, conflicting guidance, and cross-runtime coupling.

## 7. Recommended Next Release

Ship the P1 fixes, complete UI contracts and artifact retirement, and optimize PBI listing first. Preserve the offline architecture and existing ownership/backup conventions. Do not introduce a replacement application architecture.

Suggested implementation order:
1. Bind approval to a reviewed snapshot and all material generation inputs.
2. Fix repository-scoped UI state and duplicate-draft Resume.
3. Enforce installer junction/reparse-point boundaries.
4. Complete multi-file rollback and recovery behavior.
5. Complete UI evidence, branch checks, and handoff contracts.
6. Correct final artifact projection and retirement across formats.
7. Replace PBI document-body reads with metadata-oriented listing.
8. Correct discovery exclusions, source coverage, and global limits.
9. Profile repeated hashing and reconcile agent instructions with measured regression trials.

### 7.1 Expected Performance Benefit

Estimate, not measured improvement: metadata-only listing could reduce the demonstrated fixture from 900 to approximately 100 content reads, about 89% fewer. This is an estimated I/O reduction for that fixture, not a proven elapsed-time improvement.

No wall-time or token-saving percentage is justified yet for the other recommendations. Any future claims should use repeated measurements on identical inputs and preserve output correctness.

### 7.2 Files Requiring Modification

Primary source and maintenance targets:
- maintainer/src/core.js: approval scopes, UI contracts, state transactions, artifact projection/retirement, listing, discovery, hashing, and generated instructions.
- maintainer/src/ui.js: repository isolation, duplicate Resume, reviewed-snapshot handling, intake transactions, and attachment limits.
- maintainer/installer/Install-PBIBuilder.ps1: path containment and readiness parity.
- maintainer/installer/PBI-Builder-Setup.ps1: registry concurrency and recoverable writes.
- maintainer/installer/Install-PBIBuilder.cmd: package verification policy.
- maintainer/release.cjs: package allowlist and provenance checks.
- maintainer/benchmark.cjs: reproducible operation timings and read counters.
- maintainer/test-core.cjs, maintainer/test-ui.cjs, maintainer/test-ps.cjs: focused regression coverage.
- maintainer/fixtures/readiness-cases.cjs: approval, UI coverage, and compatibility fixtures.

Documentation targets:
- maintainer/README.md
- docs/USER-GUIDE.md
- docs/PERFORMANCE.md
- CHANGELOG.md

Regenerate shipped HTML, bundle, installers, and checksums through the existing build/release process after authorized changes. Avoid manually patching generated copies independently of their source.

### 7.3 Upgrade Verification

- Test every material input changing after review, including concurrent edits, and confirm stale approval is rejected.
- Test duplicate-draft Resume and switching roots with active draft, question, review, and download state.
- Test CDMS, DAB, UI-only, and combined targets with verified, missing, unverified, and conflicting evidence.
- Test junction/reparse-point paths for install, repair, verify, backup, and uninstall operations.
- Inject failures at every multi-file write boundary and test interruption/restart and concurrent writers.
- Compare complete Markdown, DOCX, and JSON contents; test retirement of every old format during target changes.
- Benchmark listing at 100 and 1,000 PBIs and discovery on excluded, large, and many-project trees.
- Test duplicated evidence paths, edits, deletion, and JavaScript/PowerShell parity without weakening freshness checks.
- Test attachment limits, unscanned formats, synthetic credentials, adversarial text, and export gates.
- Test package allowlisting, signing/provenance, checksums, and execution-policy compliance.
- Complete the full PowerShell suite and native browser/editor acceptance checks.

## 8. Reproduction and Remaining Verification

To reproduce without touching the original workspace, copy the package to a temporary directory. Place its shipped Akzo-SDD-PBI-Builder.html in that copy's maintainer directory, then run the following commands from the temporary maintainer directory:

node test-core.cjs
node test-ui.cjs
node test-ps.cjs
node benchmark.cjs

The benchmark writes its report within the temporary copy. Existing core tests write generated ZIPs beside the test scripts, which is why an isolated copy is necessary for a read-only workspace audit.

The additional synthetic measurements and failure probes in this audit were executed in memory or temporary directories; they were not added to the repository's tests. The focused regression cases described above should be added only after implementation work is authorized.

Run native Edge/Chrome and real Copilot trials for CDMS, DAB, UI, and combined targets. Hold model, source revisions, and requirements constant. Record phase durations, searches, file reads, questions, tokens, cache reuse, and output correctness. Verify the Development Agent's actual consumer contract rather than inferring compatibility from export availability.

No code changes are authorized or implemented by this report. Approval of the next-release scope is the next decision.