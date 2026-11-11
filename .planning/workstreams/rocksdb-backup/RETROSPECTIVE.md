# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — CRDT Cold-Storage BlockStore Library (Sia s3d backend)

**Shipped:** 2026-10-22
**Phases:** 5 | **Plans:** 16 | **Tasks:** 40

### What Was Built
- `thirdparty/sgns-blockstore` — a standalone, installable static library (9,426 LOC / 46 files) with a frozen v1 contract: structured status taxonomy, `DurabilityLevel`, eviction-safe List-free API, one-macro conformance kit, and compiling API-shape guards.
- Three backends proving the contract: `MemoryBlockStore` (reference), `LocalBlockStore` (own RocksDB instance, atomic one-batch writes, crash-recoverable upload journal, corruption self-heal), `S3BlockStore` (`v1/blocks/` codec-preserving layout, conditional create-only PUTs, UploadDrainer).
- minio-cpp v1.0.0 integrated shaderc-style through the thirdparty superbuild (no fork), isolated behind an internal `S3Client` adapter with an in-memory fake and one-place taxonomy mapping (three distinct 412 wire shapes classified).
- Live acceptance evidence: opt-in MinIO-binary tier (TLS-capable via in-process OpenSSL cert gen) and a dev-gated two-run fresh-process Sia s3d E2E, all artifacts committed; s3d's no-per-object-durability-signal finding documented with the accepted-is-max-provable ceiling.
- Three-tier test strategy enforced from configuration: tier labels on all 15 ctest registrations, a self-inspecting fail-closed Tier-1 audit, CI lane `ctest -L Tier1 --no-tests=error`, plus fault/crash injection across kit, fakes, and the real adapter (52 fault-seam call sites).

### What Worked
- Contract-first sequencing: freezing the retrofit-brutal type-system decisions in Phase 1 (with guard tests) meant Phases 2/4 backends only implemented, never renegotiated — zero contract churn across the milestone.
- The conformance kit as a reusable instrument: one macro line gave every backend the full 17-case suite; cross-phase integration audit found 0 broken seams, 0 orphans.
- Hermetic-by-default testing from day one; live tiers were env-gated opt-ins with loud skips, so CI never needed Docker or internet.
- Tracer-first plans (repo → CommonTargets → install tree → green spike) de-risked build integration before any behavioral work.
- Committed evidence artifacts for every live claim (s3d spike stats captures, E2E logs) — verification never depended on session memory.

### What Was Inefficient
- G-3-1 detour: `std::system()` with a quoted binary path silently no-ops on Windows (UCRT re-quoting); the openssl.exe shell-out for TLS tests cost a full gap-closure plan (03-04) before in-process cert gen fixed it.
- Verification covered-digest churn: any later edit to a covered file (Phase-5 fault seams legitimately touched Phase-3/4 files) marks earlier VERIFICATIONs stale, forcing either refresh or an override at close — a structural cost of the digest design.
- Single Windows build tree: shared library-target rebuilds forced sequential waves in Phases 4/5 where parallel execution was otherwise possible.
- Phase-3 close needed a UAT resumption for the live MinIO tier; the tier's first live runs surfaced fixture mismatches (spike-tls vs shared bucket) that hermetic tests could not catch.

### Patterns Established
- Fail-closed test selection: `ctest -L` (never `-LE`) + `--no-tests=error` + a registration-vs-label count audit with proven teeth (3 negative probes).
- Fault seams at the fake/adapter level (key overlay before op table, success-slot flips, commit-tail XOR corruption hook) instead of mocking at call sites.
- Honest durability vocabulary in the API (`ObjectStoreAccepted` as an explicit ceiling) rather than implying more than the backend proves.
- Library-local `result<T, BlockStatus, policy::terminate>` alias to side-step boost's default policy for struct error types.

### Key Lessons
1. Never `std::system()` a quoted path in Windows test harnesses — use CreateProcess or link the library (OpenSSL C API in-process cert gen removed an entire class of environment dependency).
2. Verification fingerprints must be refreshed together with the `verified:` timestamp, and any covered-file edit — even from a later phase — invalidates them; plan the refresh at phase close.
3. Token-grep prohibitions must use call-form patterns (`->Flush\(`) — bare tokens match the documentation that states the prohibition.
4. MSVC debug crashes on `std::vector` from gsl::span iterator temporaries inside `EXPECT_EQ`; bind one named `const auto keys =` before iterating (two `.begin()`/`.end()` temporaries = "iterators from different containers").
5. CMake regex has no `{n,m}` intervals; use character classes and `\\1` backrefs.
6. A backend's real behavior can falsify protocol assumptions (MinIO serving TLS-only on the API port killed first-byte-sniffing); probe early, gate hard, keep the fallback decision at failure time.

### Cost Observations
- Model mix: not tracked per-model this milestone (workstream ran inline + subagents on the Copilot runtime).
- Sessions: single-workstream, 4 calendar days (2026-10-19 → 2026-10-22).
- Notable: plan durations ranged 10–95 min; the longest (04-01, 95 min) carried the hermetic S3BlockStore core; gap-closure plan 03-04 (56 min) was entirely avoidable via lesson 1.

---

## Milestone: v1.1 — SuperGenius Cold-Storage Integration & CRDT Garbage Collection

**Shipped:** 2026-11-10
**Phases:** 7 (6-12) | **Plans:** 21

### What Was Built
- Library unblocked for the real DAG: blake2b-256 CID widening across all three backends (verify against the CID's own multihash) + installed `OpenMinioS3Client` factory with an out-of-tree Tier-1 consumer proof.
- The integration seam: one journal-spill decorator at the `IpfsDatastore`/`GlobalDB::New` construction point delivers spill + fallback + serving with zero changes to GraphsyncDAGSyncer/CrdtDatastore/ipfs-lite; gated `SGNS_COLD_STORAGE` OFF-by-default wiring in SuperGenius + GeniusSDK; strict tri-state `blockstore` config (blank=disabled byte-identical, malformed=loud, env=credentials-only).
- Full lifecycle: background drainer (split-phase, crash-restart reconciliation) → flush-gated durability (`Durable` only after s3d `/objects/flush` + `pendingObjects==0` evidence) → eviction-only retention GC (two-phase, tombstones/metadata never purged, bounded disposed markers) → CID-verified cold-read fallback with async re-warm serving.
- Hardening capstone: 13-case barrier-driven fault-race matrix with byte-flip teeth and seeded jitter, resurrection counter-tests (including a real production defect found failing-first: `InElemsNotTombstoned` empty-enumeration), outage/recovery soaks with a true kill-9 resume, and the fresh-clone three-platform proof (tag-build run 42905264387: Windows 153/153, Linux 152/152, OSX 155/155, cold storage ON).

### What Worked
- Single-seam decorator design held for the entire milestone — no phase had to touch graphsync/CRDT core; the Phase-12 race matrix exercised the seam rather than new integration points.
- Fail-closed Tier-1 discipline from day one: every phase landed hermetic tests in the lane, and the tier-label audit kept labels honest (green in CI for the first time this milestone).
- Deterministic race instrumentation: WindowGate latches + TimingS3Client decorator (barriers, not sleeps) made evict×serve×drain crossings reproducible; env-knob jitter seeds made flakes re-runnable.
- Failing-first counter-tests: writing the resurrection suite RED exposed a production-reachable defect (`crdt_set.cpp`) that unit-green code had masked.
- Human checkpoints with checklists: the D-03 tag-cut gate (push innermost-first, cut thirdparty tag, dispatch tag build, record evidence) ran exactly as designed across a two-week pause.
- Evidence-based UAT: accepting a fully-green three-platform CI run as UAT evidence (user ruling, recorded in 12-UAT.md) collapsed 17 checkpoints to a 5-minute review with zero lost coverage.

### What Was Inefficient
- The thirdparty release tag had to be re-cut (`test_coldstorage` → `test_coldstorage_rtti`) because a RocksDB RTTI requirement surfaced after the first cut — a payload-boundary pre-check would have saved a full CI round.
- SUMMARY `coverage:` frontmatter was malformed across 12-01/12-02 (missing `id`, inline verification maps), forcing the fail-safe human-checkpoint path in UAT classification.
- Per-phase verification staleness: sequential builds on a shared tree leave earlier phases' VERIFICATION.md "stale" by timestamp even though nothing regressed; resolving this required a milestone audit rather than being automatic.
- Environmental friction on the dev box: zombie cl.exe locking test files, concurrent ctest fixture-dir contention (RocksDB LOCK) — killed-stray hygiene before lanes became routine.

### Patterns Established
- Test fakes ship WITH the library (installed public headers) — supersedes cache-variable/source-overlay approaches for tarball consumers.
- Evidence trios (runbook README + run-capture + status-capture) for any wall-clock/kill proof; redaction grep committed alongside.
- Env-knob reproducibility contract (jitter seeds, soak iteration counts, resume mode) on every nondeterministic test.
- Goal-backward verification with line-level citations (file:line evidence tables) as the VERIFICATION.md house style.

### Key Lessons
1. gtest filter grammar is positive-negative with ONE dash: `*-A:B:C` — `*-A:-B:-C` silently drops the later exclusions.
2. Pass test exclusions through the environment, never through eval'd string re-parsing (tokenization turned regex pipes into shell pipes once).
3. Sequential-phase milestones need a milestone-level audit instrument; per-phase gates cannot credit later integrated state.
4. A user-accepted CI evidence ruling (recorded verbatim in the UAT) is a legitimate UAT instrument for CI-proven checkpoints — local re-runs added nothing.
5. gc/eviction code paths need empty-enumeration semantics pinned to upstream (go-ds-crdt) — an empty set is "not in set", never "not tombstoned".

### Cost Observations
- Model mix: not tracked per-model (Copilot runtime, inline + subagents).
- Timeline: 2026-10-22 → 2026-11-10 (calendar 20 days; the D-03 human checkpoint straddled 2026-10-28 → 2026-11-10).
- SuperGenius dev_blockstore: 76 commits in the window; thirdparty 24; sgns-blockstore 29.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 4 days | 5 | First rocksdb-backup milestone; established three-tier testing + fail-closed CI as the workstream norm |
| v1.1 | 20 days | 7 | Single-seam integration discipline; barrier-driven race instrumentation; evidence-based UAT via accepted CI runs; human-checkpoint (tag cut) protocol |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 15 ctest registrations (Tier-1 lane 12/12, full battery 14/14+) | taxonomy/conformance kit across all 3 backends | minio-cpp pinned v1.0.0, no GNUS fork |
| v1.1 | SuperGenius Tier-1: 12→17 cold-storage suites + tier1_static_audit in CI (Win 153/153, Linux 152/152, OSX 155/155 fresh-clone) | fault-race matrix, resurrection counter-tests, soak evidence trio, milestone audit 5/5 seams | no new third-party deps; blake2 vendored object code reused from ipfs-lite-cpp |

### Top Lessons (Verified Across Milestones)

1. (First milestone — candidate pool seeded above; re-rank after v1.1+)
2. Verified in v1.1: fail-closed Tier-1 discipline scaled from 15 registrations to a three-platform fresh-clone lane without lane drift (tier audit held).
3. Verified in v1.1: hermetic fakes + evidence artifacts beat live-endpoint CI — the live tier stayed dev-gated and still closed its requirement with committed evidence.
