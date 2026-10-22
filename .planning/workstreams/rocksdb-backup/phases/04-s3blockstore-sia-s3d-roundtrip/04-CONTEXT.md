# Phase 4: S3BlockStore & Sia s3d Roundtrip - Context

**Gathered:** 2026-10-21
**Status:** Ready for planning

<domain>
## Phase Boundary

The terminal cold-storage tier ships. This phase delivers:

1. `S3BlockStore` — the `BlockStore` backend composing over the Phase-3 `S3Client` adapter: `v1/blocks/` full-CID codec-preserving key layout, conditional create-only PUTs (`createOnly=true` → `If-None-Match:*`, 412 → `alreadyPresent=true`), HEAD 200/404→bool / everything-else→`TemporarilyUnavailable` (BACK-07)
2. The public upload drainer — an installed-API component that drains `LocalBlockStore`'s pending journal set to `S3BlockStore` and marks `MarkUploadedAccepted` (see D-01..D-04)
3. `S3Client` header promotion to installed headers (03 D-04 honored — `S3BlockStore` is the first public consumer)
4. The day-one dev-gated live s3d entrance spike: conditional-PUT + HEAD semantics + `/stats/uploads` durability field shapes at pinned s3d v0.2.1 — a HARD entrance gate for s3d-dependent work (D-05..D-07)
5. Opt-in MinIO-binary integration tests instantiating the Phase-3 harness: `MinioS3Client`→`S3BlockStore` roundtrip, Put → Get → CID-verify (S3D-01/SC3)
6. The dev-gated live s3d E2E (S3D-02/SC4): two-run fresh-process proof, drainer-driven spill upload, dev-run s3d via env vars, committed run-log evidence
7. The S3D-03 durability finding: evidence-cited characterization doc shipped in the repo, cited from `Durability.hpp` (D-12/D-13)

Out of this phase: durability-signal polling implementation (fast-follow milestone), `MarkUploadedDurable` wiring (caller/tooling until polling exists), `TieredBlockStore`/retrieval tiering facade (REQUIREMENTS Future list), fault-matrix execution (Phase 5), consumer wiring in `CommonBuildParameters.cmake`.

Requirements: BACK-07, S3D-01, S3D-02, S3D-03.

</domain>

<decisions>
## Implementation Decisions

### Store & drainer composition
- **D-01:** Phase 4 ships **`S3BlockStore` AND the upload drainer** — a library component that iterates `LocalBlockStore`'s pending journal set (tooling enumeration, 02 D-05), Puts each block to `S3BlockStore`, and calls `MarkUploadedAccepted` on remote-present outcomes. Phase 2's "for Phase 4's uploader" intent is honored in-phase; a tiered facade remains deferred future work — **Reversibility:** costly — the drainer binds the journal transition surface (02 D-06), the store's Put semantics, and consumer spilling behavior simultaneously
- **D-02:** The drainer is a **public installed API** (installed header, first-class library capability) — consumers (SuperGenius, genius-tube) drive the actual hot→cold spilling themselves, so the upload path is not test scaffolding. Follows the `S3Client` promotion precedent (03 D-04) — **Reversibility:** costly — published API surface; removal is an API break
- **D-03:** Drain semantics are **per-item, continue-on-failure**: each pending block uploads independently; the drain returns a per-item outcome vector (uploaded / alreadyPresent / failed with taxonomy status) and keeps going past failures. Mirrors the frozen `PutMany` no-all-or-nothing contract (01 D-14); a later re-drain retries only still-pending blocks. Crash-safe by construction — journal state advances only on per-item remote-present outcomes — **Reversibility:** costly — the return shape and re-drain contract bind consumer call sites
- **D-04:** The drainer marks **`MarkUploadedAccepted` only** — both `achieved` and `alreadyPresent` count as remote-present and advance the journal to Accepted. `MarkUploadedDurable` stays a caller/tooling transition until the durability-polling implementation lands (fast-follow milestone) — keeps the phase honest with "200-OK ≠ durable" and decouples the drainer from the in-phase S3D-03 discovery outcome — **Reversibility:** reversible — Durable wiring is added later without touching Accepted semantics

### s3d entrance spike
- **D-05:** **Day-one dev-gated live s3d spike** (Phase-3 D-11 discipline) opens the first Phase-4 plan: prove at a real s3d v0.2.1 endpoint what S3BlockStore semantics will rely on, BEFORE the store bakes in assumptions. Contingency is decided **then, on real evidence** (D-10 posture: no pre-committed fallback ladder; if a needed s3d capability is genuinely missing, decide with facts in hand) — **Reversibility:** reversible — spike scope adjustable in planning
- **D-06:** The spike covers the **full trio including durability**: (1) conditional PUT `If-None-Match:*` → expect 412 on re-put, (2) HEAD 200/404 semantics, (3) `/stats/uploads` + staged-read header field shapes. The S3D-03 finding doc is written from this spike ground truth + `openapi.yml` cross-read — one dev session feeds both the entrance criterion and the characterization — **Reversibility:** reversible
- **D-07:** The spike is a **hard entrance gate**: s3d-dependent work (E2E, durability finding, any s3d-conditional semantic) blocks until the spike runs against real s3d. Hermetic work (conformance vs fake, drainer vs fake, MinIO tier) proceeds in parallel — **Reversibility:** reversible — mirrors Phase-1 C1 gating discipline

### s3d E2E design (S3D-02)
- **D-08:** The E2E test **connects to a dev-managed running s3d** via env-provided config (endpoint URL, access keys, bucket, TLS flag — the 03 D-09 env-var + loud-skip pattern). The test NEVER spawns or manages s3d: the Sia account/wallet is dev-owned state, fundamentally heavier than the MinIO-binary child process — **Reversibility:** costly — Phase-4's Tier-3 test shape and evidence procedure bind to this model
- **D-09:** "A fresh library instance" is proven by a **two-run fresh-process design**: run A (upload) seeds via the library; run B (verify) is a genuinely fresh process with zero local state that retrieves and CID-verifies the block. Committed evidence shows both runs — an honest cold-retrieval proof (same-process reconstruction proves nothing about cold reads) — **Reversibility:** costly — test binary interface (upload/verify modes) and evidence format bind together
- **D-10:** The E2E's upload run exercises the **drainer-driven spill path**: `LocalBlockStore` Put → drainer → s3d (`MarkUploadedAccepted` lands in the journal); the verify run retrieves via a fresh `S3BlockStore`. The drainer ships this phase (D-01), so its first live proof comes free here — this is the milestone's actual story, end to end — **Reversibility:** costly — the E2E evidence artifact encodes this path
- **D-11:** The evidence artifact is a **committed run log** (Phase-3 precedent: `03-04-live-run-evidence.log`): CIDs, object keys, sizes, timestamps, s3d version, pass/fail for both runs. Human-readable and diffable; **no secrets in the log** (endpoint host at most, never credentials) — **Reversibility:** reversible

### Durability finding disposition (S3D-03)
- **D-12:** The finding ships as a **repo doc + header citation**: a characterization doc in the sgns-blockstore repo (e.g., `docs/s3d-durability.md`), AND `Durability.hpp`'s `ObjectStoreAccepted` doc comment cites it — the API's "200-OK ≠ durable" honesty is grounded in a committed, versioned characterization of the pinned s3d. Consumers see the same truth the library encodes — **Reversibility:** costly — published header documentation and shipped doc
- **D-13:** The finding meets an **evidence-cited bar**: raw `/stats/uploads` output before/after an upload, staged-read header observations, and the `openapi.yml` field definitions are committed as spike evidence, and every claim in the finding doc traces to an artifact. SC5's "characterized from the pinned version's admin API" is auditable, not asserted — **Reversibility:** reversible

### the agent's Discretion
- Exact CID string encoding in the key layout (BACK-07 locks `v1/blocks/` full-CID codec-preserving; base32/base58 form and separator details follow the architecture doc + research)
- `S3BlockStore` construction/config shape (bucket, prefix, injected `S3Client`) beyond the requirement letter
- `GetSize` (HEAD content-length) and verify-on-read mapping details beyond BACK-07/CORE-04
- Drainer construction shape (free function vs small class), option surface, and exact per-item result type
- Env-var names for the s3d endpoint/credentials/bucket; secret-hygiene mechanics in the evidence log
- MinIO-tier test breadth for `S3BlockStore` beyond the SC3 letter (e.g., key-layout observability checks)
- Unique-CID/re-run discipline for the two-run E2E (fresh run pair vs re-verify of previously-seeded CIDs)
- Where the s3d spike's evidence artifacts live in the repo (test tree vs docs)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements; S3 backend layout (Phase 2 of the doc), eviction ≠ delete invariants, cold-tier semantics

### Workstream planning
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — BACK-07, S3D-01, S3D-02, S3D-03 (this phase); Future list (polling, TieredBlockStore, Durable wiring all deferred); Out of Scope table
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 4 goal, 5 success criteria, research note (durability-signal discovery is in-phase; polling is fast-follow)
- `.planning/workstreams/rocksdb-backup/phases/01-blockstore-contract-memory-backend-conformance-kit/01-CONTEXT.md` — frozen contract D-01..D-16 (result envelope, `PutOutcome { achieved, alreadyPresent }`, conformance macro, guard tests)
- `.planning/workstreams/rocksdb-backup/phases/02-localblockstore-rocksdb-cold-tier/02-CONTEXT.md` — journal semantics D-03..D-06 (pending-set birth, tooling enumeration, transition methods the drainer composes over)
- `.planning/workstreams/rocksdb-backup/phases/03-minio-cpp-integration-s3client-adapter/03-CONTEXT.md` — adapter decisions D-01..D-12 + Q1 amendment (createOnly option, 412→alreadyPresent, harness pattern, S3Client promotion planned here)

### Research (2026-10-19)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-19.md` — key decisions (s3d 200-OK ≠ durable → 4-value DurabilityLevel + honest ObjectStoreAccepted; C2 MinIO-binary CI; durability-signal discovery pinned Phase 4)
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-19.md` — pitfall 2 (transport-as-NotFound), 3 (ETag never a proof); TLS-vs-s3d-self-signed note
- `.planning/research/ARCHITECTURE-rocksdb-backup-2026-10-19.md` — adapter rationale, tier composition
- `.planning/research/STACK-rocksdb-backup-2026-10-19.md` — s3d v0.2.1 pin facts

### Phase-1/2/3 codebase (the foundation being extended)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp`, `BlockStatus.hpp`, `Durability.hpp`, `Options.hpp`, `Capabilities.hpp`, `Cid.hpp` — frozen public contract; `Durability.hpp` gains the ObjectStoreAccepted citation (D-12); `Cid.hpp` carries the library-local `result<R,S,policy::terminate>` alias MANDATORY in any new header
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp`, `BlockStoreTooling.hpp` — journal transition methods (02 D-06) + pending-set enumeration (02 D-05) the drainer consumes
- `thirdparty/sgns-blockstore/src/S3Client.hpp` — the adapter interface (5 ops + config) promoted to installed headers this phase (03 D-04)
- `thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp/.cpp` — stateful fake; conformance kit runs against S3BlockStore through it
- `thirdparty/sgns-blockstore/src/MinioS3Client.cpp/.hpp` — real client; one-place taxonomy mapping (note: THREE distinct 412 error shapes must classify to alreadyPresent — see STATE.md Phase-03 decision note)
- `thirdparty/sgns-blockstore/test/MinioServerHarness.hpp/.cpp` — the env-gated harness Phase 4 instantiates (TLS + plaintext functional; G-3-1 closed)
- `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` — the kit `S3BlockStore` instantiates via `SGNS_BLOCKSTORE_CONFORMANCE_TESTS`
- `.planning/workstreams/rocksdb-backup/phases/03-minio-cpp-integration-s3client-adapter/03-04-live-run-evidence.log` — the committed-evidence precedent D-11 follows

### Build & conventions
- `thirdparty/build/CommonTargets.cmake` — sgns-blockstore entry (no new ExternalProject expected this phase; changes are library-internal)
- `Coding Standards.md` (workspace root) — C++ style: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen on public interfaces
- `.planning/codebase/TESTING.md` — GTest via superbuild; verification-inside-`build/<Platform>/<Config>`-tree rule

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase-3 adapter stack — `S3Client` interface, `InMemoryS3Client` fake (stateful, `createOnly`-enforcing), `MinioS3Client` (taxonomy mapping in one place): `S3BlockStore` composes directly; conformance runs against the fake
- `MinioServerHarness` — env-gated MinIO child process (TLS + plaintext both proven live, G-3-1 closed in 03-04): SC3 instantiates it for the store tier
- Journal machinery — `LocalBlockStore` transitions (`MarkUploadedAccepted`/`MarkUploadedDurable`) + tooling pending-set enumeration: the drainer's exact composition surface, already crash-tested
- Frozen `PutOutcome { achieved, alreadyPresent }` — SC2's 412→AlreadyExists-as-success maps 1:1 (03 D-02); `PutMany` per-item vector precedent shapes the drain result (D-03)
- `FaultController` seam — available if the drainer/store want fault conformance coverage this phase (full matrix is Phase 5)

### Established Patterns
- Status mapping in exactly one place per backend (`MemoryBlockStore`, `LocalBlockStore`, `MinioS3Client` precedents) — `S3BlockStore` maps adapter results, never raw HTTP
- Loud labelled skips for gated tests; env-var binary/endpoint location, no auto-download, no fixed sleeps
- Library-local `result<R,S,policy::terminate>` alias in every new header; explicit mapping of `CidOf` failures
- Committed live-run evidence logs for gated tiers (03-04 precedent)

### Integration Points
- `BlockStoreTooling.hpp` pending-set enumeration ↔ drainer iteration loop (D-01/D-03)
- `src/S3Client.hpp` → `include/sgns-blockstore/` promotion (first installed consumer: `S3BlockStore`; 03 D-04)
- `Durability.hpp` doc comment ↔ `docs/s3d-durability.md` citation (D-12)
- CI: hermetic conformance + fake-driven tests join the default lane; MinIO tier opt-in; s3d tier dev-only — TEST-01 discipline maintained

### Landmines (verified in Phases 1–3)
- `policy::terminate` alias mandatory — `.value()` on failure terminates; guard with `has_value()`
- MinIO/minio-cpp serves **three distinct 412 error shapes** (`PreconditionFailed:`, `HTTP status code: 412`, `invalid response received; status code: 412`) — the mapper classifies all three; S3BlockStore's AlreadyExists mapping inherits this
- Never verify TLS against s3d's per-start self-signed cert; plain-HTTP loopback for tests where possible
- Windows/MSVC: `std::vector` from `gsl::span` iterator temporaries crashes in debug — use string iterators in tests
- ETag is never a durability proof (research pitfall 3)

</code_context>

<specifics>
## Specific Ideas

- Drainer flow sketch: enumerate pending set (tooling) → for each CID: `S3BlockStore.Put` (createOnly) → on success slot (`achieved` OR `alreadyPresent`) call `MarkUploadedAccepted(cid)` → collect per-item outcome → return vector. Failures never abort siblings; re-drain retries only still-pending blocks
- E2E flow sketch: run A (upload): `LocalBlockStore.Put` (unique CID) → drainer → s3d; run B (verify): fresh process, fresh `S3BlockStore`, `Get` → CID-verify; committed log shows both runs with CIDs, keys, sizes, timestamps, s3d version
- Spike trio sketch: repeated conditional PUT must 412; HEAD must 200/404 cleanly; `/stats/uploads` field shapes captured before/after upload — evidence artifacts committed, finding doc cites them (D-13)

</specifics>

<deferred>
## Deferred Ideas

- Durability-signal polling implementation — fast-follow milestone per roadmap note
- `MarkUploadedDurable` wiring into any automated path — caller/tooling-only until polling exists (D-04)
- `TieredBlockStore` / retrieval tiering / peer racing — REQUIREMENTS Future list (needs measured latencies)
- Background/async drainer scheduling — v1 ships the synchronous one-shot drain; orchestration cadence is consumer policy

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched Phase 4 on the generic keyword "create" only (score 0.2); unrelated to the BlockStore library; same disposition as Phases 1–3; stays with base SuperGenius planning

</deferred>

---

*Phase: 4-S3BlockStore & Sia s3d Roundtrip*
*Context gathered: 2026-10-21*
