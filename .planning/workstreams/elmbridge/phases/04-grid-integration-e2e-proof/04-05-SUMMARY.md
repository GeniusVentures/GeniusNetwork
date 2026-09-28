---
phase: 04-grid-integration-e2e-proof
plan: 05
subsystem: testing
tags: [e2e, settlement, escrow, overtime, cancellation, ipfs, single-node, audit]

requires:
  - phase: 04-01
    provides: stop schema + embedding_file role + envelope stamps (D-04)
  - phase: 04-02
    provides: ProcessElmWorkItem worker path, save branch, production cache
  - phase: 04-03
    provides: ELM splitter + ProcessImage submit branch + rate record
  - phase: 04-04
    provides: ElmSettlementData arithmetic + AsyncPayEscrow chain
provides:
  - GeniusNode::ProcessingDone ELM settlement leg (task-JSON sniff → elm_subtask_map → per-result envelope fetch → windows → AsyncPayEscrow)
  - elm_e2e_test — the milestone acceptance E2E (3 legs: empty-cache 2-work-item, overtime cancelled-no-regrab, non-ELM regression)
  - Anti-scope audit record (JOB-04) with grep-level proofs
  - Deliverable→test matrix (E2E-03 coverage evidence)
affects: [milestone v1.0 completion]

tech-stack:
  added: []
  patterns:
    - "Drainer-pattern ioc wait: work guard + helper-thread drain + cv-bounded wait for any node-thread completion post (4th site: leg-2 tail fetch)"

key-files:
  created:
    - SuperGenius/test/src/processing/elm_e2e_test.cpp
  modified:
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/processing/processing_service.cpp
    - SuperGenius/test/src/processing/CMakeLists.txt

key-decisions:
  - "Overtime leg fires the deadline DURING generation, not before it: single-node transport serves the model from the node's own local store (~1s for 557MB), so a 64-token cap completes legitimately (finish_reason=max_tokens) inside the 18s deadline. The leg caps max_output_tokens at 2048 so generation is still running at expiry and the per-token external-cancel poll converts the deadline Cancel() into finish_reason=cancelled."
  - "elm_cost_clocks_test ElmCostNode legs are FLAKY post-develop-merge (C++ 'vector too long' from node-fixture startup, passes on repeat/isolation) — classified pre-existing, same family as the DEFERRED child_registration/processing_nodes SetUpTestSuite failures in STATE.md; not a Phase 4 blocker."
  - "processing_multi_test has been commented out of the build since 2025-12-09 (upstream commit 3ca011d26, pre-elmbridge) — the E2E-02 regression gate is covered by elm_e2e_test leg 3 + the processing/elm suite battery instead."

patterns-established:
  - "Deadline-vs-work calibration: an overtime proof must ensure the work outlives the deadline — the long pole (download) is NOT long on a single-node fixture (local store hits); size the token budget so generation spans expiry"

requirements-completed: [RES-02, E2E-01, E2E-02, E2E-03, JOB-04]

coverage:
  - id: D1
    description: "Empty-cache single-node 2-work-item E2E: submit→split→grab→download-once→generate→publish→settle with exact-refund proof"
    requirement: E2E-01
    verification:
      - kind: e2e
        ref: "elm_e2e_test.EmptyCacheTwoWorkItemE2E — PASSED 2026-09-28 (27.9s; cold transport, one cache entry, refund = 300−burn−billable recomputed exactly)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Overtime: deadline overrun → terminal cancelled envelope → queue drains, never re-grabbed"
    requirement: E2E-01
    verification:
      - kind: e2e
        ref: "elm_e2e_test.OvertimeLegCancelledNoReGrab — PASSED 2026-09-28 (37.1s; finish_reason=cancelled observed in node log)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Non-ELM regression gate: legacy chunk path unaffected"
    requirement: E2E-02
    verification:
      - kind: e2e
        ref: "elm_e2e_test.NonElmLegacyJobStillSubmits — PASSED (2.0s) + registration_transaction_test/elm_settlement_test/14 sgproc suites green"
        status: pass
    human_judgment: false
  - id: D4
    description: "ProcessingDone ELM settlement wiring (stamps reach the payout)"
    requirement: RES-02
    verification:
      - kind: e2e
        ref: "Leg 1's exact-refund assertion — the refund only computes correctly if ProcessingDone fetched both envelopes and passed real windows into AsyncPayEscrow"
        status: pass
    human_judgment: false

---

## Performance

- Plans: 5/5 complete (this SUMMARY closes 04-05; waves 1-4 previously green)
- E2E full suite: 3/3 legs PASS in one process, ~67s total (leg1 27.9s / leg2 37.1s / leg3 2.0s)
- Regression battery 2026-09-28: elm_splitter_test PASS, elm_settlement_test PASS, elm_e2e_test PASS (ctest), registration_transaction_test PASS (161.7s), elm_validation_mode/elm_lock_timeout/14 sgproc_* suites PASS, sgproc_elm_processor_test PASS (58.4s, fixture-gated)
- Builds: SuperGenius Release green (elm_e2e_test + full engine), GeniusSDK Release solution green (exit 0), GeniusWallet untouched
- Commits: SuperGenius dev_elmruntime 41f7f8492 (+ prior afad5865b, 98fc192da, 15a448030, 7904162b0), SGProcessingManager dev_elmruntime 5c5af6a

## Accomplishments

1. **Task 1 (committed earlier, afad5865b + 15a448030):** ProcessingDone ELM settlement leg — task-JSON sniff, elm_subtask_map inverse, per-result envelope fetch via the drainer pattern (ioc completion-race fix), ElmSettlementData windows into AsyncPayEscrow; payout-notify fix in TransactionManager (CONFIRMED early return starving AsyncWaitForTransactionOutgoing); seed-provider registration for single-node transport; ELM node-TTL scaling from the derived lock timeout at both ProcessingNode::New sites.
2. **Task 2 (closed this session):** Leg 2 green after two root-caused fixes (see Deviations). Full E2E now passes as one process: empty-cache E2E proves D-05/D-08/D-09/D-10 (one download for two subtasks, exact refund), overtime leg proves D-11 (cancelled terminal, no re-grab), leg 3 proves E2E-02.
3. **Task 3:** Regression battery + anti-scope audit + build gates collected below; deliverable→test matrix recorded.

## Task Commits

- SGProcessingManager 5c5af6a — elmbridge 04-05: close ioc completion races in ELM fetch and artifact save
- SuperGenius afad5865b — feat(04-05): ProcessingDone ELM settlement wiring (Pattern 4)
- SuperGenius 98fc192da — test(04-05): E2E bring-up — fixture, publish, overtime, regression legs
- SuperGenius 15a448030 — elmbridge 04-05: E2E bring-up — payout notify fix, seed providers, ELM TTL, e2e test
- SuperGenius 7904162b0 — elmbridge 04-05: advance SGProcessingManager pointer
- SuperGenius 41f7f8492 — test(04-05): overtime leg green — drainer fetch + deadline-fires-mid-generation
- Root 1c94c35, dbda07b — pointer advances (final pointer commit follows this SUMMARY)

## Files Created/Modified

- `SuperGenius/test/src/processing/elm_e2e_test.cpp` — created (98fc192da), green-fixed (41f7f8492)
- `SuperGenius/src/account/GeniusNode.cpp/.hpp` — settlement leg + GetBitswap exposure
- `SuperGenius/src/account/TransactionManager.cpp` — CONFIRMED early-return notify fix
- `SuperGenius/src/processing/processing_service.cpp` — ELM TTL from derived lock timeout (both node-creation sites)
- `SuperGenius/test/src/processing/CMakeLists.txt` — elm_e2e_test registration

## Deliverable → Test Matrix (E2E-03 coverage)

| Phase 4 deliverable | Passing test(s) |
|---|---|
| 04-01: ElmGeneration.stop schema + regen | sgprocbase_elm_job_schema_test; stop firing exercised in elm_e2e_test leg 1 (finish_reason assertion) |
| 04-01: embedding_file role end-to-end | sgprocelmruntime_manifest_test (26/26); E2E fixture publishes + fetches embeddings_bf16.bin over real ipfs:// |
| 04-01: envelope stamps D-04 | sgprocelmruntime_envelope_test; E2E leg 1 asserts finish>grab on both envelopes |
| 04-02: ProcessInternal ELM intercept | sgprocbase_elm_routing_test |
| 04-02: ProcessElmWorkItem (prompt/deadline/stop/stamps/publish) | sgproc_elm_processor_test (fixture); E2E legs 1-2 (prompt fetch, deadline cancel, publication) |
| 04-02: CheckElmValidity stop bounds | sgprocbase_elm_job_schema_test |
| 04-02: save branch + OQ2 digests | E2E leg 1 (ipfs:// artifact fetch, chunk_hashes==1, result_hash non-empty); sgprocmanagerexec_* |
| 04-03: ELM splitter + elm_subtask_map | elm_splitter_test |
| 04-03: ProcessImage ELM submit branch | elm_cost_clocks_test.ElmCostRows/ElmSubmitRejectedBeforeEscrow (submit+hold); E2E legs 1-2 (full submit) |
| 04-03: rate record CRDT sibling | elm_cost_clocks_test.ElmRateRecordPutsSiblingKey (flaky-fixture note below) |
| 04-04: settlement arithmetic + split | elm_settlement_test |
| 04-04: BuildPayoutOutputs ELM branch + parity | elm_settlement_test; payout_outputs_test (non-ELM parity) |
| 04-05: ProcessingDone settlement leg | E2E leg 1 exact-refund proof |
| 04-05: E2E + overtime + regression legs | elm_e2e_test 3/3 |

Every row maps; no unmappable deliverable.

## Anti-Scope Audit (JOB-04, against FEATURES.md Anti-Features)

1. **No proto changes by elmbridge work:** `git log --grep="elmbridge|04-0|elm_"` over `src/**/proto/` in the phase range → ZERO commits. (The two .proto files appearing in the raw `afad5865b^..HEAD` diff — Consensus.proto member_certificate_slots, ValidatorRegistry registry slots — come from the develop merge 39d1f699c's upstream commits a6cb22eb5/ac3817e0d, present in `origin/develop` before elmbridge; not phase work.)
2. **No bidding/negotiation/capability-advertising symbols:** grep over the phase diff's added lines for `bid|auction|negotiat|advertise|inventory` → only incidental matches (comments: "intent-negotiation reshuffle", consensus "re-advertise the signed proposal" — pre-existing consensus-mesh terminology in merged develop code, unrelated to worker bidding).
3. **No /v1 HTTP surface:** `git grep '"/v1|openai'` over `SuperGenius/src` and `SGProcessingManager/{src,include}` → only schema `$id` version strings (`.../v1.0/schema.json`); zero endpoints.
4. **No SuperGenius-side aggregation:** no code combines per-work-item results into a job blob — the only cross-result code is settlement windows (`elm_settlement.cpp`: money arithmetic only, zero content handling). GeniusNode aggregation grep hit is a config-timing comment.
5. **No claims/leases/worker-selection beyond existing grab:** grep `claim.*subtask|lease.*worker|selectWorker` → ZERO.

## GeniusWallet Audit Row (checker I7)

**GeniusWallet: build-green by non-modification.** `git log` across the phase's commits shows ZERO GeniusWallet-source changes; the root-level `M GeniusWallet` submodule entry is a dirty working tree only (generated_plugin_registrant files + a pre-existing pointer drift to dev_almalinux from unrelated tooling runs) — no elmbridge commit touches it and no Dart surface changed.

## Deviations from Plan

1. **Overtime leg premise correction (plan expected download to be the long pole):** single-node transport serves the "download" from the node's own local store in ~1s (it published the blocks; seed-provider registry). The 18s deadline therefore never fired with a 64-token cap — generation finished in ~4s as legitimate `max_tokens` (run2 evidence). Fix: cap `max_output_tokens=2048` so generation spans expiry; the deadline Cancel() + per-token external-cancel poll produce `finish_reason=cancelled`. Committed in 41f7f8492.
2. **Leg-2 tail fetch used the bare `ioc->run()`** (leg 1's drainer fix wasn't ported): completion posted from node threads arrived after run() drained → "Value of: ok" failure with a green pipeline. Ported the drainer pattern (4th site).
3. **processing_multi_test not in build** (commented out upstream 2025-12-09, commit 3ca011d26, pre-elmbridge): E2E-02's plan-named leg is unavailable; gate covered by elm_e2e_test leg 3 (same-node legacy job) + registration_transaction_test + the 14-suite sgproc battery + processing_* suites.
4. **Run-1 AV (heap corruption, `AZJ77akme` garbage + 0xC0000005 during cold weight fetch) never reproduced** across 4+ subsequent full runs after the ioc completion-race fixes (SGPM 5c5af6a + test-side drainers). Attributed to that race family; flagged for recurrence watch.

## Issues Encountered

- **elm_cost_clocks_test ElmCostNode legs flaky (pre-existing):** intermittent `C++ exception "vector too long"` from node-fixture startup (~1 leg fails per full run; passes on repeat/isolation; test file unchanged since 09-14; passed the 09-24 battery). Classified post-develop-merge node-fixture startup flake — same family as the DEFERRED child_registration/processing_nodes SetUpTestSuite failures already recorded in STATE.md. Not a Phase 4 blocker; needs dedicated debugging.
- Windows log-rotation "file in use" errors on sgnslog rename: benign noise across node fixtures.

## Self-Check: PASSED

- elm_e2e_test 3/3 (single process, 2026-09-28)
- Regression battery green (see Performance)
- GeniusSDK Release build exit 0; SuperGenius Release green
- Anti-scope audit: 5/5 clean
- Chain consistency: SGPM 5c5af6a ⊆ SuperGenius HEAD (41f7f8492); root pointer commits 1c94c35/dbda07b + final pointer (post-SUMMARY)

## User Setup Required

- `SGPROC_ELM_TEST_MODEL_DIR` must point at the staged fixture (six files, hashes per `SuperGenius/SGProcessingManager/test/fixtures/README.md`); staged + verified at `SuperGenius/SGProcessingManager/test/fixtures/elm-test-model` on this machine.

## Next Phase Readiness

- This plan closes Phase 4 and the v1.0 milestone's final wave. Milestone completion flows through phase verification → `/gsd-audit-milestone`/`/gsd-complete-milestone` at the user's discretion.
