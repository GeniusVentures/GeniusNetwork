# Phase 2: Manifest & Model Cache - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-10
**Phase:** 2-Manifest & Model Cache
**Areas discussed:** Reuse verification depth, Cache root & disk config, Manifest parse strategy, Eviction state & testing

---

## Reuse Verification Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Size-first fast path | Stat every artifact against manifest size_bytes (instant). Mismatch → quarantine + re-download. No hashing on hit. Trusts the publish-time gate for content integrity on trusted local disk. | ✓ |
| Full sha256 on every hit | Every cache hit re-hashes all artifacts before load. Strongest integrity (catches disk bitrot), but a 300-500MB model re-hash per subtask adds seconds and burns worker threads. | |
| Hybrid (config flag) | Size check always, plus sha256 only if the cache dir is configured as shared/external; plain size-only for local default. Two code paths. | |

**User's choice:** Size-first fast path
**Notes:** Matches Pitfall 8's recommendation; publish-time gate is the correctness mechanism.

### Mismatch handling follow-up

| Option | Description | Selected |
|--------|-------------|----------|
| Quarantine + fail acquire | Rename to .bad-<hash>, fail the acquire as a structured RESOURCE_RESOLUTION error; the SAME acquire retry re-downloads cleanly. No queue livelock. | ✓ |
| Quarantine + auto-refetch | On mismatch, transparently quarantine and immediately retry the fetch inside the same acquire call — the subtask never sees the corruption. | |
| Delete + re-download | Delete the corrupt entry outright (no .bad- marker), then re-download. Loses forensic evidence; the .bad- name is the telemetry signal. | |

**User's choice:** Quarantine + fail acquire
**Notes:** No auto-refetch — the subtask's funding clock keeps running during a re-download it has no visibility into; the caller decides whether to retry.

---

## Cache Root & Disk Config

| Option | Description | Selected |
|--------|-------------|----------|
| FileManager cache dir | Reuse FileManager::getCacheDir() and nest: <cacheDir>/elmruntime/<manifest-hash>/. One root for all node-local caching, consistent with the existing results/ convention. Fail closed if unset/empty. | ✓ |
| New config knob | New dedicated setting (env var or config, e.g. SGPROC_ELM_CACHE_DIR) defaulting under the FileManager cache dir. Operator flexibility, extra plumbing. | |
| Hardcoded relative dir | Hardcode a relative 'cache/' directory next to the executable. Ignores existing machinery; breaks multi-node deployments where cwd differs. | |

**User's choice:** FileManager cache dir
**Notes:** Zero new configuration surface for the cache location.

### Disk pressure policy

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed byte cap | LRU eviction triggers when the cache's total bytes exceed a fixed cap (configurable, sane default like 10-20GB). Manifest size_bytes makes the arithmetic trivial and deterministic. | ✓ |
| Free-space threshold | Evict when std::filesystem::space() free space drops below a threshold. Adapts to the volume but depends on what else shares it — less deterministic for tests. | |
| Both (cap + floor) | A byte cap AND a free-space floor, whichever triggers first. Most robust, two axes for v1.0. | |

**User's choice:** Fixed byte cap
**Notes:** Deterministic and testable; no free-space axis in v1.0.

---

## Manifest Parse Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Quicktype regen | Add the manifest shape to gnus-processing-schema.json and regenerate — same pipeline as the Phase 1 ELM job block. One schema authority, constraint checking for free, consistent with SCHEMA-01..05. | ✓ |
| Hand-rolled parse | A small hand-rolled nlohmann::json parse in src/elmruntime/ (~150 lines). No generated/ churn, but breaks the quicktype norm and re-implements constraint checking by hand. | |
| Separate quicktype file | A NEW separate gnus-elm-manifest-schema.json with its own quicktype output directory. Clean separation, but a second codegen pipeline for one small struct. | |

**User's choice:** Quicktype regen
**Notes:** The manifest's bytes are hash-pinned by the work item's model_manifest_hash, so schema evolution rides the same content-addressing as everything else.

---

## Eviction State & Testing

### Restart state

| Option | Description | Selected |
|--------|-------------|----------|
| Directory-scan rebuild | On startup, scan cache/<hash>/ dirs: reconstruct entries, rebuild LRU order (directory mtime), pin counts start at zero. A populated disk cache survives restarts. | ✓ |
| Persisted index file | Persist an index file (LRU timestamps, sizes, pin state) written atomically; load on start. Index-vs-disk drift is a new bug class; pins are meaningless across restarts. | |
| In-memory only | LRU order resets on restart (all entries equally 'cold'). Simplest, but degrades eviction quality after every restart. | |

**User's choice:** Directory-scan rebuild
**Notes:** The Phase 4 empty-cache E2E still works because it starts with no entries.

### Quarantine retention

| Option | Description | Selected |
|--------|-------------|----------|
| Keep forever | .bad-<hash> dirs persist as forensic evidence; the log line at quarantine time is the telemetry. Ignored by cache-size accounting; never block re-download. | ✓ |
| Auto-clean policy | Keep at most N recent quarantine dirs (or delete older than X days) during eviction sweeps. Bounds disk growth from repeated poison events. | |
| Delete immediately | Quarantine in memory only and delete the dir contents immediately. No forensic trail on disk. | |

**User's choice:** Keep forever
**Notes:** PITFALLS asks for quarantine logging — the persisted dir plus the log line covers it.

### Test fetch strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Injectable fetcher | ElmArtifactFetcher takes an injectable fetch interface; production wires FileManager::LoadASync, tests inject file://-backed or in-memory lambdas. FileManager stays the only production fetcher. | ✓ |
| file:// fixtures only | Tests point manifest URIs at local files through the real FileManager. Full production path, but couples every unit test to AsyncIOManager/io_context drain machinery. | |
| Both layers | Injectable interface for fast unit tests, plus one or two file://-through-FileManager integration tests. | |

**User's choice:** Injectable fetcher
**Notes:** Unit tests never need IPFS; FileManager remains the only production fetcher (issue #17 mandate).

---

## Claude's Discretion

- Exact default byte cap value (10-20GB suggested) and its configuration mechanism
- Exact quicktype spelling of manifest types (record actual generated names, don't assume)
- Internal structure of single-flight map, pin-refcount RAII handle, quarantine rename mechanics
- Staging-directory naming and cleanup discipline for partial downloads
- Unit-test structure under test/elmruntime/
- Smoke-check placement (inside acquire or post-publish step — must complete before entry is marked usable)

## Deferred Ideas

None — discussion stayed within phase scope.
