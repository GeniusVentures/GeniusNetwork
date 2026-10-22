# Phase 4: S3BlockStore & Sia s3d Roundtrip - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-21
**Phase:** 4-S3BlockStore & Sia s3d Roundtrip
**Areas discussed:** Composition scope, s3d entrance spike, s3d E2E evidence, Durability finding

---

## Composition scope

| Option | Description | Selected |
|--------|-------------|----------|
| Pure remote backend | S3BlockStore implements BlockStore over the adapter; journal interplay exercised only by tests; uploader/facade becomes future phase | |
| Backend + drainer | Additionally ship a small library component (e.g., PendingUploadDrainer): iterates pending set, Puts to S3BlockStore, marks Accepted | ✓ |
| Planner decides | Lock only what the SCs demand; leave the drainer question to gsd-planner | |

**User's choice:** Backend + drainer
**Notes:** Phase 2 built the journal transitions "for Phase 4's uploader"; that intent is honored in-phase.

| Option | Description | Selected |
|--------|-------------|----------|
| Public installed API | Drainer ships as an installed public header — consumers drive the actual spilling, so the upload path is first-class (03 D-04 precedent) | ✓ |
| Tooling interface | Drainer lands next to pending-set enumeration (BlockStoreTooling.hpp family) | |
| Method on type | Concrete method on a backend/composite type (EvictLocal-style placement) | |

**User's choice:** Public installed API

| Option | Description | Selected |
|--------|-------------|----------|
| Per-item, continue | Per-item outcome vector, keep going past failures; re-drain retries only still-pending; mirrors PutMany (01 D-14) | ✓ |
| Abort on first fail | Stop at first failed upload; simpler but one flaky object blocks the whole pending set | |

**User's choice:** Per-item, continue

| Option | Description | Selected |
|--------|-------------|----------|
| Accepted only | Mark MarkUploadedAccepted after successful remote Put; Durable stays caller/tooling until polling fast-follow | ✓ |
| Wire if discovered | Also mark Durable within this phase if S3D-03 finds a usable per-object signal | |
| Planner decides | Resolve the Durable-marking question after the S3D-03 finding exists | |

**User's choice:** Accepted only

---

## s3d entrance spike

| Option | Description | Selected |
|--------|-------------|----------|
| Day-one spike | First Phase-4 plan opens with a dev-gated live s3d probe (conditional PUT, HEAD, admin API); contingency decided then (D-10/D-11 discipline) | ✓ |
| Pre-committed ladder | Decide the fallback NOW (unconditional-PUT mode option or version bump) before evidence | |
| Research first | Researcher characterizes from openapi.yml/source; spike only if inconclusive | |

**User's choice:** Day-one spike

| Option | Description | Selected |
|--------|-------------|----------|
| Trio incl. durability | One live session: conditional PUT, HEAD semantics, /stats/uploads field shapes; S3D-03 finding written from spike ground truth | ✓ |
| S3 semantics only | Spike covers conditional PUT + HEAD; durability characterization runs as a separate task | |

**User's choice:** Trio incl. durability

| Option | Description | Selected |
|--------|-------------|----------|
| Hard entrance gate | s3d-dependent work blocks until the spike runs; hermetic work (conformance, drainer vs fake) proceeds | ✓ |
| Best-effort timing | Proceed on MinIO-proven semantics until s3d is available; risk late surprises | |

**User's choice:** Hard entrance gate

---

## s3d E2E evidence

| Option | Description | Selected |
|--------|-------------|----------|
| Dev-run s3d + env | Dev owns s3d + Sia account; test connects to env-provided endpoint (03 D-09 pattern, loud skip) | ✓ |
| Harness child proc | Test spawns s3d as a child process like the MinIO harness; drags Sia wallet lifecycle into test machinery | |

**User's choice:** Dev-run s3d + env

| Option | Description | Selected |
|--------|-------------|----------|
| Two-run fresh process | Run A uploads unique CID; run B is a fresh process with zero local state that retrieves + verifies; evidence shows both runs | ✓ |
| Same-run reconstruct | Put, destroy store, reconstruct in-process, Get — proves little about cold retrieval | |

**User's choice:** Two-run fresh process

| Option | Description | Selected |
|--------|-------------|----------|
| Drainer-driven spill | Upload run: LocalBlockStore Put → drainer → s3d; verify run: fresh S3BlockStore; drainer's first live proof free here | ✓ |
| Direct store roundtrip | Both runs via S3BlockStore directly; matches SC letter exactly | |
| Both paths | Direct roundtrip as SC-letter test + second gated case for the drainer | |

**User's choice:** Drainer-driven spill

| Option | Description | Selected |
|--------|-------------|----------|
| Committed run log | Phase-3 precedent (03-04-live-run-evidence.log): CIDs, keys, sizes, timestamps, s3d version, pass/fail; no secrets | ✓ |
| Log + JSON report | Adds machine-checkable JSON (CIDs, hashes, /stats/uploads snapshot, config echo) | |
| JSON only | Compact but breaks the Phase-3 evidence precedent | |

**User's choice:** Committed run log

---

## Durability finding

| Option | Description | Selected |
|--------|-------------|----------|
| Repo doc + header cite | Findings doc ships in the repo (docs/s3d-durability.md) AND Durability.hpp's ObjectStoreAccepted doc cites it | ✓ |
| Repo doc only | Doc ships but headers stay silent about s3d specifics | |
| .planning only | Finding lives only in phase artifacts; consumers never see the rationale | |

**User's choice:** Repo doc + header cite

| Option | Description | Selected |
|--------|-------------|----------|
| Evidence-cited finding | Raw /stats/uploads output, staged-read headers, openapi.yml fields committed; every claim traces to an artifact | ✓ |
| Prose finding only | Synthesized prose; a future reader must re-run the probe to check claims | |

**User's choice:** Evidence-cited finding

---

## the agent's Discretion

- Exact CID string encoding in the key layout (BACK-07 locks the layout; encoding details follow architecture doc + research)
- S3BlockStore config shape (bucket, prefix, injected client); GetSize/verify-on-read mapping details
- Drainer construction shape (function vs class), option surface, exact per-item result type
- Env-var names for s3d endpoint/credentials/bucket; secret-hygiene mechanics in the log
- MinIO-tier test breadth beyond the SC3 letter; unique-CID/re-run discipline for the two-run E2E
- Where spike evidence artifacts live in the repo

## Deferred Ideas

- Durability-signal polling implementation (fast-follow milestone)
- MarkUploadedDurable wiring into automated paths (until polling exists)
- TieredBlockStore / retrieval tiering / peer racing (REQUIREMENTS Future list)
- Background/async drainer scheduling (v1 ships synchronous one-shot drain)
