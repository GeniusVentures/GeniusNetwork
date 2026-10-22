# Phase 3: minio-cpp Integration & S3Client Adapter - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-21
**Phase:** 3-minio-cpp Integration & S3Client Adapter
**Areas discussed:** Conditional-PUT in adapter, SC4 live-endpoint proof, Entrance-criterion fallback, Dep-bundling mechanics

---

## Conditional-PUT in adapter

| Option | Description | Selected |
|--------|-------------|----------|
| Precondition option on Put | Put options carry createOnly=true; adapter sends If-None-Match:*; Phase 4 flips the flag; one Put op, no HTTP-isms | ✓ |
| Separate PutIfAbsent op | Distinct ~6th op; clearer call sites but splits the put path — fake and MinioS3Client implement two ops | |
| Raw-headers escape hatch | Generic header-bag parameter; leaks raw HTTP/S3 semantics past the adapter boundary | |

**User's choice:** Precondition option on Put

| Option | Description | Selected |
|--------|-------------|----------|
| Success slot + alreadyPresent | Mirrors frozen D-04 PutOutcome; Phase-4 SC2 maps 1:1 with zero re-freeze | ✓ |
| Dedicated failure class | AlreadyExists-style adapter failure; forces failure→success translation at the BlockStore layer | |
| Passthrough error code | Raw S3 error code in result; SDK-isms leak past the adapter | |

**User's choice:** Success slot + alreadyPresent

| Option | Description | Selected |
|--------|-------------|----------|
| Stateful + precondition + faults | Stateful object map, createOnly enforcement, injectable per-op fault responses; covers SC3 and seeds Phase 5 | ✓ |
| Stateful + precondition only | No fault scripting yet; Phase 5 retrofits a frozen fixture | |
| Minimal map | keys→bytes, 404 on miss; SC3 error paths and Phase-4 conformance retrofit onto it | |

**User's choice:** Stateful + precondition + faults

| Option | Description | Selected |
|--------|-------------|----------|
| Internal adapter op | delete proven via fake tests; guard tests keep BlockStore delete-free; BACK-05 names it | ✓ |
| Drop delete from v1 | ~4 ops; needs a BACK-05 amendment | |
| Tooling seam only | delete on a separate tooling interface mirroring CORE-06 | |

**User's choice:** Internal adapter op

---

## SC4 live-endpoint proof

| Option | Description | Selected |
|--------|-------------|----------|
| MinIO-binary harness now | Env-gated MinIO-server child-process harness lands in Phase 3 (C2: binary, no Docker); SC4 proven in-phase; Phase 4 reuses | ✓ |
| Loopback stub only | Stub covers mapping now; real-endpoint roundtrip defers to Phase 4 — SC4 splits across phases | |
| Dev-manual evidence | Committed dev-machine log, never CI; weakest repeatability | |

**User's choice:** MinIO-binary harness now

| Option | Description | Selected |
|--------|-------------|----------|
| Opt-in only | Env-gated, never default CI lane; TEST-01 Tier-2 discipline; loud labelled skip | ✓ |
| Default CI lane | Contradicts TEST-01's "Tier 2 opt-in"; adds a server process to every CI run | |
| Opt-in + one CI job | A dedicated Linux CI job always opts in for continuous SC4 evidence | |

**User's choice:** Opt-in only

| Option | Description | Selected |
|--------|-------------|----------|
| Stub-driven mapping tests | Loopback stub serves scripted 5xx/garbage/truncated/refused at MinioS3Client; deterministic taxonomy assertions; Phase-5 seed | ✓ |
| MinIO-derived only | Stop/kill the child server; can't produce garbage/truncated deterministically | |
| Fake-level only | Fake implements the same interface — MinioS3Client mapping paths never exercised; does not satisfy SC4 | |

**User's choice:** Stub-driven mapping tests

| Option | Description | Selected |
|--------|-------------|----------|
| Env-pointed, loud skip | Env var points at pre-installed binary; loud skip when unset; zero network at test time | ✓ |
| Auto-download pinned | Harness downloads pinned minio at setup; adds network dependency to test setup | |
| Exclude Windows | Linux/macOS only; primary dev platform left without SC4 evidence | |

**User's choice:** Env-pointed, loud skip

---

## Entrance-criterion fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Patch exposes it | Hermeticity patch additionally exposes conditional headers; keeps pin + no-fork; deepest divergence | |
| Re-pin newer tag | Fresh API surface + dep-set re-verification | |
| Drop conditional | Breaks Phase-4 SC2 and BACK-07's conditional create-only wording | |
| USER FREEFORM | No pre-committed contingency — fork-and-fix acceptable if a feature is genuinely missing, decided at failure time | ✓ |

**User's choice:** USER FREEFORM — "If minio-cpp lacks a feature we need, we probably decide to fork it and make the changes at that point? Why is this even being brought up, do we expect it to happen?"
**Notes:** Answered the premise directly: no — research rates failure probability LOW (README-verified feature; headers never compiled against; hosted doxygen stale). The day-one spike is cheap insurance. BUILD-02's "no fork" remains the default integration mechanism, not a never-fork pledge.

| Option | Description | Selected |
|--------|-------------|----------|
| Day-one spike | Inside first Phase-3 plan; Phase-1 C1 discipline | ✓ |
| After build wiring | Later discovery risks wasted build plumbing | |
| Research-phase only | Read-only research can't answer a compile/link question | |

**User's choice:** Day-one spike

| Option | Description | Selected |
|--------|-------------|----------|
| Full trio | Conditional headers + BaseUrl config fields + TLS on/off smoke | ✓ |
| Headers only | Conditional headers; BaseUrl/TLS verified incidentally later | |

**User's choice:** Full trio

| Option | Description | Selected |
|--------|-------------|----------|
| Committed patch set | Patch files with purpose notes, divergence reviewed at phase close | |
| Feature-detect config | Compile probe choosing between two product variants; doubles test matrix | |
| Ad hoc | Divergence only discoverable by diffing upstream | |
| USER FREEFORM | "See previous answer" — no heavy process; minimal-diff norm, decide-as-needed | ✓ |

**User's choice:** USER FREEFORM — minimal-diff norm; mechanics left to planning/research

---

## Dep-bundling mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch script + pin file | GNUS-owned script in PATCH_COMMAND, shaderc git-sync-deps mirror | |
| FetchContent tarballs | Pinned release-tarball URLs; no git but HTTP at configure | |
| Pre-seeded cache | Builder provides sources; hard error if absent | |
| USER FREEFORM | Upstream's miniocpp-deps.cmake mechanism as-is — "they already have a syncing mechanism. I don't see a problem with this." | ✓ |

**User's choice:** USER FREEFORM — minio-cpp's own mechanism fetches/builds deps inside the ExternalProject step; no GNUS script/pins/patch pre-committed. Matches BUILD-02's primary formulation.
**Notes:** Research SUMMARY's GNUS-fork-of-inih and hermeticity-patch recommendations are superseded by this decision — intervene only on concrete failure discovered by research/spike.

| Option | Description | Selected |
|--------|-------------|----------|
| Inject CMakeLists | Fetch script writes minimal CMakeLists into inih tree | |
| Meson in-step | Adds meson+ninja to every platform incl. Windows/MSVC | |
| GNUS overlay tree | Effectively the fork/separate-submodule approach BUILD-02 rules out | |
| USER FREEFORM | "Won't the cmake for minio-cpp build all this?" — upstream owns building its deps | ✓ |

**User's choice:** USER FREEFORM — upstream mechanism owns inih's build; concrete MSVC buildability is a research/spike question

| Option | Description | Selected |
|--------|-------------|----------|
| thirdparty/build/ | Script + pins beside CommonTargets.cmake; upstream checkout pristine | |
| Inside minio-cpp tree | GNUS files inside an upstream-tag checkout | |
| Dedicated repo | Another moving piece | |
| USER FREEFORM | "Nowhere" — no GNUS fetch script or pin file exists under this decision | ✓ |

**User's choice:** USER FREEFORM — Nowhere

| Option | Description | Selected |
|--------|-------------|----------|
| Internal now, install in P4 | S3Client interface in src/, not installed; promoted with Phase 4's S3BlockStore | ✓ |
| Install interface now | SDK-free interface headers installed immediately; SC2 check polices real headers | |

**User's choice:** Internal now, install in P4

---

## the agent's Discretion

- `S3ClientConfig` field set beyond the research-listed surface (endpoint, path-style, region, https, tls-verify)
- Adapter result-type mechanics (library-local `policy::terminate` alias mandatory; no SDK types)
- Loopback stub implementation (raw sockets vs in-tree cpp-httplib server)
- Harness env-var names, child-process lifecycle, port/temp-dir management
- `MinioS3Client` threading/execution model
- Per-platform CI evidence details for SC1
- Any minimal patch to minio-cpp if upstream's mechanism concretely breaks (minimal-diff norm)

## Deferred Ideas

None — discussion stayed within phase scope.
