# Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-22
**Phase:** 6-sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory
**Areas discussed:** Widening scope (LIB-01), CidOf API shape, OpenMinioS3Client contract (LIB-02), Out-of-tree proof + config timing

---

## Gray-area selection + todo cross-reference

All 4 presented gray areas were selected for discussion. One todo matched by keywords only (`2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`, area: testing, score 0.6) — user ruled it unrelated; reviewed, not folded, stays backlog.

## Widening scope (LIB-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Exact pair | Gate accepts exactly sha256 + blake2b-256; verification explicitly branches on both; matches D-08 additive posture | ✓ |
| Allowlist constant | Compile-time accepted-set constant that gates and conformance iterate — structurally a pair today | |
| General multihash | Accept any HashType; needs generic hash-by-type dispatch (libp2p may not expose one) | |

**User's choice:** Exact pair
**Notes:** STATE.md flagged this as THE entrance decision. SuperGenius CRDT produces exactly one new shape (CIDv1/DAG_CBOR/blake2b-256).

### Vector provenance (SC1)

| Option | Description | Selected |
|--------|-------------|----------|
| Independent + cross-check | Pin independently-derived literals (RFC 7693 / IPLD DAG_CBOR fixtures) AND commit one getCidOf cross-check dev-run artifact | ✓ |
| Independent only | Pin independently-derived literals only; compatibility with getCidOf implicitly trusted | |
| getCidOf-derived | Generate vectors from real getCidOf output — proves consumer compatibility but not independent | |

**User's choice:** Independent + cross-check
**Notes:** No library→SuperGenius dependency — the cross-check is committed evidence, not a linked test.

### Still-unsupported hash posture

| Option | Description | Selected |
|--------|-------------|----------|
| Keep throw-at-entry | std::invalid_argument at API entry unchanged; rejection guard tests re-target a still-out-of-set hash | ✓ |
| Result-envelope it | Convert rejection to BlockStatus failure — conflicts with SC3 no-break bar | |
| You decide details | Planner picks exemplar hash and rewrite mechanics; throw posture stays | |

**User's choice:** Keep throw-at-entry

## CidOf API shape

| Option | Description | Selected |
|--------|-------------|----------|
| 3-arg overload | CidOf(bytes, codec, HashType) — new symbol; existing 2-arg signature literally untouched | ✓ |
| Defaulted 3rd param | Single declaration gains HashType = sha256 default — touches the frozen signature | |
| Named helper | CidOfBlake2b(bytes, codec) — parallel name, wider installed surface | |

**User's choice:** 3-arg overload

## OpenMinioS3Client contract (LIB-02)

### Return type

| Option | Description | Selected |
|--------|-------------|----------|
| result + shared_ptr | result<std::shared_ptr<S3Client>, BlockStatus> — envelope-consistent, SDK-free, injects straight into S3BlockStore::Open | ✓ |
| result + unique_ptr | Mirrors internal MinioS3Client::Open exactly; consumer converts at injection | |
| Bare ptr + throw | Bare shared_ptr + invalid_argument throw on bad config — departs from Open conventions | |

**User's choice:** result + shared_ptr

### Construction-time behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Eager validate, no I/O | Validate config eagerly; zero network I/O at construction; connection failures surface later via op taxonomy | ✓ |
| Pure lazy | Validate nothing; every error surfaces at first op — far from cause | |
| Validate + probe | Eager validation + blocking connectivity probe — adds I/O/latency, awkward failure mode | |

**User's choice:** Eager validate, no I/O
**Notes:** BaseUrl-snapshot landmine (Phase 3): port/virtual-style must be right before client init — eager validation catches bad config at the call site.

## Out-of-tree proof + config timing

### config.cmake.in hardening timing

| Option | Description | Selected |
|--------|-------------|----------|
| Prove first, harden as forced | SC4 consumer proof first; harden config.cmake.in exactly as far as the proof forces; rest defers to Phase 7 | ✓ |
| Harden fully now | Commit to full find_dependency hardening in 06-02 up front | |
| Defer all to Phase 7 | Minimal config now; accept SC4-may-pass-while-consumers-churn risk | |

**User's choice:** Prove first, harden as forced
**Notes:** Evidence-driven — matches the user's Phase-3 D-10/D-05 no-pre-committed-contingency posture.

### Proof mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| Tier-1 ctest consumer | Standalone CMake project under test/ consuming the install tree, hermetic compile+link+construct, fail-closed lane | ✓ |
| CI script check | Script outside ctest — escapes tier discipline | |
| Opt-in tier | Gated like MinIO Tier-2 — unnecessary, proof needs no network | |

**User's choice:** Tier-1 ctest consumer

## the agent's Discretion

- Guard-test exemplar hash choice + rewrite mechanics
- blake2b implementation entry point (libp2p crypto API at the pinned tree) — evidence-based contingency if missing
- Optional consolidation of the three throw-site checks into one shared validate helper
- Conformance vector-set composition beyond the SC1 letter
- Factory declaration placement/wording in S3Client.hpp
- Consumer project name/location/CMake mechanics under test/
- dag-cbor = one CodecToken() switch case; unknown-codec catch-all stays

## Deferred Ideas

- Vulkan capability-probe deadlock todo — reviewed, unrelated, stays backlog (see above)
