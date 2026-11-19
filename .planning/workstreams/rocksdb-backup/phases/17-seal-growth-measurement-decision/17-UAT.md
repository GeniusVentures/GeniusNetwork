---
status: testing
phase: 17-seal-growth-measurement-decision
source: [17-VERIFICATION.md]
started: 2026-11-19T05:35:00Z
updated: 2026-11-19T05:35:00Z
---

## Current Test

number: 1
name: Workload-spectrum representativeness
expected: |
  The measured spectrum (deep/wide/mixed shapes × ¼/½/1 erase fractions × 10^6/10^7 scale, 10^8 extrapolated-and-flagged; per-row bytes measured 52.000 at every scale and shape; density matrix exact with round-trips) is a defensible "representative workloads" reading of SEAL-01 per D-05/D-13.
awaiting: user response

## Tests

### 1. Workload-spectrum representativeness
expected: deep (64/depth-63) + wide (73/depth-2/breadth-8) + mixed (41/depth-32/breadth-9) shapes at ¼/½/1 erase fractions; 10^6 + 10^7 materialized on the growing root (warm/cold/reopen), 10^8 extrapolated and flagged; every number committed in seal_growth_evidence.json.
result: [pending]

### 2. D-12 verdict ratification
expected: "VALIDATED — in-band, with noted limitation" honors SC2: band (±25%) derived and committed before the verdict; walk profile (Completed, visited 64, walk_gaps 0) contains no bound-binding evidence; the hermetic topology's below-envelope reading is correctly recorded as a topology artifact (in-band-with-noted-limitation) rather than dead-weight evidence; zero production touch with the empty SuperGenius/src diff as the branch's evidence.
result: [pending]

### 3. Prohibition-block ratification
expected: The four judgment-tier prohibitions hold on the collected deterministic evidence — (i) read/count/time-only posture (source gates: zero deletion/compaction; grow root never wiped by code); (ii) no vendored edit / no spill-compaction-sidecar machinery (vendored tree clean; options table defers redesign to triggers); (iii) no production change beyond the verdict-gated constant (src diff EMPTY — the verdict was in-band so nothing was edited); (iv) no evidence misrepresentation (10^8 flagged everywhere; every number cites the committed JSON; verifier cross-checked all cited numbers exact).
result: [pending]

### 4. Floor seeding-rate window semantics (minor)
expected: The floor status line reports an in-loop rate (158,706/s at 17-01's first run; generation-inclusive) while the JSON records the total-elapsed rate (143,313/s) — both labeled generation-inclusive; confirm the window semantics are acceptable (does not affect the decision record, which cites the JSON value).
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
