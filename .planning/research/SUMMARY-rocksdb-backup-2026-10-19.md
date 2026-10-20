# Project Research Summary

**Project:** `sgns-blockstore` — CID-native cold-storage block library (rocksdb-backup workstream, milestone v1.0)
**Domain:** C++17 static library, new `thirdparty/` submodule — BlockStore abstraction + Memory/RocksDB/S3 backends + CID verification
**Researched:** 2026-10-19
**Confidence:** HIGH overall (per-area assessment below; three open verification items carried to planning)

**Scope guard (from milestone context):** vertical slice of `supergenius-sharded-ipld-cache-architecture.md` Phases 1+2 ONLY. No tiered retrieval, no path sharding, no eviction, no CARv2, no PeerBlockStore. SuperGenius consumption (the `IpfsDatastore` seam) is a LATER milestone. The library builds standalone in thirdparty/ with zero SuperGenius headers, consumable identically by SuperGenius/GeniusSDK and genius-tube.

---

## Executive Summary

Every mature content-addressed store in the reference ecosystem — boxo/kubo's Blockstore, S5's `Store`/`BlobStore` split, IPFS Cluster's state export/import, Sia s3d — converges on the same small core: `Put`/`Get`/`Has`/`GetSize` over content-addressed keys, hash verification centralized in one facade layer, decorator-based composition for anything tiered, and a conformance test kit instantiated against every backend. The milestone delivers exactly that shape as `sgns-blockstore`: a synchronous, outcome-based `BlockStore` interface; `MemoryBlockStore`; `LocalBlockStore` over RocksDB (its own instance/directory); and `S3BlockStore` speaking to Sia s3d (or any S3-compatible endpoint) through an internal `S3Client` adapter implemented on minio-cpp v1.0.0. CID verification happens at the library boundary on every Put and (default-on) every Get — closing the exact gap the existing stack carries today (`RocksdbDatastore`'s FIL-117 no-verification TODO).

The recommended approach leans on what the repo already owns. RocksDB arrives consumer-provided via `find_package(RocksDB CONFIG)` (stable 9.x–11.x API only; genius-tube pins 11.1.2, this workspace has 9.4.0 — dual-compatible surface is cheap for this slice). The CID type comes from the existing libp2p/ipfs-lite-cpp family (one genuine conflict on which — see Cross-Document Analysis). The only new thirdparty surface is minio-cpp v1.0.0 plus three tiny dependencies (pugixml v1.16, cpp-httplib v0.62.0, inih r62; OpenSSL/zlib/nlohmann-json are already vendored). minio-cpp wins decisively over aws-sdk-cpp for this slice: C++17 floor, active maintenance, no libcurl, first-class static builds, and a 4-call surface behind our adapter. Construction order matters more than technology choice: interface + error taxonomy + conformance kit first, then the pure-local backend, then the SDK adapter with a fake client, then the S3 backend and s3d roundtrip, then fault/crash-injection hardening with measurement evidence.

The dominant risks are semantic, not technological. **(1)** s3d's 200-OK on PUT means *staged on local disk*, not durable on Sia — GET succeeds from staging, so naive roundtrip tests prove nothing; the `DurabilityLevel` enum and honest `ObjectStoreAccepted` semantics must be frozen into the Phase-1 type system, with durability-signal discovery pinned as a task in the s3d phase and crash/staging-loss tests at the end. **(2)** Transport failure flattened into `NotFound` is the CRDT-corruption trap the architecture doc forbids — the error taxonomy must exist before any backend. **(3)** The thirdparty superbuild has repo-documented landmines (wrapper-vcxproj no-op builds, MSBuild incremental-link staleness, W:-drive disk pressure, ninja byproducts) — all have established guards. **(4)** Two genuine research conflicts (CID dependency choice; CI S3 endpoint mechanism) plus two interface-shape disagreements (`Remove` in v1? `List` on the interface?) are surfaced below with opinions — the roadmapper should convert each into an explicit Phase-1/Phase-3 entrance criterion rather than papering over them.

---

## Key Findings

### Recommended Stack

(from STACK.md — versions verified against upstream 2026-10-19; integration details verified against this workspace's `thirdparty/build/` sources)

The stack is deliberately boring: one new GNUS-authored static lib modeled on `AsyncIOManager`, one new external SDK behind an adapter, three tiny transitive deps, and everything else reused from the existing superbuild. No package managers — submodules + `ExternalProject_Add` per `thirdparty/AGENTS.md`, with `BUILD_BYPRODUCTS`/`DEPENDS` wired for ninja one-pass determinism.

**Core technologies:**
- **`sgns-blockstore` v0.1.0 (new GeniusVentures repo)** — the library itself; AsyncIOManager-style CMakeLists, installs `lib/cmake/sgns-blockstore/` export so SuperGenius and genius-tube consume it identically.
- **minio/minio-cpp v1.0.0** (2026-09-09) — S3 client behind the internal `S3Client` adapter. Apache-2.0 (keep `MINIO_CPP_ENABLE_RDMA=OFF`), C++17 floor, active (MinIO-founder-led, 4 releases Aug–Sep 2026), dependency set changed in v0.7.0 from curl/curlpp to **cpp-httplib** — the genuinely new deps are only pugixml/cpp-httplib/inih.
- **pugixml v1.16 / cpp-httplib v0.62.0 / inih r62** — minio-cpp's deps; inih needs a GNUS fork adding a CMakeLists (upstream is meson-only).
- **RocksDB (consumer-provided, min 9.4.0)** — `LocalBlockStore` opens its OWN instance/directory; never bundle, never share the CRDT/GlobalDB handle.
- **CID type from the libp2p family** — see Conflict C1; both candidate resolutions agree the library must never include `ipfs_lite/ipfs/*` (datastore/merkledag/graphsync).
- **Test endpoints:** pinned `minio/minio:RELEASE.2025-10-15T17-29-55Z` image for dev; **Sia s3d v0.2.1 is manual/gated acceptance only** (needs Sia account + indexer registration + real uploads — not hermetic, never CI).

**Critical version facts:** minio-cpp ≥ v0.53.1 of cpp-httplib (pin v0.62.0); minio-cpp's deps file (`miniocpp-deps.cmake` inside its cmake directory) falls back to configure-time `git clone` and hard-errors on missing pugixml — the GNUS fork must pre-accept config packages and turn the clone fallback into a hard error (hermeticity patch, defense-in-depth). Hosted doxygen for minio-cpp is stale (pre-1.0 `minio::http::` API) — code against the pinned tag's README/examples only.

### Expected Features

(from FEATURES.md — evidence from boxo, S5 s5-rs, IPFS Cluster, s3d, AWS docs; core op set cross-verified across ≥3 independent systems)

**Must have (table stakes, all P1 for this slice):**
- `Put(CID, bytes)` with verify-before-accept; `Get` returning structured `BlockStatus` (Found/NotFound/TemporarilyUnavailable/Corrupt/Unauthorized) — never a bare error code
- `Has` (HeadObject-backed), `GetSize`, `PutMany` (API shape now, naive impl)
- CID verification on every read, default ON, toggleable — a cold-storage *trust* library
- **Structured error taxonomy** — authoritative-NotFound vs transport failure vs corruption; the single most important correctness feature
- Memory backend (deterministic hermetic tests); RocksDB local backend (LocalCommitted tier)
- Codec-preserving versioned key layout (`v1/blocks/<codec-prefix>/<cid>`) — trivially cheap now, brutal to retrofit (boxo's multihash-only keying is a documented regret: enumeration loses the codec)
- Conditional create-only puts (`If-None-Match:*`; 412 → AlreadyExists-as-success) — cross-verified AWS + s3d ("evaluated atomically with the write")
- `DurabilityLevel` type surface now (Phase-5 eviction consumes it later; retrofit = API break)
- Restore-to-local helper (Get + verify + local Put) — proven by the acceptance E2E: fresh instance retrieves from s3d and verifies
- Shared backend conformance-suite contract + one live s3d/MinIO integration tier
- Deadlines/cancellation in `ReadOptions`/`WriteOptions`; internal `S3Client` adapter with zero SDK type leakage

**Should have (differentiators):** `VerifyAll`/audit scrub (v1.x — cheap composition of list+verify), s3d staged-vs-durable diagnostics surfacing, additive coexistence with the existing RocksDB `BackupEngine` path (separate dirs/prefixes + explicit compatibility test), metrics hook points at the interface layer.

**Defer (v2+, mapped to doc Phases 3–6):** TieredBlockStore/PeerBlockStore (P3), path sharding/rendezvous ownership (P4), eviction policy (P5), CARv2 packing (P6 — s3d already bin-packs small objects into 4 MiB slabs; measure first), CRDT-history GC (needs causal-stability spec), mutable path→CID registry (SuperGenius CRDT already owns path state), negative caching, generic KV passthrough (destroys the content-addressed invariant).

### Architecture Approach

(from ARCHITECTURE.md — SuperGenius/thirdparty facts read directly from source; S5 patterns from s5-rs main)

Standalone library in thirdparty/, consumed later by SuperGenius through a **SuperGenius-side adapter** (`BlockStoreBackedIpfsDatastore : public IpfsDatastore`, wired at `globaldb.cpp:322-344`, mirror-mode first) — the dependency direction is enforced structurally by build order: thirdparty builds first, so a SuperGenius include from sgns-blockstore cannot even link. `LocalBlockStore` must NOT wrap `IpfsDatastore`/`RocksdbDatastore` (inherits sync-only/no-status/no-verification ceiling; couples to GlobalDB's backup/restore/abort lifecycle; drags ipfs-lite machinery into genius-tube) — it owns its own RocksDB instance with byte-compatible `cid.toBytes()` keys (future migration aid only). MinIO SDK types never leak past the library's internal sources directory. S5 patterns to borrow: capability struct (`BlockStoreCapabilities` — where s3d staging semantics get expressed later), decorator composition (tiering = just another BlockStore), conformance kit per backend, verification in the facade not per-backend, atomic temp-write+rename, HEAD→exists mapping with 200/404→bool and everything else→TemporarilyUnavailable.

**Major components:**
1. **Public interface layer** — `Block.hpp`, `BlockStatus.hpp`, `BlockResult.hpp`, `Options.hpp`, `BlockStore.hpp`, `Capabilities.hpp` (installed headers; CID/bytes/strings only)
2. **Backends** — `MemoryBlockStore` (hermetic reference), `LocalBlockStore` (own RocksDB, atomic writes, upload journal), `S3BlockStore` (`v1/blocks/` layout, conditional PUT)
3. **Internal S3 adapter** (under the library's internal sources, e.g. `S3Client.hpp` there) — 4–5 op adapter interface; `MinioS3Client` impl + `InMemoryS3Client` fake
4. **`test/conformance/`** — the reusable `BlockStoreConformanceTests` target (S5 `StoreTests` analog) + `test/fakes/`
5. **Orchestration** — `CommonTargets.cmake` `ExternalProject_Add` entries + `.gitmodules` (AsyncIOManager precedent `:741-776`); consumer wiring (`CommonBuildParameters.cmake`) deliberately NOT this milestone

### Critical Pitfalls

(from PITFALLS.md — repo-grounded; 11 pitfalls total, top 5 here)

1. **s3d durability ambiguity** — 200 OK = staged on local disk; GET/HEAD succeed from staging; nothing in the PUT response distinguishes staged from transferred. *Avoid:* ship `DurabilityLevel` (LocalCommitted/PeerReplicated/ObjectStoreAccepted/ObjectStoreDurable) in Phase 1 with the invariant "a Put never returns a level it did not verify"; discover/pin the real signal (admin API `:8001` `/stats/uploads` + `/prometheus` exist today — exact field semantics are the one MEDIUM item) during the s3d phase; treat staging dir + SQLite as part of the durability path; safe default = accepted-is-max-provable, local copy pinned.
2. **Transport failure treated as NotFound** — a temporary outage becomes observed absence; downstream, a cache miss is indistinguishable from "this CRDT operation never happened." *Avoid:* freeze the taxonomy (NotFound/Timeout/Unavailable/AuthFailure/Corrupt/Cancelled) before any backend; map minio-cpp error codes to it in exactly ONE place; unknown → `Unknown`, never `NotFound`; fault-injection tests with a loopback stub prove no sticky negative cache.
3. **CID verification skipped on "trusted" sources / ETag shortcuts** — the classic "ETag is the MD5" assumption is structurally false under s3d (client-side encryption before upload — server digests are over ciphertext). *Avoid:* verification unconditional at the BlockStore boundary on every Get including local; ETag/HEAD metadata never a proof (Content-Length = cheap pre-check only); corruption counter-tests (flip one byte locally and in S3 → `Corrupt` with source attribution).
4. **Crash-safety gaps** — torn local writes; crash between local commit and remote upload with no durable intent record; aborted multipart state. *Avoid:* temp+fsync+atomic-rename from the first write path; durable upload journal (`CID → PendingUpload|UploadedAccepted|UploadedDurable`) reconciled on restart; plain PutObject for small blocks (skip multipart entirely this slice); crash-injection tests.
5. **Workspace thirdparty build landmines** — wrapper vcxproj builds compile nothing; MSBuild silently skips refreshed `.lib` members (green builds, stale binaries); no dependent rebuild on header change; W:-drive disk pressure (~17.6 GB free vs ~162 GB SG Debug tree); two-pass-ninja byproducts. *Avoid:* canonical `ExternalProject_Add` + `DEPENDS` + `BUILD_BYPRODUCTS`; verify inner-vcxproj mtime + deployed-tree hash audit; `/t:Rebuild` dependents after header changes; marker byte-greps on test exes; budget disk before configuring; innermost-first commits, exact-path staging.

Honorable mentions: SigV4/path-style/clock-skew config surface (explicit `path_style=true`, pinned region, plain-HTTP loopback — never verify TLS against s3d's per-start self-signed cert); no `List` in operating-path code; credentials via env/0600-files never in committed config; `/WHOLEARCHIVE` or (simpler) no static self-registration; three-tier test strategy (hermetic stub always-on → MinIO-binary opt-in → s3d manual/dev-only with committed evidence).

---

## Cross-Document Analysis

The four researchers agree on ~90% of the ground (all contradictions below are resolveable with a decision, none block the roadmap shape). Agreements first, then explicit conflicts with recommendations.

### Strong agreements (all four docs)

- **Scope discipline:** architecture-doc Phases 1+2 only; tiering/sharding/eviction/CARv2 explicitly later; interfaces must not preclude them (decorator pattern is the mechanism).
- **Dependency direction:** library depends on nothing SuperGenius-shaped; the future seam is a SuperGenius-side adapter; enforced by build order.
- **s3d staging semantics** (the named FEATURES↔PITFALLS cross-check): both independently found that PUT-ack ≠ durable, GET serves from staging, and the admin API (`/stats/uploads`, `/prometheus`) is the observable signal today. FEATURES' "expose ObjectStoreAccepted honestly, surface pending-upload stats as diagnostics" and PITFALLS' Pitfall 1 are the same finding at different depth. **One scope nuance:** FEATURES schedules the durable-signal *probe* as v1.x fast-follow; PITFALLS pins signal *discovery* (read `openapi.yml` at the pinned s3d version, don't guess metric names) inside the slice's s3d phase. Reconciliation: v1.0 ships honest `ObjectStoreAccepted` + docs; signal **discovery** happens in the s3d phase (cheap: read the spec, record findings); the polling **implementation** is fast-follow if a per-object signal exists, else the fallback (accepted-is-max-provable, local copy pinned — eviction is out of scope anyway) is the documented answer to architecture-doc Open Question #5 for this milestone.
- **CID is the only authority:** verify at the boundary; ETag never a proof (s3d client-side encryption); "the exact S3 key is not authoritative."
- **minio-cpp over aws-sdk-cpp:** STACK's comparison table and ARCHITECTURE's adapter rationale converge — the `S3Client` seam keeps even this decision reversible.
- **Conformance-kit-first:** S5's `StoreTests` pattern (FEATURES differentiator, ARCHITECTURE Phase-1 contents, PITFALLS P1 enabler).

### Conflicts — resolve as entrance criteria

**C1. CID dependency: STACK (libp2p `p2p_cid`) vs ARCHITECTURE (ipfs-lite-cpp granular `cid` target).** The two docs give directly opposing recommendations on the library's one shared type:
- STACK: use `libp2p::multi::ContentIdentifier` + `ContentIdentifierCodec` from `p2p_cid`; claims it provides complete CIDv0/v1 parse/format bytes↔string and links only multihash/sha/uvarint/multibase — zero ipfs-lite-cpp, which matters because "genius-tube must not need ipfs-lite-cpp just to get a CID type." Rejects ipfs-lite-cpp's `cid` target claiming it drags fmt/soralog/c-ares/blake2/cbor.
- ARCHITECTURE: link only the granular `cid`(+`outcome`+`buffer`) targets from ipfs-lite-cpp's exported config; claims raw libp2p drops `toBytes/toString/getCidOf` (RocksDB keys, S3 keys, verify-on-put would need "hand-rolled codecs — not acceptable") and that every consumer already builds ipfs-lite-cpp so marginal cost ≈ 0.
- The contradiction is partly **factual** (does `ContentIdentifierCodec` provide string↔bytes round-trip? is the granular `cid` target heavyweight or not?) and partly **philosophical** (minimal footprint vs one-CID-definition-everywhere).
- **Recommendation:** resolve empirically with a day-one Phase-1 spike: a ~10-line test that (a) round-trips CID→bytes→string using only `p2p_cid`, and (b) implements `CidOf(bytes, codec)` as a thin in-library helper (sha256 multihash + CIDv1 construct — composition, not codec reimplementation). If green → adopt STACK's `p2p_cid` (smaller genius-tube footprint, matches the milestone's "no SuperGenius-adjacent baggage" goal; ARCHITECTURE itself concedes the escape hatch of extracting a cid micro-package). If the spike fails → fall back to ARCHITECTURE's granular-target linking. Either way, both docs' shared guardrail holds: no `ipfs_lite/ipfs/*` includes, CI-grep-enforced.

**C2. CI S3 endpoint mechanism: STACK (Docker, pinned image) vs PITFALLS (no Docker in CI; spawn MinIO binary).** STACK recommends `docker run minio/minio:RELEASE.2025-10-15...` as the hermetic CI endpoint; PITFALLS Pitfall 10 documents from this repo's own CI files that Linux jobs run inside AlmaLinux containers on self-hosted runners with **no Docker daemon and no `services:` usage**, and Windows has no guaranteed daemon. **Recommendation:** PITFALLS wins for CI (it's repo-grounded): spawn the MinIO server **binary** as a child process on `127.0.0.1:<port>` (single static Go binary, no Docker needed), env-gated. STACK's pinned Docker image remains the right fixture for dev machines and the manual s3d acceptance lane. Either way: never `play.min.io`, never registered-s3d in CI (egress WAF/rate-limiting proven by the tokenprice diagnosis).

**C3. `Remove`/`Delete` in the v1 interface: FEATURES vs PITFALLS.** FEATURES' v1 surface includes `Remove(CID)` ("boxo parity… the policy calling it lives far upstream") and a `DeleteResult` type; PITFALLS Pitfall 5 says a Delete-shaped API on BlockStore invites the fatal misuse later (CRDT history/tombstone purge breaks network-wide convergence) and prescribes: **no delete operation on the S3 backend in v1 at all**, `EvictLocal(cid)` naming for local-only reclamation later, header docs restating the three "eviction does NOT mean" invariants, plus a guard test asserting the API shape. **Recommendation:** PITFALLS wins — boxo parity is a weak argument against a documented CRDT-correctness failure mode; blocks are immutable and the slice has no GC. Omit `Remove`/`DeleteResult` from the v1 interface; revisit only with Open Question #13 (GC policy) answered.

**C4. Enumerate/List on the interface: FEATURES vs PITFALLS.** FEATURES lists "Enumerate/List CIDs (local iterator + S3 ListObjectsV2)" as P1 (needed for audit/restore); PITFALLS Pitfall 6 prescribes "the BlockStore interface exposes Get/Put/Has — no List" (listing is tooling/audit only; O(keyspace) at millions of objects; s3d lists served from SQLite). These reconcile cleanly: **keep the core interface List-free** (the operating-path rule stays CI-greppable) and expose enumeration as a **separate optional tooling/audit interface** (e.g., `BlockStoreEnumerator` or a free function) clearly documented as never-called-from-runtime; restore-to-local accepts a manifest/CID list rather than requiring enumeration. Both researchers' intents survive.

**C5. minio-cpp dependency set: ARCHITECTURE stale vs STACK/PITFALLS current.** ARCHITECTURE says minio-cpp deps are "libcurl, openssl, pugixml, etc." — outdated (curlpp was removed in v0.7.0, Aug 2026). STACK verified the v1.0.0 set (cpp-httplib/inih/nlohmann-json/openssl/pugixml/zlib) and PITFALLS Pitfall 7 explicitly warns against the curl/libxml assumption. **Resolved in favor of STACK/PITFALLS**; ARCHITECTURE self-flagged this area MEDIUM ("not yet prototyped"). Planning must use STACK's dependency list; the hermeticity patch (C1-adjacent: pre-provided config packages, clone-fallback → hard error) is a Phase-3 prerequisite.

**Minor notes:** STACK asserts conditional `If-None-Match` is within minio-cpp's feature set; FEATURES flags raw-header exposure as unverified. Treat "minio-cpp can send `If-None-Match:*` at the pinned tag" as a Phase-3 entrance criterion (cheap test, high consequence — it underpins write-once idempotency). `DurabilityLevel`: define the architecture doc's full 4-value enum (incl. `PeerReplicated`, unproducible in v1 — type-system placeholder for later tiering), per PITFALLS; FEATURES' 3-value variant is a subset.

---

## Implications for Roadmap

Suggested phase structure — synthesizes ARCHITECTURE Q5's build order with PITFALLS' phase tags and FEATURES' P1 set. Five phases: the conformance kit must exist before the first real backend; the orchestration entry must exist before the first external dependency; the adapter+fake must precede the live-service backend; SDK build risk is isolated in exactly one phase; hardening/measurement closes.

### Phase 1: Library skeleton + BlockStore contract + MemoryBlockStore + conformance kit
**Rationale:** Types and the conformance kit are the verification instrument for everything after; the taxonomy/API-shape decisions are the ones that are brutal to retrofit. Also the home of the C1 CID spike (entrance criterion).
**Delivers:** repo bootstrap (AsyncIOManager-style CMakeLists + install/export config), `Block`/`BlockStatus`/`GetBlockResult`/`PutResult`/`ReadOptions`/`WriteOptions`/`DurabilityLevel` (4-value)/`BlockStoreCapabilities`, `BlockStore` interface (no List, no Remove — per C3/C4), CID dependency decision + `CidOf` helper, `MemoryBlockStore`, verify-on-put/get hooks, `test/conformance/` reusable suite, `CommonTargets.cmake` entry + `.gitmodules` from day one.
**Addresses (FEATURES):** interface + result types, CID verify, memory backend, error taxonomy, DurabilityLevel, conformance contract.
**Avoids (PITFALLS):** 2 (taxonomy first), 5 (API naming freeze + guard test), 6 (no-List interface rule), 11 (config schema: no `secret_key:` field exists to be misused).

### Phase 2: LocalBlockStore over RocksDB
**Rationale:** Pure-local — no network, no MinIO — proves the abstraction against a real persistent backend and lands the crash-safety machinery the S3 tier's journal will reuse.
**Delivers:** own RocksDB instance/directory, `cid.toBytes()` keys, atomic temp+fsync+rename writes, durable upload journal (PendingUpload/UploadedAccepted/UploadedDurable) + startup reconciliation + temp-sweep, verify-on-read with corruption self-heal, conformance suite green, `DEPENDS rocksdb` in CommonTargets.
**Addresses:** RocksDB local backend (LocalCommitted tier), restore-to-local helper.
**Avoids:** 3 (local verification + heal), 4 (atomic writes + journal), and anti-patterns 1/6 (standalone instance, never GlobalDB's handle).

### Phase 3: thirdparty integration of minio-cpp (+3 deps) + S3Client adapter
**Rationale:** The one genuinely new external surface — isolate SDK/build risk here, behind the fake client, so Phase 4 is pure composition. **Recommended `--research-phase` target** (see flags).
**Delivers:** submodules pugixml v1.16 / cpp-httplib v0.62.0 / inih r62 (GNUS CMakeLists fork) / minio-cpp v1.0.0 (GNUS fork with hermeticity patch), ExternalProject_Add blocks in dependency order with byproducts, internal `S3Client` interface + `MinioS3Client` + `InMemoryS3Client` fake, single-point error-code→taxonomy mapping, explicit config surface (endpoint/path-style=true/pinned region/tls_verify/https), entrance-criterion checks (conditional-header exposure; BaseUrl config at pinned tag; TLS on/off smoke).
**Uses (STACK):** minio-cpp v1.0.0 + 3 deps; reuse vendored openssl/zlib/nlohmann-json; no vcpkg ever.
**Avoids:** 7 (pin + vendored deps + CRT — build from source on Windows), 8 (all superbuild guards: inner-vcxproj audit, `/t:Rebuild`, marker byte-greps, disk budget), 9 (config surface, no SDK cloud defaults).

### Phase 4: S3BlockStore + s3d roundtrip + metrics
**Rationale:** Composed over Phase 3's adapter; the slice's terminal deliverable, ending in the acceptance E2E (fresh instance retrieves a block from s3d and verifies).
**Delivers:** `v1/blocks/<codec>/<prefix>/<cid>` layout, conditional create-only PUT (`If-None-Match:*`, 412→AlreadyExists-success), HeadObject-backed `Has`, deadlines/retries/structured errors, verify-on-get, separate tooling/audit enumeration interface (C4), metrics hook points, MinIO-binary integration tests (env-gated), s3d manual acceptance roundtrip + **durability-signal discovery** (read `openapi.yml` at pinned v0.2.1; record metric names; check for staged-read distinguishing headers) + measurement evidence (PUT/GET/HEAD throughput, SQLite size, staging usage — the CARv2 decision data).
**Avoids:** 1 (honesty + discovery + docs; staging-full → Unavailable), 9 (loopback HTTP, never verify self-signed), 6 (layout adopted as-is; no List in operating path).

### Phase 5: Hardening — fault/crash injection, scale probe, evidence
**Rationale:** The trust claims (taxonomy, crash-safety, durability honesty, corruption attribution) are only proven under failure; PITFALLS dedicates a full phase tag to exactly this, and the repo's evidence-file conventions want numbers.
**Delivers:** loopback-stub fault-injection matrix (conn-refused/500/503/truncated/garbage → taxonomy classes; no sticky negative cache), crash-injection (kill between temp-write/rename, commit/upload, upload/record-update → clean recovery), corruption counter-tests (local + S3 byte-flip → Corrupt with attribution + self-heal), s3d durability tests (upload-with-Sia-paused, staging-disk-full, crash-recovery — dev-only, evidence committed), dev-machine scale probe (~10⁵–10⁶ objects, gated off in CI), backup-triad docs (recovery phrase / s3d SQLite / config), Loud labelled skips + ctest timeouts.
**Avoids:** 10 (three-tier strategy complete, no live-endpoint/Docker CI dependencies), and closes out 1/3/4/6's test obligations.

### Phase Ordering Rationale

- **Conformance kit before backends (S5's core lesson):** every backend is born under the same suite; Memory is the deterministic reference (Phase 1) that makes Local (2) and S3-with-fake (3→4) comparable.
- **Orchestration entry from Phase 1:** keeps CI honest from the first commit; consumer wiring (`CommonBuildParameters.cmake`) deliberately excluded until a consumer exists (dead config otherwise — ARCHITECTURE Q5 note).
- **Adapter + fake before live service:** Phase 4 never debugs SDK integration and store semantics simultaneously; SDK build risk (the flagged MEDIUM area) is quarantined in Phase 3.
- **Hardening last but hermetic tests from day one:** tier-1 (stub/memory) tests exist from Phase 1; Phase 5 adds failure modes, not the first tests.
- **Pitfall mapping is phase-tagged in PITFALLS.md** (P1…P5 tags align 1:1 with these phases) — planners can lift mitigations directly.

### Explicitly later milestones (do NOT add to this roadmap)

- SuperGenius seam: `BlockStoreBackedIpfsDatastore` adapter + `globaldb.cpp:322-344` wiring (mirror mode first) + `CommonBuildParameters.cmake` entry — needs this library shipped first.
- Architecture-doc Phases 3–6: `TieredBlockStore`/`PeerBlockStore`, path sharding/rendezvous ownership, durability-driven eviction, CARv2 (measure-first gate), CRDT GC (needs causal-stability spec).

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 — YES, `--research-phase` recommended:** minio-cpp v1.0.0 header-level API surface at the pinned tag (BaseUrl constructor/config fields, path-style + HTTPS toggles, region pinning, raw conditional-header exposure, error-code surface — hosted doxygen is stale, README/examples only), hermeticity patch shape, inih fork practicality, Windows CRT/source-build verification, ExternalProject wiring details. Both STACK and ARCHITECTURE independently flagged this MEDIUM.
- **Phase 1 — targeted spike, not full research:** the C1 CID-dependency spike (p2p_cid round-trip + CidOf helper) plus the C3/C4 interface-shape decisions. Everything else in Phase 1 follows established AsyncIOManager patterns.
- **Phase 4 — targeted in-phase research tasks:** s3d `openapi.yml` durability-signal field semantics (the one MEDIUM item in PITFALLS); staged-read headers; fallback design if no per-object signal exists.

Phases with standard patterns (skip research-phase):
- **Phase 2:** RocksDB usage is well-trodden in this repo; atomic-write/journal patterns documented in PITFALLS with precedents.
- **Phase 5:** repo has strong precedent for hermetic loopback stubs, deadline+condition polling, evidence files, ctest timeout bounds.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions verified against upstream 2026-10-19; integration verified against this workspace's thirdparty sources. One MEDIUM seam: minio-cpp header-level API at pinned tag (Phase 3 research). |
| Features | MEDIUM–HIGH | Core op set cross-verified across ≥3 independent systems (boxo/S5/Cluster/existing IpfsDatastore); conditional writes cross-verified AWS+s3d. Self-flagged caveat: GSD provider-id seam underrates the evidence; the real gap is minio-cpp conditional-header exposure (entrance criterion). |
| Architecture | HIGH | All SuperGenius/thirdparty facts read directly from source with line anchors; seam (globaldb.cpp:322-344) verified. minio-cpp build integration MEDIUM (dep list was stale — corrected by STACK/PITFALLS per C5). |
| Pitfalls | HIGH | Repo-grounded (planning history, CI files, AGENTS.md); s3d/minio-cpp items verified against primary sources. One MEDIUM: exact s3d durability-metric field semantics (Phase-4 discovery task). |

**Overall confidence:** HIGH for plan-shaping conclusions (phase structure, stack choice, interface shape, risk register). The named open items below are narrow, cheap to verify in-phase, and none change the roadmap shape.

### Gaps to Address

1. **C1 CID dependency (STACK vs ARCHITECTURE conflict):** resolve via Phase-1 day-one spike (p2p_cid round-trip + CidOf helper); fallback = ipfs-lite-cpp granular `cid` target. Do not let Phase-1 planning start without this decision recorded.
2. **minio-cpp v1.0.0 API surface at pinned tag:** BaseUrl config (path-style/HTTPS/region), raw `If-None-Match` header exposure, error-code enumeration — verify against the tag's README/examples/tests, never the hosted doxygen. Phase-3 entrance criteria.
3. **s3d durability-signal field semantics:** admin `/stats/uploads`//prometheus endpoints verified to exist; exact "this object's group uploaded vs pending" metric must be read from pinned v0.2.1's `openapi.yml`/source in Phase 4; documented fallback (accepted-is-max-provable + local pinned) if no per-object signal exists.
4. **inih GNUS fork must exist** (CMakeLists added to meson-only upstream) before the Phase-3 build task runs — repo-creation prerequisite, not a research gap.
5. **RocksDB version skew (9.4.0 workspace vs 11.1.2 genius-tube):** recommended = dual-compatible stable-API surface (cheap for this slice); bumping the workspace's rocksdb is out of scope and touches every consumer.
6. **CI S3 endpoint mechanism (C2):** adopt MinIO-binary-as-child-process for CI (repo CI has no Docker); keep STACK's pinned Docker image for dev/manual lanes. Confirm the pinned MinIO server binary distribution is fetchable in CI lanes during Phase-3/5 planning.
7. **Interface-shape decisions (C3/C4):** no Remove/Delete in v1 core; enumeration on a separate tooling interface — record both as frozen Phase-1 decisions with the PITFALLS guard test.

## Sources

### Primary (HIGH confidence)
- Upstream repos fetched 2026-10-19: `minio/minio-cpp` @ v1.0.0 (README, releases, `vcpkg.json`, deps file in its cmake dir), `yhirose/cpp-httplib` (v0.62.0), `zeux/pugixml` (v1.16), `benhoyt/inih` (r62), `SiaFoundation/s3d` @ v0.2.1 (README: staging/packing/conditional writes/admin API/config), `minio/minio` (archival notice 2026-04-25, frozen release tag), `aws/aws-sdk-cpp` (1.11.913, rejected alternative)
- Reference systems: `ipfs/boxo` Blockstore (incl. codec-loss limitation), `s5-dev/s5-rs` @ main (Store/BlobStore/StoreFeatures/testutil/CachingStore), `ipfs-cluster` (state export/import), `go-ds-flatfs` (write-once safety), AWS S3 conditional-writes docs — fetched 2026-10-19
- Workspace source (authoritative): `supergenius-sharded-ipld-cache-architecture.md`; `SuperGenius/src/crdt/globaldb/globaldb.cpp` (:200-300, :322-349); `SuperGenius/src/crdt/graphsync_dagsyncer.{hpp,cpp}`; `thirdparty/ipfs-lite-cpp` (datastore.hpp, datastore_rocksdb + FIL-117, cid.hpp, CMakeLists:59-75); `thirdparty/libp2p/src/multi/`; `thirdparty/build/CommonTargets.cmake` (:140-173, :497-532, :741-776); `thirdparty/AsyncIOManager/CMakeLists.txt`; `GeniusSDK/cmake/CommonBuildParameters.cmake`; `thirdparty/.gitmodules:96-98`; `thirdparty/AGENTS.md`; `SuperGenius/.github/workflows/cmake.yml`

### Secondary (MEDIUM confidence — flagged, verify in-phase)
- Exact s3d durability-metric field semantics (README-verified endpoints; spec not yet read) — Phase-4 discovery
- minio-cpp pinned-tag header surface incl. conditional-header exposure (README-verified; headers not yet compiled against) — Phase-3 entrance criteria
- Windows prebuilt-bundle CRT linkage (moot if building from source, the recommended path)

### Tertiary (context)
- Repo memories quoted into `.planning/workstreams/ipfs-improve/phases/04-*/04-RESEARCH.md` and `tokenprice/phases/02-*/02-RESEARCH.md` (thirdparty-inner-vcxproj-rebuild, msbuild-incremental-link-skip, w-drive-disk-full, gsd-windows-crlf, windows-ci-docker-desktop) — HIGH for quoted content, MEDIUM for unquoted nuance

---
*Research completed: 2026-10-19*
*Ready for roadmap: yes — resolve C1 spike and Phase-3 entrance criteria during phase planning, not before*
