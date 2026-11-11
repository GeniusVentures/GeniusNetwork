# Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Library-only widening of the shipped v1.0 `sgns-blockstore` — removing the two SuperGenius integration blockers additively, with the conformance kit as the proof instrument. This phase delivers:

1. **LIB-01 — hash-gate widening:** the CID hash gate accepts blake2b-256 (CIDv1/DAG_CBOR — the exact shape `sgns::common::getCidOf` gives every CRDT DAG block) alongside sha-256; verify-on-put/get checks bytes against the CID's own multihash for both hashes; known blake2b-256/DAG_CBOR vectors join the conformance kit and run green against Memory, Local, and S3 backends; the S3 key layout's display-only codec token gains `dag-cbor`
2. **LIB-02 — installed S3 client factory:** `OpenMinioS3Client(const S3ClientConfig&)` declared in installed `S3Client.hpp` (interface-typed, SDK-free), proven by an out-of-tree consumer TU that compiles+links only against `sgns-blockstore::sgns-blockstore` from the install tree

Out of this phase: any SuperGenius/GeniusSDK consumption wiring (`CommonBuildParameters.cmake` — Phase 7), spill/drain/fallback/GC (Phases 8-11), `CidOf` behavior changes beyond the additive overload, any re-shape of the S3 key layout (the codec token is display-only today and stays display-only).

Requirements: LIB-01, LIB-02.

</domain>

<decisions>
## Implementation Decisions

### Hash-gate widening (LIB-01)
- **D-01:** The gate widens to **exactly the pair {sha-256, blake2b-256}** — hard accepted set, verification explicitly branches on both hashes; no allowlist machinery, no general multihash dispatch. Matches Phase-1 D-08's additive-widening posture: the next widening (if ever needed) is another additive change — **Reversibility:** costly — the conformance kit, guard tests, and both verification branches bind the accepted set; narrowing after SC3's no-break bar is published would be an API break
- **D-02:** Conformance vectors are **independently derived AND cross-checked**: pin literals derived from an independent source (RFC 7693 blake2b test vectors / IPLD DAG_CBOR fixtures), and additionally cross-check once against real `sgns::common::getCidOf` output via a **committed dev-run artifact** (no library→SuperGenius dependency — the cross-check is evidence, not a linked test). The compatibility claim with the actual CRDT CID producer is thereby evidenced, not trusted
- **D-03:** Hashes still outside the accepted set (e.g. sha-512) keep the **`std::invalid_argument` throw-at-entry** programmer-error contract — the D-08 posture is unchanged, only the accepted set grew. Existing blake2b-*rejection* guard tests re-target a still-out-of-set hash — **Reversibility:** one-way — the throw contract is the published v1.0 API behavior SC3 exists to protect

### CidOf public API
- **D-04:** blake2b capability surfaces as a **3-arg overload `CidOf(bytes, codec, HashType)`** — a new symbol; the existing 2-arg signature stays literally untouched (delegates to sha-256). An unsupported `HashType` argument throws `invalid_argument` (D-03 posture). Most literal reading of SC3's no-break bar — **Reversibility:** costly — published installed-helper surface; once consumers (tests, Phase 7+ adapters) call the 3-arg form, removing it is an API break

### Installed factory (LIB-02)
- **D-05:** `OpenMinioS3Client(const S3ClientConfig&)` returns **`result<std::shared_ptr<S3Client>, BlockStatus>`** — envelope-consistent with every `Open()` in the library (`MinioS3Client::Open`, `S3BlockStore::Open`, `LocalBlockStore::Open` precedents), interface-typed so the installed header stays SDK-free, and injects straight into `S3BlockStore::Open(std::shared_ptr<S3Client>, ...)`. Implementation is a thin wrapper over the internal `MinioS3Client::Open`; `MinioS3Client.hpp` stays uninstalled — **Reversibility:** costly — the published factory signature is what SC4's out-of-tree consumer proof compiles against
- **D-06:** Construction is **eager config validation, zero network I/O** — validate endpoint/bucket/port/path-style at the factory call (bad config fails AT the call site, dodging the BaseUrl-snapshot landmine: port/virtual-style must be right before client init); the minio client is lazy, so connection failures surface later through the op taxonomy, never at construction — **Reversibility:** costly — documented construction contract; consumers will rely on no-I/O-at-construction for startup ordering

### Out-of-tree proof & package-config hardening
- **D-07:** **Prove first, harden as forced:** build the SC4 out-of-tree consumer proof first; harden `cmake/config.cmake.in` exactly as far as the proof forces (transitive miniocpp/httplib/nlohmann_json/pugixml `find_dependency` resolution); anything the minimal consumer doesn't need defers to Phase 7's real `CommonBuildParameters.cmake` consumption. Evidence-driven — the Phase-3 D-10/D-05 no-pre-committed-contingency posture
- **D-08:** The proof runs as a **Tier-1 hermetic ctest**: a standalone CMake project under `test/` (its own `CMakeLists.txt` doing `find_package(sgns-blockstore CONFIG REQUIRED)` against the install tree), compile+link+construct only, zero network, registered with a Tier-1 label in the fail-closed lane — **Reversibility:** costly — the CI lane, tier label, and consumer-project shape bind together (v1.0 tier discipline)

### the agent's Discretion
- Which still-rejected hash becomes the guard-test exemplar (e.g. sha-512) and the guard-test rewrite mechanics
- The blake2b implementation entry point (libp2p crypto blake2 API shape at the pinned tree) — researcher confirms; any missing-API contingency decided on evidence per D-10 posture
- Whether the three duplicated per-backend throw-site checks consolidate into one shared validate helper (`S3BlockStore.hpp:163` already references a `ValidateCidHash` name) — planner's call
- Conformance-kit vector-set composition beyond the SC1 letter (payload diversity, DAG_CBOR fixture choices)
- Exact placement/wording of the factory declaration in `S3Client.hpp` (Doxygen per Coding Standards)
- The out-of-tree consumer project's name/location under `test/` and its CMake mechanics (how the install tree is pointed at)
- The `dag-cbor` codec token is a new `CodecToken()` switch case (SC2's observable); the `unknown-codec` catch-all stays as-is

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — LIB-01, LIB-02 (this phase's letter); Out of Scope table
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 6 goal, 4 success criteria, suggested 2-plan waves, research note (widen-scope + free token change)

### Frozen v1.0 contracts (archived milestone contexts)
- `.planning/workstreams/rocksdb-backup/milestones/v1.0-phases/01-blockstore-contract-memory-backend-conformance-kit/01-CONTEXT.md` — frozen contract D-01..D-16; D-08 is the widening reservation this phase executes; conformance-macro shape
- `.planning/workstreams/rocksdb-backup/milestones/v1.0-phases/03-minio-cpp-integration-s3client-adapter/03-CONTEXT.md` — S3Client seam decisions D-01..D-12 (sync/blocking contract, no HTTP-isms past the seam, result alias)
- `.planning/workstreams/rocksdb-backup/milestones/v1.0-phases/04-s3blockstore-sia-s3d-roundtrip/04-CONTEXT.md` — S3Client.hpp promotion boundary, key-layout decision (display-only codec token), MinioS3Client.hpp deliberately uninstalled

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements; eviction ≠ delete invariants

### Library code being widened
- `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp` — `CidOf` declaration (gains the 3-arg overload) + the mandatory library-local `result<R,S,policy::terminate>` alias
- `thirdparty/sgns-blockstore/src/Cid.cpp` — current sha-256-hardcoded implementation of `CidOf` and the verification hashing
- `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp` — installed seam (gains the `OpenMinioS3Client` declaration); `S3ClientConfig` is the SDK-free config surface
- `thirdparty/sgns-blockstore/src/MinioS3Client.hpp` / `.cpp` — the internal `Open()` precedent the factory wraps; never installed
- `thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp:25`, `src/LocalBlockStore.cpp:37`, `src/S3BlockStore.cpp:30` — the three identical throw-site gates being widened
- `thirdparty/sgns-blockstore/src/S3BlockStore.cpp:43-52` — `CodecToken()` switch (gains `dag-cbor`)
- `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` — the kit; already contains a `MakeBlake2bCid()` helper and the blake2b-rejection tests that flip to roundtrip tests
- `thirdparty/sgns-blockstore/test/memory_block_store_test.cpp`, `local_block_store_test.cpp`, `s3_block_store_test.cpp` — per-backend blake2b rejection tests to re-target
- `thirdparty/sgns-blockstore/cmake/config.cmake.in` — the package config D-07 hardens as forced
- `thirdparty/sgns-blockstore/test/header_hygiene_check.cmake` — the installed-header SDK-type guard SC3 keeps green
- `thirdparty/sgns-blockstore/CMakeLists.txt` — install rules (installed vs src headers)

### Cross-check evidence source
- SuperGenius `sgns::common::getCidOf` — the real CRDT CID producer the D-02 committed cross-check artifact is generated from (dev-run against a SuperGenius build; library must NOT link SuperGenius)

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen on public interfaces
- `.planning/codebase/TESTING.md` — GTest via superbuild; verification-inside-`build/<Platform>/<Config>`-tree rule
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier contract (Tier-1 hermetic fail-closed lane; where D-08's consumer test registers)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BlockStoreConformanceTests.hpp` — the kit already has `MakeBlake2bCid()` and `FaultController` probing; vector tests slot in beside the sha-256 known-vector set (`PutNonSha256HashThrowsInvalidArgument` et al. become roundtrip/rejection-retarget suites)
- `MinioS3Client::Open(S3ClientConfig) -> result<unique_ptr<MinioS3Client>, BlockStatus>` — the exact internal factory the installed free function wraps
- `header_hygiene_check.cmake` + tier-label CI lane (`tier1_audit_check.cmake`) — the guards SC3 keeps green and the lane D-08's consumer test joins
- Guard-test infrastructure for "no SDK types in installed headers" — extends naturally to asserting the factory declaration leaks nothing

### Established Patterns
- Status mapping / gate checks in exactly one place per backend — widening edits three known sites (+ optional consolidation at planner's discretion)
- Library-local `result<R,S,policy::terminate>` alias in every touched header; `.value()` on failure terminates — guard with `has_value()`
- `Open()` → `result<Ptr, BlockStatus>` factory convention — D-05 follows it
- Loud labelled skips for gated tiers; committed evidence artifacts for dev-run proofs (D-02's cross-check artifact follows the `03-04-live-run-evidence.log` precedent)

### Integration Points
- Installed `S3Client.hpp` gains the `OpenMinioS3Client` declaration; `cmake/config.cmake.in` gains only what the SC4 consumer forces
- `Cid.hpp` gains the 3-arg overload (src/Cid.cpp implements both)
- `CodecToken()` switch gains `DAG_CBOR → "dag-cbor"` (display-only; no key-shape change, no parse-back)
- Phase 7 consumes the result: `find_package(sgns-blockstore CONFIG REQUIRED)` in both `CommonBuildParameters.cmake` files relies on the hardened-enough config and the installed factory

</code_context>

<specifics>
## Specific Ideas

- Locked signatures discussed:
  - `CidOf(gsl::span<const uint8_t> bytes, MulticodecType::Code codec, multi::HashType hash)` — overload; 2-arg form unchanged (sha-256)
  - `OpenMinioS3Client(const S3ClientConfig&) -> result<std::shared_ptr<S3Client>, BlockStatus>` — installed free function in `S3Client.hpp`
- Accepted hash set after this phase: exactly `{sha256, blake2b_256}` (`libp2p::multi::HashType` values); everything else still throws `std::invalid_argument` at API entry
- Vector bar: pin independently-derived literals AND commit one `getCidOf` cross-check artifact (dev-run evidence, not a linked test)

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- `2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (area: testing) matched Phase 6 by keywords only (supergenius, cpp); user ruled it unrelated to the blockstore library phase — stays a backlog todo for its own task/phase

</deferred>

---

*Phase: 6-sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory*
