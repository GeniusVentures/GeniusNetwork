# Phase 5: Fault Injection & Three-Tier Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-22
**Phase:** 5-Fault Injection & Three-Tier Hardening
**Areas discussed:** Crash-injection realism, Fault-matrix breadth, Corruption injection mechanics, Tier inspectability (SC3)

---

## Gray-Area Selection

All four identified gray areas were selected for discussion (multiSelect).

**Todo cross-reference:** "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" matched on generic keyword "crash" (score 0.2) — skipped, same disposition as Phases 1–4; stays with base SuperGenius planning.

---

## Crash-injection realism

| Option | Description | Selected |
|--------|-------------|----------|
| In-process only | Extend the proven Phase-2 FaultController seam: inject fault → close-without-clean-shutdown → reopen → WAL recovery is real. Deterministic, portable, no child-process machinery. | ✓ |
| Subprocess kills | Real kill-9 of a child process mid-operation on all desktop platforms. Ground-truth realism, but Windows child-process + kill signaling was the exact portability cost Phase 2 rejected. | |
| Hybrid + smoke | In-process covers the full matrix; ONE dev-gated subprocess-kill smoke (e.g. Linux/dev lane only) proves WAL recovery survives real process death once. | |

**User's choice:** In-process only
**Notes:** Closes Phase-2 D-07's explicitly-defered "Phase 5 may add subprocess kills" door.

| Option | Description | Selected |
|--------|-------------|----------|
| Reinterpret + document | Interrupted local write = crash-before-WAL-commit → NOTHING visible. Three SC2 windows → four real states (pre-commit, pending, uploaded-but-unmarked). | ✓ |
| Literal temp files | Build temp-file machinery so a mid-temp-write kill exists. Contradicts Phase-2 D-02 vacuous-by-design. | |
| Planner decides | Leave window mapping to /gsd-plan-phase preserving D-02 atomicity. | |

**User's choice:** Reinterpret + document

| Option | Description | Selected |
|--------|-------------|----------|
| All four states | Pre-commit, pending, uploaded-but-unmarked (reopen → re-drain → alreadyPresent → Accepted — the idempotent re-put payoff), accepted. | ✓ |
| SC3 minimal three | Just the three SC2-letter windows; skip uploaded-but-unmarked. | |

**User's choice:** All four states

| Option | Description | Selected |
|--------|-------------|----------|
| Hermetic fake only | InMemoryS3Client scripts remote-present/absent deterministically; crash tests stay Tier-1, CI everywhere. | ✓ |
| Fake + MinIO case | Also one opt-in MinIO-binary crash case (Tier 2). | |
| Fake + s3d replay | Hermetic matrix plus dev-gated s3d replay against live Sia. | |

**User's choice:** Hermetic fake only

---

## Fault-matrix breadth

| Option | Description | Selected |
|--------|-------------|----------|
| Full stack | Stub→MinioS3Client taxonomy + S3BlockStore over faulting fake + drainer-under-fault (partial uploads, per-item continue, re-drain retries pending). | ✓ |
| Adapter + store | Stub matrix + store-over-fake; drainer faults left to crash windows only. | |
| SC1 letter only | Loopback-stub faults at MinioS3Client; store/drainer stay as covered by Phases 3-4. | |

**User's choice:** Full stack

| Option | Description | Selected |
|--------|-------------|----------|
| Per-case recovery | Every fault case ENDS with a good-fetch-succeeds assertion in the same test. | ✓ |
| One recovery test | Single dedicated recovery test after the whole fault sequence. | |
| Planner decides | Only requirement: SC1's clause provably covered. | |

**User's choice:** Per-case recovery

| Option | Description | Selected |
|--------|-------------|----------|
| Split by generality | Backend-generic fault cases extend the kit's FaultController section; transport-specific (stub/HTTP) and drainer suites stay standalone. | ✓ |
| All standalone | Entire Phase-5 matrix in standalone targets; kit untouched. | |
| All in kit | Everything as a fault-conformance macro section per backend — stub/drainer cases aren't backend-generic. | |

**User's choice:** Split by generality

| Option | Description | Selected |
|--------|-------------|----------|
| Split by layer | Framing broken mid-read → adapter → TemporarilyUnavailable. Complete-but-wrong-length body → store CID-verify → Corrupt with remote attribution. | ✓ |
| All TempUnavailable | Any truncation at any layer → TemporarilyUnavailable. | |
| Spike it first | Research exact cpp-httplib/minio-cpp truncation behaviors at the pinned tag before deciding. | |

**User's choice:** Split by layer

---

## Corruption injection mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| FaultController hook | Corrupt-after-commit point: post-WriteBatch internal byte flip. API-only tests, no internals coupling, portable. | ✓ |
| Direct RocksDB | Second raw rocksdb::DB handle writes flipped bytes. Real bit-rot ground truth but couples tests to CF naming. | |
| Hook + one disk case | Hook drives matrix; one direct-disk case proves real on-disk corruption reaches the same outcome. | |

**User's choice:** FaultController hook

| Option | Description | Selected |
|--------|-------------|----------|
| Fake scripting only | InMemoryS3Client Get returns flipped bytes → Corrupt, remote attribution. | ✓ |
| Stub wrong-body too | LoopbackHttpStub serves valid 200 with wrong body against real MinioS3Client. | |
| Fake + stub case | Fake drives store-level matrix; stub adds one transport-boundary wrong-body case. | |

**User's choice:** Fake scripting only

| Option | Description | Selected |
|--------|-------------|----------|
| Re-fetch every Get | Every Get re-fetches + re-reports Corrupt; no bad-byte caching; repaired remote → next fetch succeeds. | ✓ |
| Journal-mark bad | Remember remote-corrupt state so repeated Gets short-circuit — machinery D-09 never designed for remote. | |

**User's choice:** Re-fetch every Get

| Option | Description | Selected |
|--------|-------------|----------|
| Get-path + doc note | Corruption proof rides Get; Has/GetSize documented as NOT content-verifying. | ✓ |
| Assert blind spot too | Additionally assert Has/GetSize stay blind to flipped bytes in tests. | |

**User's choice:** Get-path + doc note

---

## Tier inspectability (SC3)

| Option | Description | Selected |
|--------|-------------|----------|
| CTest labels + lane | LABELS Tier1/2/3 per test; CI ctest restricted to Tier1. Readable from CMake + CI workflow. | ✓ |
| Targets per tier | Separate test targets/directories per tier; CI runs only Tier1 set. | |
| Env-gates + docs | Gating as-is; inspectability via documentation alone. | |

**User's choice:** CTest labels + lane

| Option | Description | Selected |
|--------|-------------|----------|
| Audit as ctest test | Static audit (no fixed sleeps, no non-loopback hosts in Tier-1) IS a Tier-1 test — self-inspecting, runs everywhere ctest runs. | ✓ |
| CI step only | Audit as a separate CI workflow step outside ctest. | |
| Convention only | PR-review enforcement, no automated audit. | |

**User's choice:** Audit as ctest test

| Option | Description | Selected |
|--------|-------------|----------|
| Skip meta-test | Tier-1 meta-test runs gated binaries with clean env, asserts loud SKIP. | |
| No meta-test | Rely on proven env-gate + loud-skip; labels + audits carry inspectability. Leaner. | ✓ |

**User's choice:** No meta-test

| Option | Description | Selected |
|--------|-------------|----------|
| In-repo doc | docs/testing-tiers.md in sgns-blockstore: test × tier × gate env × evidence; referenced from README. | ✓ |
| CMake comments | Tier inventory as structured comments atop test/CMakeLists.txt. | |
| Workspace doc | GeniusNetwork-root-level doc under .planning or docs/. | |

**User's choice:** In-repo doc

| Option | Description | Selected |
|--------|-------------|----------|
| Existing evidence | Phase-4 artifacts (docs/evidence/s3d-spike/, run logs) satisfy SC3 Tier-3 clause; no re-run. | ✓ |
| Refresh once | Re-run s3d E2E after hardening, refresh committed evidence. | |

**User's choice:** Existing evidence

---

## the agent's Discretion

- FaultController hook naming/granularity (corrupt-after-commit fault-point shape)
- Stub fault-case enumeration beyond SC1's four classes (exact 5xx codes, garbage shapes, truncation offsets)
- Audit-test implementation mechanics (grep patterns, allowlist, placement)
- CI workflow edits and exact ctest invocation form (coordinate with SuperGenius CI conventions)
- Kit fault-section macro naming/extensibility mechanics
- Test file naming/layout in test/ beyond existing conventions
- Exact label strings and Tier-2/3 label × env-gate interaction
- Accepted-state assertion mechanism (journal state reader vs drain idempotency vs both)
- docs/testing-tiers.md exact format and README reference wording
- Four-state window-model documentation location (test-file header vs doc)

## Deferred Ideas

- Subprocess-kill crash tests — rejected (D-01); revisit only as additive dev-gated smoke in a future milestone
- MinIO-binary (Tier-2) and s3d (Tier-3) crash-window replays — rejected (D-04); hermetic fake carries the proof
- Durability-signal polling, MarkUploadedDurable automated wiring, TieredBlockStore/retrieval tiering, metrics surface — unchanged REQUIREMENTS Future list
