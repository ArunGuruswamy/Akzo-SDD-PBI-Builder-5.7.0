# PBI Builder → Akzo Master SDD agent: development handoff contract (5.7.0)

For the maintainers of the Akzo Master SDD agent. It describes what PBI Builder 5.7.0 hands over, how to verify it, what
SDD 4.2.5 already does with it, and the consumer changes still needed. It implements the Builder side of
SDD-TWO-AGENT-AUDIT-2026-11-07 (P0-5, P0-6, P0-7, P0-10 and P1-5). Observations about SDD 4.2.5 come from running its
unmodified helper (`copilot/modules/investigate/scripts/akzo.ps1`) in `maintainer/test-570.cjs`; no IDE session was run.

## What the Builder produces
Approve & Generate writes, in one transaction with the approval and in Chat (PowerShell) and the form (browser) alike, into
`playbook/pbis/<folder>/`:

| File | Content |
| --- | --- |
| `Refined-PBI-<CDMS\|DAB\|UI>.md/.json/.docx` | One Refined PBI per selected implementation target; `REFINED-PBI.*` without a target |
| `business-rules.json` | schemaVersion 2 (below) |
| `BRANCH-COVERAGE-MATRIX.md` | The same branches as a table |
| `HANDOFF-MANIFEST.json` | Binds the files above to the approval |

Both engines write `business-rules.json`, `BRANCH-COVERAGE-MATRIX.md`, `HANDOFF-MANIFEST.json` and every `Refined-PBI-*.json`
byte for byte alike for the same state; only the `.md` and `.docx` renderings differ between Chat and the form.

The ZIP (`<folder>-final-pbis.zip`) keeps the 5.x layout: the files above at the root, attachments under `attachments/`,
working records (`pbi.json`, `pbi-state.json`, `REQUEST.md`, `DRAFT-PBI.md`, …) under `supporting/`.

## business-rules.json schemaVersion 2
Everything in schemaVersion 1 is kept unchanged; added:
- `rules[].evidence[].repository` and `rules[].branches[].evidence[].repository`: the `pbi.json` repository key the source belongs to.
- `decisions[].decision`: the decision text.
- `acceptanceCriteria[]`: every criterion with `id`, `rev`, `type`, `rules`, `criterion`.
- `questions[]`: `id`, `status` (`open`, `answered`, `deferred`, …), `blocking`, `decisionRef`. **`answered` is an answer**:
  the Builder never writes `resolved` for an answered question.
- `technicalRevalidation[]`: the IDs of the evidence the rules cite (historical evidence excluded): re-check these against
  today's code instead of investigating the business rules again.

## HANDOFF-MANIFEST.json (schema `akzo-pbi-handoff`, version 1)
| Field | Meaning |
| --- | --- |
| `schema`, `schemaVersion` | Contract name and version |
| `producer` | `name` (`Akzo SDD PBI Builder`), `version` |
| `disposition`, `status` | Always `DEVELOPMENT_READY` and `Development-Ready` in a written manifest (none is written otherwise) |
| `pbi` | `id` (folder name), `number`, `title`, `folder` (where it was generated; informational, the PBI may move between `playbook/pbis` and `Source/playbook/pbis`), `stateSchema` |
| `approval` | `by`, `at`, `evidence`, `reviewedContent` (64-hex reviewed-content fingerprint), `fingerprint` (16-hex approval basis) |
| `readiness` | `computedStatus`, `finalAllowed`, `issues`, `warnings` at generation |
| `target` | `key` (e.g. `dab`), `label` (e.g. `DAB + UI`), `implement` and `reference` repository keys; `null` without a target |
| `repositories[]` | `key`, `area`, `use` (`implement` or `reference`), `path` as configured |
| `documents[]` | Per implementation target: `area`, `md`, `json`, `docx`, `repository` (its path) |
| `requirements[]`, `acceptanceCriteria[]` | Rule `id`/`rev`/`kind`; criterion IDs |
| `decisions[]`, `questions[]` | IDs and statuses (`questions[]` also `blocking`, `decisionRef`) |
| `evidence[]` | `id`, `repository`, `system`, `level`, `kind`, `source`, `location`, `revision`, `sha256`, `verification` |
| `files[]` | `path` (relative, `/`), `role` (`refined-pbi`, `business-rules`, `branch-coverage-matrix`), `target`, `bytes`, `sha256` |
| `attachments[]` | `path` (`attachments/<name>`), `bytes`, `sha256` of the PBI folder copy |

The manifest does not list or hash itself. A matching hash shows a file is unchanged since generation; it does not prove who
produced it.

## Golden package
`maintainer/fixtures/golden/pbi-309446-final-pbis.zip` is a real Download Complete Package from this Builder (309446-shaped
DAB + UI PBI, six answered questions, Legacy and CDMS as references, one attachment), regenerated with
`node maintainer/make-golden-package.cjs` on every release. `test-570.cjs` fails when it is from another Builder version or
when a freshly generated package has other file names, schemas, roles or status values. Copy it into the SDD agent's test
fixtures and import it there; delete its HANDOFF-MANIFEST.json for the "no manifest" case, or edit a file for the "tampered" case.

## Verifying a package
Accept a handoff only when all hold (the Builder's own `StartDevelopment` checks the same and more):
1. `schema` is `akzo-pbi-handoff`, `schemaVersion` is 1, `disposition` is `DEVELOPMENT_READY`.
2. Every `files[].path` is relative, has no `..`, is not `HANDOFF-MANIFEST.json` and not under `history/`, and its SHA-256
   matches. In a ZIP the same paths are at the root.
3. `approval.by`, `approval.at` and `approval.reviewedContent` equal `approvals.user` (and its `basis.reviewedContent`) in
   `pbi-state.json`.
Never treat `business-rules.json` without such a manifest as approved: Export developer handoff writes it for working drafts.

## Importing with SDD 4.2.5 today
Builder Start Development prints one command per implementation target:

    & "$env:USERPROFILE\.akzo-agent\modules\investigate\scripts\akzo.ps1" pick -Source '<repository>\playbook\pbis\<folder>' -File 'Refined-PBI-DAB.md'

With `-File`, SDD 4.2.5 imports the right document from the folder and from the ZIP (verified for DAB and UI of the 309446
shape): `refined-pbi.md` is the target's Refined PBI, `suggestedId` is the PBI number, the handoff files, records and the
attachment are supporting documents, and no attachment is reported missing.

## Consumer updates required in the SDD agent
Not made here: this release changes only the PBI Builder. Numbers refer to the audit.
1. **Know the 5.5+ document names (P0-1).** `$BuilderDocs` in `akzo.ps1` lists only `REFINED-PBI.md`, `PBI-CDMS/DAB/UI.md`,
   `CDMS-/DAB-REFINED-PBI.md`. Add `Refined-PBI-CDMS.md` (cdms), `Refined-PBI-DAB.md` (dab) and `Refined-PBI-UI.md` (ui).
   Today, without `-File` (including Start-Development.cmd → Browse), SDD 4.2.5 imports **DRAFT-PBI.md** from any 5.5+
   package, the multi-document choice never appears, and each `Refined-PBI-*.json/.docx` is flagged "second primary PBI".
2. **Treat `answered` as answered (P0-2).** `openQuestions` keeps every status but `resolved`; the Builder writes
   `answered` (and `deferred`). Read `questions[]` from business-rules.json or the manifest.
3. **Verify HANDOFF-MANIFEST.json before import (P0-3)** as above; refuse, or warn and ask, on a mismatch. Use `documents[]`
   for the per-target choice and recommend the one whose `repository` is the open workspace.
4. **Map evidence with `evidence[].repository` (P0-9).** Sources are relative to the Builder repository (`DAB Repo/...`);
   strip the matching `repositories[].path` before looking the file up in a registered repository.
5. **Keep `use: reference` repositories read-only (P1-1)** (Legacy and CDMS for DAB + UI), and treat other targets' Refined
   PBIs as related references, not as a second primary PBI.
6. **Reuse the approved business content (P0-4):** Builder BR and AC IDs, decisions and `technicalRevalidation[]`, instead of
   re-extracting requirements or re-asking PO/BA questions; a business change goes back to the Builder.
7. **Keep explicit PBI selection and implementation approval.** The Builder never starts the SDD agent and never approves
   implementation; queuing a PBI is not consent to implement it.
8. **Test with the golden package (P0-10)** instead of hand-written fixtures with pre-5.5 names.
