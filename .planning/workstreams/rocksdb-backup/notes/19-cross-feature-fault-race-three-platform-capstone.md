# Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone Rulings (v1.2 Phase 19)

**Ruled:** 2026-11-20
**Context commits:** SuperGenius `3e3e970e4`→`723189461` (19-01: seam + X1/X2 born red + the fix(19-01) re-checks) → `50ad85673` (19-02: X3/X8/X5) → `6abd028cf`→`bdeb9e95c` (19-03: X4/X4-B/X6/X7/X9) → `21b74aba4`→`b17787b0e` (19-04: X10 + X11 full-wire) → `3b5885d2f` (19-05: the dispatch-instrument lane steps) on `dev_coldstorage_additions`
**Requirements:** TEST-02 (the fault-race matrix + Tier-1 registration), TEST-03 (the three-platform dispatch evidence + lane closure)
**Decisions ruled here:** D-01 through D-16 (19-CONTEXT)

This is the capstone record the Phase 19 suite header cites (the both-homes discipline): `cold_cross_feature_fault_race_test.cpp`'s case grammar header points at the matrix table below, and the CI lane steps in `build-release-tags.yml` cite the both-lanes reading ruled here. It joins the rulings chain:

- `notes/16-txpruner-gc-composition-rulings.md` (the pruner×GC composition rulings — X3/X5/X8's ancestry)
- `notes/17-seal-growth-decision.md` (the seal-growth measurement + the kForcedWalkPeerFailoverPerCid validation X9 reads by symbol)
- `notes/18-collectibility-policy-downgrade-interlock.md` (the exemption + interlock record X6/X7 cross)

---

## (a) THE MATRIX TABLE — the landed X1..X11 (rendered ONCE; the suite header points here)

Boundaries: S1 serve evidence consult · S2 cold Get · S3 Rehydrate · S4 refusal classification/terminality · S5 requester failover/budget · E2 durability-state flip at the cold gate · E4 erase-commit · R1 walk start · R2 walk restore fetch/visit · R4 GC eviction/exemption consult.

| Case | Landed TEST_F(s) | Boundary | Primary hazard | Layer(s) | Tier |
|------|------------------|----------|----------------|----------|------|
| X1 | `Cross_EraseCommitVsServe_EvidenceLandsMidConsult` (+`_RealThreadBarrier`) | evidence lands mid serve consult (E4→S1) | resurrection | seam + barrier | Tier1 |
| X2 | `Cross_EraseCommitVsServe_InflightColdGetNoRehydrateAfterEvidence` (+`_RealThreadBarrier`) | evidence lands before Rehydrate, cold Get in flight (E4→S2/S3) | resurrection | seam + barrier (seeded jitter) | Tier1 |
| X3 | `Cross_DurabilityFlipVsColdGate_ServeNeverUnlocksErase` (+`_LegB`) | durability flip at the cold gate vs concurrent serve (E2→S2) | lost last copy | seam; real-thread legs (park-vs-cycle wedge → completed-side invariants) | Tier1 |
| X4 | `Cross_GcEvictionMidWalkRestore_RestoreCompletesOrAborts` (+`_LegB`) | GC eviction mid walk-restore (R4→R2) | partial-history validation | seam + barrier (seeded jitter); **execution note:** a linked ancestor is reachability-pinned on the landed line — the case ASSERTS the pin (candidates == [canary]) and carries the same-CID half-evicted state in the fault arm; the dichotomy's abort arm = the Malformed consult | Tier1 |
| X5 | `Cross_EraseMidWalkVisit_EvidenceSkipsNeverPartial` (+`_LegB`) | TxPruner erase before/at the walk's visit (E4→R2) | partial-history validation + resurrection | seam (deterministic erase-then-walk restructure) + real-thread walk | Tier1 |
| X6 | `Cross_DowngradeArmsMidWalk_InterlockHoldsTimeline` | downgrade ack/arming mid walk (18-interlock→R1/R2) | partial-history validation | seam-only (the flagged assumption: true-concurrency residue proven by 18-02/18-03) | Tier1 |
| X7 | `Cross_ExemptionConsultVsConcurrentPrune_FailClosedControlsStay` | exemption consult vs concurrent /prune/blk write (R4→E4) | partial-history validation (wrongly-exempted gap) | seam + embedded fail-closed controls (green-and-stay-green) | Tier1 |
| X8 | `Cross_RehydrateVsSecondErase_GateDefersOnRejournaledPending` (+`_LegB`) | rehydrate's re-journal vs the next cycle's gate (S3→E2) | lost last copy (double-erase) | seam + barrier | Tier1 |
| X9 | `Cross_PeerBudgetVsEvidenceTerminality_RefusalNotNotfound` | failover-budget exhaustion vs evidence terminality (S5→S4) | partial-history validation (misclassification) | seam + barrier (seeded jitter; budget read by symbol at M−1/M/M+1) | Tier1 |
| X10 | `Cross_SuiteEnd_AuditWalkAndCounterTeeth` | the suite boundary (all cases' end states) | all three, loudly | audit + counter-teeth + zero-CID baseline (teeth ungated — green knob-ON) | Tier1 |
| X11 | `Cross_FullWire_RefusalFailoverUnderConcurrentErase` | the composed wire (S4/S5 × E4 across nodes) | resurrection + lost last copy | real-thread, real pubsub — the ONE full-wire leg; **execution note (A5 invoked):** the A-side concurrent-erase-mid-serve leg is covered hermetically by X3-B leg 2 + X8-B (per-node tx stacks are outside the leg-3 recipe); the wire leg lands refusal terminality + failover-serves-unevidenced | Tier1 (default; promotion contract below) |

Hazard coverage (D-04): resurrection = X1/X2/X5/X11; partial-history validation = X4/X5/X6/X7/X9; lost last copy = X3/X8/X11. The per-`TEST_F` leg splits (seam case + real-thread sibling) are the recorded 19-02/19-03 execution grammar — a wedged leg dies independently of its seam sibling; the matrix rows are the claims, the `TEST_F`s their carriers.

Fault-arm inventory (knob `SGNS_CROSS_RACE_RED_ARMS_ENABLE`, never set in CI): X1, X2 (blinded consult/re-check — the resurrection teeth), X3-B, X8-B (part-truth journal/remote — lost-last-copy teeth), X5-B (marker-less erase — restore teeth), X4 (evidence lands mid-park + blinded lookup — evidenced-ancestor restore), X6 (torn-ack landing — interlock laundering), X7 (forged `Pruned` verdict — wrongly-exempted gap), X9 (blinded seam-point consult — vocabulary loss). X10's teeth legs are their own teeth (ungated). Final local record: knob-off 16/16 ×3 consecutive; knob-ON RED 9/9 carriers; Tier-1 20/20.

---

## (b) THE QUARANTINE TABLE — NON-cold entries ONLY

**Contract line (D-12):** a **cold-labeled failure is NEVER quarantined** — any `cold_*` failure in any lane is fix-forward in scope. No Phase 19 commit adds an exclusion matching a cold test name. The table documents and defers; it never invents exclusions.

**Grammar rules:** gtest filter grammar is POSITIVE-NEGATIVE with ONE dash — `*-A:B:C` (each `:X` appends one exclusion). The replace form (`-A` alone after re-assignment) drops base exclusions — forbidden (run 41744226815 recurrence; the original grammar failure was run 35781614193). `CTEST_EXCLUDE_REGEX` appends with `|`.

| ID | Tests | Platforms | Mechanism | First-occurrence run(s) | Class |
|----|-------|-----------|-----------|------------------------|-------|
| Q1 | `LocalPriceManagerTest.*` (e.g. `ConcurrentGetQuotesAcrossThreads`) | Windows-Release, OSX | `GTEST_FILTER` base `*-LocalPriceManagerTest.*` (full-suite lane only; the Tier-1 lane carries no filter) | 40840831965, 40927749627 | load-timing flake |
| Q2 | `ConsensusPendingLifecycleTest.CertificateCallbackStallsUntilPostCommitReadbackCanReleaseSameSlot` | all desktop | `GTEST_FILTER` base | recorded with Q1's base-filter commits | load-timing flake |
| Q3 | `TrustFirstBootE2ETest.TransientRefreshRetryExhaustionIsCappedCoalescedAndIdle` | desktop; recurred aarch64-Debug under the replace-formed filter | `GTEST_FILTER` base + append | 41744226815 (recurrence) | load-timing flake (the grammar lesson's carrier) |
| Q4 | `secure_storage_test` | Linux-wide | `CTEST_EXCLUDE_REGEX="secure_storage_test"` (full-suite lane; the Tier-1 lane is keyring-free and unaffected) | 40828950625 | keyring/dbus environmental |
| Q5 | `network_config_private_network_test` exit-time teardown SegFault | OSX | none today — crash-report capture only (marker + collect + upload); candidate for the first NEW entry, ruled separately if promoted | 41744226815, 41900284573 | macOS teardown debt (v1.1 round-14 ruling: backlog) |
| Q6 | MNN Vulkan-exposed suites/cases (`processing_*_test` suites + `AccountManagement.SetPayoutAddress`, `ProcessingNodesTest.PostProcessing`, `ProcessingNodesModuleTest.SinglePostProcessing`) | Linux aarch64 Debug | `CTEST_EXCLUDE_REGEX` append + `GTEST_FILTER` append (the `*-A:B:C` form) | 35675445960, 35701510569, 37082942495 | environmental (lavapipe ICD on ARM) |
| Q7 | multi_node smoke | Release-only | TBD at promotion time | `[ASSUMED]` — not verified this phase; fill from dispatch history before any new exclusion is built on it | flake (v1.1 dispatch history) |

---

## (c) THE PORTABILITY RUNBOOK (D-14)

**The four named items:** (1) the CloudflareWARP adapter is ENVIRONMENTAL on the Windows runner — its presence breaks libp2p dialing; diagnosis, not a code fix. (2) Distinct per-node base paths (fresh fixture dirs per case — Windows LOCK contention, Pitfall 4). (3) Poll predicates, never bare sleeps — `PollUntil` with generous instrumented deadlines; on exhaustion dump the involved status structs (`GetColdStorageStatus` fields, walk counters, barrier flags) — instrument, never bump. (4) Gtest filter grammar: `*-A:B:C`, one dash, colon-appended (see the quarantine rules above).

**Required env vars:** `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` — presence-checked, NEVER echoed (the flush path warns when unset; hermetic lanes do not need it, dispatch evidence runs carry it via the runner secret). `SGNS_COLD_STORAGE` — the cache flag rides the dispatch's `cold_storage` input (`-DSGNS_COLD_STORAGE=ON` on every desktop configure line through `COLD_STORAGE_ARGS`).

**Parallelism caps:** `CTEST_JOBS` = max(8, cores) (the two Pick-ctest-parallelism steps); `CMAKE_BUILD_PARALLEL_LEVEL=8`.

**Crash-report capture:** macOS — the marker-before-tests + `.ips` marker-windowed collect + upload steps (`Mark macOS diagnostic start` / `Collect macOS crash diagnostics` / `Upload macOS crash diagnostics`). Linux — the gdb batch backtrace re-run step (`Capture segfault backtraces (Linux)`), best-effort.

**Dispatch toggles:** `run_tests` (gates every test step through `env.RUN_TESTS`), `cold_storage` (`-DSGNS_COLD_STORAGE=ON` on desktop configures), `thirdparty_tag` (checked against the recorded tag before dispatch — use the recorded cold-build tag or newer; `main`/`develop` map to the platform-tag form). Per-job platform matrix: Windows-Release, Linux-x86_64/aarch64, OSX (Release/Debug).

**The D-11 both-lanes-green reading:** a platform is green when BOTH lanes are green — (1) `ctest -L Tier1 --no-tests=error` (the labeled hermetic set, including `cold_cross_feature_fault_race_test`) and (2) the full-suite lane (which carries `node_startup_test`'s walk legs + `globaldb_integration_test` cold legs). `node_startup_test` is NOT relabeled: `RESOURCE_LOCK genius_node_pool` + full-node boots do not belong in the hermetic fail-closed lane. CI output ordering across jobs is not a contract — the per-platform pass/fail of both lanes is (the flagged $COVERAGE ordering assumption).

**The B1/B2 push-topology ruling:** **B2 CONFIRMED at the Task-3 checkpoint (2026-11-20)** — `cmake.yml`'s `on.push.branches` stays `develop`/`main`; the permanent Tier-1 ON legs are dormant-in-topology for `dev_coldstorage_additions` until the v1.2 merge (the v1.1 posture). The B1 alternative (adding the branch to the push filters) was offered as a veto and DECLINED on runner load: the full ~28-job matrix per push against the SG-WIN11 thermal cap and the gv-OSX-Large tart VM's standing load. B1 remains one line if re-ruled later.

---

## (d) THE X11 PROMOTION RECORD (D-06)

`Cross_FullWire_RefusalFailoverUnderConcurrentErase` runs in the Tier-1-registered suite BY DEFAULT (no env knob). **Promotion = ONE green dispatch run of `build-release-tags.yml`** (`run_tests=true`, `cold_storage=true`) with all three desktop platforms green on X11 specifically — **re-ruled at the Task-3 checkpoint (2026-11-20): one green, not two** — the permanent lane is the recurrence guard (the dispatch doubles as the D-16 evidence run). **Failure handling:** any cold-labeled X11 failure → diagnose via the status dumps → fix-forward (in scope) → re-dispatch. A **second distinct flake after a fix** demotes: the case body flips to opt-in via `SGNS_CROSS_RACE_FULLWIRE_ENABLE` with a loud labelled gtest skip without the knob — the demotion requires a recorded ruling HERE with run IDs (never a silent skip, never a quarantine entry). Local stability record (19-04): green alone + 3 consecutive full-suite runs (20.8/20.9/21.8 s), zero deadline exhaustions.

---

## (e) THE D-15/D-16 EVIDENCE TABLE (one green dispatch per platform — recorded at the Task-3 checkpoint)

**Dispatch 1 — run 45235774034 (2026-11-23, dev_coldstorage_additions @ 3b5885d2f, run_tests=true, cold_storage=true, tag test_coldstorage_rtti): FIX-FORWARD, not the closing evidence.**

| Platform | Outcome | Detail |
|----------|---------|--------|
| Windows-Release | Full lane 168/169; **Tier-1 fail-closed lane 20/20 GREEN** | The only full-lane failure: `ColdComposeMatrixTest.Converge_FixedPointIsStable_ReRunsChangeNothing` (:2313 snapshot-field flip — the load class; green locally 3/3). **The Tier-1 lane proved the new step + `cold_cross_feature_fault_race_test` membership green on Windows.** |
| OSX (Debug+Release) | Both lanes: `cold_cross` **X11** refusal-leg merge + compose `Converge` | X11 (run-45235774034 find): B fetched + merged the evidenced cid while B's S3 op count stayed flat — the cold chain never crossed S3 on that fetch; the Windows passes were genuine (no peer Request for cid_x) but the leg could pass vacuously. Fixed in `9804dbf8f` (the direct B-consult teeth). |
| Linux (all 4) / iOS (all) / Android (all) | **Build failure** — the GNU/lld link find | `undefined reference to sgns::base::Buffer::Buffer(std::vector<uint8_t>)` from `StageBlockRemoval` (16-02): libbuffer.a precedes libcrdt_graphsync_dagsyncer.a; single-pass linkers never pull buffer.cpp.o; MSVC/Apple multi-pass resolve — latent since 16-02, invisible until the branch's first Linux build. Fixed in `9804dbf8f` (ctor inlined into buffer.hpp). |

**Open fix-forward item (cold-labeled — never quarantined):** ~~the compose `Converge` load-flake~~ **FIXED in `8e792470a`** — root cause: the drive awaited only the gc-only root's *marker* (the pruned block's disposal was never awaited), and a marker-only await can observe `disposed=true` from inside the D-16 HALF1→HALF2 window (bytes leave only in HALF2) — the before/after snapshots straddled the half. The fix awaits the **byte-level fixed point** (both targets' markers set AND `HasRawBlockBytes == false`). Compose suite 18/18 ×3, Tier-1 20/20.

**Dispatch 2 — run 45252321451 (2026-11-23, @ 8e792470a, user-cancelled after the build stage): iOS/Android still red — the OFF-build stub find, fixed in `583734cba`.** iOS/Android are **OFF builds** (the instrument's `COLD_STORAGE_ARGS` gates `-DSGNS_COLD_STORAGE` onto Linux/OSX/Windows only) → `ColdStorageStackStub.cpp` compiles there — and the four Phase-16 forwardings (`IsColdDisposed` 16-COMP-03; the `SetGc*HookForTesting` trio 16-COMP-02) landed in `ColdStorageStack.cpp` **without stub twins**, so every OFF-build consumer pulling the GlobalDB unity object (`sgns-trust`) failed to link with exactly those four undefined. The dispatch-1 five-resolved/four-unresolved split matches the stub's contents — a real production defect, invisible because no OFF platform had built the branch. Linux x86_64 **built clean** in dispatch 2 (the buffer-ctor fix held; the ON side was never affected). Windows/OSX jobs were cancelled before completing.

**Dispatch 3 — run 45257655488 (2026-11-23, @ 583734cba): Windows + Linux Release CLOSING EVIDENCE OBTAINED; iOS Release = the pre-existing MoltenVK thirdparty item; OSX = the X11 real find (production gap, fix designed).**

| Platform | Outcome | Detail |
|----------|---------|--------|
| **Windows-Release** | **FULLY GREEN** — full lane 169/169 AND Tier-1 fail-closed lane 20/20 (cold_cross + X11 green) | **Windows closing evidence ✓** |
| **Linux-x86_64-Release + aarch64-Release** | **GREEN** (build + both lanes) | **Linux closing evidence ✓** |
| Android (all 3) + iOS Debug + iOS-sim Debug | GREEN | the dispatch-2 stub fix held everywhere |
| iOS Release + iOS-sim Release | Build fails at SGProcessingManager tests (`capability_validator_test`, `sgprocmanagerexec_budget_test`): `mvkOSVersion()` undefined from `libMoltenVK.a` | **ROOT CAUSE VERIFIED from the thirdparty build logs (run 43321951865, 2026-11-12)**: both configs generated `libMoltenVK-merged.a` (`[152/152]`), but at INSTALL time the appended `install(FILES ... RENAME libMoltenVK.a)` printed **"Up-to-date:"** on the fast Release configs and **silently skipped the copy** — upstream's `install(TARGETS MoltenVK)` had already written the plain archive, and the mtime comparison (same-second tie in fast Release builds, and/or differing libtool date behavior — the jobs ran **different Xcode toolchains**: Release 16.4, Debug 26.3-rc, the workflow pins neither) kept the 48-member unmerged archive. iOS-Debug installed the merged 139-member lib; iOS-Release + iOS-sim-Release shipped the unmerged one. **FIXED in thirdparty `da17826`** (`MoltenVKStatic.cmake`: `install(CODE file(REMOVE <dest>/libMoltenVK.a))` ahead of the merge install — no destination, no up-to-date comparison). **Remaining action: push thirdparty `da17826`, re-run the thirdparty build to regenerate + re-upload the iOS/iOS-sim assets to `test_coldstorage`, then re-dispatch SuperGenius on the same tag.** Runner hygiene follow-up recorded: pin `DEVELOPER_DIR` in build-targets.yml (the 16.4/26.3-rc flap). |
| OSX Debug + Release | X11 (both lanes) + compose race-legs (`InteractionC`, `Interleave`, `Race` — tart-VM load class; `Converge` itself now GREEN — the byte-level fix held) + `cold_storage_resurrection_test` (Tier-1, detail untriaged) | See the X11 find below |
| Linux Debug (both arches) | `cold_seal_growth_test` only (155/168) | Debug-only soak slowness class (Phase 17 measurement test; Release green) |

**THE X11 FIND (run 45257655488, the case's teeth paid off):** the consult-teeth PASSED (B's own `LookupPruneEvidence` answered `Pruned`) yet the merge happened — pinning a **production resurrection gap**: (a) A's broadcaster pushes new head CIDs to connected peers through the **direct peer-queue path (topic-agnostic)** — a "private" topic does not isolate on the wire (macOS Requests 3/4 fetched the private cids before any test drive); (b) `getNode` only consults evidence on **cold-chain misses** — its cache/DAG-service steps precede the consult, so a block already stored by a background fetcher **merges without a consult**. Fix designed (worker-side terminal evidence guard at `HandleRootCIDBlock`, no-retry terminal marking; the naive broadcaster-thread placement deadlocks ShutdownNow's lifecycle join, and retry-marking starves the workers): currently STASHED locally (`x11-guard-wip`) — the dev machine's pubsub-world tests wedge even on the pristine tree (machine state; needs reboot), and CI is the working verifier.

| Platform | Run link | Toggles | thirdparty tag | Branch SHA | Full-suite lane | Tier-1 fail-closed lane (incl. cold_cross_feature_fault_race_test) |
|----------|----------|---------|----------------|------------|-----------------|---------------------------------------------------------------------|
| Windows-Release | https://github.com/GeniusVentures/SuperGenius/actions/runs/45235774034 | run_tests=true, cold_storage=true | test_coldstorage_rtti | 3b5885d2f | 168/169 (compose load flake) | **GREEN 20/20 (membership proven)** |
| Linux-x86_64-Release | (same run) | same | same | same | build failed — the link find (fixed 9804dbf8f) | — |
| OSX-Release | (same run) | same | same | same | X11 + compose (both fixed/recorded — re-dispatch pending) | X11 + compose |

One green per platform closes the capstone record — **confirmed as the bar at the checkpoint (the one-green X11 re-rule: the permanent lane is the recurrence guard)**. Membership check: the Tier-1 lane listing must include `cold_cross_feature_fault_race_test` in each platform's run evidence (checked from dispatch output, not the local lane alone). **Next dispatch (post-9804dbf8f) is the closing candidate.**
