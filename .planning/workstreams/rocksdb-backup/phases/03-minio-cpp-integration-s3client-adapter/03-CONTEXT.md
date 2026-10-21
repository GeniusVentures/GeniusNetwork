# Phase 3: minio-cpp Integration & S3Client Adapter - Context

**Gathered:** 2026-10-21
**Status:** Ready for planning

<domain>
## Phase Boundary

S3 client **capability** — not an S3 `BlockStore` — lands behind an internal adapter. This phase delivers:

1. minio-cpp v1.0.0 (pinned upstream tag, submodule) built through the thirdparty superbuild on all five platform builds via `CommonTargets.cmake`, using **minio-cpp's own dependency mechanism (`miniocpp-deps.cmake`) as-is** to fetch/build pugixml/cpp-httplib/inih inside the ExternalProject step — statically linked, non-exported
2. The internal `S3Client` adapter interface (~5 ops: put/get/head/delete + config) — internal headers in Phase 3, NOT installed (promoted with Phase 4's `S3BlockStore`)
3. `MinioS3Client` (minio-cpp-backed) mapping every failure to the Phase-1 status taxonomy in exactly one place — unknown → `Unknown`/`TemporarilyUnavailable`, never `NotFound`
4. `InMemoryS3Client` fake: stateful, precondition-enforcing, per-op fault-scriptable — drives hermetic adapter tests (SC3) and seeds Phase 5's fault matrix
5. The env-gated MinIO-binary child-process test harness (SC4's live-endpoint proof) — landed THIS phase; Phase 4 reuses it for `S3BlockStore`
6. Day-one entrance-criterion spike: conditional `If-None-Match:*` exposure + BaseUrl config fields + TLS on/off smoke at the pinned tag

Out of this phase: `S3BlockStore` and key layout (Phase 4), MinIO tests for the store tier (Phase 4 instantiates the harness), s3d anything (Phase 4), fault matrix execution (Phase 5), consumer wiring in `CommonBuildParameters.cmake`.

Requirements: BUILD-02, BUILD-03, BACK-05, BACK-06.

</domain>

<decisions>
## Implementation Decisions

### Adapter contract
- **D-01:** Conditional create-only Put is a **precondition option on `Put`** (options carry `createOnly=true`; adapter sends `If-None-Match:*`; Phase 4 just flips the flag) — one Put op, no HTTP-isms past the seam, no separate `PutIfAbsent` op, no raw-header bag — **Reversibility:** costly — the internal op-set shape binds the fake, `MinioS3Client`, and Phase-4 `S3BlockStore` call sites simultaneously
- **D-02:** "Object already exists" (412 / precondition failed) reports through the **success slot with `alreadyPresent=true`** — mirrors frozen Phase-1 D-04 `PutOutcome { achieved, alreadyPresent }`; Phase-4 SC2 (412 → AlreadyExists-as-success) maps 1:1 with zero re-freeze; no dedicated failure class, no raw passthrough codes — **Reversibility:** costly — Phase-4 mapping and conformance assertions bind to the payload shape
- **D-03:** `delete` stays an **internal adapter op** (BACK-05 names it; future tooling/audit consumers) — proven via fake tests; guard tests keep `BlockStore` itself delete-free; delete never climbs to the public interface — **Reversibility:** costly — guard tests + tooling surface bind the placement
- **D-04:** The `S3Client` interface is **internal in Phase 3** (src/, not installed); promoted to installed headers with Phase 4's `S3BlockStore`, its first public consumer — installed surface stays minimal per phase — **Reversibility:** reversible — promotion in Phase 4 is additive

### Fake fidelity
- **D-05:** `InMemoryS3Client` = **stateful object map + `createOnly` enforcement + injectable per-op fault responses** (FaultController-style: next-op returns scripted 5xx/garbage/truncated/refused) — covers SC3 (200/404/error) now and is the Phase-5 fault-matrix seed — **Reversibility:** costly — Phase-5 matrix composes on the scripting surface; retrofitting a minimal fake later rewrites fixtures

### SC4 live-endpoint proof
- **D-06:** The **MinIO-binary child-process harness lands in Phase 3** (C2 decision: server binary, no Docker) — env-gated, satisfying SC4 fully in-phase; Phase 4 instantiates the same harness for `S3BlockStore` instead of building one — **Reversibility:** costly — Phase 4's test tier binds to the harness shape
- **D-07:** MinIO-binary tests are **opt-in only** (env-gated), never the default CI lane; **loud labelled skip** when the gate is unset — TEST-01 Tier-2 discipline from day one — **Reversibility:** costly — Phase-5 SC3 inspects this configuration
- **D-08:** The "maps every failure" half of SC4 is proven by a **loopback stub server** (raw HTTP) serving scripted 5xx/garbage/truncated/connection-refused directly at `MinioS3Client` — deterministic taxonomy assertions with no sticky negative cache; the stub becomes Phase 5's fault-matrix seed — **Reversibility:** reversible
- **D-09:** The harness locates MinIO via an **env var pointing at a pre-installed binary**; loud skip when unset; **no auto-download** — zero network at test time — **Reversibility:** reversible

### Entrance criterion
- **D-10:** **No pre-committed contingency** for `If-None-Match:*` unavailability — research rates failure probability LOW (README-verified feature; headers never compiled against; hosted doxygen stale). If a needed feature is genuinely missing, decide then — **forking minio-cpp to add it is acceptable at that point**; BUILD-02's "no fork" is the default integration mechanism, not a never-fork pledge
- **D-11:** Entrance criterion verified as a **day-one spike inside the first Phase-3 plan** (Phase-1 C1 discipline), covering the **full trio**: conditional-header exposure + BaseUrl config fields (path-style/HTTPS/region) + TLS on/off smoke against a local endpoint — **Reversibility:** reversible — spike scope adjustable in planning

### Dependency bundling
- **D-12:** **minio-cpp's own dependency mechanism (`miniocpp-deps.cmake`) is used as-is** inside the ExternalProject step — it fetches/builds pugixml v1.16 / cpp-httplib v0.62.0 / inih r62 with upstream's own pins. **No GNUS fetch script, no separate pin file, no injected inih CMakeLists, no pre-committed hermeticity patch** — matches BUILD-02's primary formulation ("its own dependency mechanism... pinning enforced per its mechanism"). If upstream's mechanism hits a concrete wall (e.g., inih meson-only build on MSVC), surface it via research/day-one spike and handle then — **Reversibility:** reversible — integration mechanics stay adjustable until phase close. **NOTE for downstream agents:** research SUMMARY `:139`/`:195` recommends GNUS forks of inih and minio-cpp (hermeticity patch) — that recommendation is **superseded by this decision**; do not pre-create forks

### the agent's Discretion
- `S3ClientConfig` field set beyond the research-listed surface (endpoint, path-style=true, pinned region, https, tls-verify)
- Adapter result-type mechanics, provided they use the library-local `result<R,S,policy::terminate>` alias (Cid.hpp) and leak no SDK types
- Loopback stub implementation approach (raw sockets vs in-tree cpp-httplib server side)
- Harness env-var names, child-process lifecycle, port/temp-dir management
- `MinioS3Client` threading/execution model (sync blocking calls mirror the frozen BlockStore style)
- Per-platform CI evidence details for SC1 (which lanes run where)
- Any minimal patch to minio-cpp should upstream's mechanism concretely break — minimal-diff norm, decide-as-needed (user posture), documented wherever the shaderc precedent documents its patch

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements; adapter-seam rationale and eviction ≠ delete invariants

### Workstream planning
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — BUILD-02/BUILD-03/BACK-05/BACK-06 (this phase); Out of Scope table (no vcpkg, no Docker CI)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 3 goal, 4 success criteria, research note (entrance criteria)
- `.planning/workstreams/rocksdb-backup/phases/01-blockstore-contract-memory-backend-conformance-kit/01-CONTEXT.md` — frozen contract D-01..D-16 (taxonomy, `PutOutcome.alreadyPresent`, guard tests, conformance macro)
- `.planning/workstreams/rocksdb-backup/phases/02-localblockstore-rocksdb-cold-tier/02-CONTEXT.md` — FaultController crash-seam pattern, pimpl + superbuild wiring precedent

### Research (2026-10-19)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-19.md` — Phase 3 section (`:137-142`), critical version facts (`:38`: miniocpp-deps.cmake clone-fallback behavior), minor notes (`:117`: entrance criterion rationale). Read WITH D-12's supersession note above
- `.planning/research/STACK-rocksdb-backup-2026-10-19.md` — minio-cpp v1.0.0 / cpp-httplib v0.62.0 / pugixml v1.16 / inih r62 version facts; MINIO_CPP_ENABLE_RDMA=OFF
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-19.md` — pitfall 2 (transport-as-NotFound), 3 (ETag never a proof), config-surface notes (path-style, pinned region, plain-HTTP loopback, never verify TLS against s3d self-signed)
- `.planning/research/ARCHITECTURE-rocksdb-backup-2026-10-19.md` — adapter rationale, minio-cpp-over-aws-sdk-cpp comparison

### Phase-1/2 codebase (the foundation being extended)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp`, `BlockStatus.hpp`, `Options.hpp`, `Capabilities.hpp`, `Durability.hpp` — frozen public contract the adapter maps INTO
- `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp` — library-local `result<R,S,policy::terminate>` alias MANDATORY in any new header (Phase-1 landmine)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp` — seam pattern D-05's fake scripting mirrors
- `thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp` — status-mapping-in-one-place precedent
- `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` — hermetic test style (adapter tests mirror, not instantiate, the kit)

### Build integration
- `thirdparty/build/CommonTargets.cmake` — sgns-blockstore entry (gains minio linkage for `MinioS3Client`); shaderc `PATCH_COMMAND` precedent (`~:438`); `ExternalProject_Add` + `DEPENDS` + `BUILD_BYPRODUCTS` norms; Python3 already required
- `Coding Standards.md` (workspace root) — C++ style: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen on public interfaces

### Testing conventions
- `.planning/codebase/TESTING.md` — GTest via superbuild; verification-inside-`build/<Platform>/<Config>`-tree rule

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Frozen Phase-1 headers — the taxonomy/types the adapter maps into; `PutOutcome { achieved, alreadyPresent }` is the exact shape D-02 mirrors
- `FaultController` seam — D-05's per-op fault scripting copies this proven pattern
- Superbuild orchestration — `ExternalProject_Add` entries with `_CMAKE_COMMON_CACHE_ARGS`, `BUILD_BYPRODUCTS`, `DEPENDS`; Python3 interpreter already found for shaderc's patch step
- libp2p/outcome result envelope — the `policy::terminate` alias landmine is documented and guard-tested

### Established Patterns
- Status mapping in exactly one place per backend (`MemoryBlockStore`, `LocalBlockStore` precedents) — `MinioS3Client` follows
- Loud labelled skips for gated tests (Phase-1 D-10 kit pattern) — D-07/D-9 reuse
- pimpl + `find_package(<Name> CONFIG)` + superbuild `DEPENDS` (Phase-2 wiring) — minio-cpp entry mirrors

### Integration Points
- `thirdparty/build/CommonTargets.cmake` — new `ExternalProject_Add(minio-cpp ...)` entry; sgns-blockstore entry gains the minio dependency so `MinioS3Client` links
- Installed-header guard test (Phase 1) — extends to assert no minio-cpp type in any installed header (SC2)
- Phase-4 seam: the adapter interface + fake + harness are exactly what `S3BlockStore` composes over

### Landmines (verified in Phases 1–2)
- `policy::terminate` alias mandatory — `.value()` on failure terminates; guard with `has_value()`
- Never `OUTCOME_TRY` a `CidOf` failure into a `BlockStatus` envelope — map explicitly
- Hosted minio-cpp doxygen is stale (pre-1.0 `minio::http::` API) — code against the pinned tag's README/examples only
- `miniocpp-deps.cmake` falls back to configure-time `git clone` — accepted by D-12 (upstream mechanism as-is), but the researcher should confirm pin behavior during the spike
- Windows: MSVC debug crashes building `std::vector` from gsl::span iterator temporaries — use string iterators in tests

</code_context>

<specifics>
## Specific Ideas

- Put semantic sketch: `PutObject(key, data, PutObjectOptions{ createOnly = true })` → success-slot result carries `alreadyPresent=true` when the precondition fails (412) — the fake enforces this statefully, `MinioS3Client` maps the real 412
- Harness discipline: env-gated MinIO server child process (binary located via env var), per-test temp dirs, loud skip when unset; never `play.min.io`, never live internet
- Loopback stub serves the Phase-5 matrix preview: connection-refused, 5xx, truncated bodies, garbage responses → each asserts its taxonomy class, and a subsequent good fetch succeeds (no sticky negative cache)
- TLS posture: plain-HTTP loopback for tests; `tls_verify` toggle in config; never verify TLS against s3d's per-start self-signed cert (Phase-4 note carried from research)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched Phase 3 on generic keywords only ("capability, path, cpp"); unrelated to the BlockStore library; same disposition as Phase 1; stays with base SuperGenius planning

</deferred>

---

*Phase: 3-minio-cpp Integration & S3Client Adapter*
*Context gathered: 2026-10-21*
