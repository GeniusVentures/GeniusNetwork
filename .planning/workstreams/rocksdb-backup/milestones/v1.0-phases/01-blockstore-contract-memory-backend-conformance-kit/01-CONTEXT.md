# Phase 1: BlockStore Contract, Memory Backend & Conformance Kit - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning

<domain>
## Phase Boundary

The `sgns-blockstore` library exists as a buildable/installable thirdparty target whose public contract is frozen and proven before any real backend exists. This phase delivers:

1. The frozen type system: `BlockStatus` taxonomy (`Found`/`NotFound`/`TemporarilyUnavailable`/`Corrupt`/`Unauthorized`), 4-value `DurabilityLevel` (incl. `PeerReplicated` placeholder), `PutOutcome`, `ReadOptions`/`WriteOptions`, `BlockStoreCapabilities`
2. The `BlockStore` interface (`Put`/`Get`/`Has`/`GetSize` + `PutMany`) — List-free, delete-free, eviction-safe
3. `MemoryBlockStore` hermetic reference backend
4. The reusable `BlockStoreConformanceTests` kit (header-only, one-macro instantiation, fault-seam standardized)
5. The C1 CID-dependency spike (day-one, full 3-part acceptance bar) + public `CidOf` helper
6. BUILD-01: new thirdparty submodule, CMake static-library target, installed public headers, `CommonTargets.cmake` orchestration entry

Out of this phase: any real persistent backend (Phase 2), minio-cpp (Phase 3), S3 (Phase 4), fault matrix execution (Phase 5), consumer wiring in `CommonBuildParameters.cmake`.

</domain>

<decisions>
## Implementation Decisions

### Result-type mechanics
- **D-01:** All public ops carry results via the outcome envelope: `outcome::result<T, BlockStatus>` — the repo-wide convention; since C1 likely lands on `p2p_cid`, outcome ships with libp2p anyway, costing consumers nothing extra — **Reversibility:** one-way — this is the published v1.0.0 contract every header, conformance assertion, and consumer call site rides on; the phase exists to freeze it
- **D-02:** `BlockStatus` is a rich struct, not a bare enum: `{ StatusClass code; BlockSource source; std::string message; }` riding the outcome failure slot — source attribution (success criterion 3) is first-class and assertable by the conformance kit — **Reversibility:** one-way — published API shape; the conformance kit and Phase-5 fault matrix assert against it
- **D-03:** An authoritative miss is a failure value: `Get -> result<Block, BlockStatus>` with `code == NotFound` (the `EXPECT_OUTCOME_FALSE`-style pattern); one uniform pattern for all five classes, no `optional`-in-success second pattern — **Reversibility:** one-way — encoded in the kit's assertions and every consumer's miss handling
- **D-04:** `Put -> result<PutOutcome, BlockStatus>` where `PutOutcome { DurabilityLevel achieved; bool alreadyPresent; }` — Phase 4's conditional-put `412 -> AlreadyExists-as-success` just sets `alreadyPresent = true`; nothing re-frozen later; carries the "never return a DurabilityLevel not verified" invariant — **Reversibility:** one-way — Phase 4 semantics bind to this payload

### CID type surface
- **D-05:** The CID type is a direct alias: `using Cid = libp2p::multi::ContentIdentifier;` in the public header; the library links `p2p_cid` and re-exports it in its CMake package config — one CID definition everywhere, zero conversion friction for SuperGenius CRDT call sites — **Reversibility:** costly — swapping the alias for a wrapper later touches every header and consumer; if the C1 spike fails, the alias still holds but points at the ipfs-lite-cpp granular `cid` target instead
- **D-06:** The C1 spike must pass a full 3-part bar before `p2p_cid` is adopted: (1) CIDv0 + CIDv1 round-trip bytes<->string using only `p2p_cid`, (2) `CidOf(bytes, codec)` verified against known vectors, (3) a standalone consumer TU includes every public header and links only `p2p_cid` — no ipfs-lite-cpp, no fmt/soralog/c-ares dragged in. Fallback on failure: ipfs-lite-cpp granular `cid` target — **Reversibility:** reversible — spike criterion only, cheap to adjust during Phase 1
- **D-07:** `sgns::blockstore::CidOf(bytes, codec)` ships as a public installed helper — future consumers (SuperGenius-side adapter, genius-tube) need exactly one verified CID constructor instead of hand-rolling multihash encoding — **Reversibility:** costly — removing a published helper is an API break
- **D-08:** v1 accepts any codec but restricts hashing to sha-256 multihash (what this repo's CRDT/IPLD pipeline produces); any other hash code is rejected at API entry as an invalid argument (programmer error) — the frozen 5-value runtime taxonomy stays untouched — **Reversibility:** reversible — widening to more hash functions later is additive

### Conformance kit shape
- **D-09:** The kit is a header-only template suite instantiated by one macro: `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(SuiteName, factory)` (S5 `StoreTests` style) — compiles into each backend's test binary, no extra CMake wiring, literally one step — **Reversibility:** costly — every backend's test TU binds to the macro and factory shape
- **D-10:** The kit defines the fault-injection seam NOW: an optional `FaultController` interface the kit probes for; backends implementing it get fault conformance tests (induced failure -> correct taxonomy class, no sticky negative cache) for free; backends without it get loud labelled skips — retrofitting suite shape in Phase 5 is what the research warns against — **Reversibility:** costly — kit shape plus every backend that implements the controller
- **D-11:** Suite bodies assert with plain GTest (`EXPECT_TRUE` + manual extraction) — zero macro surface; kit depends on GTest + outcome only — **Reversibility:** reversible — internal to the kit
- **D-12:** The conformance kit is build-time only (built with `TESTING=ON` inside the repo, not installed/exported) — all v1 backends live in this repo; revisit if an external consumer needs to run conformance against a wrapper — **Reversibility:** reversible — install/export can be added later without breaking anyone

### v1 contract breadth
- **D-13:** Full P1 freeze: `Put`/`Get`/`Has`/`GetSize` + `PutMany` (naive impl) + `ReadOptions`/`WriteOptions` + `BlockStoreCapabilities` + 4-value `DurabilityLevel` all land in v1.0.0 — later phases implement behind the frozen header set; no signature changes ever — **Reversibility:** one-way — the published v1.0.0 header set is this phase's core deliverable
- **D-14:** `PutMany` returns per-block outcome vectors with explicitly NO all-or-nothing guarantee (a failed item never rolls back siblings) — the naive loop implementation is conformant; the future S3 backend streams without faking atomicity — **Reversibility:** one-way — the no-atomicity promise is a documented contract consumers rely on
- **D-15:** `ReadOptions { std::chrono::steady_clock::time_point deadline; bool verify = true; }` and `WriteOptions { deadline }` — deadline plus the CORE-04 verify toggle, nothing speculative; Memory backend ignores deadlines (never blocks), backends that can honor them do — **Reversibility:** costly — adding fields to exported structs later is an ABI break
- **D-16:** `EvictLocal(cid)` is a concrete method on backend types (`MemoryBlockStore` now, `LocalBlockStore` in Phase 2) — NEVER on the `BlockStore` interface. The guard test asserts both: the interface exposes no delete-shaped method, and `EvictLocal` exists only on backend types (cannot touch remote) — **Reversibility:** costly — guard test, backend types, and Phase-5 test levers bind this placement

### the agent's Discretion
- Exact `StatusClass`/`BlockSource` enum member naming and header file layout (`Block.hpp`, `BlockStatus.hpp`, `BlockStore.hpp`, etc. — research's proposed set is guidance, not law)
- Guard-test mechanics (compile-time checks vs CI grep) for "no delete-shaped method" and "no SDK types in headers" — as long as both criteria are provably enforced
- `MemoryBlockStore` internals (map type, locking) — thread-safety contract choice belongs to planning, but v1 need not promise more than single-threaded use unless planning finds a reason
- `BlockStoreCapabilities` field set beyond max-`DurabilityLevel` reporting
- Repo bootstrap details inside the AsyncIOManager precedent (test dir layout, `test/conformance/` target shape)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements (its Phases 1+2 vertical slice only); defines the eviction≠delete invariants and the three "eviction does NOT mean" statements the header docs must restate

### Workstream planning
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — 21 mapped requirements; Phase 1 = CORE-01..06, BACK-01, BACK-02, BUILD-01
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 1 goal, success criteria (5), and the C1/C3/C4 research notes

### Research (2026-10-19)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-19.md` — conflicts C1–C5 with recommendations; Phase-1 deliverables list; pitfall mitigations
- `.planning/research/ARCHITECTURE-rocksdb-backup-2026-10-19.md` — component layout, dependency-direction enforcement, S5 patterns to borrow
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-19.md` — pitfalls 2/5/6/11 are Phase-1-tagged (taxonomy-first, API-shape freeze, no-List, config schema)
- `.planning/research/STACK-rocksdb-backup-2026-10-19.md` — the C1 p2p_cid position and dependency facts

### Build integration
- `thirdparty/AGENTS.md` — submodule + `ExternalProject_Add` conventions for new thirdparty components
- `thirdparty/build/CommonTargets.cmake` — the orchestration file this phase extends; AsyncIOManager precedent (~`:741-776`) for the new entry; shaderc `PATCH_COMMAND` precedent (~`:438`) for pinned-dependency patch steps
- `thirdparty/AsyncIOManager/` — the repo-bootstrap precedent (CMakeLists + cmake config + install/export shape) the new library mirrors
- `Coding Standards.md` (workspace root) — C++ style: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen on public interfaces

### Testing conventions
- `.planning/codebase/TESTING.md` — GTest ~1.14 via superbuild, `test/testutil` patterns, verification-inside-`build/<Platform>/<Config>`-tree rule

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `outcome` (vendored thirdparty, libp2p family) — the result envelope D-01 builds on; already built by the superbuild
- GTest superbuild target (`thirdparty/GTest`, ~1.14.0) — the conformance kit's only test dependency (D-11)
- libp2p `p2p_cid` target — the preferred CID dependency (D-05/D-06); outcome ships alongside it
- `thirdparty/AsyncIOManager` CMake structure — copy this shape for the new library repo (static lib, install, export `lib/cmake/sgns-blockstore/`)

### Established Patterns
- `ExternalProject_Add` + `DEPENDS` + `BUILD_BYPRODUCTS` in `CommonTargets.cmake` — required for ninja one-pass determinism (repo-documented landmine)
- `outcome::result<T, E>` return convention with test macros — the library follows the convention; the kit uses plain GTest (D-11)
- `sgns::` namespace, PascalCase headers, Doxygen `@brief`/`@param` on public interfaces — per `Coding Standards.md`

### Integration Points
- `thirdparty/build/CommonTargets.cmake` — new `ExternalProject_Add(sgns-blockstore ...)` entry + `.gitmodules` row (BUILD-01; from day one)
- CMake package config install (`lib/cmake/sgns-blockstore/`) — the seam both SuperGenius and genius-tube will `find_package` later; consumer wiring in `CommonBuildParameters.cmake` is deliberately NOT this milestone
- `ipfs_lite/ipfs/*` includes are permanently banned from the library — CI-greppable

</code_context>

<specifics>
## Specific Ideas

- Exact result signatures discussed and locked:
  - `Get(cid) -> outcome::result<Block, BlockStatus>` (miss = failure, `code == NotFound`)
  - `Put(cid, bytes, opts) -> outcome::result<PutOutcome, BlockStatus>` with `PutOutcome { DurabilityLevel achieved; bool alreadyPresent; }`
  - `ReadOptions { std::chrono::steady_clock::time_point deadline; bool verify = true; }`, `WriteOptions { deadline }`
- Instantiation macro name agreed: `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(SuiteName, factory)`
- Spike acceptance bar is exactly three parts (round-trip v0+v1, `CidOf` vs known vectors, standalone TU linking only `p2p_cid`) — the spike is the Phase-1 entrance criterion

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched Phase 1 on generic keywords only ("supergenius, cpp"); unrelated to the BlockStore library; stays with the base SuperGenius project planning

</deferred>

---

*Phase: 1-BlockStore Contract, Memory Backend & Conformance Kit*
