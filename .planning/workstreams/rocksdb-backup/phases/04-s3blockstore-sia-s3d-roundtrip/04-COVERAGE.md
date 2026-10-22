# Phase 4 API Coverage Matrix — Sia s3d v0.2.1 (S3 API + Admin API) & MinIO S3 Surface

**Produced by:** gsd-planner (api-coverage contribution — detector fired: phase integrates external services)
**Date:** 2026-10-21
**Scope:** the external API surface reachable by this phase's code and sessions, enumerated from the pinned s3d v0.2.1 tag's `openapi.yml` + README compatibility matrix (captured verbatim in 04-RESEARCH.md Code Examples / Pattern 6) and the frozen 5-op S3Client adapter (Phase 3, 03 CONTEXT).

**Decision vocabulary:** `INTEGRATE` = this phase exercises or carries the capability deliberately. `OPT-OUT` = deliberately not exercised/carried; every opt-out carries a one-line reason (mandatory). Default is INTEGRATE.

**Structural constraint (frozen upstream of this phase):** the `S3Client` adapter surface is frozen at 5 ops (put/get/head/delete + config — BACK-05, 03 CONTEXT). Opt-outs at the STORE level (capabilities the adapter does not even expose to `S3BlockStore`) are legitimate rows: the store composes only what the BlockStore contract needs.

## S3 API surface (s3d :8000 / MinIO — same adapter path)

| # | Capability | s3d v0.2.1 status | Decision | Where exercised | Reason (mandatory for OPT-OUT) |
|---|------------|-------------------|----------|-----------------|--------------------------------|
| 1 | PutObject — incl. `If-None-Match: *` conditional create-only | Supported (conditional ops since 0.1.3; atomic with the write — `s3/preconditions.go` source-verified) | **INTEGRATE** | 04-01 store Put (always createOnly) + conformance; 04-02 spike trio item 1 (live 412 shape); 04-03 MinIO roundtrip + E2E run A | — |
| 2 | GetObject | Supported | **INTEGRATE** | 04-01 store Get (verify-on-read, Corrupt+Remote); 04-02 staged-read capture; 04-03 roundtrip + E2E run B | — |
| 3 | HeadObject | Supported (compat matrix ✓) | **INTEGRATE** | 04-01 Has/GetSize mapping; 04-02 spike trio item 2 (missing-key classification); 04-03 key-layout observability | — |
| 4 | DeleteObject | Supported | **INTEGRATE (adapter-internal only)** — **OPT-OUT at the BlockStore store level** | Adapter 5-op surface (03, frozen); store-level opt-out enforced by `!HasDelete<S3BlockStore>` guard (04-01) | CORE-05: nothing in the BlockStore API can remove remote blocks or CRDT history; Delete is tooling/audit-only behind the adapter seam (03 D-03; promotion reconciliation documented in the promoted header banner, 04-01) |
| 5 | CopyObject | Honors If-Match/If-None-Match (per README) | **OPT-OUT** | — | No consumer: blocks are immutable and re-put via conditional PutObject (alreadyPresent path); copy adds nothing for content-addressed data |
| 6 | Multipart upload (CreateMultipartUpload / UploadPart / CompleteMultipartUpload) | Supported (conditions evaluated at Complete) | **OPT-OUT** | — | Blocks are single-shot immutable payloads (block sizes, not streamed files); multipart is not in the frozen 5-op adapter and no store path needs it — re-added additively at the adapter if a future consumer appears |
| 7 | Bucket lifecycle (CreateBucket / ListBuckets / DeleteBucket / policies) | Supported | **OPT-OUT (library level)** — bucket provisioning is a caller/test-fixture concern | Test fixtures only: `MinioServerHarness::MakeBucket` (Phase 3, unchanged); dev provisions the s3d bucket (04-02 user_setup) | The library targets a pre-provisioned bucket via `S3ClientConfig.bucket`; bucket management is operator/tooling scope, not BlockStore scope |
| 8 | Listing (ListObjectsV2 / ListMultipartUploads) | Supported | **OPT-OUT** | — | CORE-06: the core interface is List-free; enumeration exists only on the local tooling surface (`GetPendingUploads` — the pending journal, not remote listing); remote listing returns as tooling if an audit need is ever specified |
| 9 | Presigned URLs / POST-policy uploads | SigV4 signing supported | **OPT-OUT** | — | No consumer: the adapter is a direct SigV4 client (static keys, env-provided in dev tiers); presigning a read/write capability out of the library contradicts the no-delete/verify-on-read posture until a spec exists |
| 10 | Object versioning / delete markers | Not relied on | **OPT-OUT** | — | Immutability is enforced by create-only conditional writes (capability 1), not by versioning; s3d's delete-marker semantics are out of the BlockStore model entirely |
| 11 | GetBucketLocation / region discovery | Supported (SDK-internal) | **OPT-OUT** | — | Region pinned us-east-1 in `S3ClientConfig` (03 D-11 BaseUrl discipline: pinned region avoids the discovery roundtrip); nothing to integrate |
| 12 | Remaining object ops (AppendObject, SelectObjectContent, tagging, ACLs…) | Partial per compat matrix | **OPT-OUT** | — | Not in the frozen 5-op adapter surface; no BlockStore semantics map onto them |

## Admin API surface (s3d :8001 — HTTP Basic, loopback default)

| # | Capability | Decision | Where exercised | Reason (mandatory for OPT-OUT) |
|---|------------|----------|-----------------|--------------------------------|
| A1 | `GET /stats/uploads` (UploadStats/TransferStats/ActiveUpload) | **INTEGRATE** | 04-02 spike + finding doc (curl-only evidence; 04-03 session enrichment) — S3D-03's characterization source | — |
| A2 | `POST /objects/flush` (blocking staged→Sia upload + pin) | **INTEGRATE** | 04-02 evidence sequence (before-put/after-put/after-flush triple); 04-03 optional closure capture — the finding doc's positive mechanism | — |
| A3 | All other admin endpoints (`/stats/*` others, `/objects` admin CRUD, `/accounts`, `/users`, `/keys`, `/system/*` incl. `/snapshots`, `/slabs`, `/contract`…) | **OPT-OUT** | — | No library or evidence need this phase: S3D-03's question is answered by A1/A2 + openapi.yml; zero C++ admin client ships (curl-only per D-13 mechanics); account/user/key management is dev-owned CLI work (04-02 user_setup), not API integration |

## Auth surfaces

| # | Capability | Decision | Where exercised | Reason (mandatory for OPT-OUT) |
|---|------------|----------|-----------------|--------------------------------|
| S1 | SigV4 static keys (S3 API) | **INTEGRATE** | All live tiers via `S3ClientConfig` (env-only credentials, never committed) | — |
| S2 | Admin HTTP Basic (username ignored, adminPassword) | **INTEGRATE** (session-only) | 04-02/04-03 curl captures; env-only credential | — |
| S3 | TLS transport (s3d self-signed per start) | **OPT-OUT (test lanes)** | Plain-HTTP loopback lanes; `tlsVerify` stays default-true | Never TLS-verify against s3d's per-start self-signed cert (research landmine); TLS posture itself is proven at the MinIO tier (Phase 3 G-3-1) and the config surface carries useTls for real deployments |

## Seal gate

`check api-coverage.verify-pre` reads this matrix at phase completion: every row above carries an explicit decision; the matrix is decided BEFORE plans finalize (this file) and executors reference it — 04-02/04-03 tasks must not expand the exercised surface beyond the INTEGRATE rows without appending a decided row here first.
