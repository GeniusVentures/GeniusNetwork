# Phase 7: SuperGenius Build Wiring & Config Gate - Context

**Gathered:** 2026-10-23
**Status:** Ready for planning

<domain>
## Phase Boundary

The integration exists and is OFF by default — every subsequent v1.1 phase builds on this foundation. This phase delivers:

1. **INTG-01 — build wiring:** both `CommonBuildParameters.cmake` files (`SuperGenius/build/`, `GeniusSDK/cmake/`) resolve sgns-blockstore from the superbuild install tree via `find_package(sgns-blockstore CONFIG REQUIRED)` (explicit `*_DIR` hints, ordered after the miniocpp dependency chain, outside the libssh2 `PREFER_CONFIG` window — the AsyncIOManager consumption precedent), linking `sgns-blockstore::sgns-blockstore`, gated behind `SGNS_COLD_STORAGE` (default OFF; OFF on iOS/Android until mobile install trees are verified), with dual-RocksDB (9.4/11.1) coexistence proven in one binary on Windows/Linux/macOS
2. **INTG-02 — config gate:** `crdt_config.json` gains a nested `blockstore` section with strict tri-state semantics (absent/blank ⇒ blockstore not constructed, behavior byte-identical to today; present-but-malformed ⇒ loud startup failure, never silent disable); `SGNS_BLOCKSTORE_S3_ACCESS_KEY`/`_SECRET_KEY` env vars take precedence for credentials and are never logged (endpoint/bucket loggable, keys redacted); `ColdStorageOptions` + `LoadCrdtConfig` extension threaded through `GlobalDB::New`
3. **TEST-01 anchor — Tier-1 lane:** hermetic SuperGenius-side tests (InMemoryS3Client fake; config-gate cases first) run under `ctest -L Tier1 --no-tests=error` fail-closed on all platforms — no Docker, no live endpoints — plus `GeniusWallet/assets/crdt_config.json` schema parity
4. **M3 decision recorded:** the cold-journal backup posture is decided and documented (see D-09/D-10) — no journal exists yet (spill lands Phase 8); this phase locks the posture and its documentation only

Out of this phase: any spill/drain behavior (Phase 8), read fallback (Phase 9), durability advancement (Phase 10), GC and M3 tooling (Phase 11), fault-race hardening (Phase 12), mobile legs (Future — option stays OFF), any change to the GlobalDB backup engine itself (out of scope milestone-wide).

Requirements: INTG-01, INTG-02, TEST-01 (anchor).

</domain>

<decisions>
## Implementation Decisions

### Config section shape & naming
- **D-01:** The cold-storage section is a **nested `blockstore` object** in `crdt_config.json` — the backend-agnostic capability name (not `s3d.*`, not flat `blockstore_*` keys). INTG-02's own wording; future knobs (retention in Phase 11, backpressure in Phase 8) nest cleanly under it. Canonical across node config, `GeniusWallet/assets/crdt_config.json`, docs, and the `SGNS_BLOCKSTORE_S3_*` env prefix — **Reversibility:** costly — the section name binds the shipped config schema, the wallet asset, env-var naming, and operator docs; renaming after configs are written in the field is a breaking schema change
- **D-02:** S3 fields sit **directly under `blockstore`** (`endpoint`, `bucket`, `access_key`, `secret_key`; optional `prefix`, `path_style`, `tls`) — no `s3` sub-object. One backend exists in v1.1; simplest parse and simplest wallet-asset parity — **Reversibility:** costly — config field paths bind the node parser, wallet asset, and docs; inserting an `s3` level later is a schema migration

### Tri-state semantics (INTG-02 contract, fully specified)
- **D-03:** **Absent section or all-required-fields-blank ⇒ disabled, byte-identical to today** — no blockstore constructed, no new code paths taken (the SC2 bar)
- **D-04:** **Partially-filled section ⇒ loud startup failure naming the missing field** — any required field filled while another required field is blank/missing signals intent to enable; silently disabling it is exactly the silent-disable failure INTG-02 forbids
- **D-05:** **Unknown keys inside `blockstore` ⇒ loud startup failure naming the key** — catches `"acess_key"`-style typos at startup instead of as confusing auth failures at first drain (Phase 8+); the strict-typo posture follows from malformed=loud
- **D-06:** **Whole-file JSON parse failure keeps the legacy lenient behavior** — warn + defaults for the existing backup keys; the blockstore section is treated as absent ⇒ disabled. The loud contract applies only when the section is inspectable; this preserves byte-identical behavior for existing deployments running corrupt configs — **Reversibility (D-03..D-06):** costly — these semantics are the operator contract proven by the config-gate hermetic tests (SC2/SC3 evidence binds them); loosening any edge after publication breaks the fail-loud guarantee

### Env override surface
- **D-07:** **Credentials only** — exactly two env vars exist: `SGNS_BLOCKSTORE_S3_ACCESS_KEY`, `SGNS_BLOCKSTORE_S3_SECRET_KEY`. Endpoint/bucket/tls/prefix come solely from the config file. Credentials-in-env matches the k8s secret-injection pattern, which is where env overrides earn their keep
- **D-08:** **Env never activates** — env vars override credential *values* but the `blockstore` config section is the only activation switch; a blank/absent section stays disabled regardless of environment. Keeps the SC2 byte-identical bar airtight (a stray exported env var can never change node behavior) and keeps the config-gate test matrix small — **Reversibility:** costly — the blank-config byte-identical claim (SC2) is stated over this rule; adding an env-activation path later invalidates the guarantee for every blank-config deployment

### M3 cold-journal backup posture
- **D-09:** **The cold journal is declared rebuildable** — not backed up. Recovery semantics: re-drain pending uploads as-is first; where a gap exists (journal older than a restored GlobalDB ⇒ blocks never marked for upload ⇒ silent cold-store gap), rebuild from a CID-verified diff of hot-store CIDs vs the S3 remote listing. Relies on the library's idempotent createOnly + CID-verify contracts; S3 is already the system of record for cold data. Zero backup-engine surface (consistent with the milestone-wide out-of-scope boundary on `globaldb.cpp` backup-path changes). The rebuild tooling itself lands in Phase 11 — **Reversibility:** reversible — a documented posture; switching to co-scheduled backup later adds tooling without unwinding anything shipped
- **D-10:** **Documented in the architecture doc** — the M3 decision + rebuild semantics land in `supergenius-sharded-ipld-cache-architecture.md` (ops/runbook section), cited from this CONTEXT so the Phase 11 planner inherits it. No code in Phase 7

### The Agent's Discretion
- Exact CMake mechanics inside the consumption block (hint variable names, ordering details) following the AsyncIOManager precedent at `SuperGenius/build/CommonBuildParameters.cmake:406` / `GeniusSDK/cmake/CommonBuildParameters.cmake:313`
- How `SGNS_COLD_STORAGE` gates compilation (conditional source inclusion vs preprocessor guards) — planner's call
- Where the loud failure surfaces (`GeniusNode` init vs `GlobalDB::New` error propagation) as long as startup fails loudly with a precise message
- `ColdStorageOptions` struct shape and threading mechanics through `GlobalDB::New`
- Test registration mechanics for the SuperGenius Tier-1 lane (target location, `addtest()`, label wiring, tier-audit) per v1.0 patterns
- Exact error-message wording (constraint: must name the missing field / unknown key)
- Wallet-asset parity shape: omit the section entirely vs ship `"blockstore": {}` — both are blank/absent per D-03; planner picks
- Whether `path_style`/`tls` defaults come from `S3ClientConfig` defaults or are set explicitly

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — INTG-01, INTG-02, TEST-01 (this phase's letter); Out of Scope table (backup engine untouched, no new deps, blank-config byte-identical)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 7 goal, 4 success criteria, 3 suggested plan waves, research note (this phase's two planner decisions are now resolved as D-01..D-10)

### Research (v1.1, 2026-10-22)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — "Phase 1" mapping (research numbering) = this phase; P12 build/CI traps; gaps list (config naming, mobile legs, M3 — all now resolved or deferred deliberately)
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — P10 (silent-disable / blank-vs-missing confusion / credentials in logs), P12 (fresh-clone breakage, unlabeled tests), M1 (dual RocksDB MSVC static-link risk), M3 (GlobalDB backup blind to cold dir — the D-09 decision closes this)
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — file:line citations for the consumption patterns and config seam this phase wires

### Code being wired (read before editing)
- `SuperGenius/build/CommonBuildParameters.cmake` — RocksDB block :118-120; libssh2 `PREFER_CONFIG` window :384-404 (new find_package goes OUTSIDE/after it); AsyncIOManager consumption precedent :406-409
- `GeniusSDK/cmake/CommonBuildParameters.cmake` — same trio: :141-144, :291-311, :313-317
- `SuperGenius/src/account/GeniusNode.cpp` — `LoadCrdtConfig` :552-610 (the lenient precedent being extended; note the D-06 boundary: legacy leniency stays for file-level failures)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — `GlobalDB::New` construction seam :322-365 (threading point for `ColdStorageOptions`); backup loop :429-477 (lifecycle pattern reference); backup engine :365-420/:250-282 (M3 context — read-only, no changes)
- `GeniusWallet/assets/crdt_config.json` — wallet asset gaining schema parity (currently flat `backup_*` keys only)
- `thirdparty/build/CommonTargets.cmake` — superbuild rocksdb entry :140-173 and the Phase-6 sgns-blockstore entry (:762+ region) whose install tree this phase consumes

### Library surface being consumed (frozen v1.0 + Phase 6)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp` — installed `OpenMinioS3Client(const S3ClientConfig&)` factory (Phase-6 D-05/D-06: eager validation, zero network I/O at construction) and the SDK-free `S3ClientConfig` that `ColdStorageOptions` maps onto
- `thirdparty/sgns-blockstore/cmake/config.cmake.in` — package config hardened as forced by the Phase-6 consumer proof
- `thirdparty/sgns-blockstore/test/` — the out-of-tree consumer proof project (already demonstrates the consumption shape) and the `InMemoryS3Client` fake the SuperGenius-side hermetic tests reuse
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier contract; the Tier-1 fail-closed lane discipline this phase transplants to the SuperGenius side
- `.planning/workstreams/rocksdb-backup/phases/06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids/06-CONTEXT.md` — immediate predecessor: factory contract, prove-first-harden-as-forced posture, consumer-side find_dependency findings that ride along

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements; gains the M3 ops/runbook section (D-10)

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style for `ColdStorageOptions` and loader code
- `.planning/codebase/STACK.md` — build entry points, superbuild-first ordering, both `CommonBuildParameters.cmake` locations
- `.planning/codebase/TESTING.md` — verification-inside-`build/<Platform>/<Config>`-tree rule; superbuild-then-find_package wiring order; `addtest()` registration

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **AsyncIOManager consumption block** (both `CommonBuildParameters.cmake` files) — the exact pattern SC1 requires: explicit `*_DIR` install-tree hint + `find_package(... CONFIG REQUIRED)`, placed after the libssh2 `PREFER_CONFIG` window
- **Phase-6 out-of-tree consumer proof** (`thirdparty/sgns-blockstore/test/`) — a standalone CMake project already doing `find_package(sgns-blockstore CONFIG REQUIRED)` against the install tree; the Tier-1-registered compile+link+construct precedent
- **Installed `OpenMinioS3Client` + `S3ClientConfig`** — what `ColdStorageOptions` ultimately constructs; eager validation means bad config fails at the factory call, complementing D-04's loader-time loudness
- **`InMemoryS3Client` fake** (library test kit) — the hermetic S3 stand-in for SC4's SuperGenius-side tests
- **`LoadCrdtConfig`** (`GeniusNode.cpp:552`) — the extension point; its `BackupOptions` defaults + member-load pattern is the shape to follow (minus the leniency, per D-04..D-06)
- **v1.0 tier-label + audit discipline** (`tier1_audit_check`-style guards, loud labelled skips) — the SuperGenius-side lane mirrors this machinery

### Established Patterns
- Superbuild-first wiring order: build the thirdparty component, then add `find_package` to `CommonBuildParameters.cmake`, then build SuperGenius (`TESTING.md` verification convention)
- `CMAKE_FIND_PACKAGE_PREFER_CONFIG` window discipline — restore-on-scope-exit; new finds go outside the window
- Phase-6 consumer-side CMake findings ride along: `find_package(httplib CONFIG REQUIRED)` before miniocpp; RocksDB's chain needs `Snappy_DIR` forwarded; hint via `CMAKE_PREFIX_PATH` (never `-D` dotted cache names)
- Fail-closed test lanes: `ctest -L Tier1 --no-tests=error`, tier labels at registration, loud skips for gated tiers

### Integration Points
- Both `CommonBuildParameters.cmake` files gain the gated consumption block (the only CMake edits; `SGNS_COLD_STORAGE` option gate)
- `GeniusNode::LoadCrdtConfig` gains `ColdStorageOptions` parsing (strict for `blockstore`, legacy-lenient at file level) → threaded through `GlobalDB::New`
- `GeniusWallet/assets/crdt_config.json` gains schema parity
- SuperGenius test tree gains the config-gate Tier-1 test target (the lane every later phase lands tests in)

</code_context>

<specifics>
## Specific Ideas

- Locked section shape (blank = disabled):
  ```json
  "blockstore": {
    "endpoint": "",
    "bucket": "",
    "access_key": "",
    "secret_key": "",
    "prefix": "",
    "path_style": true,
    "tls": true
  }
  ```
  (exact optional-field defaults are agent discretion; required set = endpoint, bucket, access_key, secret_key)
- **Derived composition (D-04 + INTG-02 precedence — planner should confirm at plan time):** the required-field check runs *after* env resolution — credentials supplied via `SGNS_BLOCKSTORE_S3_*` satisfy the credential requirement (otherwise the env-credential feature would force secrets into the config file and be a dead letter). Endpoint/bucket must come from config. Not independently user-confirmed; follows necessarily from the locked letters.
- Exactly two env vars exist; neither ever activates (D-07/D-08)
- M3 recovery semantics, in order: re-drain the journal as-is → if divergence suspected, CID-verified rebuild from S3 remote listing (HEAD per object) → re-journal the diff. Tooling = Phase 11.

</specifics>

<deferred>
## Deferred Ideas

- M3 rebuild tooling (rebuild-from-remote-listing command) — Phase 11 (with GC, which is its consumer)
- Mobile superbuild legs (iOS/Android sgns-blockstore install trees) — Future requirement; `SGNS_COLD_STORAGE` stays OFF on mobile until verified
- Full env-override surface (endpoint/bucket via env) and env-only activation — explicitly **rejected** in D-07/D-08, not deferred; revisit only with a concrete container-deployment requirement
- Metrics surface for the gate (config-load telemetry) — the milestone's Future metrics list

### Reviewed Todos (not folded)
- `2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (area: testing) matched Phase 7 by keywords only (supergenius, cpp); user ruled it unrelated to the blockstore workstream in Phase 6's discussion — stays a backlog todo for its own task/phase

</deferred>

---

*Phase: 7-SuperGenius Build Wiring & Config Gate*
