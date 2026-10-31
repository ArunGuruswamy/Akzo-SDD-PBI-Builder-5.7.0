# Akzo SDD PBI Builder 5.0: user guide

You do not need to know the templates, the code or terms such as plugins or workflows. Describe
what you need; the builder asks only for business decisions.

The workflow is: **Start PBI → enter requirements → select the legacy repository → select the
development target → deep analysis → review → approve once → generate → preview and download.**

## Start a PBI
**In the form** (recommended). Open `playbook/pbi-builder/PBI-Builder.html`, or the package's
`Akzo-SDD-PBI-Builder.html`, choose the repository folder and open the **New PBI** tab. It has
four steps:

1. **Requirements**: PBI number (an Azure DevOps number or your own identifier such as
   `LOCAL-12`), title, description and acceptance criteria are required; attachments are
   optional. Acceptance criteria are kept exactly as entered. Missing fields are marked
   where they are, with the reason.
2. **Legacy repository**: choose the configured legacy source (for example
   AN.ColorDMS.Customizations). **Validate** lets you browse to the folder to check its name and
   Git root. **Add or remove repositories** takes you to setup; removing a repository there only
   changes the configuration, never the folder. The form remembers your last choice.
3. **Development target**: "Which project are you developing the PBI for?", one choice:

   | Choice | Implemented in | Read only (reference) | Final PBIs |
   | --- | --- | --- | --- |
   | CDMS + UI | CDMS, shared Angular UI | Legacy | PBI-CDMS.md (with a shared UI section) |
   | DAB + UI | DAB, shared Angular UI | Legacy, **CDMS** | PBI-DAB.md (with CDMS references and a shared UI section) |
   | UI Only | Shared Angular UI | Legacy, CDMS and DAB contracts | PBI-UI.md |
   | Both (CDMS + DAB + UI) | CDMS, DAB, shared Angular UI | Legacy | PBI-CDMS.md, PBI-DAB.md and one PBI-UI.md |

   The form lists each repository's role and path; **Correct repository paths** fixes a missing
   one. DAB always reads CDMS to reuse what CDMS already implements, and never changes it. CDMS
   and DAB share one Angular application, so UI work is planned once.
4. **Review & start**: the analysis mode (Quick, **Deep** by default, or Comprehensive), optional
   extra references, optional details, and a summary. **Start analysis** saves the intake and
   gives you the prompt for Copilot. **Save draft** keeps unfinished work.

If the PBI number already exists, you choose **Resume**, **Review** or **Start New Version** (a new
folder). Nothing is overwritten.

**In Copilot.** Select "Akzo SDD PBI Builder - <your project>" and type `Start PBI` (or Create
PBI, New PBI, Start Development, Implement PBI). The agent asks for what is missing in one
message, then the legacy repository and the development target. Start Development and
Implement PBI prepare the PBI; they never change application code.

The agent then investigates on its own: it reads the actual code (never only file names or older
analysis documents), marks each finding Verified, Proposed, Unverified or Contradicted, and
reports progress at milestones.

## Answer business questions
After investigating, the agent asks only what the request and the code cannot settle, all
together in one **decision review**. A rule your request already states is recorded as a decision
without a question. Each question shows:
- what happens today, what the requirement expects and what is missing;
- its recommendation and why;
- numbered choices: the recommended option, alternatives, then Custom answer and Decide later;
- a ready-to-use answer and the implementation impact with evidence.

Conflicting acceptance criteria are always asked about, never resolved silently.

| Where | How you answer |
| --- | --- |
| VS Code | Choose an option in the question control Copilot shows, or type a custom answer |
| Visual Studio, or when no control appears | Type `1`, `2`, `3`… (the last two are "Custom answer" and "Decide later"); `back` edits your previous answer, `status` shows progress, `why` explains the question |
| The form, Continue tab, **Answer business questions** | Load questions, pick an answer or write a custom one, enter your name, Submit. Edit previous answer and Decide later are there too |

Your answer is saved at once with your name and the time. It decides that one question; it is not
the approval of the PBI. Answered questions are not asked again unless the requirement changes.
The agent keeps its own history copies of every document it changes; you never run a snapshot
command.

## Other commands
| Command | What it does |
| --- | --- |
| `Resume PBI 305915` | Continues a draft or the next open question |
| `Review PBI 305915` | Summarizes status, decisions and open questions |
| `Edit PBI 305915` | Changes details or an earlier answer |
| `Show Decisions 305915` | Lists decisions with who, when and what they replaced |
| `Analyze Legacy 305915` | Explains how the legacy CRM process works, with file and line evidence |
| `Show Technical Flow 305915` | The traced call chain |
| `Extract Plugin Rules 305915 FormulaPlugin` | Writes PLUGIN-RULES.md: each validation and business rule with its condition, exact error message, data needed, whether DAB must implement it, and test cases |
| `Analyze Workflows 305915 Create Paint System` | Writes PLUGIN-WORKFLOW-COVERAGE.md for the classic workflows and custom workflow activities on that operation |
| `Generate Acceptance Criteria 305915` | Proposed Given/When/Then criteria for review |
| `Export PBI 305915` | Points to Review & approve; before approval, the draft clearly marked |
| `Validate PBI 305915` | Explains the readiness check result |

These are phrases for the agent, not editor commands. The number can also be a title or folder.

## Attachments: what to expect
- The agent reads what its tools can open: text, Markdown, source files and usually images
  attached in chat.
- If it cannot open a file (for example some PDF or Word files), it says so and asks for text or
  an export. It never guesses a file's content.
- Nothing in an attachment counts as an approved requirement just because it is written there.

## Review, approve once and download
When the analysis is complete the agent sets the draft to Ready for Review and sends you to the
form: **Continue** tab, select the PBI, **Review selected PBI**. The review shows seven cards: the
PBI, requirements and acceptance criteria, repository analysis, implementation approach (CDMS,
DAB and shared UI), business decisions, untrusted content and sensitive data, and technical
readiness with any blockers. Then:

- **Approve & Generate** (needs your name): records your final approval, bound to a fingerprint
  of exactly what you reviewed, sets the PBI to Development-Ready and generates the final PBIs
  for the target, each as Markdown, Word (DOCX) and JSON. Every file is read back and checked;
  if anything fails, the earlier files are restored and nothing is approved. It is disabled
  while a blocker remains.
- **Request Changes**: saves your change request as a refinement brief and gives you the prompt
  for the agent. Nothing is approved.
- **Save Draft**: saves the review and your note in the PBI's history folder. Nothing is approved.

After generation the **PBI Generated Successfully** window lists each PBI (for Both: CDMS, DAB and
shared Angular UI) with Download DOCX, Download MD, Download JSON and Preview, plus **Download
Complete Package — ZIP** with every PBI and the supporting documents. Downloads are read from the
generated files and refused if a file changed since. Where the browser supports it you choose
where to save. Browsers cannot open File Explorer, so the window shows the PBI folder instead.

Your approval is the approval of the PBI draft only. PO/BA, security, architecture or technical
sign-off that your organization requires is a separate step; the documents say it is not recorded
by this tool. A later change to anything you reviewed makes the approval stale; review and approve
again. The final PBIs carry local draft identifiers; the tool never creates or publishes Azure
DevOps work items.

## Additional implementation references
The development target already decides which repositories are analyzed. Under **Add
implementation references** (Review & start) you can add other configured repositories as extra
read-only references for this PBI. The agent compares each requirement with them in the
"Implementation comparison" section of VALIDATION-MATRIX.md, with file and method references, or
"No matching implementation found". Configure repositories once: form setup (paths typed as
`Name = path`, plus the Legacy, CDMS, DAB and shared Angular UI paths) or the setup window's
**Repositories...** button (Browse per repository). The check confirms completeness and
consistency; it cannot confirm that the content is right or who really approved.

## CDMS, DAB and the legacy rules
The agent reads the legacy code (plugins, workflows, custom workflow activities, JavaScript,
HTML web resources and ribbon commands) and lists every business rule once, with all the places
it was found, in VALIDATION-MATRIX.md. Ask for LEGACY-BUSINESS-RULE-CATALOG.md or
BUSINESS-RULE-OWNERSHIP.md if you want them as separate documents.

## The repository is the source of truth
PBI -> repository discovery -> source investigation -> business-rule validation -> gaps ->
decisions only when blocked -> readiness -> refined PBI and SDD handoff.

The agent reads the application repository itself. It never needs, writes or waits for a separate
end-to-end analysis document. Older analysis documents, including the ColorDMS reports the form
can still install on request, are optional background: never a prerequisite, never evidence of
current behavior, and never deleted by the Builder. Every investigation checks the current code
again. Findings go, briefly and with file references, into EVIDENCE.md and VALIDATION-MATRIX.md.

Required per PBI: REQUEST.md, DRAFT-PBI.md, VALIDATION-MATRIX.md, EVIDENCE.md, DECISION-LOG.md,
OPEN-QUESTIONS.md, pbi-state.json and the final refined PBI. Only on request: PLUGIN-RULES.md,
PLUGIN-WORKFLOW-COVERAGE.md, the rule catalog, shared rules, ownership and acceptance-criteria
documents, and the developer handoff export.

- **CDMS:** a rule an existing CRM plugin already handles (with its registration checked) is
  reused; the PBI says to verify it, not to build it again. Workflow and JavaScript rules are
  included as CDMS API work or verification.
- **DAB:** there is no DAB plugin. Every applicable rule is a DAB requirement, implemented in DAB's
  own code (Azure Functions, CQRS handlers, FluentValidation for input checks, domain services,
  GraphQL). The PBI says what DAB already has, what is partial and what is missing.
- **Both:** one shared set of business rules and decisions, and two separate application PBIs.

Every rule is checked branch by branch (for example Yes and No, failure and rollback). A plugin
that handles the Yes path does not make the rule covered; a missing No path is reported as a
gap with its risk and a proposed approach.

## Handing over to development
On the Continue tab, select the PBI and click **Export developer handoff**. It writes
`business-rules.json` (for the development agent) and `BRANCH-COVERAGE-MATRIX.md` from the PBI's
recorded state, and keeps earlier exports in `history/`. The file separates approved
requirements, proposed requirements and technical findings, and lists every open gap.

Legacy code tells the agent what DAB must do; it never proves what DAB already does. If an
earlier decision left legacy evidence out of a PBI, it stays until you change it.

## Visual Studio: what the agent can read
In Visual Studio, Copilot's agent file tools read only files in the open solution, or in the
opened folder and its subfolders (Microsoft: "Use Agent Mode", FAQ). A repository next to it, such
as `..\AN.ColorDMS.Customizations`, is out of reach unless the folder you open contains it. The
agent checks this before every analysis, reports a source it cannot read as "configured but
inaccessible" (never as missing), and says which conclusions stay unverified.

Repository-level agents are found in the `.github\agents` folder at the repository root, and
skills in `.github\skills` (Visual Studio 18.5 or later; Microsoft Learn, "Use Agent Skills").
Install the Builder at the Git root (the folder with `.git`); the installer warns otherwise.

The agent searches the whole repository, not only the loaded solution. A repository can hold
several solutions, for example plugins in one and JavaScript web resources in a sibling one;
open the repository root as a folder so all of them are reachable. **Discover sources** lists
every solution and, per folder, the kinds of files it holds, including JavaScript that no project
lists. To name the folders that matter in one repository, create
`playbook\pbi-builder\knowledge\SEARCH-SCOPE.md` yourself, for example:

```
# Search scope
- Source/Formula
- Source/WebResources
- Source/Measurement
- Source/MarketColor
```

The installer never writes or overwrites it. Before saying a feature is missing, the agent searches
every relevant layer and reports each finding as found and verified, found but not yet reviewed,
not found within the listed searches, or inaccessible.

| Analysis | Install the Builder into | Role / sources | Open in Visual Studio |
| --- | --- | --- | --- |
| Custom (Legacy CRM/XRM) only | the legacy repository | role `legacy`, legacy source `.` | File > Open > Folder on the repository root (a `.sln` in a subfolder would leave the root, and the Builder's `playbook\` folder, outside the agent's reach) |
| DAB (GraphQL) only | the DAB repository | role `dab`, DAB source `.` | the repository root folder |
| CDMS only | the CDMS repository | role `cdms`, CDMS source `.` | the repository root folder |
| Several repositories | the repository you work in; other sources as relative paths (`../Legacy`) | as above | a common parent folder that contains every clone. Not verified yet: whether Visual Studio still lists an agent stored in a child repository when the opened folder is the parent. Check it with the list below; if the agent does not appear, analyse from each repository in turn |

Never copy application source into the Builder's folders; the Builder reads it where it is.

**Discover sources** (Continue tab of the form) writes `playbook\pbi-builder\knowledge\SOURCE-MAP.md`:
solutions, projects, project references, target frameworks, markers (CRM SDK, workflows, Web
Forms, Azure Functions, GraphQL, FluentValidation, data access) and whether each configured source
could be read. It reads only solution and project files and counts the rest; it never copies
code or configuration values. Run it again when projects change.

### Visual Studio check (once per team machine)
1. Install the Builder (form or `Install-PBIBuilder.cmd`) into the repository, then open the folder
   as in the table.
2. Copilot Chat > agent picker: "Akzo SDD PBI Builder - <project>" is listed (Visual Studio 18.4 or
   later).
3. Select it, open the **Tools** panel and confirm `readfile`, `code_search`, `find_references` and
   `editfiles` are available and enabled (Microsoft notes that custom-agent tool groups can start
   disabled; re-enable them there).
4. Ask: "Check source access." It should name each source as readable, configured but inaccessible
   or not configured, quoting one file it actually read.
5. For several repositories, repeat steps 2 to 4 with the parent folder open.
