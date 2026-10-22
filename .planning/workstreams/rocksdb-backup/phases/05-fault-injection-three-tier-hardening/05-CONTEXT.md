# Phase 5: Fault Injection & Three-Tier Hardening - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning

<domain>
## Phase Boundary

The hardening proof layer over the finished three-backend stack. This phase delivers:

1. The crash-injection matrix: kill windows across the journal lifecycle (pre-commit, pending, uploaded-but-unmarked, accepted) proven via in-process FaultController reopen + WAL recovery, journal reconciliation, and idempotent re-drain — against hermetic fakes only (TEST-02)
2. The fault matrix at three levels: loopback-stub faults at `MinioS3Client` (SC1 letter: connection-refused, 5xx, truncated bodies, garbage responses), `S3BlockStore` over the faulting fake (corrupt-response rejection, `Has` under faults), and `UploadDrainer` under injected faults (partial uploads: per-item continue-on-failure, journal advances only on remote-present, re-drain retries only still-pending) (TEST-02)
3. The corruption matrix: byte-flipped local blocks (via a FaultController corrupt-after-commit hook) rejected as `Corrupt` with local attribution + Phase-2 self-heal semantics; byte-flipped remote blocks (via fake scripting) rejected as `Corrupt` with remote attribution, re-fetch-every-Get, never remote-deleted (TEST-02)
4. Tier inspectability mechanics (SC3/TEST-01): CTest LABELS Tier1/Tier2/Tier3 with the CI lane restricted to Tier1, a static audit AS a Tier-1 ctest test (no fixed sleeps, no non-loopback hosts in Tier-1 sources), and `docs/testing-tiers.md` — the human-readable tier inventory
5. Backend-generic fault cases extend the conformance kit's existing FaultController section; transport-specific and drainer suites stay standalone

Out of this phase: subprocess-kill crash tests (explicitly rejected — Phase-2 D-07 door now closed), any s3d re-run (Phase-4 evidence satisfies SC3's Tier-3 clause), durability-signal polling implementation, `MarkUploadedDurable` automated wiring, `TieredBlockStore`/retrieval tiering, MinIO-tier crash cases, consumer wiring in `CommonBuildParameters.cmake`, any new library capability.

Requirements: TEST-01, TEST-02.

</domain>

<decisions>
## Implementation Decisions

### Crash-injection mechanism
- **D-01:** Crash injection is **in-process FaultController reopen ONLY** — inject fault, close-without-clean-shutdown, reopen, RocksDB WAL recovery does the real work. NO subprocess kills: Phase-2 D-07's "Phase 5 may add" door is now **closed**; the Windows child-process/kill-signaling portability cost stays rejected. Deterministic, portable, runs in every CI lane — **Reversibility:** reversible — a subprocess smoke could still be added additively later, but the matrix binds to the in-process seam
- **D-02:** SC2's "mid-temp-write" window is **reinterpreted against the atomic design and documented**: there are no temp files (Phase-2 D-02, one WriteBatch), so an interrupted local write = crash-before-WAL-commit ⇒ NOTHING visible (`Get`→`NotFound`, no journal record). SC2's three named windows map onto **four real states**: pre-commit (nothing exists), pending (block+`PendingUpload`, remote absent), uploaded-but-unmarked (remote present, journal still `PendingUpload`), accepted. The mapping is documented where the crash tests live — **Reversibility:** costly — the SC2 audit trail and every crash-test assertion bind to this window model
- **D-03:** The matrix proves **all four states**, including the uploaded-but-unmarked payoff: reopen → reconciliation surfaces pending → re-drain → createOnly Put → `alreadyPresent` → `MarkUploadedAccepted` advances — the idempotent re-put semantics (Phase-1 D-04 / Phase-4 D-03) prove crash-safety by construction — **Reversibility:** costly — the matrix asserts these exact journal transitions
- **D-04:** Crash windows involving the remote tier run against the **hermetic fake only** (`InMemoryS3Client` scripts remote-present/absent). No MinIO-binary or s3d crash cases — crash tests stay Tier-1 and run in CI everywhere — **Reversibility:** reversible

### Fault-matrix breadth
- **D-05:** The matrix runs the **full composed stack**: (a) loopback-stub faults at `MinioS3Client` for taxonomy honesty (SC1 letter); (b) `S3BlockStore` over the faulting fake (corrupt-response rejection via CID verify, `Has` under 5xx → `TemporarilyUnavailable`); (c) `UploadDrainer` under injected faults — TEST-02's "partial uploads": one item fails mid-drain, siblings continue, journal advances only on remote-present outcomes, re-drain retries only still-pending blocks — **Reversibility:** costly — the test-suite structure and TEST-02 coverage claims bind
- **D-06:** SC1's "no sticky negative caching — a subsequent good fetch succeeds" is asserted **per-case**: every fault case ENDS with a good-fetch-succeeds assertion in the same test; each fault proves its own recovery inline — **Reversibility:** costly — every matrix fixture follows this shape
- **D-07:** Matrix home is **split by generality**: backend-generic fault cases (corrupt bytes → `Corrupt`, induced backend failure → correct taxonomy class) extend the conformance kit's existing FaultController section (instantiable per backend via the established macro pattern); transport-specific suites (`LoopbackHttpStub`/HTTP garbage at `MinioS3Client`) and the drainer-under-fault suite stay **standalone** test targets — **Reversibility:** costly — kit macro surface and fixture placement bind simultaneously
- **D-08:** Truncated-body taxonomy is **split by layer**: HTTP framing broken mid-read → adapter reports `TemporarilyUnavailable` (transport); a complete-but-wrong-length body that arrives → store-level CID verify fails → `Corrupt` with remote source attribution (CORE-04 verification boundary, CORE-02 honesty) — **Reversibility:** costly — taxonomy assertions at both layers bind

### Corruption injection mechanics
- **D-09:** Local byte-flips are injected via a **FaultController corrupt-after-commit hook**: after the WriteBatch lands, internally flip bytes in the blocks column family. Tests stay API-only — no direct RocksDB second-handle access from tests, no coupling to CF naming internals, portable across all five platforms. The hook joins the installed `FaultController.hpp` seam designed for exactly this — **Reversibility:** costly — the hook becomes part of the installed seam surface
- **D-10:** Remote byte-flips are injected via **`InMemoryS3Client` scripting only**: scripted `Get` returns flipped bytes for a stored key → store CID-verify fails → `Corrupt` with remote attribution. Deterministic, Tier-1 hermetic — **Reversibility:** reversible
- **D-11:** **Remote-corrupt repeated-Get semantics**: every `Get` re-fetches and re-reports `Corrupt` — no caching of bad bytes, and the remote block is NEVER deleted (CORE-05; the store cannot self-heal a remote tier it has no delete for). If the remote is later repaired, the next fetch succeeds — mirroring the no-sticky-negative-cache discipline. Local corruption keeps Phase-2 D-09's evict-and-surface self-heal unchanged — **Reversibility:** costly — asserted semantics differ per tier and both bind
- **D-12:** Corruption proof rides the **Get path only** (verification lives on fetch); `Has`/`GetSize` are **documented in headers as NOT content-verifying** (HEAD metadata only). No test assertions pinning the blind spot beyond the doc note — **Reversibility:** reversible

### Tier inspectability (SC3/TEST-01)
- **D-13:** Primary tier separation is **CTest LABELS + CI lane**: every sgns-blockstore test declares `LABELS Tier1|Tier2|Tier3` in `test/CMakeLists.txt`; the CI invocation is restricted to Tier1 (`ctest -L Tier1` or `-LE Tier2,Tier3`). Tiers are readable directly from the test CMake + CI workflow — the "verifiable from CI/test configuration" clause is satisfied by configuration itself. Env-gating (Phases 3-4) remains the inner defense layer — **Reversibility:** costly — CI workflow + every test registration carry the labels
- **D-14:** The static audits (no fixed sleeps in test sources; no non-loopback hosts in Tier-1 tests) run **AS a Tier-1 ctest test** — self-inspecting, runs everywhere ctest runs, part of the test configuration rather than a CI-only step — **Reversibility:** reversible
- **D-15:** **No skip meta-test** — the env-gate + loud-labelled-skip pattern (proven live in Phases 3-4) carries enforcement; labels + audits carry inspectability. One less moving part — **Reversibility:** reversible
- **D-16:** The human-readable tier inventory lives at **`docs/testing-tiers.md` inside the sgns-blockstore repo**: every test binary × tier × gate env var × evidence pointers (s3d run logs), referenced from the repo README — lives with the code it describes — **Reversibility:** reversible
- **D-17:** SC3's Tier-3 "committed evidence" clause is satisfied by **Phase-4's existing artifacts** (`docs/evidence/s3d-spike/`, committed run logs). Phase 5 does NOT re-run s3d — **Reversibility:** reversible

### the agent's Discretion
- `FaultController` hook naming/granularity (the corrupt-after-commit fault point's exact shape and any sibling points)
- Stub fault-case enumeration beyond SC1's four classes (exact 5xx codes, garbage body shapes, truncation offsets)
- Audit-test implementation mechanics (grep patterns, allowlist shape, source-file scope) and its test-file placement
- CI workflow edits (which lanes, exact ctest invocation form) — coordinated with existing SuperGenius CI conventions
- Kit fault-section macro naming/extensibility mechanics (how the generic fault cases join `SGNS_BLOCKSTORE_CONFORMANCE_TESTS`)
- Test file naming/layout inside `test/` beyond existing conventions
- Exact label strings (`Tier1` vs `tier1`) and how Tier-2/3 labels interact with env-gates
- Whether the accepted-state window asserts via the journal state reader, drain idempotency, or both
- `docs/testing-tiers.md` exact format and README reference wording
- The four-state window-model documentation location (test-file header comment vs doc — D-02 requires it documented somewhere discoverable)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements; verification-at-boundary and eviction ≠ delete invariants the fault/corruption matrix proves

### Workstream planning
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — TEST-01, TEST-02 (this phase); Out of Scope table (no Docker CI, no live-internet endpoints); Future list (polling, TieredBlockStore — all stay deferred)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 5 goal + 3 success criteria (the SC2 window language D-02 reinterpretation addresses)
- `.planning/workstreams/rocksdb-backup/phases/01-blockstore-contract-memory-backend-conformance-kit/01-CONTEXT.md` — frozen contract D-01..D-16: taxonomy (CORE-02), verify-at-boundary (CORE-04), `PutOutcome { achieved, alreadyPresent }`, FaultController seam, conformance macro, guard tests
- `.planning/workstreams/rocksdb-backup/phases/02-localblockstore-rocksdb-cold-tier/02-CONTEXT.md` — D-02 (atomic WriteBatch, no temp files — the SC2 reinterpretation anchor), D-06 (journal transition methods), D-07 (in-process crash seam — D-01 here closes its open door), D-09 (evict-and-surface self-heal — local corruption semantics)
- `.planning/workstreams/rocksdb-backup/phases/03-minio-cpp-integration-s3client-adapter/03-CONTEXT.md` — D-05 (fake per-op fault scripting), D-07/D-09 (env-gated opt-in + loud-skip discipline), D-08 (loopback stub as fault-matrix seed)
- `.planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-CONTEXT.md` — D-03 (drain per-item continue-on-failure semantics the drainer-under-fault suite asserts), D-04 (`MarkUploadedAccepted`-only advancement), D-08..D-11 (Tier-3 dev-gate + committed-evidence pattern D-17 leans on)

### Research (2026-10-19)
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-19.md` — pitfall 2 (transport-as-NotFound — the SC1 matrix exists to prove it can't happen), 3 (torn writes → D-02 mapping), 4 (crash windows → D-03 window model)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-19.md` — key decisions (TEST-02 fault injection depends on Phase-2 journal; three-tier strategy origin)

### Codebase (the surfaces the matrix drives)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp` — the seam D-01/D-09 extend (crash points today; corrupt-after-commit hook lands here)
- `thirdparty/sgns-blockstore/test/LoopbackHttpStub.hpp/.cpp` — the raw-HTTP stub D-05(a) scripts (Phase-3 D-08 seed)
- `thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp/.cpp` — per-op fault scripting for D-04/D-05(b)/D-10
- `thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp` — the proven in-process reopen pattern D-01 generalizes
- `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` — the kit whose FaultController section D-07 extends
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp`, `BlockStoreTooling.hpp` — journal transitions + pending-set enumeration (D-03 assertions read these)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/UploadDrainer.hpp` — the per-item drain contract D-05(c) runs under faults
- `thirdparty/sgns-blockstore/src/MinioS3Client.cpp/.hpp` — the one-place taxonomy mapping SC1 asserts against (THREE distinct 412 shapes already handled)
- `thirdparty/sgns-blockstore/docs/s3d-durability.md`, `thirdparty/sgns-blockstore/docs/evidence/s3d-spike/` — D-17's existing evidence
- `thirdparty/sgns-blockstore/test/CMakeLists.txt` (in-tree) — where D-13 LABELS land

### Build & conventions
- `thirdparty/build/CommonTargets.cmake` — sgns-blockstore entry (`TESTING:BOOL=ON` gate; no superbuild change expected this phase)
- `Coding Standards.md` (workspace root) — C++ style: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen on public interfaces
- `.planning/codebase/TESTING.md` — GTest via superbuild; verification-inside-`build/<Platform>/<Config>`-tree rule

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LoopbackHttpStub` — already serves scripted 5xx/garbage/truncated/connection-refused (Phase-3 SC4 proof); Phase 5 formalizes it into the systematic SC1 matrix
- `InMemoryS3Client` fault scripting — stateful per-op fault injection; drives store-level and drainer-level suites hermetically
- `FaultController` + `local_block_store_crash_test.cpp` reopen pattern — the proven crash mechanic; extend with corrupt-after-commit (D-09) and the drainer-window states (D-03)
- Conformance kit FaultController section — the backend-generic fault cases D-07 extends
- Journal state reader + tooling pending-set enumeration — D-03's four-state assertions read them
- `MinioServerHarness` + env-gate/loud-skip pattern — Tier-2/3 discipline D-13/D-15 build on

### Established Patterns
- Status mapping in exactly one place per backend — the matrix asserts the mapper's outputs, never re-implements classification
- Loud labelled skips for gated tests; env-var binary/endpoint location; no auto-download; no fixed sleeps (TEST-01 — now audit-enforced per D-14)
- Library-local `result<R,S,policy::terminate>` alias in every header; `.value()` on failure terminates — guard with `has_value()`
- Committed live-run evidence logs for gated tiers (D-17 reuses, doesn't refresh)

### Integration Points
- `test/CMakeLists.txt` — LABELS on every test target + the audit test registration (D-13/D-14)
- CI workflow (SuperGenius cmake.yml lane) — ctest invocation restricted to Tier1 (D-13)
- `FaultController.hpp` — the corrupt-after-commit hook joins the installed seam (D-09)
- `docs/testing-tiers.md` + README — new inventory doc (D-16)
- Conformance kit macro — generic fault-section extension (D-07)

### Landmines (verified in Phases 1–4)
- `policy::terminate` result alias mandatory; never `OUTCOME_TRY` a `CidOf` failure into a `BlockStatus` envelope
- THREE distinct minio-cpp 412 error shapes must classify to alreadyPresent (mapper handles; matrix must not regress it)
- Windows/MSVC debug: `std::vector` from `gsl::span` iterator temporaries crashes — use string iterators in tests
- Never verify TLS against s3d's per-start self-signed cert
- Crash-test discipline: close-without-clean-shutdown must skip RocksDB clean-Flush paths or the WAL recovery proof is vacuous

</code_context>

<specifics>
## Specific Ideas

- Four-state window model (what crash tests prove): pre-commit ⇒ nothing exists; pending ⇒ block + `PendingUpload`, remote absent; uploaded-but-unmarked ⇒ remote present, journal `PendingUpload` → reopen → re-drain → `alreadyPresent` → Accepted; accepted ⇒ stable. The mid-write state does not exist — that absence IS the Phase-2 D-02 proof
- Drainer-under-fault flow sketch: seed N pending blocks → script fake: item 2 returns 5xx → drain → item 1/3..N upload, item 2 fails with taxonomy status → journal: 1/3..N Accepted, 2 still Pending → good-fetch-succeeds follow-up on item 2 (per-case recovery, D-06) → re-drain uploads only item 2
- Corruption flow sketches: local — Put real block → corrupt-after-commit hook fires → reopen → Get: `Corrupt` + local attribution + entry atomically removed → Get: `NotFound` → re-Put repairs (Phase-2 D-09 self-heal); remote — Put via fake → script flipped bytes → Get: `Corrupt` + remote attribution → Get again: still `Corrupt` (re-fetch, no bad-byte cache) → repair remote → Get succeeds
- Audit-test sketch: a Tier-1 ctest that scans the test tree's Tier-1 sources for fixed-sleep constructs and non-loopback host literals; fails loudly with file:line; allowlist lives next to it

</specifics>

<deferred>
## Deferred Ideas

- Subprocess-kill crash tests — explicitly rejected this phase (D-01 closes Phase-2 D-07's open door); could be revisited only as an additive dev-gated smoke in a future milestone
- MinIO-binary (Tier-2) crash-window replay and s3d (Tier-3) crash replay — rejected for Phase 5 (D-04); hermetic fake carries the proof
- Durability-signal polling implementation, `MarkUploadedDurable` automated wiring, `TieredBlockStore`/retrieval tiering, metrics surface — unchanged, REQUIREMENTS Future list

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched Phase 5 on the generic keyword "crash" only (score 0.2); unrelated to the BlockStore library; same disposition as Phases 1–4 (fifth consecutive review); stays with base SuperGenius planning

</deferred>

---

*Phase: 5-Fault Injection & Three-Tier Hardening*
