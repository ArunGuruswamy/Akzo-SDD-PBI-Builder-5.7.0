# Performance: 5.6.2 versus 5.7.0 (8 November 2026)

`node maintainer/benchmark-570.cjs 7` on one Windows 11 laptop (Node 20.20.2). Both versions run on the same PBI
309446-shaped workspace (DAB + UI, six answered mandatory questions, one attachment); 5.6.2 is the release commit's
`core.js` read from git. Medians of seven runs; counts come from `PBI.measure()`. Wall-clock times on one machine are
indicative, not a promise.

| Measure | 5.6.2 | 5.7.0 | Change |
| --- | --- | --- | --- |
| Approve & Generate, approval to verified handoff (ms) | 163 | 174 | +11 |
| File opens during approval | 144 | 151 | +7 |
| Bytes read during approval | 364,251 | 384,936 | +20,685 |
| File writes during approval (including history/ copies) | 10 | 13 | +3 handoff files |
| Bytes written by approval | 93,439 | 114,066 | +20,627 |
| Generated, hash-verified files | 6 | 9 | +3 |
| Complete Package ZIP: assemble and zip (ms) | 18.8 | 22.7 | +3.9 |
| ZIP entries | 14 | 18 | +3 handoff files, +1 attachment |
| ZIP size (bytes) | 86,807 | 107,990 | +21,183 |
| Start Development: verify and build commands (ms) | — | 68 | new; 63 opens, 0 writes |
| Handoff completeness: targets / manifest files | — | 2 / 8 | DAB and UI; 6 Refined PBI files + 2 handoff files |

The end-to-end test through the real PowerShell installer reports the same shape: 140 → 146 file opens per approval,
98 → 101 repeated opens (`test-e2e.cjs`).

## What the extra work is
- Three prior-state probes and three read-backs of the handoff files: the read-backs are the intentional integrity check
  (each written file must equal what was generated) that the Refined PBIs already had.
- One read of each attachment to record its SHA-256 in the manifest.
- No business analysis runs after approval: the handoff is derived from the approved `pbi-state.json` and the readiness
  report the approval already computed.

## Not optimized
Nothing measured here is a bottleneck: the handoff (with business-rules.json schema 2) adds about 11 ms to an approval dominated by the existing readiness
checks, and Start Development runs once per hand-over. Reusing the review snapshot's attachment hashes would save one small
read per attachment at the cost of coupling two functions; not done.
