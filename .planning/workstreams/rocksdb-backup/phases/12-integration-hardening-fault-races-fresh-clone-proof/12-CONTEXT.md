# Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof - Context

**Gathered:** 2026-10-27
**Status:** Ready for planning

<domain>
## Phase Boundary

TEST-02 — the v1.1 capstone hardening evidence. The integration's trust claims hold under induced failure and reproducible builds; whatever fixes the evidence forces land here. This phase delivers:

1. **SC1 — evict × serve × drain fault races:** under `FaultController` timing injection, zero `Corrupt`-from-race, zero lost blocks, zero peer-blacklist writes originating from storage failures
2. **SC2 — resurrection counter-test:** delete → GC → re-deliver a pre-delete delta ⇒ the value is absent everywhere (restore must not resurrect GC'd values)
3. **SC3 — s3d-unavailable soak:** bounded journal growth (assertion semantics pinned in D-06), the alarm firing, publishes continuing for the soak duration; teardown-under-load joins cleanly; peer cold-fetch under injected s3d latency stays within its deadline budget
4. **SC4 — fresh-clone proof:** configure + build + `ctest -L Tier1` green on Windows, Linux, and macOS with cold storage ON, using only pushed commits across the three repos (SuperGenius, GeniusSDK, thirdparty/sgns-blockstore); every new test labeled and gated (tier-label audit)

Out of this phase: any new product capability (evidence + forced fixes only), mobile legs (option stays OFF), tombstone purging / epoch-based deletion compaction (v2+), per-object durability-signal polling (fast-follow milestone-wide), the GlobalDB backup engine (out of scope milestone-wide).

Requirements: TEST-02.

</domain>

<decisions>
## Implementation Decisions

### Fresh-clone proof surface (SC4)
- **D-01:** **The proof is the CI ON-lane on all three platforms, enabled by a thirdparty tag build that SuperGenius pulls from a specified tag** — the thirdparty release cut (the exact dependency the Phase-7 verdict deferred) happens in/around this phase: the thirdparty `build.yml` produces a release containing sgns-blockstore, and SuperGenius CI consumes that specified tag. No local fresh-clone run — CI is the sole proof surface (also avoids a ~100+ GB thirdparty build on the dev machine's W: drive) — **Reversibility:** costly — the release-cut + tag-pinned consumption is the milestone's reproducibility contract; unwinding it re-opens the Phase-7 blocked-on-release-cut posture
- **D-02:** **Both CI surfaces carry the ON lane** — (a) a permanent cold-storage-ON configure leg in `cmake.yml` (the every-push regression net), and (b) the `build-release-tags.yml` dispatch with the `thirdparty_tag` input and cold storage ON for the one-time milestone evidence — **with the testing flag enabled on the tag build** so `ctest -L Tier1` actually runs there (per the 14-toggle dispatch set; RUN_TESTS-style toggles must be ON) — **Reversibility:** costly — CI workflow topology is a published team contract; removing the permanent ON leg later is a regression-posture change
- **D-03:** **User checkpoint for the thirdparty tag cut** — the phase wires everything; a human checkpoint (11-04 Wave-4 precedent) has the user dispatch the thirdparty tag build and confirm the tag exists before the SuperGenius ON-lane runs against it. The executor never dispatches workflows and never pushes — **Reversibility:** reversible — checkpoint placement is workflow mechanics
- **D-04:** **"Only pushed commits" is inherent + fail-closed validated** — CI only ever builds pushed commits, and everything through Phase 11 is already pushed (user confirmed, end of Phase 11); where a runbook/script kicks off, it validates the tested SHAs exist on their remotes before starting — **Reversibility:** reversible — validation mechanics
- **D-05:** **Evidence is minimal: a checklist doc with results** — SHAs, tags, platforms, pass counts; raw logs live in CI run history and commit history, not committed artifacts — **Reversibility:** reversible — documentation posture (note: lighter than the TEST-03/gc-e2e committed-artifact precedent, deliberately — CI runs are self-archiving)

### Soak assertion semantics (SC3)
- **D-06:** **"Bounded journal growth" = no-multiply + drain** — during the outage, pending-record count ≤ distinct published CIDs (retries never duplicate records — no retry-storm multiplication), the Phase-8 watermark + alarm fire at their configured thresholds, AND after the fault clears the journal drains to zero (or pre-outage baseline) within a bounded window. The soak therefore has two phases: outage + recovery. A literal hard cap was rejected — Phase 8 D-01..D-04 locked unbounded-journal + watermark + alarm as the backpressure design — **Reversibility:** costly — this is the assertion contract the SC3 soak tests are stated over; loosening it re-opens what "bounded" means against the Phase-8 lock
- **D-07:** **Both soak shapes** — an iteration-based soak (N publish cycles under sustained fault injection; deterministic count, CI-safe runtime) runs in the Tier-1 CI lane, plus one dev-gated wall-clock soak (tens of minutes, never in CI) with committed evidence covering SC3's "for the soak duration" literally — **Reversibility:** reversible — test-suite composition
- **D-08:** **Full-stack actors under one sustained outage** — publishes + drainer attempts + flush-cadence backoff + GC inhibited (staging-unhealthy flag) + peer cold-fetch attempts + graphsync serving all run inside the soak window; the honest integration capstone rather than isolated actor soaks — **Reversibility:** reversible — scenario composition (attribution cost accepted; deterministic race matrix D-10/D-11 provides the isolation layer)
- **D-09:** **Teardown covers clean Stop() AND kill-9 mid-soak** — clean Stop() under load (bounded grace-flush attempt, ordered joins backup-loop → drainer → GC thread → cold-serve executor, no hangs/deadlocks) extends the Phase-10 shutdown-under-load proof with the GC actor and in-flight evict marks; kill-9 mid-soak + restart asserts journal reconciliation, pending re-drain, and no duplication — **Reversibility:** reversible — test-scope extension of twice-proven patterns

### Race & resurrection methodology (SC1/SC2)
- **D-10:** **Deterministic barriers + randomized jitter, both** — deterministic barrier-driven interleavings for the named hazard crossings (highest signal, zero flake) plus randomized `FaultController` timing-jitter iterations with end-state invariant checks for the long tail of orderings — **Reversibility:** reversible — test methodology
- **D-11:** **Matrix = pairwise + all-three, timed at the risky phase boundaries** — evict×serve, evict×drain, serve×drain pairwise plus the simultaneous triple, each crossing driven at the dangerous moments: GC mark, grace-expiry, delete-batch, delete-time re-check/cancel, re-warm attach. Exhaustive actor-phase products were rejected as diminishing returns; the minimal named-scenario-only shape was rejected as under-covering the phase boundaries where Phase-11's correctness lines actually race — **Reversibility:** reversible — matrix enumeration scope
- **D-12:** **Zero-lost-blocks proof = per-scenario asserts + full end-state audit + log scans** — each scenario asserts its own expected end state; at suite end an audit walk asserts every published CID is exactly one of {hot, cold-local, S3-retrievable CID-verified, disposed-with-remote-copy}; log-scan asserts prove zero peer-blacklist writes and zero misattributed `Corrupt` originating from storage failures — **Reversibility:** costly — the audit walk is the SC1 evidence bar downstream verification re-runs
- **D-13:** **Resurrection counter-test lives at node level via pubsub re-delivery** — in-process GlobalDB pair (11-03 lane precedent): put value → CRDT delete (tombstone) → force GC past retention + grace (tiny test-config ages) → evict → re-deliver the pre-delete delta block through the pubsub path (the realistic resurrection vector: peer re-broadcast) → assert the value is absent in BOTH nodes' set queries, no re-integration occurred (disposed-marker dedup), and the remote copy is intact. Direct datastore injection was rejected as skipping the realistic vector — **Reversibility:** costly — the counter-test is the SC2 trust claim ("restore must not resurrect GC'd values") stated as an executable contract

### Fix-forward posture
- **D-14:** **Fixes may go additive into the library** — defects found by the evidence may be fixed in SuperGenius and additively in sgns-blockstore (installed headers may gain additive surface per the Phase-6/10 widening precedent); no removals or renames of public API. Any library change means the thirdparty tag checkpoint (D-03) re-cuts before the fresh-clone proof runs — **Reversibility:** costly — additive-only keeps the installed-header contract and genius-tube compatibility; a breaking change later is a deprecation cycle
- **D-15:** **Deep defects checkpoint the user** — if a fix exceeds the budget (one failed fix attempt, or the fix would touch a locked decision from any prior CONTEXT), the executor pauses with findings + options (fix-forward / defer with documented risk / split out), per the 11-04 human-checkpoint precedent. No unbounded autonomous fix loops — **Reversibility:** reversible — governance mechanics
- **D-16:** **Minimal test seams in product code are allowed** — deterministic race-driving may add small test-only hook/barrier points (e.g., pause-at-mark in the GC thread), test-build-gated or otherwise inert in release builds, kept minimal and documented per seam — **Reversibility:** reversible — seams are additive and gated

### The Agent's Discretion
- Exact barrier/hook mechanics per named crossing (which seams D-16 needs: GC mark/grace-expiry/delete-batch/delete-time-re-check, re-warm attach, drain snapshot)
- N for the Tier-1 iteration soak; the wall-clock soak's duration (tens of minutes) and its committed-evidence artifact format
- The bounded drain window's assertion form (timeout bound, polling cadence)
- `cmake.yml` ON-leg shape (matrix leg vs separate job) and the exact dispatch-toggle wiring that enables testing on the tag build (D-02)
- The tier-label audit's mechanics (SC4: script vs checklist — verifying every new test is labeled Tier1/Tier2/Tier3 and gated accordingly)
- The minimal checklist doc's location and shape (D-05; e.g. SuperGenius docs vs workstream planning)
- Log-scan mechanics for the zero-blacklist / zero-misattributed-Corrupt asserts
- How the resurrection test forces GC past retention + grace (tiny ages in test config vs direct pass invocation)
- Regression-test discipline per landed fix (failing-first test in the Tier-1 lane)
- Per-scenario expected-end-state table design (which end states are legal per crossing)
- Randomized-iteration count and seed policy for the jitter legs (reproducibility on failure)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — TEST-02 (this phase's letter — all four evidence clauses); Out of Scope table
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 12 goal, 4 success criteria, 3 suggested plan waves, research note (standard — v1.0 fault kit, tier contract, evidence-capture habits directly reusable)

### Prior phase context (binding decisions this phase's races attack/consume)
- `.planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-CONTEXT.md` — the GC correctness lines the races induce failures against (D-05 fresh walk, D-08 snapshot+re-check, D-13/D-14 grace + delete-time cancel, D-15 in-memory marks, D-16 library-atomic batch); disposed-marker dedup (D-11) and NotFound split semantics (D-12) the resurrection test exercises; the 11-03 two-GlobalDB in-process lane precedent
- `.planning/workstreams/rocksdb-backup/phases/10-flush-gated-durability-advancement/10-CONTEXT.md` — the shutdown-under-load proof D-09 extends (SC3 interplay); flush-owned-by-drainer (D-02), bounded grace flush (D-04), staging-health predicate (D-12/D-13) the soak's GC-inhibition leg consumes
- `.planning/workstreams/rocksdb-backup/phases/09-cold-read-fallback-local-reads-graphsync-serving/09-CONTEXT.md` — the cold-fetch/serving paths the races cross (D-01 chain, D-05 don't-have+re-warm, D-08 HasBlock local-only); the explicit note that "Phase-12's soak carries the outage-signal visibility"; the peer-cold-fetch deadline budget SC3's last clause asserts

### Research (v1.1, 2026-10-22)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — the seam synthesis; backpressure + durability-bar milestone decisions the soak asserts
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — silent-disable and logging pitfalls; the freeze-hazard class
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — file:line citations for the seam and backup-loop pattern

### CI / release machinery (the fresh-clone proof surface — D-01..D-05)
- `SuperGenius/.github/workflows/cmake.yml` — develop CI; gains the permanent cold-storage-ON leg (D-02a); existing Tier-1 step anchors lane wiring
- `SuperGenius/.github/workflows/build-release-tags.yml` — the tag-build dispatch (14-toggle platform/build/test set, `thirdparty_tag` input, exit-78 skip gates); gains ON configure + testing-flag-enabled posture (D-02b)
- `thirdparty/build/CommonTargets.cmake` — the superbuild the release tarball is cut from (sgns-blockstore + minio-cpp + pugixml entries; tarball-limit-driven binary-dir constraints documented inline)
- `SuperGenius/cmake/CommonBuildParameters.cmake` + `GeniusSDK/cmake/CommonBuildParameters.cmake` — the `SGNS_COLD_STORAGE` option and sgns-blockstore `find_package` hints the ON-lane configures ON
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — the tier contract; Tier-1 fail-closed lane discipline; tier-label rules the SC4 audit enforces

### Fault kit & test surfaces (SC1/SC2/SC3 evidence instruments)
- `thirdparty/sgns-blockstore/test/` — `InMemoryS3Client` fake + `FaultController`/`S3FaultKind` scriptable faults (timing injection D-10/D-11); the fake admin endpoint for outage/flush faulting
- `thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp` + `S3Client.hpp` — the fault-injection surface every race/soak test drives
- `SuperGenius/test/` — the cold-storage Tier-1 suites this phase extends (config-gate, spill/drainer behavior, `cold_storage_fallback_test`, `cold_read_freeze_latency_test`, GC fault/retrievability suites)
- `thirdparty/sgns-blockstore/docs/s3d-durability.md` — the s3d characterization backing outage semantics (staged ≠ durable; 503 SlowDown → TemporarilyUnavailable)

### Code under race/fix (read before editing)
- `SuperGenius/src/crdt/globaldb/` — `ColdStorageManager` (drainer + GC thread + flush cadence + shutdown join ordering D-09 asserts), `BlockStoreBackedIpfsDatastore`, `ColdStorageStack`, `globaldb.cpp` `Shutdown()` ordering
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` + `crdt_heads.cpp` — the reachability/set-row surfaces the resurrection test drives
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — the responder + cold-serve path the serve-side races and peer-cold-fetch budget touch
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp` — the pubsub receive path the resurrection re-delivery rides

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style for test seams, soak harness, and any fixes
- `.planning/codebase/TESTING.md` — verification-inside-`build/<Platform>/<Config>`-tree rule; `addtest()` registration; Tier-1 lane wiring; gtest filter syntax gotchas

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`FaultController`/`S3FaultKind` + `InMemoryS3Client` (with fake admin endpoint)** — the timing/outage injection kit SC1's races, SC2's re-delivery, and SC3's soak all drive; extended per-scenario, not replaced
- **The 11-03 two-GlobalDB in-process graphsync lane** — the resurrection counter-test's transport topology (D-13) is already proven infrastructure
- **Phase-10 shutdown-under-load test** — the teardown-under-load leg (D-09) extends it with the GC actor + in-flight evict marks rather than building anew
- **Phase-8/10/11 Tier-1 suites** — crash-resume, reconciliation, backpressure-alarm, GC fault suites exist; Phase 12 composes them under sustained fault rather than re-proving them in isolation
- **SuperGenius CI (`cmake.yml` + `build-release-tags.yml`) + thirdparty `build.yml` release pipeline** — the machinery the ON-lane (D-01/D-02) plugs into; tag inputs and dispatch toggles already exist

### Established Patterns
- Own-thread lifecycle with ordered shutdown joins (backup loop → drainer [+grace flush] → GC thread → cold-serve executor) — D-09's teardown asserts this exact ordering under load
- Snapshot-at-initiation + re-check evidence semantics (Phase-10 D-03, Phase-11 D-08) — the race matrix's phase-boundary crossings are chosen exactly where these lines are vulnerable
- Safe-direction crash analysis (under-eviction safe; remote copy + GC-03 retrieval exist) — the end-state audit's legal states (D-12) encode it
- Tri-state config strictness + Tier-1 fail-closed `ctest -L Tier1 --no-tests=error` lane — every new test registers here; the SC4 tier-label audit polices it
- Tag-build consumption of pinned thirdparty releases (`thirdparty_tag` input, GITHUB_ENV container-path discipline) — the known landmine class from past tag-build fixes

### Integration Points
- `cmake.yml` gains the permanent ON leg; `build-release-tags.yml` gains ON configure + testing-enabled posture for the milestone dispatch
- The thirdparty release cut includes sgns-blockstore (+ its minio-cpp/pugixml deps) — the D-03 user checkpoint gates the ON-lane on its existence
- `ColdStorageManager`/GC thread may gain minimal test seams (D-16) — gated, documented per seam
- Any additive library surface (D-14) flows through the installed-header compile-check gates from Phases 6/7

</code_context>

<specifics>
## Specific Ideas

Factual constraints from the discussion that bind implementation:

- The user runs the thirdparty tag build; SuperGenius pulls from a specified tag (D-01/D-03) — the executor wires and validates, never dispatches or pushes
- The tag build must run with the testing flag on (D-02) — an ON configure without tests executing is not the proof
- Everything through Phase 11 is already pushed (user-confirmed); the proof's "only pushed commits" clause starts satisfied and stays satisfied because CI builds pushed commits only
- Phase 8's unbounded-journal+watermark+alarm lock stands (D-06): "bounded journal growth" is a no-multiplication + post-recovery-drain claim, never a hard cap
- Evidence posture for the fresh-clone proof is deliberately minimal (D-05) — a checklist doc; CI run history is the archive (contrast with TEST-03's committed gc-e2e artifacts, which remain the standard for the dev-gated wall-clock soak's evidence per D-07)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched only on keyword (score 0.6, "supergenius"); unrelated to cold-storage hardening; third consecutive phase reviewed-not-folded (Phases 10, 11, 12); stays in the backlog for its own track

</deferred>

---

*Phase: 12-Integration Hardening, Fault Races & Fresh-Clone Proof*
