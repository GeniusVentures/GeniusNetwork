# Phase 5: Fault Injection & Three-Tier Hardening - Pattern Map

**Mapped:** 2026-10-22
**Files analyzed:** 14 (10 modified/extended, 4 new)
**Analogs found:** 13 / 14 (12 exact/role-adjacent in-repo analogs + 1 flagged partial seam dimension; 1 no-analog doc stub)

**Tracked-source gate (#3645):** every analog below verified via `git ls-files` inside `thirdparty/sgns-blockstore` (19 paths) and `thirdparty` root (`build.yml`) — all tracked, zero mirror paths.

**Scope guard:** this phase is extension, not invention (RESEARCH key insight). Every mechanism has an in-repo precedent from Phases 1–4. Locked decisions D-01..D-17 bind each mapping below; the planner must not re-litigate them.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `include/sgns-blockstore/LocalBlockStore.hpp` | library header / test seam | file-I/O (WAL batch) | itself — `CrashPoint` enum + `SetCrashPointForTesting` (`:63-73`, `:258-266`) | exact (in-place extension) |
| `src/LocalBlockStore.cpp` | library backend | file-I/O (WAL batch) | itself — `BeforeCommit` gate + Put commit tail (`:337-364`) | exact (in-place extension) |
| `src/InMemoryS3Client.hpp` | test fake (service) | request-response (fault-gated map) | itself — `SetFault` + op fault table (`:46`, `:81-84`) | partial (per-key overlay = new dimension; byte-flip kind = op-table extension) |
| `src/InMemoryS3Client.cpp` | test fake (service) | request-response | itself — `FaultGate` (`:52-73`) + `Get` success slot (`:94-106`) | partial (same two deltas as header) |
| `test/local_block_store_crash_test.cpp` | test suite (extend) | file-I/O + reopen (WAL recovery) | itself — states 1/2 + reopen discipline (`:14-28`, `:202-267`) | exact |
| `test/minio_s3_client_test.cpp` | test suite (extend) | request-response (raw wire) | itself — stub fault matrix + recovery case (`:134-303`) | exact |
| `test/upload_drainer_test.cpp` | test suite (extend) | batch (per-item drain) | itself — fault drain + convergence cases (`:117-315`) | exact (depends on per-key overlay seam) |
| `test/s3_block_store_test.cpp` | test suite (extend) | request-response via fake | itself — `GetWrongBytesAtDerivedKeyIsCorruptRemote` (`:214-246`) | exact |
| `test/conformance/BlockStoreConformanceTests.hpp` | test kit macro (extend) | request-response (generic) | itself — FaultController section (`:253-341`) | exact |
| `test/CMakeLists.txt` | build config (modify) | n/a | itself — `addtest` blocks + `header_hygiene` `add_test` (`:25-33`, `:182-184`) | exact |
| `test/tier1_audit_check.cmake` | static audit utility (new) | file-I/O (source scan) | `test/header_hygiene_check.cmake` (whole file, 50 lines) | exact (clone with new pattern sets) |
| `thirdparty/.github/workflows/build.yml` | CI config (modify, 1 line) | n/a | itself — "Run sgns-blockstore tests" step (`:364-373`) | exact |
| `docs/testing-tiers.md` | docs (new) | n/a | `docs/s3d-durability.md` (structure/tone) | role-match |
| `Readme.md` (repo root, new minimal) | docs (new) | n/a | none — repo has no README | no analog |

**Assertion-source surfaces (read-only, not modified):** `include/sgns-blockstore/BlockStoreTooling.hpp:57-77` (`GetPendingUploads`), `include/sgns-blockstore/LocalBlockStore.hpp` (`GetUploadState`/`MarkUploadedAccepted`/`MarkUploadedDurable`), `include/sgns-blockstore/UploadDrainer.hpp:59-70` (`DrainItem`). The four-state matrix and drainer-under-fault suites assert through these — see Shared Patterns.

---

## Pattern Assignments

### 1. `include/sgns-blockstore/LocalBlockStore.hpp` (library header / test seam — D-09, Q2 Open Question 1)

**Analog:** itself — the `CrashPoint` seam this file already carries. Research recommends (and CONTEXT discretion allows) a concrete `SetCorruptAfterCommitForTesting(...)` method next to `SetCrashPointForTesting`, NOT a widening of the frozen `FaultController` interface.

**Seam precedent** (`LocalBlockStore.hpp:63-73`):
```cpp
    enum class CrashPoint
    {
        None,         ///< normal operation
        BeforeCommit, ///< Put short-circuits before DB::Write (simulated death)
    };
```

**Method + member precedent** (`LocalBlockStore.hpp:258-277`):
```cpp
        /**
         * @brief Arm the TEST-ONLY crash-point seam (D-07).
         *
         * Concrete method on the backend type ONLY - the frozen
         * FaultKind enum and FaultController surface are untouched.
         * Defaults to CrashPoint::None; BeforeCommit makes subsequent
         * Puts return TemporarilyUnavailable before any DB::Write call
         * without mutating stored state.
         *
         * @param point the crash point to arm (None clears)
         */
        void SetCrashPointForTesting(CrashPoint point);

    private:
        LocalBlockStore(); // construction goes through Open()
        // ...
        std::unique_ptr<Impl> impl_;
        FaultKind fault_ = FaultKind::None; ///< conformance seam state (never read by production paths)
        CrashPoint crash_point_ = CrashPoint::None; ///< test-only crash seam state (D-07)
```
Replicate this exact shape: sibling arm-method + trailing-underscore member + Doxygen `@brief` declaring it TEST-ONLY and naming the decision. A `bool corrupt_after_commit_ = false;` member (or small struct) joins `crash_point_`.

**Style constraints:** Ullman braces, Doxygen on every public member (`Coding Standards.md`); keep the pimpl discipline — zero RocksDB types in this header (see class doc, "Pimpl (Phase-2 Pattern 1)").

**Header note to extend:** `FaultController.hpp:41-44` already anticipates this phase — "Phase 5 later induces the same class over real transports." The hook does NOT go there; keep `FaultController.hpp` frozen (frozen-kit note, kit `:26-30` of `BlockStoreConformanceTests.hpp` banner discipline).

**Side effect (planner decision, Research Open Question 4):** once no test opens a second handle, the published CF-name constants (`kBlocksColumnFamilyName` `:27`, `kUploadJournalColumnFamilyName` `:32`) lose their only consumer. Default posture: keep (additive). The hook itself must never expose CF names across the API.

---

### 2. `src/LocalBlockStore.cpp` (library backend — D-09 firing point)

**Analog:** itself — the Put path around the exact firing point (RESEARCH Q2 pinned).

**Firing point** (`src/LocalBlockStore.cpp:337-364`):
```cpp
        // D-07 test seam: simulate process death BEFORE the atomic
        // DB::Write commit. The caller never sees success and NOTHING is
        // written - no torn block, no orphan journal record.
        if (crash_point_ == CrashPoint::BeforeCommit)
        {
            return BlockStatus{StatusClass::TemporarilyUnavailable,
                               BlockSource::Local,
                               "crash point: process simulated dead before "
                               "DB::Write"};
        }

        // D-02/D-03/D-04: ONE WriteBatch carries the block bytes AND - only
        // for a new block - the PendingUpload journal record. ...
        rocksdb::WriteBatch batch;
        batch.Put(impl_->blocks_, KeySlice(key.value()),
                  rocksdb::Slice(reinterpret_cast<const char*>(bytes.data()),
                                 bytes.size()));
        if (!already_present)
        {
            batch.Put(impl_->journal_, KeySlice(key.value()),
                      JournalRecord::Encode(UploadState::PendingUpload));
        }
        const auto committed = impl_->db_->Write(impl_->wo_, &batch);
        if (!committed.ok())
        {
            return MapStatus(committed, "Put: batch commit failed");
        }
        return PutOutcome{DurabilityLevel::LocalCommitted, already_present};
```
**The hook fires between the `!committed.ok()` return and the final `return PutOutcome{...}`** — after the batch lands, before the caller sees success. Mechanics (RESEARCH Q2): read the just-committed value back through `impl_->blocks_`, flip a byte, write it back through `impl_->db_` with `sync` — the store's OWN handle, no second DB open, no CF-name string crossing the API.

**Hook must-NOT rules (bind the plan):**
- never touch the journal CF (self-heal assertions check journal co-removal — `StoredCorruptionSelfHealsEvictAndSurface`),
- never fire when disarmed,
- do not fire on the `already_present` re-Put path unless scripted (keeps re-Put-repairs composable),
- do NOT route through `FaultGate`/`fault_` — the kit's `CorruptData` kind corrupts only the returned copy and must NEVER evict (`FaultCorruptionDoesNotEvict` regression, crash test `:167-198`). The hook is a different animal: real stored bytes.

---

### 3+4. `src/InMemoryS3Client.hpp` / `.cpp` (test fake — D-05(c)/D-10, Gaps A + B)

**Analog:** itself — the per-op fault table and FaultGate. **Both deltas are additive to the fake only; `S3Client.hpp`'s `S3FaultKind` stays frozen** (fake-internal scripting methods are cleaner — RESEARCH Q6).

**Existing seam to extend** (`src/InMemoryS3Client.hpp:44-54, 80-84`):
```cpp
        /**
         * @brief Script a fault for one op kind (FIFO-free: persists until
         *        cleared or overwritten for that op).
         * @note CONFORMANCE-TEST SEAM: production code MUST NOT call this.
         */
        void SetFault(S3Op op, S3FaultKind kind);
        // ...
        mutable std::mutex mutex_;
        std::map<std::string, std::vector<uint8_t>> objects_;
        std::array<S3FaultKind, 4> faults_ = {
            S3FaultKind::None, S3FaultKind::None,
            S3FaultKind::None, S3FaultKind::None,
        };
```

**Gate + success-slot precedent** (`src/InMemoryS3Client.cpp:52-73, 94-106`):
```cpp
    std::optional<BlockStatus> InMemoryS3Client::FaultGate(S3Op op) const
    {
        switch (faults_[OpIndex(op)])
        {
            case S3FaultKind::Unavailable:
                return BlockStatus{StatusClass::TemporarilyUnavailable,
                                   BlockSource::Remote,
                                   "fault injection: S3 backend unavailable"};
            // ... CorruptData, Unauthorized ...
            case S3FaultKind::None:
                break;
        }
        return std::nullopt;
    }

    result<S3Object, BlockStatus> InMemoryS3Client::Get(const std::string& key)
    {
        std::lock_guard<std::mutex> guard(mutex_);
        if (auto gate = FaultGate(S3Op::Get))
        {
            return gate.value();
        }
        auto it = objects_.find(key);
        if (it == objects_.end())
        {
            return BlockStatus{StatusClass::NotFound, BlockSource::Remote,
                               "S3 object not found: " + key};
        }
        return S3Object{ key, it->second };
    }
```

**Gap A — per-key overlay (PARTIAL analog; flag for planner):** the op-indexed array has no per-key dimension; "item 2 fails while siblings upload" (D-05c) is inexpressible today — the drainer banner even documents this limitation (`upload_drainer_test.cpp:15-24`). Nearest seam: add a per-key map (e.g. `std::map<std::string, S3FaultKind> key_faults_`) consulted BEFORE (or after — planner picks precedence) the op-level gate inside `FaultGate`, plus `SetFaultForKey(key, S3Op, S3FaultKind)` / cleared by `ClearFaults()`. **Delta to document in the plan:** precedence rule between key-scoped and op-scoped faults, and thread-safety under the existing `mutex_`.

**Gap B — flipped-bytes-in-success-slot:** hook at the final line of `Get`: when scripted, return `S3Object{ key, flipped_copy(it->second) }` in the SUCCESS slot — so `S3BlockStore`'s CID verify is the detector (CORE-04) and D-11's re-fetch-still-Corrupt becomes assertable. Do NOT add this as an `S3FaultKind` on `Get` — existing `CorruptData` returns a `Corrupt` FAILURE from the adapter; the new kind must succeed at the adapter layer and fail at the store layer (D-08 layer split).

**Alternative already in-repo (no seam change):** planting wrong bytes at the derived key via `fake_->Put(key, wrong_bytes)` — see §7. Acceptable, but couples tests to the key layout; the scripted kind removes that coupling.

---

### 5. `test/local_block_store_crash_test.cpp` (test suite extend — D-01/D-02/D-03/D-09)

**Analog:** itself — states 1 and 2 of the four-state matrix are already proven here; extend to states 3/4, replace `CorruptStoredBlock` with the hook, extend the banner with the D-02 four-state window model (discretion: banner is the recommended documentation home).

**No-flush discipline banner to extend** (`:14-28`):
```cpp
 * CRASH MODEL (read before touching anything here):
 *  - In-process close-without-flush + reopen exercises RocksDB WAL
 *    recovery - the REAL recovery path a process crash takes. ...
 *  - There is deliberately NO mid-DB::Write fault point: a WriteBatch
 *    serializes as ONE atomic WAL record, so an interrupted Write leaves
 *    the whole batch or none of it ...
 *  - No test calls Flush() or SyncWAL() anywhere: with
 *    avoid_flush_during_shutdown=true the close-then-reopen path is
 *    crash-faithful, and any flush/sync would silently convert these
 *    proofs into no-ops (RESEARCH Pitfall 2).
```
Append the D-02 mapping here: SC2's three windows → four real states (pre-commit / pending / uploaded-but-unmarked / accepted); "the mid-write state does not exist — that absence IS the Phase-2 D-02 proof."

**Reopen pattern every new state reuses verbatim** (`:70-89`):
```cpp
    std::shared_ptr<LocalBlockStore> ReopenStore(const std::string& dir)
    {
        auto opened = LocalBlockStore::Open(LocalBlockStoreOptions{dir});
        if (!opened)
        {
            ADD_FAILURE() << "LocalBlockStore::Open failed for " << dir
                          << ": " << opened.error().message;
            return nullptr;
        }
        return std::shared_ptr<LocalBlockStore>(std::move(opened.value()));
    }

    std::shared_ptr<LocalBlockStore> MakeStore(const std::string& dir)
    {
        std::error_code ec;
        std::filesystem::remove_all(dir, ec);
        return ReopenStore(dir);
    }
```
Crash = scope-block end (destructor, no-flush close); recovery = next `ReopenStore`. State template: `CrashBeforeCommitLeavesNothing` (`:202-233`) — arm seam → failing/succeeding Put → `}` → reopen → assert `Get`/`Has`/`GetPendingUploads`/`GetUploadState` (full reader triple).

**State 3 construction (uploaded-but-unmarked, D-03 payoff):** Put → drain into the fake (remote holds object) → crash BEFORE the mark. Scripting the crash-before-mark window needs the per-key/put fault seam (§3 Gap A) or drain-then-close ordering — planner picks within D-03's letter. Post-reopen assertions: still `PendingUpload` → re-drain → Put success slot `alreadyPresent=true` → `GetUploadState`→`UploadedAccepted` → pending empty. The convergence template already exists in the drainer suite (`ReDrainConvergesAndRePutIsAlreadyPresent`, §6).

**State 4 (accepted):** assert BOTH the reader (`GetUploadState`==`UploadedAccepted`, pending empty) and the no-op re-drain (empty pending → empty result vector) — research discretion recommendation.

**The pattern being REPLACED** (`:91-131` `CorruptStoredBlock`, raw second RocksDB handle + `kBlocksColumnFamilyName`): delete it and the `RocksDB::rocksdb` test link + the CMake comment justifying it (§10) once the D-09 hook lands. Also retire the `<rocksdb/db.h>` includes (`:45-46`).

**Existing corruption semantics to keep green:** `StoredCorruptionSelfHealsEvictAndSurface` (`:139-164`) — first Get `Corrupt`+Local, second Get `NotFound` (atomic evict of block AND journal), re-Put repairs with `alreadyPresent==false`. Re-point its corruption step from `CorruptStoredBlock` to the hook; keep every assertion unchanged.

---

### 6. `test/upload_drainer_test.cpp` (test suite extend — D-05(c)/D-06, Gaps C + D)

**Analog:** itself — the fixture and the fault/convergence cases; plus the banner limitation note that Gap A lifts.

**Banner limitation the extension resolves** (`:15-24`):
```cpp
 * Test-shape note (documented deviation from the plan letter): the
 * fault tables at BOTH layers are op-kind-grained (fake SetFault, local
 * FaultController), so "exactly one of two items fails" inside a
 * SINGLE drain call is not mechanically expressible. Record-and-
 * continue, journal-default-success, and pending-retention are
 * asserted per item on all-failing drains; sibling independence is
 * proven by convergence after partial clears; the mixed-outcome shape
 * is covered by the fresh-store re-drain (alreadyPresent) path.
```
Rewrite this note once per-key faults exist: the partial-failure suite (seed N pending → script item 2's KEY for a 5xx/unavailable Put → drain → siblings upload, item 2 fails with taxonomy status, journal: siblings Accepted / item 2 still Pending) becomes mechanically expressible.

**Fixture** (`:79-101`):
```cpp
    class UploadDrainerTest : public ::testing::Test
    {
    protected:
        void SetUp() override
        {
            auto opened_local =
                LocalBlockStore::Open(LocalBlockStoreOptions{ FreshDir() });
            ASSERT_TRUE(opened_local);
            local_ = std::move(opened_local.value());
            fake_ = std::make_shared<InMemoryS3Client>();
            auto opened_remote = S3BlockStore::Open(fake_);
            ASSERT_TRUE(opened_remote);
            remote_ = std::move(opened_remote.value());
        }

        std::unique_ptr<LocalBlockStore> local_;
        std::shared_ptr<InMemoryS3Client> fake_;
        std::unique_ptr<S3BlockStore> remote_;
    };
```

**Assertion templates to clone:** `RemotePutFaultRecordsFailuresAndRetainsPending` (`:166-200`, per-item record + journal default-success + pending retention) and `ReDrainConvergesAndRePutIsAlreadyPresent` (`:206-265`, convergence + fresh-store `alreadyPresent=true` while journal still advances — the state-3 re-drain payoff in miniature). **Gap D (D-06):** every new fault case ENDS with the inline good-fetch-succeeds/re-drain-succeeds assertion in the SAME test — today's fault tests clear faults only in the NEXT test; do not copy that shape.

---

### 7. `test/s3_block_store_test.cpp` (test suite extend — D-08 store half / D-10 / D-11 remote corruption matrix)

**Analog:** itself — `GetWrongBytesAtDerivedKeyIsCorruptRemote` (`:214-246`) is today's remote-corruption proof:

```cpp
TEST_F(S3BlockStoreTest, GetWrongBytesAtDerivedKeyIsCorruptRemote)
{
    using sgns::blockstore::conformance::MakeCid;
    using sgns::blockstore::conformance::SpanOf;
    const std::string payload = "remote corruption probe payload";
    const auto cid = MakeCid(payload);
    ASSERT_TRUE(store_->Put(cid, SpanOf(payload)));

    // Derive the key in-test exactly as the store does, then plant
    // mismatched bytes at it through the fake.
    auto cid_string =
        libp2p::multi::ContentIdentifierCodec::toString(cid);
    // ... fanout derivation ...
    const std::string wrong = "NOT the block that hashes to this CID";
    const std::vector<uint8_t> wrong_bytes(wrong.begin(), wrong.end());
    auto planted = fake_->Put(key, wrong_bytes);
    ASSERT_TRUE(planted);

    auto got = store_->Get(cid);
    ASSERT_FALSE(got);
    EXPECT_EQ(got.error().code, sgns::blockstore::StatusClass::Corrupt);
    EXPECT_EQ(got.error().source, sgns::blockstore::BlockSource::Remote);
    EXPECT_NE(got.error().message.find("Get"),
              std::string::npos); // op context present
}
```
Extend with the D-10 scripted seam (preferred — no key-layout coupling) and the D-11 semantics: Get → `Corrupt`+Remote → Get AGAIN → still `Corrupt` (re-fetch, no bad-byte cache) → repair the fake (`ClearFaults` / re-plant good bytes) → Get succeeds (no sticky negative cache, per-case D-06) → fake still holds the key (remote NEVER deleted — assert via `ObjectKeys()`).

**Layer discipline (Pitfall 4):** the complete-but-wrong-length `Corrupt` assertion lives HERE (store level), never in `minio_s3_client_test.cpp` — the adapter is transport-honest only. No new test may call `CidOf` to "check" what the store should have checked.

---

### 8. `test/conformance/BlockStoreConformanceTests.hpp` (kit macro extend — D-07)

**Analog:** itself — the fault section (`:253-341`). New generic cases (e.g. induced-failure taxonomy class per `FaultKind`, already-covered corrupt/unavailable/unauthorized stay) join INSIDE the `SGNS_BLOCKSTORE_CONFORMANCE_TESTS` macro body so every backend instantiates them free.

**Macro case shape to replicate exactly** (backslash-continued, `:246-270` abridged):
```cpp
    /* Fault-seam cases (D-10): probed via dynamic_pointer_cast; backends      \
     * without the seam get loud labelled skips naming [fault-conformance].    \
     */                                                                        \
    TEST_F(SuiteName, FaultUnavailableSurfacesAsTemporarilyUnavailableNeverNotFound)      \
    {                                                                                      \
        using sgns::blockstore::conformance::SpanOf;                                       \
        ASSERT_TRUE(store_->Put(cid_a_, SpanOf(payload_a_)));                              \
        auto fc = std::dynamic_pointer_cast<sgns::blockstore::FaultController>(store_);    \
        if (!fc)                                                                           \
        {                                                                                  \
            GTEST_SKIP() << "[fault-conformance] backend does not implement "              \
                            "FaultController";                                             \
        }                                                                                  \
        fc->SetFault(sgns::blockstore::FaultKind::Unavailable);                            \
        auto got = store_->Get(cid_a_);                                                    \
        ASSERT_FALSE(got);                                                                 \
        EXPECT_EQ(got.error().code,                                                        \
                  sgns::blockstore::StatusClass::TemporarilyUnavailable);                  \
```
Rules: factory invoked PER CASE (fresh store), `dynamic_pointer_cast<FaultController>` probe + `GTEST_SKIP` with the `[fault-conformance]` label, plain EXPECT/ASSERT with manual `.value()`/`.error()` (kit discipline: zero outcome test macros), every fault case ends with fault-cleared success (see `FaultClearsNoStickyNegativeCache` `:271-290` — the D-06 shape predates the decision; new cases make it explicit). Transport-specific and drainer suites stay OUT of the kit (D-07 split).

---

### 9. `test/tier1_audit_check.cmake` (new static audit — D-14)

**Analog:** `test/header_hygiene_check.cmake` — clone the shape wholesale; swap the pattern sets.

```cmake
if(NOT DEFINED SRC_DIR)
  message(FATAL_ERROR "header_hygiene_check: SRC_DIR must be defined (-DSRC_DIR=<repo root>)")
endif()

file(GLOB_RECURSE _headers "${SRC_DIR}/include/sgns-blockstore/*.hpp")

if(NOT _headers)
  message(FATAL_ERROR "header hygiene violation: no headers found under ${SRC_DIR}/include/sgns-blockstore")
endif()

set(_banned
    "ipfs_lite/ipfs/"
    "SuperGenius/"
    "GeniusSDK/"
    "GeniusWallet/"
    "minio"
    )

set(_count 0)
foreach(_header IN LISTS _headers)
  math(EXPR _count "${_count} + 1")
  file(STRINGS "${_header}" _lines)
  foreach(_line IN LISTS _lines)
    foreach(_pattern IN LISTS _banned)
      if(_line MATCHES ".*#include.*${_pattern}.*")
        message(FATAL_ERROR "header hygiene violation: ${_header}: ${_line}")
      endif()
    endforeach()
  endforeach()
endforeach()

message(STATUS "header hygiene OK: ${_count} headers clean")
```
Deltas for the clone: pattern set 1 = fixed sleeps (`std::this_thread::sleep_for`, `Sleep(`, `sleep(`, `usleep`, `nanosleep`); pattern set 2 = non-loopback hosts (allow `127.0.0.1`/`localhost`/`::1`; reject IP/host-shaped literals — `play.min.io` explicitly banned). Scope decision (discretion, research recommends): audit the Tier-1 source set only — the ONE existing `sleep_for` in the tree is `test/MinioServerHarness.cpp:241` (verified by grep this phase), Tier-2 bounded health-poll support code. Registration next (`§10`). Belt-and-suspenders option (research Pitfall 1): additionally fail when any registered test lacks a Tier label.

---

### 10. `test/CMakeLists.txt` (build config modify — D-13/D-14)

**Analog:** itself. Three edits:

**(a) LABELS after every registration** — one `set_tests_properties` line per test, zero surgery on the shared `addtest()` macro (`cmake/functions.cmake:12-38` owns `add_test(NAME ${test_name} ...)`):
```cmake
# From test/CMakeLists.txt:25-33 (the crash-test block, shown for the link removal below)
addtest(local_block_store_crash_test local_block_store_crash_test.cpp)
target_link_libraries(local_block_store_crash_test
    sgns-blockstore
    p2p::p2p_cid
    RocksDB::rocksdb
)
set_tests_properties(local_block_store_crash_test PROPERTIES LABELS "Tier1")
```
Tier assignment (research Q1/Q7 recommendation): pure binaries → single label; MIXED binaries (`minio_cpp_spike_test`, `minio_s3_client_test`) → `"Tier1;Tier2"`; `s3_block_store_minio_test` → `Tier2`; `s3d_spike_test`/`s3d_roundtrip_e2e` → `Tier3`. Multi-label via semicolons.

**(b) Audit test registration** — clone of the `header_hygiene` registration at `:182-184`:
```cmake
add_test(NAME header_hygiene
    COMMAND ${CMAKE_COMMAND} -DSRC_DIR=${CMAKE_SOURCE_DIR} -P ${CMAKE_CURRENT_SOURCE_DIR}/header_hygiene_check.cmake)
```
→ same three lines for `tier1_static_audit` + `tier1_audit_check.cmake` + `LABELS "Tier1"`.

**(c) RocksDB link removal** — once D-09 replaces `CorruptStoredBlock`, delete `RocksDB::rocksdb` from the crash-test link line (above), the justifying comment above it ("Crash suite links RocksDB DIRECTLY for the raw second-handle corruption forge..."), and the `<rocksdb/db.h>` includes in the test source. All 14 existing registrations (13 `addtest` + `header_hygiene`) get labels; new binaries this phase register with labels from day one.

---

### 11. `thirdparty/.github/workflows/build.yml` (CI one-line edit — D-13)

**Analog:** itself — the exact line being edited (`:364-373`, verified this phase):
```yaml
      # sgns-blockstore hermetic test lane (research Q1 resolution: ctest in
      # the build tree; SuperGenius CI consumes prebuilt thirdparty releases
      # and runs no thirdparty tests). Gated off iOS/Android legs - their
      # cross-compiled test executables cannot run on the host. The
      # superbuild entry hard-codes -DTESTING:BOOL=ON after the common args,
      # so the binaries are already built by the step above.
      - name: Run sgns-blockstore tests
        if: ${{ matrix.target == 'Windows' || matrix.target == 'Linux' || matrix.target == 'OSX' }}
        working-directory: ${{env.BUILD_DIRECTORY}}
        run: ctest --test-dir sgns-blockstore/src/sgns-blockstore-build -C ${{matrix.build-type}} --output-on-failure
```
Change: append `-L Tier1` to the `run:` line (fail-closed — `-LE "Tier2|Tier3"` fails open for unlabeled tests, research Pitfall 1). Optional (discretion): add `--no-tests=error`. Do NOT touch `SuperGenius/.github/workflows/cmake.yml` — it downloads prebuilt thirdparty and runs no sgns-blockstore tests (premise correction, research Q4). Update the step's comment to record the Tier1 restriction. Dev-machine full runs stay unlabeled `ctest`.

---

### 12. `docs/testing-tiers.md` (new doc — D-16)

**Analog (role-match):** `docs/s3d-durability.md:1-12` — title + scope preamble + every-claim-traces-to-artifact discipline:
```markdown
# s3d Durability Characterization (S3D-03)

This document characterizes the staged-vs-durable semantics of **Sia
s3d v0.2.1** as they concern the `sgns-blockstore` library: ...

**Every claim below traces to a committed artifact under
`docs/evidence/s3d-spike/` or to the pinned tag's sources** (D-13).
```
Content: the research Q7 inventory table (16 rows: every test binary × tier × gate env var × evidence pointers, incl. the two NEW tests `tier1_static_audit` and any new suite), the label × env-gate interplay rule, the CI lane line, and pointers to `docs/evidence/s3d-spike/` for Tier-3 (D-17: reuse, never refresh). Delta vs analog: an inventory/table doc, not a characterization — keep the trace-to-artifact preamble and the tier-pin preamble; drop the findings-narrative shape.

### 13. `Readme.md` (new minimal — D-16 reference target)

**No analog** — the repo has no README (verified: `file_search README*` → none in `thirdparty/sgns-blockstore`). Minimal stub: one-paragraph library description + link to `docs/testing-tiers.md` + link to `docs/s3d-durability.md`. Match the tone of `docs/s3d-durability.md`'s opening. Planner may alternatively cross-reference from existing docs only (research Open Question 3) — both satisfy D-16's letter.

---

## Shared Patterns

### 1. Per-case good-fetch recovery (D-06 — applies to EVERY new fault case)
**Source:** `test/minio_s3_client_test.cpp:276-303` (`NoStickyNegativeCache`) and kit `FaultClearsNoStickyNegativeCache` (`BlockStoreConformanceTests.hpp:271-290`):
```cpp
        stub.EnqueueResponse(Bare500());
        auto faulted = client->Get("matrix-object");
        ASSERT_FALSE(faulted);
        EXPECT_EQ(faulted.error().code, StatusClass::TemporarilyUnavailable);

        stub.EnqueueResponse(
            "HTTP/1.1 200 OK\r\n"
            "ETag: \"recovered\"\r\n"
            // ... valid object response ...
        auto recovered = client->Get("matrix-object");
        ASSERT_TRUE(recovered) << "adapter must not cache the failure";
```
Every fault case ENDS with recovery asserted inline in the same test — fault → assert taxonomy class → clear/re-script → assert success.

### 2. `policy::terminate` result discipline (applies to ALL new test code)
**Source:** `test/upload_drainer_test.cpp:267-280` (the documented in-test note):
```cpp
    // GetUploadState is fault-gated too (policy::terminate - never
    // .value() a possibly-failed envelope): clear BEFORE asserting.
    local_->SetFault(FaultKind::None);
    EXPECT_EQ(local_->GetUploadState(cid_a).value(),
              UploadState::PendingUpload);
```
`ASSERT_TRUE(res)` / `if (!res)` before any `.value()`/`.error()`. Never `OUTCOME_TRY` a `CidOf` failure into a `BlockStatus` envelope.

### 3. Test helper block (copy verbatim into any NEW test file)
**Source:** `test/local_block_store_crash_test.cpp:50-83` (and drainer `:42-77`):
```cpp
    gsl::span<const uint8_t> SpanOf(const std::string& s)
    {
        return gsl::span<const uint8_t>(
            reinterpret_cast<const uint8_t*>(s.data()), s.size());
    }

    Cid MakeCid(const std::string& payload)
    {
        return CidOf(SpanOf(payload), MulticodecType::Code::RAW).value();
    }

    // SHORT relative path under the build tree (Windows MAX_PATH); a
    // monotonic counter gives every case its own directory.
    std::string NextUniqueDir()
    {
        static std::atomic<uint64_t> next{0};
        return "test-data/local-blockstore-crash/case-"
             + std::to_string(next.fetch_add(1));
    }
```
Use string iterators (never `gsl::span` iterator temporaries) when building expected byte vectors — MSVC debug crash landmine.

### 4. `@given/@when/@then` Doxygen block on every TEST_F
**Source:** every case in all five suites (e.g. crash test `:130-138`). Non-negotiable repo convention; the four-state matrix cases must state their window in `@given`.

### 5. Journal assertion triple (D-03/D-05(c) assertions)
**Sources:** `BlockStoreTooling.hpp:57-77` (`GetPendingUploads` — "CIDs whose upload-journal state is PendingUpload", available immediately after Open), `LocalBlockStore.hpp` `GetUploadState`/`MarkUploadedAccepted` (no-fabrication NotFound rule), `UploadDrainer.hpp:59-70` (`DrainItem`: `upload` + `journal` default-success when no mark ran). Assert through these three surfaces + byte identity; never inspect RocksDB.

### 6. Loud labelled skip / env-gate (unchanged inner layer, D-15)
**Source:** `minio_s3_client_test.cpp:296-310` (`MinioServerHarness::Available()` + `GTEST_SKIP() << "[SGNS_BLOCKSTORE][MINIO-TIER] ..."`). No skip meta-test this phase; labels carry inspectability.

### 7. Taxonomy honesty — assert the mapper, never re-classify
**Source:** `src/MinioS3Client.cpp:41-44` (three distinct 412 shapes → alreadyPresent), `:89` (default → TemporarilyUnavailable, never NotFound). Matrix tests assert OUTCOMES; the three-412-shape handling must not regress.

---

## No Analog Found

| File / Dimension | Role | Data Flow | Reason | Planner Guidance |
|------|------|-----------|--------|------------------|
| `Readme.md` (repo root) | docs | n/a | No README exists anywhere in `thirdparty/sgns-blockstore` | Minimal stub; tone-match `docs/s3d-durability.md` |
| Per-key fault overlay (Gap A dimension of `InMemoryS3Client`) | test fake | request-response | Op-indexed table has no key dimension; no in-repo per-key fault precedent | Extend the existing table-driven seam (§3): `key_faults_` map + `SetFaultForKey`; define precedence vs op gate; keep `S3Client.hpp` frozen |

---

## Metadata

**Analog search scope:** `thirdparty/sgns-blockstore/{include,src,test,docs,cmake}` (full tree, 19 tracked files read/grep-verified), `thirdparty/.github/workflows/build.yml`, `thirdparty/build/CommonTargets.cmake` (via research), `cmake/functions.cmake`
**Files scanned:** 20 analog files read (13 full, 7 targeted ranges) + 2 greps (`TEST_F`/`sleep_for` sweeps)
**Tracked-source verification:** `git ls-files` — 19/19 submodule paths + 1/1 thirdparty-root path tracked
**Pattern extraction date:** 2026-10-22
**Line-number provenance:** primary reads this session, cross-checked against 05-RESEARCH.md pinned citations (which were independently verified line-by-line during research)
