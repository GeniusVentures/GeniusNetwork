# Pitfalls Research

**Domain:** Adding a CID-native cold-storage block archive library (`sgns-blockstore`) to an existing C++17/CMake/RocksDB/IPLD system (SuperGenius + thirdparty superbuild) — vertical slice: abstraction + local store + MinIO C++ SDK S3 adapter + Sia s3d roundtrip + CID verify
**Researched:** 2026-10-19
**Confidence:** HIGH (workspace-specific items grounded in this repo's own planning history and CI files; s3d/minio-cpp items verified against primary sources today — s3d `master` README v0.2.1, minio-cpp v1.0.0 README. The single MEDIUM item is the exact s3d durability-signal field, flagged below.)

**Sources:** `supergenius-sharded-ipld-cache-architecture.md` (authoritative design), s3d README (github.com/SiaFoundation/s3d, fetched 2026-10-19), minio-cpp README + stale doxygen site (github.com/minio/minio-cpp @ v1.0.0, fetched 2026-10-19), repo memories quoted in `.planning/workstreams/ipfs-improve/phases/04-*/04-RESEARCH.md` and `tokenprice/phases/02-*/02-RESEARCH.md` (thirdparty-inner-vcxproj-rebuild, msbuild-incremental-link-skip, w-drive-disk-full, gsd-windows-crlf, windows-ci-docker-desktop, supergenius-pubsub-testing), `thirdparty/AGENTS.md`, `SuperGenius/.github/workflows/cmake.yml`.

**Vertical-slice phase tags used below:** **P1 Abstraction** · **P2 Local store** · **P3 S3 adapter (MinIO SDK)** · **P4 s3d integration** · **P5 Testing**

---

## Critical Pitfalls

### Pitfall 1: s3d durability ambiguity — 200 OK on PUT means "staged on local disk," not "durably on Sia"

**What goes wrong:**
An S3 `PutObject` acknowledged by s3d returns immediately with the object written to s3d's **local uploads directory**; a background loop bin-packs pending objects into groups and uploads them to Sia only when slab waste falls below the threshold (default 10%). A `GET`/`HEAD` of the staged object **succeeds** — served from local staging — so roundtrip tests "pass" while nothing has reached Sia. If the local eviction policy (or a naive operator) treats the PUT ack as durable and drops the SuperGenius-side copy, the only remaining copy is s3d's staging buffer + SQLite metadata, and loss of that one machine loses the block.

**Why it happens:**
s3d's S3 API is deliberately ack-early (staging is the whole point of upload packing); nothing in the S3 PUT response distinguishes staged from transferred. The architecture doc already carries this as "Durability-state ambiguity" (Key risks) and Open design question #5 ("What s3d signal proves that staged data has been durably transferred to Sia?"). The trap is writing the code against S3 semantics (PUT ack = durable) instead of s3d semantics (PUT ack = accepted).

**How to avoid:**
- **P1:** Ship the `DurabilityLevel` enum from the architecture doc (`LocalCommitted` / `PeerReplicated` / `ObjectStoreAccepted` / `ObjectStoreDurable`) as two distinct, non-defaultable outcomes of Put. A Put must never return a level it did not verify. Core invariant (from the doc): local bytes are not evicted until the configured durability policy is satisfied **and recorded**.
- **P4:** Determine and pin the actual s3d durability signal. Candidate signals (verified to exist today): the **admin API** on its own port (default `127.0.0.1:8001`, HTTP Basic auth via `adminPassword`) exposing `GET /stats/uploads` (JSON) and `GET /prometheus` — upload-pipeline metrics; and `s3d status` output. Re-verify the exact metric names against `openapi.yml` at the pinned s3d version; do not guess (this is the one MEDIUM-confidence item — the existence of the endpoints is HIGH confidence from the README, the exact "staged vs transferred" field semantics must be confirmed in-phase).
- **P4:** Treat the s3d staging directory (`sia.diskUsageLimit`, default 10 GiB) and s3d's SQLite metadata as **part of the durability path**: disk-full or low-Sia-balance conditions must inhibit eviction and surface as `Unavailable`-class errors, never as success or `NotFound`.
- **P4/P5:** The only safe default for the slice is: durability = "s3d admin stats report zero pending for this object/group" (or equivalent confirmed signal) — polled with deadline. If no per-object signal exists, conservatively treat `ObjectStoreAccepted` as the maximum provable level and keep the local copy pinned (eviction is out of slice scope anyway — this must be stated in docs).

**Warning signs:**
- Any test that asserts durability immediately after PUT returns (no polling of the upload pipeline).
- Docs/comments saying "PUT succeeded ⇒ safe to evict."
- s3d staging dir grows monotonically in a long test run while tests stay green.
- GET-after-PUT succeeds on an s3d instance with networking to Sia disabled (proves nothing was tested about transfer).

**Phase to address:** P1 (enum + invariant), P4 (signal discovery + polling), P5 (durability tests: upload-with-s3d-paused, staging-disk-full, s3d-crash-recovery).

---

### Pitfall 2: Transport failure treated as NotFound (and no negative caching for it)

**What goes wrong:**
`s3d` down, staging disk full, TLS failure, DNS failure, or a 5xx gets flattened into "block not found" — the tiered store caches the miss, and a temporary outage becomes an observed absence. Downstream, a cache miss on a CRDT block is indistinguishable from "this operation never happened," which is exactly the CRDT-corruption scenario the architecture doc forbids ("a cache miss must not be interpreted as an absent or unprocessed CRDT operation").

**Why it happens:**
Convenient error enums collapse everything into `NOT_FOUND`; SDK error surfaces (minio-cpp `Response::Error()`) return strings/codes that are easy to string-match on the wrong subset. The doc's Read-path section already demands the six-way distinction (authoritative NotFound / timeout / auth failure / backend outage / peer disconnection / corrupt content); the pitfall is not designing the error taxonomy first and then being forced to retrofit semantics through message parsing.

**How to avoid:**
- **P1:** Define the result/error taxonomy before any backend exists: `NotFound` (authoritative absence only), `Timeout`, `Unavailable` (transport/5xx/disk-full/balance), `AuthFailure`, `Corrupt` (CID mismatch), `Cancelled`. Map minio-cpp error codes to this taxonomy in exactly one place in the S3 adapter; anything unrecognized maps to `Unknown`, never to `NotFound`.
- **P1/P3:** Negative caching: only authoritative `NotFound` may be negative-cached, briefly (TTL), with transport failures explicitly excluded. Model this as a separate code path from the block cache from day one, even if the slice only implements the TTL stub.
- **P5:** Fault-injection tests with a loopback stub server (workspace precedent: tokenprice HTTP stubs bound to `127.0.0.1:0`): connection-refused, 500, 503, truncated body, garbage body — each must yield its taxonomy class, and a subsequent retry after recovery must succeed (proves no sticky negative cache).

**Warning signs:**
- `if (!resp) return NotFound;`-shaped code anywhere in the adapter.
- Tests that stop a stub server and assert NotFound (they should assert Unavailable/Timeout).
- A negative-cache entry keyed on anything other than an authoritative NotFound result.

**Phase to address:** P1 (taxonomy), P3 (single mapping point), P5 (fault-injection suite).

---

### Pitfall 3: CID verification skipped on "trusted" sources (local store, ETag shortcuts)

**What goes wrong:**
(a) A fast path skips hashing for blocks fetched from the local RocksDB/file cache "because we verified on write" — but disk corruption, partial writes, or a torn cache file then silently serve wrong bytes as a valid block. (b) The classic S3 shortcut — trusting the object's **ETag as a content hash (MD5)** — is actively wrong under s3d: data is **encrypted client-side by the Sia Storage SDK before upload**, so server-visible digests are over ciphertext, never the plaintext the CID commits to.

**Why it happens:**
Hashing small blocks feels free to skip for performance; every S3 tutorial says "ETag is the MD5." Under s3d that assumption is structurally false, and under any backend the CID is the only authority (architecture doc: "The exact S3 key is not authoritative. The CID is authoritative. All retrieved bytes must verify against the requested CID").

**How to avoid:**
- **P1:** Make verification unconditional at the `BlockStore` boundary: every `Get` (any tier, any source, including local) verifies bytes against the requested CID before returning. Acceptance criteria 4 and 7 of the architecture doc make this non-negotiable.
- **P2:** Local cache writes verify before publish (compute-then-rename), and reads re-verify — a corrupted local entry surfaces as `Corrupt` and triggers a re-fetch from the next tier, not a wrong result.
- **P3:** Never use ETag/HEAD metadata as a substitute for verification; use `Content-Length` only as a cheap pre-check, not a proof.
- **P5:** Corruption counter-tests (repo precedent: SECV-01/SECV-02 corrupted-fixtures): flip one byte in a local cache file and in an S3 object; assert both yield `Corrupt` with source attribution, and assert the tiered store self-heals by re-fetching.

**Warning signs:**
- Any `verify=false` flag, `#ifdef NDEBUG`-gated hashing, or source-conditional verification.
- Code that compares an S3 ETag to a CID-derived or MD5 digest.

**Phase to address:** P1 (boundary rule), P2 (local verify + heal), P5 (corruption counter-tests).

---

### Pitfall 4: Crash-safety gaps — non-atomic local writes, crash between local commit and remote upload

**What goes wrong:**
Three distinct windows, any of which loses or corrupts data silently:
1. **Torn local cache file**: writing the block file in place; crash mid-write leaves a partial file at the final path (worse if the local store is a RocksDB column read by other components).
2. **Local-commit/remote-upload gap**: block committed locally, process crashes before (or during) upload; without a durable record of intent, the block is never archived and nobody notices — the local cache eventually evicts it and the block is gone forever.
3. **Partial multipart uploads**: aborted multipart state left in s3d consuming staging space (s3d supports `AbortIncompleteMultipartUpload` lifecycle rules precisely because of this).

**Why it happens:**
The happy path (write, upload, confirm) is what everyone tests; the crash windows require deliberate journal design. The architecture doc's local-cache rules already mandate "temporary files followed by atomic rename," and its Phase-5 plan mandates "failure injection for crashes during upload and state transitions" — but the journal/intent-record has to exist from the slice's first write path or every later test fights the design.

**How to avoid:**
- **P2:** Local writes: write to temp file in the same directory/volume, fsync, then atomic rename (`MoveFileEx` with `MOVEFILE_REPLACE_EXISTING` on Windows; `rename()` on POSIX — same-volume rename is atomic on both). Never write block bytes in place; never leave temp files on the crash path un-swept (startup sweep of known temp suffix).
- **P2/P4:** Durable upload journal (write-ahead intent record committed atomically with the local block): `CID → {state: PendingUpload | UploadedAccepted | UploadedDurable}`. On restart, reconcile: re-queue PendingUpload. PUTs are idempotent by construction (same CID ⇒ same bytes ⇒ safe overwrite) — rely on that instead of distributed transactions.
- **P4:** If multipart is ever used for large blocks, always abort-on-error and configure `AbortIncompleteMultipartUpload` lifecycle on the bucket (s3d supports prefix-based rules). For the slice, blocks are small — use plain PutObject and skip multipart entirely.
- **P5:** Crash-injection tests: kill between (a) temp-write and rename, (b) local commit and upload, (c) upload and durability-record update. Restart must recover with no visible partial block and no unarchived-but-forgotten block.

**Warning signs:**
- Block files opened for writing at their final path.
- Durability state kept only in memory (lost on restart).
- Tests that only cover clean shutdown.

**Phase to address:** P2 (atomic writes + journal), P4 (reconciliation), P5 (crash injection).

---

### Pitfall 5: Eviction-vs-delete API confusion inviting CRDT history/tombstone loss

**What goes wrong:**
Even though eviction is explicitly out of the vertical slice, an interface shaped wrong now invites the fatal misuse later: a `Delete(CID)` on the BlockStore that (or whose documentation implies it) removes remote data or path mappings; someone wires "reclaim space" or "GDPR-ish cleanup" to it, purges CRDT history or tombstones, and convergence/causal reconstruction breaks network-wide. The architecture doc's CRDT-correctness section is a direct consequence list of exactly this class of mistake (eviction ≠ logical delete; tombstones cannot be purged for age; heads must retain causal history; restoration must not resurrect tombstoned values).

**Why it happens:**
`Delete` is the idiomatic name for storage APIs; without a deliberately separated vocabulary, the local-cache concern and the archive concern blur. Once a generic `Delete` exists, every future caller (and every future AI assistant reading the header) will assume full-stack deletion semantics.

**How to avoid:**
- **P1 (design rule):** Name for scope, not convenience: `EvictLocal(cid)` on the local/tiered store (removes cached bytes only — never remote, never path-to-CID mappings, never CRDT state). The S3 backend interface exposes **no delete operation in v1 at all** (blocks are immutable; the slice has no GC). If a remote delete is ever added, it lives on the backend interface under a name like `DeleteRemoteObject` with a doc comment stating it is never called by cache logic and is CRDT-unsafe until Open Question #13 (GC policy) is answered.
- **P1:** Header-level documentation on the BlockStore interface restating the three "eviction does NOT mean" invariants (no S3 delete, no path unmapping, no CRDT delete).
- **P5:** A guard test asserting behavior, not just docs: after `EvictLocal` (once implemented later) the object must still be retrievable via the remote tier — for the slice, assert the *API shape*: the tiered/local interface exposes no deletion symbol (compile-time; e.g., a `static_assert`-style concept check or simply review-enforced with a test comment), and the S3 adapter's delete-capable SDK methods are not reachable through the BlockStore interface.

**Warning signs:**
- Any method named `Delete`/`Remove`/`Erase` on the BlockStore abstraction.
- Docs using "delete" and "evict" interchangeably.
- Roadmap tasks that mention GC/tombstone pruning without a preceding causal-stability spec.

**Phase to address:** P1 (naming/API freeze), P5 (guard test).

---

### Pitfall 6: Small-object metadata scale assumed fine because "Sia packs small objects"

**What goes wrong:**
The architecture doc's own risk list: tens of millions of CID objects stress (a) s3d's **SQLite metadata** (one row-ish per object plus upload-packing state; recovery/backup time grows with it), (b) **ListObjects** on CID-derived key spaces (O(keyspace) even when paginated; s3d lists are served from SQLite), (c) **request costs** on any future non-s3d provider (HEAD+GET per block), and (d) s3d startup/recovery time. The packing feature solves slab-space waste, not metadata or request-per-object overhead — "Sia packs them" is the seductive half-truth.

**Why it happens:**
The one-CID-one-object layout is the architecture doc's explicit Phase-1-of-packing decision (CARv2 deferred until measured) — the pitfall is not the layout, it's (1) building operating-path logic that *depends on listing* (Open Question #11), (2) running slice-scale tests only (thousands of objects) and assuming millions behave the same, and (3) no growth monitoring on the s3d SQLite file.

**How to avoid:**
- **P1 (design rule):** No operating-path code may call ListObjects/prefix listing. Discovery comes from path→CID resolution and manifests; listing is tooling/audit only. Keep this as an interface-level constraint: the BlockStore interface exposes `Get(CID)`/`Put(CID)`/`Has(CID)` — no `List`.
- **P4:** Key layout from the architecture doc (`v1/blocks/<multicodec>/<prefix>/<cid>`) with prefix fan-out — adopt as-is so later lifecycle/audit tooling stays possible.
- **P4/P5:** Measure-first mandate (doc's CARv2 section): the slice's s3d phase records PUT throughput, GET/HEAD latency, SQLite file size, staging-dir usage, and objects-per-run, with numbers written into the phase evidence — so the CARv2 decision later is data-driven, not vibes.
- **P5:** A scale-probe test (dev-machine only, CI-gated off): insert ~10⁵–10⁶ small blocks against local s3d, record SQLite size and list latency; this is the early-warning instrumentation, not a pass/fail gate.

**Warning signs:**
- Any `List*` in the adapter's non-test code.
- Slice evidence lacking object-count/SQLite-size numbers.
- Anyone asserting "millions will be fine" without the probe data.

**Phase to address:** P1 (no-List interface rule), P4 (layout + measurement), P5 (scale probe, gated).

---

### Pitfall 7: MinIO C++ SDK assumptions that are wrong for v1.0.0 (deps, API churn, docs lag, CRT)

**What goes wrong:**
Four concrete sub-traps, all verified against the v1.0.0 (Sep 2026) state of minio-cpp:
1. **Wrong dependency model.** The assumed chain "curl + libxml2" is outdated: minio-cpp now transports over **cpp-httplib** (curlpp was removed ~Aug 2026) and parses with **pugixml**, plus **openssl**, **zlib**, **inih (INIReader)**, **nlohmann-json**. Planning curl/libxml integration work wastes a phase; the genuinely *new* thirdparty deps are **cpp-httplib, pugixml, inih** (openssl/zlib/nlohmann-json are already vendored in this workspace).
2. **Stale official docs.** The doxygen site still shows the pre-1.0 API (`minio::http::BaseUrl` + `SetHost`), while the README shows the current API (`minio::s3::BaseUrl base_url("play.min.io")`). Coding against the docs site produces non-compiling code. Pin the exact tag; read its README + `examples/` + `tests/`, not the hosted docs.
3. **1.0.0 API/ABI churn.** v1.0.0 ("libminio", stable soname) landed only weeks ago, renaming namespaces and reshaping `BaseUrl`/client config; Windows-specific fixes ("Windows large file support and binary-safe downloads") landed ~2 months ago — the Windows path is young. Expect a pin-then-vendor strategy, not floating `main`.
4. **MSVC runtime mismatch.** The prebuilt Windows bundle ships static libs built with a specific CRT (`/MD` vs `/MT`). This workspace's MSVC targets use the runtime configured by `CommonCompilerOptions.cmake`; linking a `/MD` static lib into a `/MT` (or vice versa) target yields LNK warnings at best and heap/FILE* inconsistencies at worst. Verify the bundle's CRT before adopting it; otherwise build from source inside the thirdparty superbuild so the runtime matches by construction.

**Why it happens:**
minio-cpp moved fast in 2026 (RDMA, libminio release, transport replacement); most blog posts/docs predate all of it.

**How to avoid:**
- **P3:** Pin an exact release tag (v1.0.0 or later); record its SHA in the thirdparty submodule; write the adapter against that tag's README/examples. Add a comment in the adapter naming the pinned version.
- **P3:** Dependency decision recorded in phase CONTEXT: new vendored deps = cpp-httplib, pugixml, inih (each added via the workspace's `ExternalProject_Add` + `BUILD_BYPRODUCTS` + `DEPENDS` conventions — see Pitfall 8); reuse workspace openssl/zlib/nlohmann-json rather than letting vcpkg build duplicates. Do NOT introduce vcpkg into the thirdparty superbuild (it is minio-cpp's default flow but conflicts with this workspace's self-contained ExternalProject design and its offline-CI constraints).
- **P3:** Windows: prefer building minio-cpp from source in the superbuild (matches CRT/flags via `_CMAKE_COMMON_CACHE_ARGS`); treat the prebuilt bundle as a local-dev convenience only, and if used, verify CRT linkage explicitly (e.g., `dumpbin /dependents` spot-check) before linking.
- **P5:** Smoke-test the pinned SDK against a local S3 endpoint with TLS both on and off before building adapter logic on top (catches transport/ABI surprises early).

**Warning signs:**
- `find_package(miniocpp)` resolving a version nobody pinned.
- Includes referencing `minio::http::` (pre-1.0 namespace) — stale-docs contamination.
- vcpkg toolchain files appearing in thirdparty CMake.
- LNK4098 / CRT mismatch warnings dismissed as noise.

**Phase to address:** P3 (pin + vendor + CRT), P5 (TLS on/off smoke).

---

### Pitfall 8: Workspace thirdparty build-system landmines (all previously bit this repo)

**What goes wrong:**
Every one of these is documented history in this workspace, not theory:
1. **Wrapper-project trap (thirdparty-inner-vcxproj-rebuild):** building the top-level thirdparty `<pkg>.vcxproj` (or superproject wrappers) compiles **nothing** — ExternalProject-style layout means the real project is the *inner* vcxproj in `<pkg>-build/`. Symptom: build "succeeds" in seconds with zero compiler output and the lib never refreshes. Deployed `lib/` + `include/` trees drift from build-tree outputs; SuperGenius consumes the **deployed** trees via `find_package(<pkg> CONFIG REQUIRED)` + `<pkg>_INCLUDE_DIR` (pattern: AsyncIOManager in `CommonBuildParameters.cmake`).
2. **MSBuild incremental-link skip (msbuild-incremental-link-skip):** a refreshed `.lib` member silently not pulled into a linking exe — the binary contains old code while the build is green. Documented 0xC0000374 heap-corruption trap when stale-TU objects link against refreshed libs (the deployed-header ABI split).
3. **MSBuild does not rebuild dependents on thirdparty header change** — SuperGenius test targets don't even ProjectReference thirdparty libs (they enter as plain `.lib` inputs); header layout changes demand explicit `/t:Rebuild` of dependent SG lib projects, then tests.
4. **Whole-archive linking (mnn-wholearchive-vulkan):** static-lib objects that are *unreferenced* (auto-registration factories, mock transports) get dropped by the linker unless `/WHOLEARCHIVE` (precedent in `SuperGenius/test/src/account/CMakeLists.txt` and the MNN/Vulkan registration pattern). If `sgns-blockstore` ever uses static registration (backend factory self-registration), symbols vanish at link with only "unresolved external" or silent no-backend symptoms.
5. **W: drive disk pressure (w-drive-disk-full):** the drive has hit effectively-full; measured Oct 2026: ~17.6 GB free against `SuperGenius\build\Windows\Debug` = 162 GB, thirdparty Debug ≈ 19 GB, SDK ≈ 10 GB. Disk-full produces *misleading compiler errors*, not clean "no space" failures. New packages (openssl-for-minio-cpp already exists; cpp-httplib/pugixml/inih are small) must be budgeted; full-tree cleans are forbidden.
6. **Two-pass ninja / byproducts:** thirdparty's `CommonTargets.CMake` needs correct `DEPENDS` + `BUILD_BYPRODUCTS` per target or builds need two ninja passes; new-package integration must follow the documented pattern (`thirdparty/AGENTS.md`).
7. **CRLF hygiene (gsd-windows-crlf):** Windows commits of vendored/upstream-derived files need the repo's line-ending rules respected; accidental CRLF rewrites of submodule contents produce unresolvable diffs upstream.
8. **Submodule pointer discipline:** commit order innermost-first (new submodule → thirdparty pointer → SuperGenius → root), stage by exact path only (never `git add -A` in thirdparty — it sweeps unrelated local advances), never push without instruction.

**Why it happens:**
The thirdparty superbuild's ExternalProject wrapper architecture makes "what MSBuild sees" and "what actually rebuilds" diverge; every one of these traps is invisible in the build log (green builds with stale binaries).

**How to avoid:**
- **P3 (build guard):** New package integrated the canonical way: `ExternalProject_Add` in `CommonTargets.CMake` with explicit `DEPENDS` (openssl, zlib, and its own new deps), `BUILD_BYPRODUCTS` listing the lib + cmake-config files, and downstream wiring (`Miniocpp_DIR`/`SGNS_BLOCKSTORE_DIR` + include dirs in the consuming `CommonBuildParameters.cmake`, mirroring the AsyncIOManager pattern).
- **P3/P5 (build guard):** After any thirdparty rebuild on Windows: verify the **inner** vcxproj was built (inner `.lib` mtime), INSTALL/deploy ran (deployed `lib/` + `include/` mtime + `Get-FileHash` header audit), then `/t:Rebuild` dependents — never incremental across a header change. Byte-grep marker probe on linked test exes (ASCII-decode byte-grep; `Select-String` on binaries is unreliable) as the tripwire that new code actually entered the binary.
- **P3:** Budget disk before building: check W: free space first (it changes week to week); bounded builds only; never clean the whole SG tree.
- **P3:** If static registration is used anywhere in sgns-blockstore, wire `/WHOLEARCHIVE` for the test executables up front — or avoid self-registration entirely (explicit factory functions) for the slice, which is simpler and immune.
- **P3:** `.gitattributes`/line-ending check on all new files; exact-path staging; innermost-first commits.

**Warning signs:**
- A thirdparty target build finishing in seconds with no compiler output.
- Deployed header hash ≠ freshly built header hash.
- A test exe that "built fine" failing a marker byte-grep.
- Unresolved-backend / missing-factory errors only in Release or only in test exes.
- `Get-PSDrive W` free space in single-digit GB before a big configure.

**Phase to address:** P3 (integration + guards), P5 (marker probes in test evidence).

---

### Pitfall 9: SigV4 / endpoint / addressing / clock-skew integration bugs in the S3 adapter

**What goes wrong:**
- **Virtual-host vs path-style:** virtual-hosted addressing (`bucket.s3.example.com`) is impossible for raw-IP or unregistered internal hostnames; s3d only honors virtual-host bases listed in its `s3d.hostBases` config (localhost always included). Defaulting an SDK client to virtual-host style against `127.0.0.1:8000` produces baffling DNS/connection failures.
- **HTTPS-by-default + self-signed cert:** minio-cpp `BaseUrl` treats the endpoint as HTTPS by default; s3d's HTTPS listener uses a **self-signed cert regenerated every start** ("clients must skip certificate verification" per its README). A `tls_verify=true` default against s3d HTTPS fails every request with cert errors; pointing a verifying client at `https://<ip>` additionally breaks RFC 6125 hostname verification.
- **Clock skew:** SigV4 (exclusively — s3d does not implement SigV4A) rejects skewed clocks with 403; dev TestVMs, CI runners, and the s3d VM drifting from the host is routine (workspace precedent: VM-based test environments).
- **Region resolution:** clients that auto-resolve region via `GetBucketLocation` add a hidden roundtrip and another failure mode; s3d supports the call, but a pinned region avoids the extra request and the auth-failure ambiguity.
- **SigV4 payload-signing modes:** s3d accepts `UNSIGNED-PAYLOAD` and the streaming modes but not everything AWS does; a client configured for an exotic signing mode can fail only against some providers.

**Why it happens:**
Each S3-compatible server differs in exactly these corners; they only surface against a *local, self-hosted* endpoint, which is also the environment least like the tutorials.

**How to avoid:**
- **P3:** Adapter config explicitly carries `endpoint`, `path_style` (default **true** for the slice — loopback/IP endpoints), `region` (pinned, e.g. `us-east-1`; matches the architecture doc's example config), `tls_verify`, `https`. No implicit defaults derived from the SDK's cloud assumptions. The architecture doc's example config already has exactly these knobs (`path_style: true`, `region: us-east-1`, `tls_verify: true`) — implement that config surface verbatim.
- **P3/P4:** For s3d on loopback: plain HTTP (`apiAddress: 127.0.0.1:8000`) + `tls_verify` unset; if HTTPS is ever required, front it with a real reverse-proxy cert (s3d README's own recommendation), never verify against s3d's ephemeral self-signed cert in production code paths.
- **P5:** Tests: assert the adapter uses path-style + pinned region (wire-level assert via the stub server inspecting the request line/host header); a clock-skew simulation is impractical to fake hermetically at the SDK layer, so cover it with an adapter-level unit mapping of the SDK's skew error class to `AuthFailure`-with-distinct-reason (documented, not silently 403).

**Warning signs:**
- DNS lookups for `bucket.127.0.0.1` in logs.
- "certificate verify failed" against a local endpoint.
- 403s that vanish after time sync (`w32tm /resync` on the VM).
- Per-request `GetBucketLocation` calls visible in stub-server logs.

**Phase to address:** P3 (config surface + pinned region/path-style), P4 (s3d loopback HTTP), P5 (wire-level asserts).

---

### Pitfall 10: Testing that needs live internet or Docker-in-CI (both unavailable/unreliable here)

**What goes wrong:**
- Tests pointed at `play.min.io` or any live endpoint: this repo's tokenprice diagnosis proved CI-runner egress is WAF/rate-limited and unacceptable as a dependency; hermetic loopback fixtures are the established house style.
- Tests that `docker run` MinIO or s3d: this repo's CI runs Linux jobs **inside `ghcr.io/geniusventures/almalinux-8` containers on self-hosted runners** (`SuperGenius/.github/workflows/cmake.yml`) — no Docker daemon inside the job container, and no `services:` usage anywhere in existing workflows; the Windows runner is self-hosted with no guaranteed Docker daemon (repo memory: Docker Desktop must be started on demand, ~10s to come up — a dev-machine workaround, not a CI strategy).
- Tests that need a **registered** s3d: s3d setup (`s3d login`) involves an indexer/approval flow — a live-internet setup dependency that cannot run in CI at all.
- Flaky timing assertions: s3d's upload-packing loop is background and time-dependent; fixed sleeps in tests are the classic flake generator (and the repo has prior art for deadline+condition polling instead).

**Why it happens:**
Most S3 SDK testing literature assumes MinIO in Docker on a hosted runner; neither assumption holds in this workspace.

**How to avoid:**
- **P5 (design rule):** Three-tier test strategy:
  1. **Hermetic, always-on (CI):** in-process/loopback **stub S3 server** (accepts SigV4 or unsigned paths the adapter uses; scripted responses: 200/404/500/503/garbage/truncated — the fault-injection matrix from Pitfall 2) + the memory-backed BlockStore from P1. Zero network egress. Bind `127.0.0.1` on an ephemeral port (`:0`) per the tokenprice stub precedent; teardown via posted-close + join, bounded delays only.
  2. **Local-binary, opt-in (`SGNS_S3_TEST_ENDPOINT` set):** spawn the **MinIO server binary** (single static Go binary — no Docker needed) as a child process on a loopback port for real-SDK/real-server semantics tests. Marked/labelled so CI without the binary skips them cleanly.
  3. **s3d, explicitly manual/dev-only (`SGNS_S3D_TEST_*` env):** full s3d roundtrip + durability-signal tests run on dev machines/VMs where s3d is installed and registered; CI never attempts them. Evidence (logs, stats snapshots) is committed per the repo's evidence-file convention instead.
- **P5:** All waiting is deadline+condition polling (poll s3d stats/uploads until pending drains, with timeout and diagnostics dump on timeout) — never `sleep(fixed)`. ctest `TIMEOUT` bounds on every S3-touching test (house precedent: Phase-18 fail-fast timeout bound).
- **P5:** Timing assertions assert *ordering and state*, not wall-clock durations (e.g., "coalesced fetch produced exactly one backend request" — countable, not timed).

**Warning signs:**
- Any test URL that isn't `127.0.0.1`/`localhost`.
- `docker` invocations in test scripts.
- `std::this_thread::sleep_for` in test bodies.
- CI logs showing skipped-but-passing counts nobody set out to allow (make skips loud and labelled).

**Phase to address:** P5 (entire tiered strategy), with P1's memory-backend enabling tier 1 from day one.

---

### Pitfall 11: Credentials in config files (and the s3d setup secret sprawl)

**What goes wrong:**
S3 access/secret keys land in the main SuperGenius YAML config or in committed test fixtures; s3d's own setup multiplies the surface (`s3d keys create` prints the secret once; keys live in s3d's SQLite; `%APPDATA%/s3d/s3d.yml` holds admin password; the 12-word recovery phrase is the master secret for everything ever stored). One leaked config file = archive read/write compromise; one lost recovery phrase = entire archive unreadable despite slabs being safe on Sia.

**Why it happens:**
It's the path of least resistance during development ("just put the test keys in the config to get the slice running"), and s3d's interactive setup encourages ad-hoc secret placement.

**How to avoid:**
- **P1/P3 (design rule, from the architecture doc):** credentials come from environment variables, protected secret files with restricted permissions, or a secret manager — the main config file may reference *where* they are, never contain them. Config schema enforces this from the first commit (no `secret_key:` field exists to be misused; only `secret_key_file:` / env var name).
- **P5:** Test fixtures generate ephemeral keypairs at setup (MinIO supports programmatic user creation; for s3d, dev-runbooks script `s3d users create` + `keys create` with output to a 0600 temp file). `.gitignore` covers any local secret paths; example configs ship with placeholder + comment, never working keys.
- **P4:** Operational docs state the backup triad for s3d: recovery phrase, s3d SQLite metadata, and SuperGenius's own config — and that losing the phrase makes Sia-side slabs permanently unreadable (client-side encryption). This is the answer to Open Question #12 for the slice: backup responsibility is documented, not automated.

**Warning signs:**
- Any 20+-char high-entropy string in a committed YAML.
- `adminPassword: change-me` surviving into a real deployment doc.
- Recovery phrase stored in the same directory/backups as the encrypted data it protects.

**Phase to address:** P1 (config schema), P3 (env/file loading), P4 (backup triad docs), P5 (ephemeral fixture keys).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Single `DurabilityLevel` (treat PUT ack as durable) | Simpler write path; tests pass instantly | Silent data-loss class bug under s3d staging loss | Never |
| In-memory durability state (no journal) | Less I/O, faster slice | Restart forgets pending uploads → unarchived blocks | Never for upload state; acceptable for pure cache stats |
| ETag-as-verification | Saves a hash pass | Wrong under s3d client-side encryption; CID is the only authority | Never |
| `Delete()`-shaped API on BlockStore | Familiar naming | Invites CRDT history/tombstone purge | Never; `EvictLocal` only, remote delete absent from v1 |
| ListObjects in operating path | Easy "what's in the store" debugging | O(keyspace) at millions of objects; breaks on SQLite scale | Tooling/tests only, never runtime |
| Hardcoded endpoint/region/path-style in tests | Quick first green | Relearns Pitfall 9 per test; config drift hides bugs | Never; config object injected everywhere |
| Skipping the pinned-version comment / floating minio-cpp `main` | Latest features | API churn under you (v1.0.0 renamed namespaces); docs/examples mismatch | Never; pin exact tag |
| Fixed-sleep waits for s3d upload drain | Simple test code | CI flakes; suite time balloons | Never; deadline+condition poll |
| Live-endpoint smoke tests in CI | "Real" coverage | Egress blocks, rate limits, non-reproducibility (proven by tokenprice diagnosis) | Never in CI; manual-only tier |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Sia s3d | Assuming PUT ack = durable; assuming GET success proves Sia transfer | DurabilityLevel enum; admin-API `/stats/uploads`+`/prometheus` polling for pending-drain; staging dir + SQLite treated as durability path; crash/loss tests |
| s3d addressing | Virtual-host style against IP/localhost; verifying TLS against its per-start self-signed cert | Path-style + plain HTTP on loopback (or reverse-proxy with real cert); `hostBases` only if virtual-host ever needed |
| s3d lifecycle | Leaking aborted multipart state | Plain PutObject for small blocks in the slice; `AbortIncompleteMultipartUpload` prefix rule if multipart ever used |
| s3d ops | Treating it as passive tape | Monitor admin API (upload rate, staging usage), Sia contracts/funding; `diskUsageLimit` and low balance inhibit eviction |
| minio-cpp | Assuming curl/libxml deps; coding against hosted doxygen; vcpkg into superbuild; prebuilt Windows bundle CRT mismatch | Deps are cpp-httplib/pugixml/inih (+existing openssl/zlib/json); pin tag, code against its README/examples; ExternalProject_Add integration; build from source on Windows or verify bundle CRT |
| minio-cpp client config | SDK cloud defaults (HTTPS, virtual-host, auto region) against local s3d | Explicit `path_style=true`, pinned region, plain-HTTP loopback, `tls_verify` honored |
| SigV4 | Ignoring clock skew between dev VM/CI runner and s3d host | Time-sync in test runbooks; map skew-class 403 to a distinct AuthFailure reason |
| SuperGenius CMake consumption | Ad-hoc include paths to build-tree outputs | Mirror the AsyncIOManager pattern: `find_package(<pkg> CONFIG REQUIRED)` + `<pkg>_INCLUDE_DIR` + `*_DIR` in `CommonBuildParameters.cmake`, consuming deployed trees |
| thirdparty superbuild | Missing `DEPENDS`/`BUILD_BYPRODUCTS`; building wrapper vcxproj; incremental links across header changes | Canonical ExternalProject wiring; inner-vcxproj rebuild + INSTALL + deployed-tree hash audit; `/t:Rebuild` dependents; marker byte-greps |
| RocksDB (existing local store) | Turning RocksDB into the remote-storage integration point (SST archive / remote FS) | RocksDB stays hot-state/local-index only; archive is the application-level BlockStore layer (architecture doc's core decision) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| One-HEAD-then-one-GET per block | Doubled latency per fetch at any scale | GET directly (CID already names the bytes; 404 is the miss signal); HEAD only for maintenance tooling | Immediately on remote tiers |
| Negative-cache absence (or caching transport failures) | Thundering re-fetch of known-missing CIDs — or worse, sticky false-misses | Brief TTL negative cache for authoritative NotFound only; coalescing (single-flight per CID) | First multi-peer retrieval storm |
| Unbounded retry storms (backend down) | Retry amplification across peers × backend | Bounded concurrency, exponential backoff, circuit breaker on the backend adapter (architecture doc's retry-storm risk) | First s3d outage under load |
| s3d SQLite metadata growth unmonitored | Slower lists/recovery, surprise backup times | Record SQLite size in slice evidence; scale-probe test (10⁵–10⁶ objects, dev-only) | ~10⁶ objects |
| ListObjects anywhere in the read path | Multi-second reads; provider request-cost spikes | Interface forbids List (Get/Put/Has only); manifests for enumeration | ~10⁵–10⁶ objects |
| Staging-dir (diskUsageLimit) exhaustion under burst writes | PUTs start failing mid-burst, classed as errors-or-worse as NotFound | Backpressure: treat staging-full as Unavailable; monitor via admin stats; rate-limit uploads | Default 10 GiB staging, sustained ingest |
| In-place local cache writes (no temp+rename) | Torn reads under concurrent access; corruption after crash | Temp file + fsync + atomic rename; verify-before-publish | First crash or first concurrent reader |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Access/secret keys or s3d recovery phrase in committed config/fixtures | Full archive read/write compromise; phrase leak defeats client-side encryption | Env vars / 0600 secret files referenced by config; ephemeral test keys; `.gitignore`; placeholder-only examples |
| `tls_verify=false` escaping dev into defaults | MITM on the archive path in deployments | Loopback tests use plain HTTP explicitly; verification on by default for any non-loopback endpoint; s3d production TLS via reverse proxy with real cert |
| Admin API (s3d :8001) exposed or password left as `change-me` | Upload-pipeline tampering/metadata leak | Admin bind stays on localhost in runbooks; strong password in secret store; never port-forwarded in docs |
| Physical S3 keys derived from app paths | Access-control confusion (Open Question #8) | Keys are CID-derived; authorization lives in the namespace layer, never the key layout — document in adapter header |
| Secrets in CI logs (env-echo, `set -x` in runbooks) | Credential leak into artifact logs | Repo CI patterns for secrets (`GNUS_TOKEN_1` style masked env); no credential echo in test diagnostics dumps |

## Phase-Specific Warnings (vertical slice)

| Phase | Likely Pitfall | Mitigation (test / design rule / build guard) |
|-------|---------------|-----------------------------------------------|
| P1 Abstraction | Error taxonomy collapses transport+absence; `Delete`-shaped API; durability levels fudged into one | Taxonomy + `DurabilityLevel` + `EvictLocal`-only + no-`List` frozen in the interface before any backend; memory-backend unit tests assert each error class |
| P2 Local store | In-place writes; no upload journal; local reads unverified | Temp+fsync+rename; durable intent journal; verify-on-read + corruption self-heal test; startup temp-sweep test |
| P3 S3 adapter (MinIO SDK) | Wrong dep model; floating version; vcpkg leakage; CRT mismatch; wrapper-vcxproj/incremental-link traps; SDK cloud defaults vs loopback s3d | Pin tag + ExternalProject integration + deployed-tree audits + `/t:Rebuild` + marker byte-greps; explicit path-style/region/tls config surface; stub-server wire-level asserts |
| P4 s3d integration | PUT ack read as durable; staging/SQLite not in durability path; self-signed TLS verified; listing used for discovery | Admin-API durability polling; staging-full → Unavailable; loopback HTTP; CID-keyed layout, no List; record measurement evidence (throughput, SQLite size, staging usage) |
| P5 Testing | Live endpoints / Docker-in-CI assumed; registered-s3d setup in CI; fixed-sleep flakes | Three-tier strategy (hermetic stub always; MinIO-binary opt-in; s3d dev-only with committed evidence); deadline+condition polling; loud labelled skips; ctest timeouts |

## Open Verification Items (carried to planner)

1. **Exact s3d durability-signal field semantics** (Open Question #5): admin `/stats/uploads` / `/prometheus` existence verified today (HIGH); the precise metric(s) distinguishing "this object's group uploaded" vs "pending" must be read from the pinned version's `openapi.yml`/source in P4 — with a fallback design (accept-level-only, local copy pinned) if no per-object signal exists.
2. **minio-cpp BaseUrl config surface at the pinned tag** (path-style/HTTPS toggles, region pinning): README example verified; exact constructor/fields to be confirmed against the pinned tag's headers in P3 (the hosted doxygen is stale — do not use it).
3. **Prebuilt Windows bundle CRT linkage** (`/MD` vs `/MT`): must be checked with `dumpbin` if the bundle is used at all; superbuild-from-source sidesteps it.
4. **Whether s3d serves reads of still-staged objects with any distinguishing header** (would make durability detection cheaper than admin-API polling): check pinned s3d source in P4.

## Sources

- `supergenius-sharded-ipld-cache-architecture.md` — Key risks; CRDT correctness requirements; Write and durability path; Sia s3d as the first backend; CARv2 "measure first"; Open design questions #5/#8/#11/#12/#13; example runtime configuration (credentials rule) — confidence HIGH (in-repo, authoritative)
- Sia s3d README @ master (v0.2.1, fetched 2026-10-19): staging + bin-packing + background upload; SQLite metadata; `diskUsageLimit` 10 GiB default; admin API :8001 `/stats/uploads` `/prometheus`; SigV4-only, path-style + virtual-host (`hostBases`), self-signed per-start HTTPS cert; multipart limits; conditional writes — confidence HIGH
- minio-cpp README @ v1.0.0 (fetched 2026-10-19): C++17/CMake, vcpkg default flow, Alpine/pkg-config source fallback (deps: cpp-httplib, openssl, pugixml, zlib, inih, nlohmann-json), prebuilt bundles incl. windows-amd64, recent Windows large-file/binary-download fixes — confidence HIGH; hosted doxygen site showing stale pre-1.0 API — confidence HIGH (observed directly)
- Workspace planning history (confidence HIGH, in-repo): `.planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-RESEARCH.md` (Pitfalls 1–10: wrapper trap, ABI split, no-dependent-rebuild, incremental-link skip, binary grep, disk budget, staging sweep, ctest regex); `tokenprice/phases/02-*/02-RESEARCH.md` (inner-vcxproj surgical sequence, AsyncIOManager consumption pattern, submodule/branch discipline, hermetic loopback stub pattern); `tokenprice/quick/261009-*` (Docker Desktop on-demand start — dev machine, not CI); tokenprice milestone context (CoinGecko CI egress blocking — live-endpoint prohibition rationale)
- `thirdparty/AGENTS.md` (ExternalProject_Add/DEPENDS/BUILD_BYPRODUCTS conventions, two-pass ninja note, minimal-change guidance) and `SuperGenius/.github/workflows/cmake.yml` (self-hosted runners; Linux jobs inside AlmaLinux containers; RUN_TESTS matrix; no `services:` usage) — confidence HIGH (in-repo, read today)
- Repo memories (via in-repo quotes; originals at `/memories/repo/` not directly readable this session): thirdparty-inner-vcxproj-rebuild.md, msbuild-incremental-link-skip.md, mnn-wholearchive-vulkan.md, w-drive-disk-full.md, gsd-windows-crlf.md, windows-ci-docker-desktop.md, supergenius-pubsub-testing.md — confidence HIGH for content quoted into planning artifacts, MEDIUM for any nuance not captured in quotes
