---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
verified: 2026-11-17T00:00:00Z
status: human_needed
score: 27/28 must-haves verified
covered_files:
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-REVIEW.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-REVIEW-DISPOSITION.md
  - SuperGenius/src/account/proto/SGTransaction.proto
  - SuperGenius/src/crdt/cold_read_fallback.hpp
  - SuperGenius/src/crdt/crdt_datastore.hpp
  - SuperGenius/src/crdt/globaldb/CMakeLists.txt
  - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
  - SuperGenius/src/crdt/impl/crdt_datastore.cpp
  - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
  - SuperGenius/src/transaction/PruneEligibility.cpp
  - SuperGenius/src/transaction/PruneEligibility.hpp
  - SuperGenius/src/transaction/TransactionManager.cpp
  - SuperGenius/src/transaction/TransactionManager.hpp
  - SuperGenius/src/transaction/TxPruner.cpp
  - SuperGenius/test/src/account/prune_eligibility_test.cpp
  - SuperGenius/test/src/blockchain/CMakeLists.txt
  - SuperGenius/test/src/blockchain/node_startup_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp
  - SuperGenius/test/src/crdt/cold_prune_gate_test.cpp
  - SuperGenius/test/src/crdt/globaldb_erase_test.cpp
covered_digest: "v2:sha256:dcd8f173e74d7920a4179655720c4a054ef4199a5f4dbe9cb0272daef3f3ed8e"
behavior_unverified: 1
overrides_applied: 0
behavior_unverified_items:
  - truth: "PROBE-LIFT (SERVE-01 concurrency, backstop): the evidence consult is a stateless point lookup over an immutable marker row — concurrent or interrupted reads cannot interleave into a serve; the only mutable state (LRU/hot cache) is written exclusively after a NoEvidence classification"
    test: "Interleave a TxPruner erase commit with an in-flight serve: pause/observe the window between FetchNodeFromColdStorage's consult (graphsync_dagsyncer.cpp:868) / the re-warm worker's consult (ColdReadService.cpp:439) and the cold Get + Rehydrate, committing the /prune/blk marker mid-window on a CID the consult already classified NoEvidence"
    expected: "Structurally: the consult is a write-once GetRaw point lookup and Rehydrate runs only on the NoEvidence path — the truth's letter holds (verified by code reading). Dynamically: the code review (CR-01, disposition open) shows a marker committing inside the consult->Get->Rehydrate window is outrun and erased bytes are written hot, persisting until eviction — the truth's spirit is defeated by this window on getNode/GetNodeWithoutRequest/re-warm (the walk path is protected by InitCIDBlock deferral, crdt_datastore.cpp:526-529)"
    why_human: "A concurrency interleaving invariant — no test in the phase exercises it (the plan explicitly claimed only the single-threaded repeat-read stability leg and scheduled the structural argument for human review at phase verification); deciding whether CR-01 blocks phase completion or rides to Phase 16 (fix) / Phase 19 TEST-02 (deterministic repro) is a maintainer disposition call recorded as open in 15-REVIEW-DISPOSITION.md"
human_verification:
  - test: "Decide CR-01 disposition (serve-side TOCTOU: TxPruner erase committing between the evidence consult and Rehydrate resurrects erased bytes hot): accept the recorded deferral — fix lands as a pre-Phase-16 gsd-quick (re-consult after the slow cold Get, before Rehydrate, per 15-REVIEW.md's patch) or as an explicit Phase 16 requirement — or require the fix before this phase is sealed"
    expected: "A recorded maintainer decision in the disposition ledger; no code change is required by THIS phase's contract (all five ROADMAP SCs and all authored must-haves pass; the two research-discovered bugs are killed and proven), but the disposition must not remain open through Phase 16 planning"
    why_human: "The review is advisory and its finding is a genuine concurrency-window defect on the phase's headline invariant, but the phase's verification contract explicitly excluded concurrency testing and deferred the structural argument to this checkpoint; accepting a Critical's deferral is a judgment call only the maintainer can make"
  - test: "Acknowledge the executor-push posture (prohibition 'the executor never pushes anywhere — all commits stay local', verification: backstop, all three plans)"
    expected: "All six phase commits verified present and local on dev_coldstorage_additions at af644481f; no evidence of any executor push; confirm this matches expectation (Phase 13 precedent: pushes are done by the user)"
    why_human: "Push events are not reconstructible post-hoc from the local repository; process posture, not a code property"
---

# Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery Verification Report

**Phase Goal:** Evidence outranks bytes on every read path — serving and the forced walk distinguish pruned (terminal refusal) from evicted (restorable from cold), fixing both research-discovered bugs, with hermetic evidence-aware fakes backing every suite.
**Verified:** 2026-11-17
**Status:** human_needed
**Re-verification:** No — initial verification

**Codebase under verification:** SuperGenius submodule, branch `dev_coldstorage_additions`, HEAD `af644481f` (verified: `git rev-parse HEAD` = `af644481f7e41d9cdda91fa4b25b678b1a865d3c`, tree clean). Phase diff base `095c8c502`. All six claimed commits present: `638053925`, `548264dc4` (15-01), `d6a2dc08b`, `de37f79e8` (15-02), `f1f4c4768`, `af644481f` (15-03). Diff stat: 26 files, +4088/−59 — exactly matching the three SUMMARYs' combined key-files lists (no unclaimed files, no claimed-but-missing files).

## Goal Achievement

### Observable Truths

#### Plan 15-01 (13 truths) — the serving tracer

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1 core: getNode/GetNodeWithoutRequest return HISTORY_PRUNED_LOCALLY for a /prune/blk-marked CID even when cold bytes exist; consult precedes the cold Get AND Rehydrate; re-warm worker skips | ✓ VERIFIED | Consult at top of hooked path before `cold_read_hook_->Get` (`graphsync_dagsyncer.cpp:866-885`); `GetNodeWithoutRequest` returns the cold-leg result directly (`:841-846`); re-warm consult before Get (`ColdReadService.cpp:439-465`); legs S1 + `Rewarm_PrunedEvidenceSkipsRewarmWorker` + `Masquerade_PrunedMarkerWithColdBytesStillRefuses` assert refusal + hot-store absence + repeat-read stability |
| 2 | SC2 core: no-evidence CID with cold bytes serves through the cold chain and Rehydrates verbatim (evict ≈ DETACH) | ✓ VERIFIED | NoEvidence `break` into unchanged v1.1 body (`graphsync_dagsyncer.cpp:884-893`); S2, product cell `NoHot_Cold_None`, `Masquerade_EvictedColdBytesNoMarkerServesAndStaysArchive` (serve + re-warm + presence TRUE + subsequent read hot) |
| 3 | Node-local terminality: the two refusals never fall through to the peer leg — returned before GetRouteKeys | ✓ VERIFIED | `graphsync_dagsyncer.cpp:421-427` early-returns both values immediately after the cold-leg failure check, before `GetRouteKeys` (`:429`); stub leg `StubPredicate_ClassifiesConsultAndServeTerminalityTableDriven` asserts the ordering |
| 4 | Distinctness: pruned is a NEW appended Error value with its own string case — never folded into CID_NOT_FOUND; zero wire/proto changes beyond the node-local record | ✓ VERIFIED | Enum values appended after `COLD_STORAGE_UNAUTHORIZED` (`graphsync_dagsyncer.hpp:108-109`) with BIP-159-NOPRUNE-style Doxygen; one-line string cases added (diff hunk @ :93); proto diff is append-only `PrunedBlockRecord` (fields 1-3, node-local comment) — review confirmed wire compatibility |
| 5 | Fail-closed malformed: ParseFromArray failure AND zero-length value classify Malformed (PRUNE_EVIDENCE_CORRUPT) — never absent evidence, never served | ✓ VERIFIED | Explicit `marker.value().empty() \|\|` checks in BOTH decode surfaces (`globaldb.cpp:896-911`, `PruneEligibility.cpp:316-331` — the 15-01 deviation #3 fix); S4 covers garbage + zero-length on both read surfaces; product `Garbage`/`Empty` cells |
| 6 | D-01 atomic staging: one erase = ONE compose-locked WriteBatch carrying erase + BOTH marker pairs; widening touches only parameter + staging loop | ✓ VERIFIED | Signature `const std::optional<std::vector<std::pair<Buffer, Buffer>>> &extra_entries = std::nullopt` (`globaldb.hpp:521-524`); staging loop at same batch position before single commit (`globaldb.cpp:1632-1642`); guards/compose lock/post-commit seal re-assert untouched (diff hunks in EraseEntry region: only @@1558,11→1632,16); `ColdPruneEraseInterruptTest` steps 1/2/3 prove all-or-nothing across both namespaces + retry epilogue |
| 7 | D-02 record shape: /prune/blk value is a PrunedBlockRecord with /prune/tx hash back-reference + erased-at generation threaded from RunCycle | ✓ VERIFIED | `BuildPruneBlockMarkerEntry` (`PruneEligibility.cpp:333-358`); `TxPruner.cpp:298-301` threads generation; S3 and gate legs assert `pruning_tx_hash()` + `erased_at_generation() == kTestGeneration` |
| 8 | D-03 fresh start: no backfill, no /prune/tx-scan fallback — absence of a row is NoEvidence, full stop | ✓ VERIFIED | The production consult is a single GetRaw point lookup (`globaldb.cpp:874-895`); `LookupPrunedBlockEntry` NOT_FOUND comment + no scan code anywhere in the diff; absence of scan verified by reading both decode surfaces in full |
| 9 | D-04 posture: HasBlock body and four-term bool answer byte-unchanged; every classifying surface routes through the ONE predicate installed at the OpenColdStorageStack seam | ✓ VERIFIED | Zero diff hunks intersect HasBlock window :705-748 (git hunk-window check: hunks at 93/343/385/397/426/792 only); single predicate = the GlobalDB lambda installed via `SetPruneEvidenceLookupOnColdReadService` (`globaldb.cpp:870-918`, between service assignment :852 and `StartColdReadService` :919); flip-test proves every surface moves together while `HasBlock` keeps TRUE |
| 10 | Disabled-build bar: with cold off (null hook), no consult ever runs; read behavior byte-identical to 095c8c502 | ✓ VERIFIED | Null-hook early return before the consult (`graphsync_dagsyncer.cpp:857-862`); S5 asserts the pre-phase not-found shape and explicitly neither refusal value; W4 proves the walk-side posture |
| 11 | PROBE-LIFT matrix boundary cells stay distinct across {evidence}×{cold} + hot-present dedup | ✓ VERIFIED | 16-cell `INSTANTIATE_TEST_SUITE_P(ServeMatrixCells, …)` enumerating {Hot,NoHot}×{Cold,NoCold}×{None,Pruned,Garbage,Empty} with per-cell outcome assertions incl. hot-present-serves-hot and evidence-without-cold-bytes-refuses |
| 12 | PROBE-LIFT empty value is a Malformed leg, not NoEvidence | ✓ VERIFIED | `Empty` evidence variant in the serve product; `EmptyBadMessage` walk cell; S4 zero-length case |
| 13 | PROBE-LIFT SERVE-01 concurrency backstop (stateless consult; mutable state written only after NoEvidence) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Letter verified by code reading (GetRaw point lookup over a write-once row; Rehydrate only on the NoEvidence path). No test exercises concurrent interleaving — the plan claimed only repeat-read stability and scheduled the structural argument for human review at phase verification. The code review (CR-01, Critical, disposition **open**) shows the adjacent consult→Get→Rehydrate window admits a mid-serve erase commit that resurrects erased bytes hot on getNode/GetNodeWithoutRequest/re-warm (walk protected by InitCIDBlock). See Human Verification |

#### Plan 15-02 (7 truths) — the forced walk

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 14 | RECOVER-02: GC-evicted ancestor (cold-resident, no evidence) restored by the walk through getNode's cold-before-peers chain; hot again; skipped_pruned unmoved | ✓ VERIFIED | D-05 NoEvidence fall-through to bounded fetch (`crdt_datastore.cpp:527-547`); W1 `ForcedWalkRestoresColdResidentAncestor` (Completed, fetched=1, restored=1, skipped_pruned=0 — recorded counters) + datastore-level `NoEvidenceRestore` product cell |
| 15 | RECOVER-03: evidence-bearing ancestor skipped with ++skipped_pruned; CanRestoreElement stays terminal authority at element level, byte-untouched | ✓ VERIFIED | Pruned skip branch (`crdt_datastore.cpp:506-514`); single PruneEligibility.cpp hunk is a pure insertion at :285 — CanRestoreElement :156-170 has zero intersecting hunks; W2 asserts `CanRestoreElement(...) == false` directly (:1027-1029) + Completed, skipped_pruned≥1, hot absence, element unrestorable; `PrunedSkip` walk cell |
| 16 | RECOVER-04 abort-never-skip: true gap → ++walk_gaps, distinct FORCED_WALK_GAP failure, loud CID-naming log, Incomplete with frontier CLEARED — never skipped_pruned/deferred, never continued processing | ✓ VERIFIED | Gap mapping (`crdt_datastore.cpp:548-568`); abort routing clears frontier without touching errors (:376-405); `FORCED_WALK_GAP` enum (`crdt_datastore.hpp:120`); W3 asserts Incomplete, walk_gaps≥1, skipped_pruned==0, deferred==0, errors==0, visited fixed at 2 after abort; `NoEvidenceGap` walk cell |
| 17 | RECOVER-04 per-CID budget: kForcedWalkPeerFailoverPerCid = 8 named constant with recorded derivation, NO config knob; 1-arg getNode callers unchanged | ✓ VERIFIED | `graphsync_dagsyncer.hpp:57-82` (three-converging-8s derivation + Phase 17 re-tune note + explicit no-knob statement); route-loop budget check exits into existing ROUTE_NOT_FOUND terminal path with budget-naming log (`graphsync_dagsyncer.cpp:483-492`); 1-arg virtual delegates with unbounded sentinel (:344-352); W3 abort log names budget 8; failover mesh assertion `EXPECT_LE(…, kForcedWalkPeerFailoverPerCid)` |
| 18 | Cold-disabled walk posture: null hook preserves today's skip exactly | ✓ VERIFIED | nullopt leg returns the legacy skip shape (`crdt_datastore.cpp:493-503` with the sealed+missing-without-cold reasoning comment); W4 `ColdDisabledWalkPreservesLegacyPruneBoundarySkip` (Completed, skipped_pruned≥1, walk_gaps==0) |
| 19 | Malformed evidence in the walk fails closed: bad_message failure counted in errors, walk Incomplete | ✓ VERIFIED | `crdt_datastore.cpp:520-527`; `GarbageBadMessage` + `EmptyBadMessage` walk cells (Incomplete, errors=1, walk_gaps=0, never resurrect) |
| 20 | PROBE-LIFT walk ordering unchanged (FIFO frontier + scheduled-set dedup; no new ordering claimed) | ✓ VERIFIED | No ordering change in the diff; W1/W2 walk shapes (visited=2, FIFO head-then-ancestor) consistent with the existing frontier discipline |

#### Plan 15-03 (8 truths) — the verification surface

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 21 | SC5 product: {hot}×{cold}×{evidence}×{serve, walk visit, erase-gate} — every cell asserted, none dropped | ✓ VERIFIED | `INSTANTIATE_TEST_SUITE_P` lists enumerate exactly 16 serve + 5 walk cells (read in full — per-cell branch asserts the specified outcome incl. no-resurrection epilogue); erase-gate column in `cold_prune_gate_test.cpp` (both-marker staged, 3 interrupt steps, deferral-no-marker, cold-off-stages-marker); TEST_F/TEST_P inventory = 32 legs matching the SUMMARY's 9 Matrix + 2 Rewarm + 16 ServeProduct + 5 WalkProduct exactly; review independently confirmed the enumeration |
| 22 | SC2 masquerade counter-tests both directions, red-first | ✓ VERIFIED | `Masquerade_PrunedMarkerWithColdBytesStillRefuses` + `Masquerade_EvictedColdBytesNoMarkerServesAndStaysArchive`, both carrying red-first provenance comments naming the killed pre-phase behavior |
| 23 | SC3 source-consistency: flipping the seeded row moves every classifying surface together; four-term bool keeps TRUE (one predicate, many shapes) | ✓ VERIFIED | `ConsistencyFlip_EveryClassifyingSurfaceMovesTogether` (3 phases: consult + getNode + GetNodeWithoutRequest move NoEvidence→Pruned→Malformed; classification-must-MOVE assertions) + `Rewarm_ConsistencyFlipMirrorsServeSurfaces` (worker gate flips with the same table; HasBlock TRUE asserted in masquerade-A and S3) |
| 24 | D-01 atomicity at the erase gate: every interrupt step aborts with NEITHER marker NOR erase; deferral stages no /prune/blk | ✓ VERIFIED | `ColdPruneEraseInterruptTest` parameterized over steps 1/2/3 (value present + both markers absent + retry completes with both markers — no poisoned state); deferral leg asserts `PrunedBlockLookup::NOT_FOUND` for the deferred group |
| 25 | SERVE-04 requester failover on cold-enabled nodes: pruned peer → serving archive completes; no blacklist; CID-scoped; bounded ≤ kForcedWalkPeerFailoverPerCid | ✓ VERIFIED | `ColdEnabledPrunedPeerRefusalFailsOverToServingPeer`: Part 1 deterministic ordered-AddRoute failover, Part 2 mesh window with `EXPECT_LE(GetRootFetchAttemptsForTest(), kForcedWalkPeerFailoverPerCid)`, Part 3 functional not-blacklisted (light still serves fresh puts) + `IsOnBlackList` false throughout + storage-deterministic single-route refusal with hot absence on both ends |
| 26 | A5 discipline: zero assertions on guessed wire-status constants; observed transport recorded, never EXPECTed | ✓ VERIFIED | Read the failover leg in full — only public-consequence EXPECTs; RS_NOT_FOUND observed-posture recorded in code comments; review confirmed zero wire-constant EXPECTs |
| 27 | PROBE-LIFT boundary cells: hot-present+PRUNED serves hot; evidence+no-cold refuses; cold+no-evidence restores | ✓ VERIFIED | `Hot_*_Pruned/Garbage/Empty` cells assert hot serve (dedup posture documented in-code); `NoHot_NoCold_Pruned` asserts refusal-without-cold-bytes; `NoHot_Cold_None` asserts restore |
| 28 | PROBE-LIFT zero-length in walk-visit and erase-gate columns, not only serve | ✓ VERIFIED | `EmptyBadMessage` walk cell (Incomplete, errors=1). The erase-gate column produces rather than classifies evidence (staging legs); production never writes zero-length rows — pinned by S3/gate assertions that staged records parse with the expected generation/hash, and by `BuildPruneBlockMarkerEntry`'s always-nonzero serialization |

**Score:** 27/28 truths verified (1 present, behavior-unverified — the concurrency backstop, routed to Human Verification)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/src/account/proto/SGTransaction.proto` | PrunedBlockRecord beside PrunedTransactionRecord | ✓ VERIFIED | Append-only, fields 1-3, node-local-only comment (diff read) |
| `SuperGenius/src/transaction/PruneEligibility.hpp/.cpp` | Block-marker family (prefix, enum, 4 functions) | ✓ VERIFIED | All six symbols present; fail-closed decode with explicit empty check; CanRestoreElement untouched |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp/.cpp` | EraseEntry vector widening + staging loop + lambda install | ✓ VERIFIED | :521-524 signature; :1632-1642 loop; :870-918 install with NOT_FOUND→NoEvidence / decode-error→Malformed mapping |
| `SuperGenius/src/crdt/globaldb/CMakeLists.txt` | SGTransactionProto PRIVATE link | ✓ VERIFIED | :53 within crdt_globaldb link block |
| `SuperGenius/src/crdt/cold_read_fallback.hpp` | PruneEvidenceClass + pure virtual | ✓ VERIFIED | :53-67 enum, :184 virtual; no transaction-layer type crosses |
| `SuperGenius/src/crdt/globaldb/ColdReadService.hpp/.cpp` | std::function member + setter + override; re-warm consult before Get | ✓ VERIFIED | :483 override; :439-465 worker consult skips Pruned/Malformed with log lines |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp/.cpp` | Two refusal Error values + string cases; consult; getNode terminality; budget + bounded overload + accessor | ✓ VERIFIED | :108-109 enum; :866-885 consult; :421-427 terminality; :57-82 constant; :344-362 delegates/accessor |
| `SuperGenius/src/transaction/TransactionManager.hpp/.cpp` | Trailing defaulted generation; 2-element marker vector from same resolved path+cid | ✓ VERIFIED | :4752-4765 vector build + widened EraseEntry call |
| `SuperGenius/src/transaction/TxPruner.cpp` | RunCycle generation threading | ✓ VERIFIED | :298-301 |
| `SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp` | Hermetic Tier-1 suite, S1-S5 → full 32-leg product | ✓ VERIFIED | 1994 lines; leg inventory verified cell-by-cell; hermetic.invalid + InMemory clients + TeardownStack discipline |
| `SuperGenius/test/src/blockchain/node_startup_test.cpp` | W1-W4 walk legs | ✓ VERIFIED | :825/:948/:1076/:1216 with all specified counter and state assertions |
| `SuperGenius/test/src/crdt/cold_prune_gate_test.cpp` | Both-marker + interrupt + deferral + cold-off gate legs | ✓ VERIFIED | :934-950, :1057-1069, :1157-1174, :1176-1270 |
| `SuperGenius/test/src/crdt/globaldb_erase_test.cpp` | Cold-enabled refusal-failover extension | ✓ VERIFIED | :1431-1651, three-part proof + single-route refusal |
| CMake registrations (crdt + blockchain test CMakeLists) | Tier-1 registration under SGNS_COLD_STORAGE | ✓ VERIFIED | `set_tests_properties(cold_evidence_matrix_test PROPERTIES LABELS "Tier1")` (:430); blockchain target compile definition + link; globaldb_integration_test guarded cold links |
| `ColdStorageStack.hpp/.cpp/.cpp(stub)` (deviation add) | SetPruneEvidenceLookupOnColdReadService bridge + ODR twin | ✓ VERIFIED | Present in diff (+22/+13/+11); the gated-type boundary discipline documented in SUMMARY deviation #1 |

All artifacts: exists ✓, substantive ✓, wired ✓ (every production symbol is consumed at its downstream site — predicate → syncer walk + cold leg + re-warm; markers → erase batch → decode surfaces; budget → walk fetch + mesh assertion), data flowing ✓ (no static/hollow returns anywhere in the chain; the classification derives from a real GetRaw over seeded/production-written rows in every leg).

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| TxPruner::RunCycle(generation) | ONE WriteBatch (erase + /prune/tx + /prune/blk) | EraseTransactionEntryPruned → WithMarker → BuildPruneMarkerEntry + BuildPruneBlockMarkerEntry → EraseEntry(vector) | ✓ WIRED — S3 + gate legs prove end-to-end with production-built evidence |
| GlobalDB ctor | Every classifying surface | SetPruneEvidenceLookupOnColdReadService(lambda) → ColdReadFallback::LookupPruneEvidence → syncer consult + walk consult + re-warm gate | ✓ WIRED — flip-test proves single-source fan-out |
| FetchNodeFromColdStorage refusal | Requester failover | getNode early-return before GetRouteKeys → RecordCIDFailure → serving peer | ✓ WIRED — failover leg Part 1/2/3 green |
| ProcessForcedWalkCID | Bounded recovery + abort | LookupPruneEvidence → getNode(cid, kForcedWalkPeerFailoverPerCid) → walk_gaps → frontier clear → Incomplete | ✓ WIRED — W1-W4 + 5 walk cells |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| SERVE-01 | 15-01 | Pruned semantics even when cold bytes exist; consult before serving; no resurrection | ✓ SATISFIED | Truths 1, 5, 10-13; S1/S4/S5; product cells; masquerade-A; failover single-route refusal |
| SERVE-02 | 15-01 | GC-evicted CID served through cold chain + re-warm; evict ≈ DETACH; masquerade counter-tests | ✓ SATISFIED | Truths 2, 22; S2; masquerade-B; NoHot_Cold_None |
| SERVE-03 | 15-01, 15-03 | Three-way answer consistent via ONE role-aware GlobalDB-owned predicate | ✓ SATISFIED | Truths 9, 23 — source-consistency per the locked D-04 ruling (flip-test; HasBlock keeps its bool projection, body unchanged) |
| SERVE-04 | 15-01, 15-03 | Pruned distinct from not-found at protocol surface; requesters fail over correctly | ✓ SATISFIED | Truths 3, 4, 25, 26 |
| RECOVER-02 | 15-02 | Walk restores GC-evicted ancestors from cold; never conflates with pruned | ✓ SATISFIED | Truth 14; W1; NoEvidenceRestore |
| RECOVER-03 | 15-03 | Walk never resurrects erased elements; CanRestoreElement terminal | ✓ SATISFIED | Truth 15; W2 + element-level assertion; byte-identity gate |
| RECOVER-04 | 15-02 | Bounded per-CID failover; walk-gaps abort-never-skip | ✓ SATISFIED | Truths 16-18; W3/W4; budget constant + routing |
| TEST-01 | 15-01, 15-03 | Hermetic tri-state evidence fakes backing every suite; refusal matrix as a product | ✓ SATISFIED | Truths 11, 21, 22, 27, 28 — real-GlobalDB seeding PRIMARY + table-driven stub SECONDARY; 16+5+gate-column product; Tier-1 hermetic registration |

**Orphan check:** REQUIREMENTS.md maps exactly SERVE-01..04, RECOVER-02..04, TEST-01 to Phase 15 — all eight claimed by plans (15-01: SERVE-01/02/03 + TEST-01; 15-02: RECOVER-02/03/04; 15-03: SERVE-03/04 + TEST-01). No orphans, no gaps in coverage. (Informational: RECOVER-01 remains booked to Phase 13 in REQUIREMENTS.md traceability — a Phase-13 bookkeeping matter, not this phase's scope.)

### Behavioral Spot-Checks

Per verification instructions, heavy suites were NOT re-run; recorded suite evidence (Tier-1 15/15, regression 10/10, 32/32 matrix legs, W1-W4 counters, direct gtest filters for the new gate/failover legs) was produced on exactly the verified HEAD `af644481f` by the executors, and the independent code review cross-read the assertions. Provenance spot-checks performed instead:

| Check | Method | Result | Status |
|-------|--------|--------|--------|
| Commit provenance | `git log 095c8c502..af644481f` | All 6 claimed commits present, messages match plans | ✓ PASS |
| Leg-count claim (32) | TEST_F/TEST_P inventory in cold_evidence_matrix_test.cpp | 9 Matrix + 2 Rewarm + 16 ServeProduct (INSTANTIATE list read) + 5 WalkProduct = 32 | ✓ PASS |
| HasBlock :705-748 non-intersection | git hunk-window check vs 095c8c502 | 0 intersecting hunks | ✓ PASS |
| CanRestoreElement :156-170 non-intersection | git hunk-window check vs 095c8c502 | Single pure-insertion hunk at :285 only | ✓ PASS |
| Layering (src/crdt must not include/link PruneEligibility) | `git grep PruneEligibility -- src/crdt` | Comments + CMake comment only — no include, no link | ✓ PASS |
| Debt markers added by phase | `git diff 095c8c502..af644481f \| Select-String '^\+.*TODO\|TBD\|FIXME\|XXX'` | Zero added (pre-existing TODOs confirmed untouched) | ✓ PASS |

### Probe Execution

Not applicable — no `probe-*.sh` scripts declared by the plans; the plans' `<verify>` probes are Select-String structural counts re-derived here (all satisfied: enum=2≥2, cpp-symbols≥5, vector-widening=1, family≥5, seam≥3, service=2, caller≥2, walk-matrix≥4, gate-file≥5, erase-file≥3).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| graphsync_dagsyncer.cpp | 866-895 | CR-01: serve-side TOCTOU — consult→Get→Rehydrate window not serialized against a concurrent erase commit; resurrected bytes persist until eviction (hot legs never re-consult) | ⚠️ Warning (review Critical; disposition open) | Concurrency-window defeat of the headline invariant on getNode/GetNodeWithoutRequest/re-warm; walk path protected (InitCIDBlock deferral). Outside the phase's tested contract; see Human Verification |
| globaldb.cpp | 874-876 | WR-01: evidence lambda fails OPEN on CID::toString() error (prefix-only key → NoEvidence) | ⚠️ Warning | Requires a degenerate in-memory CID; contradicts Pitfall 7 spirit; small same-file fix |
| graphsync_dagsyncer.cpp | 493 | WR-02: budget consumed by peers whose RequestNode fails synchronously (no refund) | ⚠️ Warning | Fail-closed direction (bound never exceeded); RECOVER-02 availability only |
| PruneEligibility.cpp :295-331 / globaldb.cpp :870-918 | — | IN-01: two parallel decoders of /prune/blk (helper has no production caller) | ℹ️ Info | Test-pinned parity; consolidation candidate |
| TransactionManager.hpp :1100-1102 | — | IN-02: default generation=0 records has_erased_at_generation=true synthetically | ℹ️ Info | Latent (TxPruner is sole caller, passes real value) |
| crdt_datastore.cpp :564 | — | IN-03: dead `: 0` arm in walk-gap abort log | ℹ️ Info | Cosmetic |

No 🛑 blockers: no debt markers added, no stubs, no hollow data paths, no silent cell drops.

### Human Verification Required

### 1. CR-01 disposition — serve-side TOCTOU (decision)

**Test:** Decide the disposition of review finding CR-01 (15-REVIEW-DISPOSITION.md, status `open`): a TxPruner erase committing between the evidence consult and the cold Get/Rehydrate resurrects erased bytes hot on getNode/GetNodeWithoutRequest/re-warm; the hot path never re-consults, so the resurrection persists until eviction. Options per the disposition's triage guidance: (a) a pre-Phase-16 `gsd-quick` landing the proposed re-consult-after-slow-Get patch (+ the same for the re-warm window), or (b) fold into Phase 16 planning as an explicit requirement, with the deterministic fault-injected repro riding Phase 19's TEST-02 race matrix.
**Expected:** A recorded maintainer decision closing the `open` disposition. Verifier's assessment for context: the phase goal AS CONTRACTED is achieved — all five ROADMAP Success Criteria pass with behavioral evidence, both research-discovered bugs are killed and proven, and the phase explicitly excluded concurrency testing (15-03 flagged assumptions scheduled the structural statelessness argument for exactly this human review). CR-01 is a third, review-discovered bug in the concurrency dimension, not a failure of any authored must-have. However, an open Critical on the headline invariant must not be silently absorbed into a passed verdict.
**Why human:** Accepting a Critical finding's deferral is a maintainer judgment call; the concurrency window is unobservable to grep/presence checks and untested by any suite in the milestone so far.

### 2. Executor-push posture acknowledgment

**Test:** Acknowledge the backstop prohibition "the executor never pushes anywhere" (all three plans).
**Expected:** All six commits verified present and local at `af644481f`; no evidence of any executor push (Phase 13 precedent: pushes are user-performed). Confirm this matches expectation.
**Why human:** Push events are not reconstructible post-hoc from the local repository.

### Gaps Summary

No must-have failed; no artifact is missing, stubbed, orphaned, or hollow; every key link is wired with real data flowing; all eight phase requirement IDs are satisfied with no orphans. The single non-verified item is the SERVE-01 concurrency backstop truth, which is present and structurally sound as authored but behaviorally unexercised — and the phase's own code review found a genuine adjacent defect (CR-01, disposition open) in that exact dimension. The phase therefore routes to human decision rather than passing outright: the goal's contracted scope (the five Success Criteria, the two named bugs, the hermetic fakes) is demonstrably achieved; whether the open concurrency Critical blocks sealing or rides to Phase 16/19 is the maintainer's call.

---

_Verified: 2026-11-17_
_Verifier: the agent (gsd-verifier)_
