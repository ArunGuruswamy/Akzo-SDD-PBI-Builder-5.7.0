# Akzo SDD PBI Builder 5.1.0 — maintainer notes

Self-contained offline HTML utility plus a Windows PowerShell installer. No npm
dependencies. End users open the compiled HTML or run Install-PBIBuilder.cmd; Node 20+
and Python 3 are only needed to rebuild and test.

## Files
- `src/core.js`: the single source of generation. Agent and guide text, templates with
  `{{PBI:TOKEN}}` placeholders, `bundle()` (the generation contract for PowerShell),
  intake/refinement, comparison, readiness rules, evidence fingerprints, SHA-256
  ownership, plan/apply/rollback, ZIP writer.
- `src/ui.js`, `src/shell.html`: browser controls and layout (inline CSP, no network).
- `src/assets.json`: historical reference documents and the PBI template.
- `installer/`: `Install-PBIBuilder.ps1` (all actions), `PBI-Builder-Setup.ps1` (setup window and
  `-NoGui` batch mode over the installer; opened by double-clicking the .cmd), `Uninstall-PBIBuilder.ps1`
  (wrapper) and `.cmd` launchers. Pure ASCII so Windows PowerShell 5.1 reads them
  without a BOM.
- `fixtures/baseline-v2.0.0-core.cjs`, `baseline-v2.1.0-core.cjs`, `baseline-v3.0.0-core.cjs`:
  the exact prior generators, used only by tests and `compare-versions.cjs`;
  `baseline-v3.1.0-core.cjs`; `baseline-v2.1.0-template.md`, `baseline-v3.0.0-template.md`,
  `baseline-v3.1.0-template.md`: their templates.
- `fixtures/readiness-cases.cjs`: shared readiness scenarios for JS and PowerShell.
  `load(core)` records approvals with the basis the code under test prints.
- `fixtures/gap-cases.cjs`: the four reported 3.0.0 gaps as a 3.0.0 agent records them.
- `fixtures/fs-handles.cjs`: File System Access handles backed by real files.

## Build, test, release
```
python update-fixture.py     # only when shell.html ids/options change
python build.py              # writes Akzo-SDD-PBI-Builder.html
node --check src/core.js && node --check src/ui.js
node test-core.cjs           # 55 workflow checks on real temp files
node test-ui.cjs             # real handlers, simulated DOM (not a rendered browser)
node test-ps.cjs             # Windows PowerShell: byte equivalence with core.js, installer actions
node compare-versions.cjs    # deterministic v2.1 / 3.0.0 / 3.1.0 / current evidence (MEASUREMENTS.md)
node benchmark.cjs           # 3.1.0 versus current on identical inputs (docs/PERFORMANCE.md)
node demo-v4.cjs             # deterministic Create PBI -> questions -> validate transcript (docs/V4-DEMO.md)
node release.cjs             # package root files + ../Akzo-SDD-PBI-Builder-<version>.zip, verified
```
`test-ps.cjs` removes the inherited process-scope execution policy override so the
installer runs under the user's real policy. It never adds a bypass.

## Generation contract
`bundle()` returns `schemaVersion: 1`, the ordered `setup` entries (rendered
`template`, literal `text`, or `source: "html"`), the allowed `tokens`, IDE profiles,
precomputed analysis-document blocks, legacy file names, comparison baselines and the
readiness rule data. Both installers render tokens in one pass; an unknown token or
schema stops before any write. The PowerShell side computes only the per-config
values (`New-Config`, `ConvertTo-ConfigJson`, `ConvertTo-JsEscaped`), which
`test-ps.cjs` proves byte-identical for both IDE profiles, references on/off,
Unicode, quotes and backslashes. Bump `schemaVersion` on any incompatible change.
`PBI-Builder.html` is the browser's serialized page in the form and the package file
in PowerShell; those bytes differ, everything else is identical.

## Update contract
Installed files are tracked in `playbook/pbi-builder/installed-files.json`
(schemaVersion 1, not self-hashed). Missing target: create. Identical: unchanged.
Differing with a matching recorded hash: update (needs opt-in). Otherwise: conflict,
which blocks every write. Paths in the old manifest (or the known 2.x names) that the
new version no longer installs: `retire` when unchanged (backed up, removed after all
writes verify) or `retire-conflict` when edited/unowned (kept, reported, not
blocking). All targets are re-read before writing. Failures restore every touched
file. This is not a filesystem transaction.

## Readiness and knowledge
`readiness()` and `Get-Readiness` implement the same rules over `pbi-state.json`
(schemaVersion 2; 1 is read and reported as outdated), the PBI documents,
DECISION-LOG.md and the hashes of repo-file evidence; issue order, messages and the
`review` block are part of the contract. Approval fingerprints are the first 16 hex
characters of SHA-256 over canonical JSON (sorted keys, ordinal; whitespace runs in
strings collapsed; `canon()` / `ConvertTo-Canon`). Scopes are in `READINESS.scopes`.
PowerShell pitfalls met here: variable names are case-insensitive (`$l` overwrites
`$L`) and scoping is dynamic (a local `$sha` hides the script's `$Sha` from callees).
They check completeness and consistency only.

## Decision engine
`questionProgress`, `answerQuestion`, `skipQuestion`, `recordAnswer`, `recordSkip` (core.js)
serve the form's question panel. Writes back up pbi-state.json and DECISION-LOG.md to
history/, refuse when pbi-state.json changed since it was read, and supersede on edit. The
agent applies the same rules in chat (guided-pbi-creation.md); that part is instructions only. `refreshEvidence()` and `-Action RefreshEvidence`
hash raw bytes of repo-relative paths; external paths are skipped (agent records the
revision instead).

## Boundaries
The browser cannot silently select directories, learn absolute paths, authenticate
Copilot or select an agent. The installed agent may read source and write only PBI
documents and knowledge notes; instructions are not an OS sandbox. No model name is
hardcoded. No telemetry, network calls or new dependencies.

## Machine verification still required
Native Edge/Chrome folder dialogs and rendering; Visual Studio/VS Code agent
discovery and tool availability; live Copilot quality, time and usage.

Sources checked 24 September 2026:
https://learn.microsoft.com/en-us/visualstudio/ide/copilot-specialized-agents?view=visualstudio
https://code.visualstudio.com/docs/copilot/customization/custom-agents
https://developer.chrome.com/docs/capabilities/web-apis/file-system-access
