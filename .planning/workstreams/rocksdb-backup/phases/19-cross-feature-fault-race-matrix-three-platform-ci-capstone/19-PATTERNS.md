# Phase 19: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone - Pattern Map

**Mapped:** 2026-11-19
**Files analyzed:** 8 (1 new test suite, 2 production-header/source seam edits, 1 test-registration edit, 2 CI workflow edits, 2 planning docs)
**Analogs found:** 8 / 8 (every file class has an in-repo analog; verified against `dev_coldstorage_additions` @ `d2f2a7dec`)
**Anchor discipline (per 19-RESEARCH §Discretion 10):** excerpts below cite symbols + the `@d2f2a7dec` line numbers they were read at. Plans must cite **symbols over lines**; executors re-ggrep at task time. Highest-drift-risk files: `src/crdt/impl/graphsync_dagsyncer.cpp`, `src/crdt/globaldb/ColdStorageManager.cpp`, `test/src/blockchain/node_startup_test.cpp`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` (NEW) | test | event-driven (barrier/seam fault races) | `test/src/crdt/cold_compose_matrix_test.cpp` + `cold_gc_walk_gap_exempt_test.cpp` + `cold_storage_resurrection_test.cpp` + `cold_storage_fault_race_test.cpp` | exact (four-way) |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (MODIFY — add serve interrupt seam) | test seam in production header | event-driven | `src/transaction/TxPruner.hpp:272-289, 311` (`kInterrupt*` family + `SetCycleInterruptHookForTest`) | exact |
| `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (MODIFY — wire 3 seam steps) | test seam wiring in production source | request-response (serve path) | `src/transaction/TxPruner.cpp:296-304` (`InterruptRequested( kInterruptAfterColdGate )` call site) | exact |
| `SuperGenius/test/src/crdt/CMakeLists.txt` (MODIFY — register suite) | config (build/test registration) | batch | same file, resurrection block `@d2f2a7dec:271-306` | exact |
| `SuperGenius/.github/workflows/build-release-tags.yml` (MODIFY — add Tier-1 lane steps) | CI config | batch | `cmake.yml:691-707` (non-Linux) + `cmake.yml:797-806` (Linux) | exact |
| `SuperGenius/.github/workflows/cmake.yml` (MODIFY — push-filter user checkpoint B1/B2) | CI config | batch | own `on.push.branches` block `@d2f2a7dec:3-10`; matrix `cold_storage: [OFF, ON]` `:197-208` | exact (edit is one-line; ruling is the work) |
| `.planning/workstreams/rocksdb-backup/notes/19-cross-feature-fault-race-three-platform-capstone.md` (NEW) | documentation (rulings chain) | reference | `notes/18-collectibility-policy-downgrade-interlock.md:1-11` | exact |
| `.planning/workstreams/rocksdb-backup/phases/19-.../19-FRESH-CLONE-CHECKLIST.md` (NEW) | documentation (evidence checklist) | reference | `milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-FRESH-CLONE-CHECKLIST.md:1-20` | exact |

**No-analog files:** none. Every deliverable class has a landed precedent on this line.

---

## Pattern Assignments

### `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` (test, event-driven)

**Analog stack (compose, do not invent):** `cold_compose_matrix_test.cpp` (sibling-suite header + kit-reuse posture), `cold_gc_walk_gap_exempt_test.cpp` (hermetic fixture composition + red-first declaration), `cold_storage_resurrection_test.cpp` (the ONE full-wire leg X11 + its link set), `cold_storage_fault_race_test.cpp` (kit source — re-declare in-file, never include/extract: Pitfall 2 churns the frozen v1.1 baseline).

**Suite-header contract** — copy the doxygen posture from `cold_compose_matrix_test.cpp:1-23` (brief = phase + plan + case grammar; fixture posture paragraph; per-LEG prose; Tier-1 hermetic/deterministic/fresh-clone-safe closer) and the red-first declaration from `cold_gc_walk_gap_exempt_test.cpp:5-21`:

```text
RED-FIRST DECLARATION (D-01, 18-RESEARCH Pitfall 8): LEG-1 (the LIVE
poisoned-GC-triangle state ...) and LEG-2 (the v2 fault-injected state ...)
are RED against the UNMODIFIED walk BY DESIGN until plan 18-01 Task 2
lands ... The fail-closed CONTROL legs (NoEvidence / Malformed) are GREEN
today and must STAY green ...
```
*Source: `SuperGenius/test/src/crdt/cold_gc_walk_gap_exempt_test.cpp:5-11` @d2f2a7dec — Phase 19's version declares, per case (X1–X11), which arm is red-by-design under `SGNS_CROSS_RACE_RED_ARMS_ENABLE`, which controls stay green-and-loud, and which hazard (resurrection / partial-history / lost-last-copy) each case kills (D-04).*

**Hermetic fixture composition** — the 18-01 recipe verbatim (`cold_gc_walk_gap_exempt_test.cpp:40-58`):

```text
Fixture composition: the cold_storage_gc_test.cpp hermetic GC family
(real hot RocksDB + LocalBlockStore cold dir + InMemoryS3Client /
InMemoryS3AdminClient + real ColdReadService / GraphsyncDAGSyncer
with the evidence lookup installed + real CrdtDatastore +
AttachGcDependencies + direct GcPassOnce drive, gc_interval_ms = 0
dormant cadence). Evidence becomes consultable to the walk WITHOUT
hand-built keys: the fixture installs a lookup on the REAL
ColdReadService via SetPruneEvidenceLookup whose verdicts derive
exclusively from PrunedBlockRecord bytes stored at keys produced by
the sanctioned PruneEligibility builder (BuildPruneBlockMarkerKey) ...
The malformed control corrupts ONLY the VALUE at a sanctioned-builder
key. Zero string-formatted /prune/* keys anywhere in this file
(testing trap 1 / D-C1).
```

**Kit members to re-declare in-file** (from `cold_storage_fault_race_test.cpp` @d2f2a7dec — copy shapes, rename fixture-local):

- `PollUntil` (line 141) — the ONLY `sleep_for` in the file lives in its body; every wait is a bounded poll predicate.
- `WindowGate` (line 245) — cv-latch barrier; note the leak-proofing destructor (SC4 round 8, run 41024756227): `~WindowGate() { Release(); }`, `Enter()/WaitInside(deadline)/Release()` shape, `Release()` idempotent.
- `TimingS3Client` (line 309) — `final : public S3Client` decorator chained outermost; `SetLatencyMs / SetOnOp / SetSeededJitter / ClearTimings`; hook fires BEFORE delegation OUTSIDE every inner lock (Pitfall 7); destructor aborts in-flight waits.
- Env-knob read shape (lines 1618-1619):
```cpp
const uint64_t seed  = EnvOr( "SGNS_RACE_JITTER_SEED", 20261028ULL );
const uint64_t iters = EnvOr( "SGNS_RACE_JITTER_ITERS", 200ULL );
```
→ Phase 19 siblings: `SGNS_CROSS_RACE_JITTER_SEED` / `SGNS_CROSS_RACE_JITTER_ITERS` / `SGNS_CROSS_RACE_FULLWIRE_ENABLE` / `SGNS_CROSS_RACE_RED_ARMS_ENABLE` (each prints value + effective seed in the case's first log line — the compose-matrix convention).

**Full-wire leg (X11)** — the leg-3 recipe header from `cold_storage_resurrection_test.cpp:33-41`:

```text
(3) Resurrect_FullWire_TwoGlobalDBRedeliveryStaysDeleted - the one
    full-fidelity case (D-13): two REAL GlobalDB instances over the
    pubsub_graphsync_test MultiGlobalDBTest topology (two
    GossipPubSub hosts, separate io contexts, real in-process
    libp2p + graphsync wire), cold storage ON on the receiving node
    through the TEST-ONLY stack client override
    (SetColdStorageStackClientsForTesting - hermetic fakes, zero
    network), real background GC eviction (GetColdStorageStatus
    evidence), then re-broadcast ... over the real gossip wire ...
```
Include-block additions the full-wire leg needs (`cold_storage_resurrection_test.cpp:95-102`): `gossip_pubsub.hpp`, graphsync network impl, scheduler + asio backend, libp2p log/configurator, soralog yaml — these motivate the resurrection link set (see CMakeLists pattern below). Failure messages dump the involved status structs (instrument, don't bump — round-6 discipline).

**Include discipline (every cold suite header, copy verbatim intent):** guard every library result with `has_value()` before `.value()/.error()`; wrap CIDs explicitly (`CID cid_key( cid )` — `sgns::CID` has NO implicit ctor from the blockstore `Cid`); fresh fixture dir per case per node (Windows LOCK contention); no `sleep_for` outside `PollUntil`.

---

### `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (test seam, event-driven)

**Analog:** `src/transaction/TxPruner.hpp:272-289` — the interrupt-seam family the new serve seams join. Verbatim shape to mirror:

```cpp
/// Interrupt seam step: after Evaluate(), before grouping.
static constexpr int kInterruptAfterEvaluation = 1;
/// Interrupt seam step: immediately before EACH per-tx erase call ...
static constexpr int kInterruptBeforeErase = 2;
/// Interrupt seam step: after the erase loop, before the status update.
static constexpr int kInterruptBeforeStatus = 3;
/// Interrupt seam step: after the status update, before the INFO summary ...
static constexpr int kInterruptAfterStatus = 4;
/// Interrupt seam step: after the cold-durability conjunct admits
/// a group, BEFORE the per-tx erase loop - the TOCTOU probe
/// position between gate admission and erase-commit (v1.2 Phase
/// 14, D-07). The hook contract is unchanged: true = abort the
/// cycle at this point; the counter-test's observe-only usage
/// returns false.
static constexpr int kInterruptAfterColdGate = 5;
```

Setter shape (`TxPruner.hpp:311`): `static void SetCycleInterruptHookForTest( std::function<bool( int step )> hook );` — doc comment must state (a) each step's firing point, (b) `true` = abort semantics, (c) "No production caller may invoke this method", (d) fixture discipline: a hook armed by a failing case must never leak — clear it in the fixture destructor.

**Proposed Phase 19 declaration** (research Discretion 2; keeps the `kInterrupt*` grep family):

```cpp
// graphsync_dagsyncer.hpp - test-only, production-null (TxPruner.hpp family)
/// Interrupt seam step: after the LookupPruneEvidence consult, before the cold Get.
static constexpr int kInterruptAfterEvidenceConsult = 1;
/// Interrupt seam step: after the cold Get returns bytes, before Rehydrate.
static constexpr int kInterruptBeforeRehydrate = 2;
/// Interrupt seam step: after the cold fetch resolves, before the SERVE-04
/// terminality check in GetNode (the never-fall-through-to-peers point).
static constexpr int kInterruptAfterColdFetch = 3;
static void SetColdServeInterruptForTest( std::function<bool(int)> hook );  // true = abort
```

**In-file precedent for a DAGSyncer test seam** (`graphsync_dagsyncer.hpp:~283-295` @d2f2a7dec): `SetBlacklistBackoffTimeoutForTest( uint64_t override_ms )` — `@brief Test-only configuration seam ... @note No production caller may invoke this method.` Storage shape: `static std::atomic<uint64_t> blacklist_backoff_override_ms_for_test_;` (line ~393) — static member, production-null default. The new hook follows TxPruner's `std::function` member shape instead (per-step dispatch), `nullptr` in production, zero cost.

---

### `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (seam wiring, request-response)

**Analog:** `TxPruner.cpp:296-304` — the call-site wiring pattern (observe-and-document at the exact boundary):

```cpp
if ( InterruptRequested( kInterruptAfterColdGate ) )
{
    // Observation seam (v1.2 Phase 14, D-07): fires after the
    // cold conjunct admitted this group, BEFORE the per-tx erase
    // loop - the admission->erase-commit gap the TOCTOU
    // counter-test probes. true = abort (the seam contract).
    interrupted = true;
    break;
}
```
(Helper home: `TxPruner.cpp:527` `bool TxPruner::InterruptRequested( int step )`; other call sites at 220/314/366/410 — a seam step per boundary, each with the boundary named in the comment.)

**Wiring points inside `FetchNodeFromColdStorage`** (consult + cold Get + Rehydrate, `graphsync_dagsyncer.cpp:849-905` @d2f2a7dec — the three sites map 1:1 to the three new steps):

```cpp
switch ( cold_read_hook_->LookupPruneEvidence( cid ) )
{
    case PruneEvidenceClass::Pruned:
        ...
        return outcome::failure( Error::HISTORY_PRUNED_LOCALLY );
    case PruneEvidenceClass::Malformed:
        ...
        return outcome::failure( Error::PRUNE_EVIDENCE_CORRUPT );
    case PruneEvidenceClass::NoEvidence:
        break; // SC2: the existing v1.1 serve path, unchanged
}
// kInterruptAfterEvidenceConsult fires HERE (X1: evidence lands mid-consult)

const ColdReadStatus status = cold_read_hook_->Get( cid, bytes );
if ( !bytes.empty() )
{
    // kInterruptBeforeRehydrate fires HERE (X2: evidence lands before rehydrate)
    cold_read_hook_->Rehydrate( cid, bytes );
```

**Terminality site for step 3** (`graphsync_dagsyncer.cpp:422-430` @d2f2a7dec — X9's refusal-not-notfound boundary):

```cpp
// SERVE-04 (v1.2 Phase 15): node-local terminality - the two
// evidence-based refusals NEVER fall through to the peer leg ...
if ( node.error() == Error::HISTORY_PRUNED_LOCALLY || node.error() == Error::PRUNE_EVIDENCE_CORRUPT )
{
    return node.as_failure();
}
```

**Constraint:** `FetchNodeFromColdStorage` runs OUTSIDE `dagMutex_` by construction (see its doc comment in the header) — a blocking seam hook must not violate that (never park inside a lock the publish path takes; the TimingS3Client Pitfall-7 rule applies).

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (config, batch)

**Analog:** the resurrection registration block, verbatim `@d2f2a7dec:271-306` (this — not the compose block — is the link set X11's real pubsub needs):

```cmake
# Resurrection counter-tests (TEST-02 SC2, v1.1 Phase 12 plan 12-01):
# ... Registered ONLY under SGNS_COLD_STORAGE. Links
# the cold-storage set PLUS the pubsub/graphsync surface the full-wire
# two-GlobalDB case needs (the pubsub_graphsync_test recipe:
# genius_node_test whole-archive + p2p_logger + AsyncIOManager include).
if(SGNS_COLD_STORAGE)
addtest(cold_storage_resurrection_test
    cold_storage_resurrection_test.cpp
    crdt_mirror_broadcaster.cpp
)

target_include_directories(cold_storage_resurrection_test PRIVATE
    ${AsyncIOManager_INCLUDE_DIR}
)

target_link_libraries(cold_storage_resurrection_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
    crdt_datastore
    rocksdb
    genius_node_test
    p2p::p2p_logger
    logger
)

if(MSVC)
    target_link_options(cold_storage_resurrection_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(cold_storage_resurrection_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(cold_storage_resurrection_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()

set_tests_properties(cold_storage_resurrection_test PROPERTIES LABELS "Tier1")
endif()
```

Sibling variants on the same shape: `cold_compose_matrix_test` (`:441-473`), `cold_gc_walk_gap_exempt_test` (`:484-516`), `cold_downgrade_e2e_test` (`:526-563`, adds `target_compile_definitions` + `ipfs-lite-cpp::ipfs_datastore_in_memory`). Phase 19's block = the resurrection shape with the new target name; comment block carries the D-02 sibling rationale + which X-cases it hosts. `crdt_mirror_broadcaster.cpp` is added as a second source ONLY if the full-wire leg needs the mirror broadcaster (copy the resurrection posture; hermetic-only legs don't need it).

**Mandatory invariants** (enforced by `test/tier1_audit_check.cmake:58-77`, registered at `test/CMakeLists.txt:20`):
- Target name MUST start `cold_` — the parity regexes scope over `addtest[(]cold_[a-z0-9_]+` and `set_tests_properties[(]cold_[a-z0-9_]+`; a non-`cold_` name escapes the audit silently.
- Exactly one `set_tests_properties(... PROPERTIES LABELS "Tier1")` per `addtest(cold_*` (count parity, else FATAL_ERROR).
- The whole block inside `if(SGNS_COLD_STORAGE)` (gated-link parity, audit Check 2).
- NO new label name — the lane contract stays `ctest -L Tier1`; the new suite joins the label SET (D-11), it does not add a label.

**Local verify (per-task):** `ctest --test-dir SuperGenius/build/Windows/Release -C Release -R cold_cross_feature_fault_race_test --output-on-failure`, then the full `-L Tier1 --no-tests=error` lane; `tier1_static_audit` runs as part of the Tier-1 lane (it is itself Tier1-labeled — the lane self-polices).

---

### `SuperGenius/.github/workflows/build-release-tags.yml` (CI config, batch)

**Analog:** the two Tier-1 lane steps in `cmake.yml` — copy verbatim, adapt the `if:` to this workflow's dispatch-toggle env.

Non-Linux (`cmake.yml:691-707` @d2f2a7dec):

```yaml
      - name: Tier-1 fail-closed lane
        # !cancelled(): the lane is an INDEPENDENT signal - a full-suite
        # failure (e.g. a known flaky integration test) must not mask the
        # fail-closed lane by skipping it (07-REVIEW WR-02).
        if: ${{ !cancelled() && env.RUN_TESTS == 'true' && matrix.target != 'Linux' }}
        working-directory: ${{ github.workspace }}/SuperGenius/${{ env.BUILD_DIRECTORY }}
        # TEST-01 (v1.1 Phase 7): -L Tier1 never includes unlabeled tests
        # and --no-tests=error fails an empty selection ...
        # TEST-02 SC4 (run 40840831965): contended-runner budget for the
        # SC1 absolute-p99 guard on the self-hosted mac.
        env:
          SGNS_TEST_P99_BOUND_MS: ${{ matrix.target == 'OSX' && '2000' || '' }}
        run: ctest . -j ${{ env.CTEST_JOBS }} -C ${{ matrix.build-type }} --output-on-failure -L Tier1 --no-tests=error
```

Linux (`cmake.yml:797-806` @d2f2a7dec):

```yaml
      - name: Tier-1 fail-closed lane (Linux)
        working-directory: ${{ github.workspace }}/SuperGenius/${{ env.BUILD_DIRECTORY }}
        if: ${{ env.RUN_TESTS == 'true' && matrix.target == 'Linux' }}
        shell: bash
        # TEST-01 (v1.1 Phase 7): hermetic Tier-1 lane; the keyring/dbus
        # wrapper above is not needed (cold-storage Tier-1 tests touch no
        # keyring and no MNN). Additive step - the existing fail-open
        # full-suite lane above is unchanged (Pitfall 12).
        run: ctest . -j ${{ env.CTEST_JOBS }} -C ${{ matrix.build-type }} --output-on-failure -L Tier1 --no-tests=error
```

Placement: after the existing `Run tests` steps (`build-release-tags.yml:791-803` non-Linux; `:866-928` Linux dbus-run-session lane) — the additive-step posture both workflows already document. `RUN_TESTS` env is populated at `:219` (`inputs.run_tests && ...desktop gating`); `CTEST_JOBS` at `:768-778`. Cold Tier-1 tests are keyring-free — no dbus wrapper on the Linux variant.

**Do NOT touch** the exclusion plumbing while there (quarantine mechanism quote for the notes doc, `build-release-tags.yml:892-914` @d2f2a7dec — the append-never-replace grammar):

```bash
GTEST_FILTER_VALUE="*-LocalPriceManager.*...:ConsensusPendingLifecycleTest...:TrustFirstBootE2ETest..."
CTEST_EXCLUDE_REGEX="secure_storage_test"
if [ "${{ matrix.abi }}" = "aarch64" ] && [ "${{ matrix.build-type }}" = "Debug" ]; then
    CTEST_EXCLUDE_REGEX="${CTEST_EXCLUDE_REGEX}|processing_datatypes_test|..."
    # APPEND ... the old replace form dropped the base exclusions ...
    GTEST_FILTER_VALUE="${GTEST_FILTER_VALUE}:AccountManagement.SetPayoutAddress:..."
fi
```

---

### `SuperGenius/.github/workflows/cmake.yml` (CI config, batch)

**Analog:** its own trigger block `@d2f2a7dec:3-10`:

```yaml
on:
  push:
    branches:
      - develop
      - main
    paths-ignore:
      - ".github/**"
      - "Readme.md"
```

The B1 edit (if ruled) = add `dev_coldstorage_additions` under `push.branches` (and consider `pull_request.branches` symmetry). B2 (recommended) = no edit; the ruling + load math lands in `notes/19-*` (research Discretion 6; A3). The `cold_storage: [OFF, ON]` matrix already exists (`:197-208`, ON limited to Windows-Release / Linux-x86_64-Release / OSX-Release via excludes at `:200-308`; `RELEASE` upload-exclusion at `:173`) — legs are NOT to be restructured; both test lanes already run per ON leg (`:691-707`, `:797-806`). Note `paths-ignore: .github/**` means workflow edits themselves never trigger the lane.

---

### `.planning/workstreams/rocksdb-backup/notes/19-cross-feature-fault-race-three-platform-capstone.md` (documentation, reference)

**Analog:** `notes/18-collectibility-policy-downgrade-interlock.md:1-11` — the rulings-chain header contract:

```markdown
# Collectibility Policy & Downgrade Interlock Rulings (v1.2 Phase 18)

**Ruled:** 2026-11-19
**Context commits:** SuperGenius `84d87d462` ... → `2c94e481b` (executed Phase 18 HEAD ...) on `dev_coldstorage_additions`
**Requirements:** POLICY-01 (...), POLICY-02 (...)
**Decisions ruled here:** D-01 through D-14 (18-CONTEXT)

This is the policy record the Phase 18 code cites at its ruling sites (the
both-homes discipline, notes/16 D-12 precedent): ... It joins
`notes/16-txpruner-gc-composition-rulings.md` and `notes/17-seal-growth-decision.md`
in the rulings chain.
```

Body shape: lettered sections `(a)`, `(b)`, ... each carrying one ruling with verbatim code-anchored semantics, run-ID-cited evidence, and a "Red-first evidence trail" subsection naming commits. Phase 19 contents per D-13/D-14: the **matrix table** (case → boundary → hazard → layer → tier — the artifact TEST-02 verification reads; render ONCE here, suite header points at it), the **quarantine table** (NON-cold only, contract line at the table head: cold-labeled failures NEVER quarantined — fix-forward; per entry: mechanism, `*-A:B:C` grammar note, first-occurrence run IDs; Q5/Q7 mechanism decisions recorded here), the **portability runbook** (CloudflareWARP = environmental, distinct per-node base paths, poll predicates, gtest filter grammar, env vars incl. `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` presence + `SGNS_COLD_STORAGE` cache flag, `CTEST_JOBS`/`CMAKE_BUILD_PARALLEL_LEVEL` caps, crash-report capture, dispatch toggles, exclusion pointers, B1/B2 push-topology ruling), **evidence links** (per-platform green dispatch runs + parameters), **X11 promotion record** (two-green-dispatch rule, demotion path). Filename joins the `NN-<kebab-topic>.md` chain.

---

### `.planning/workstreams/rocksdb-backup/phases/19-.../19-FRESH-CLONE-CHECKLIST.md` (documentation, reference)

**Analog:** `milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-FRESH-CLONE-CHECKLIST.md:1-20` — the checklist contract:

```markdown
# 12-FRESH-CLONE-CHECKLIST - SC4 Fresh-Clone Proof (TEST-02 / D-05)

Status: **COMPLETE 2026-11-10** - all three SC4 legs green in SuperGenius Tag
Build run 42905264387 (workflow_dispatch, dev_blockstore @ 9994718ce,
thirdparty tag `test_coldstorage_rtti`, run_tests=true, cold_storage=true,
all 15 jobs success). Evidence tables below.

## D-04 fail-closed validation record (git ls-remote, ...)
| Repo | Branch | Local SHA | Remote SHA | Pushed? |
```

Shape to refresh: Status line with run ID + parameters; push-state tables (repo/branch/SHA/pushed); numbered **User actions (the D-03 checkpoint)** section (push innermost-first, dispatch toggles `thirdparty_tag`/`run_tests`/`cold_storage`, expected per-platform outcomes incl. `-DSGNS_COLD_STORAGE=ON` log-verified and the Tier-1 lane step result); EXPECTED-RED caveats. Phase 19 extensions: the Tier-1 lane step now also exists in `build-release-tags.yml` (verify per platform), the both-lanes-green reading of D-11 (Tier-1 label set AND full-suite lane incl. `node_startup_test` walk legs), and a pointer to the quarantine table in `notes/19-*`. Home: phase dir (the v1.1 precedent home).

---

## Shared Patterns

### Interrupt-seam family (applies to hpp + cpp edits)
**Source:** `src/transaction/TxPruner.hpp:272-289, 311` + `TxPruner.cpp:220-410` call sites
**Apply to:** `graphsync_dagsyncer.hpp` / `impl/graphsync_dagsyncer.cpp` seams.
Contract: `static constexpr int kInterrupt<Position> = N;` numbered steps, one doc-commented `static void Set*ForTest( std::function<bool(int)> hook )`, hook member `nullptr` in production, `true` = abort, boundary named in the call-site comment, fixture destructor clears armed hooks (leak discipline), "No production caller may invoke this method" note.

### Tier-1 label + audit contract (applies to the suite registration)
**Source:** `test/tier1_audit_check.cmake:58-77`; enforced shape visible in every block of `test/src/crdt/CMakeLists.txt`
**Apply to:** the new `addtest(cold_cross_feature_fault_race_test ...)` block.
Rules: `cold_`-prefixed name; label parity (one `set_tests_properties(... LABELS "Tier1")` per registration); whole block under `if(SGNS_COLD_STORAGE)`; lane selection is ALWAYS `ctest -L Tier1 --no-tests=error` (never `-LE`, never bare `-L`); no new label names.

### Hermetic fixture composition + sanctioned builders (applies to every hermetic case)
**Source:** `cold_gc_walk_gap_exempt_test.cpp:40-58` fixture paragraph; `PruneEligibility.hpp` builders (`BuildPruneMarkerKey`/`BuildPruneBlockMarkerKey`/entries + tri-state lookups — the ONLY marker homes)
**Apply to:** all of X1–X10. Real components + `InMemoryS3*` fakes installed via `SetColdStorageStackClientsForTesting` / `SetPruneEvidenceLookup`; evidence seeded exclusively at builder-produced keys; zero string-formatted `/prune/*` keys; fresh fixture dir per case.

### Barrier discipline + env-knob reproducibility (applies to every race case)
**Source:** `cold_storage_fault_race_test.cpp:141` (PollUntil), `:245` (WindowGate), `:309` (TimingS3Client), `:1618-1619` (EnvOr knobs)
**Apply to:** the whole suite. No `sleep_for` outside PollUntil's body; destructor-safe gates/decorators (teardown can never hang); every nondeterministic leg reads `SGNS_CROSS_RACE_*` knobs and prints seed+values up front.

### CI exclusion grammar (applies to workflow edits + quarantine table)
**Source:** `build-release-tags.yml:866-928` (env-carried exclusions, `*-A:B:C` grammar, append-never-replace comments citing runs 35781614193 / 41744226815)
**Apply to:** the Tier-1 lane steps (they need NO exclusions — cold Tier-1 is never quarantined) and the notes/19 quarantine table's mechanism column.

### Rulings-chain doc shape (applies to both new docs)
**Source:** `notes/18-*.md:1-11` header + lettered sections; `12-FRESH-CLONE-CHECKLIST.md` status/table/checkpoint shape
**Apply to:** `notes/19-*.md` cites 16/17/18 by path and is cited from code comments only via path (both-homes discipline); checklist carries run IDs + parameters + user-action steps.

## No Analog Found

None — all eight files have exact or role-exact analogs. The genuinely NEW surface (three named serve-path interrupt steps) is itself a copy of the TxPruner seam family onto new boundary points.

## Metadata

**Analog search scope:** `SuperGenius/test/src/crdt/` (all cold suites + CMakeLists), `SuperGenius/src/transaction/`, `SuperGenius/src/crdt/` (+ `impl/`, `globaldb/` headers via research record), `SuperGenius/.github/workflows/`, `SuperGenius/test/tier1_audit_check.cmake`, `.planning/workstreams/rocksdb-backup/notes/`, `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-*/`
**Files scanned:** ~15 read or grep-verified this session (all excerpts from the working tree @ `d2f2a7dec`)
**Pattern extraction date:** 2026-11-19
