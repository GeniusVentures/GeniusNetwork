# Phase 19: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone - Context

**Gathered:** 2026-11-19
**Status:** Ready for planning

<domain>
## Phase Boundary

TEST-02 + TEST-03 — the v1.2 closing capstone. The composed system — erase × serve × recovery — is disproof-proven under induced failure at every phase boundary via an extended fault-race matrix (curated boundary-case list extending v1.1's 13-case matrix), and the recovery-walk suites (read: the full cold Tier-1 contract) run green on Windows, macOS, and Linux CI lanes with cold storage ON — as a PERMANENT lane, not dispatch-only evidence. The Windows/macOS walk-lane portability list is documented as a full lane runbook so the three-platform lanes stay reproducible run over run.

1. **SC1 (TEST-02)** — the extended matrix crosses erase × serve × recovery; induced failures at each phase boundary cannot produce resurrection, partial-history validation, or lost last copies (`VALUE_PRESENT_INVARIANT_VIOLATION` stays loud); barrier-driven (no sleeps), red-first proven, env-knob reproducibility on every nondeterministic test
2. **SC2 (TEST-03)** — recovery-walk suites green on Windows, macOS, and Linux CI lanes — fresh-clone, cold storage ON, tier labels intact
3. **SC3** — the Windows/macOS walk-lane portability list documented (CloudflareWARP adapter = environmental, distinct per-node base paths, poll predicates, gtest filter grammar) plus the full lane runbook, so the lanes stay reproducible run over run

**What changes in this phase:** additive test code (the new sibling matrix suite + its serve-side seams + one full-wire leg), CI workflow edits (permanent 3-platform cold-ON Tier-1 lane), and documentation (one `notes/19-*` runbook/evidence doc + refreshed fresh-clone checklist). Production code is expected untouched — UNLESS a red-first matrix case finds a real bug, which is fix-forward in scope (Phase 16 D-03 precedent: repair the half, keep the design). Zero new dependencies (workstream rule). Live MinIO stays dev-gated/Tier-3.

Out of this phase: soak-scale capacity evidence (Phase 17 owns measurement; its Tier-1 floor already feeds these lanes), cold collectibility machinery (v2 contract ask — Phase 18 record), cross-node downgrade topology (Phase 18's compositional ruling), any fix for the known NON-cold macOS teardown debt (quarantine-table scope, deferred to SuperGenius backlog per the v1.1 round-14 ruling).

Requirements: TEST-02, TEST-03.

**Status note:** Phase 19 depends on Phases 13-18 settled. At gather time: 14 and 18 are Complete; 13 (4/4 plans), 15 (3/3), 16 (3/3), 17 (3/3) show plans executed with verification still pending. All v1.2 code is landing on `dev_coldstorage_additions`. Planning research MUST re-locate all code anchors against the final post-verification line (Phase 18 executed on the post-17 line; consult STATE.md's landed-line notes before editing).

</domain>

<decisions>
## Implementation Decisions

### Matrix shape & case grammar (SC1)
- **D-01:** **Curated boundary list — not a formal 3-axis product** — the erase × serve × recovery crossing is implemented as named cases at specific phase-boundary failure points (pre-erase staging, post-commit erase, cold-fetch serve, refusal classification, walk-start, mid-walk GC eviction, ...), each asserting its impossibility. A formal {erase points} × {serve points} × {recovery points} product was considered and declined (combinatorial explosion nobody can keep green on three platforms) — **Reversibility:** costly — the case list is the evidence contract TEST-02 verification reads against; reshaping it post-hoc re-opens what "crossing" meant
- **D-02:** **New sibling suite; v1.1's 13-case matrix stays frozen** — the extended matrix lands as a `cold_cross_feature_fault_race_test.cpp`-family sibling (the `cold_compose_matrix_test.cpp` precedent), with its own ctest Tier-1 label. Extending the v1.1 suite in place was declined (it churns the frozen baseline the v1.1 SC4 evidence was gathered on) — **Reversibility:** costly — the Tier-1 label becomes part of the lane contract D-09 proves green; renaming/removing it later breaks the lane's assertions
- **D-03:** **~8–12 new cases, two-layer discipline per case** — every boundary gets a deterministic seam-stepped leg, plus a real-thread barrier leg where true concurrency is the claim (Phase 16 D-06 applied per case). Roughly doubles v1.1's matrix. Minimal-delta (~5–6, leaning on Phase 14/15/16 suites as compositional evidence) was declined — the capstone's letter is disproof at EVERY boundary — **Reversibility:** costly — case count drives the lane runtime budget on three platforms
- **D-04:** **Hazard-mapped per case** — each case designates its primary hazard (resurrection / partial-history validation / lost last copy) and asserts it loudly; the matrix table documents which case kills which hazard. All three hazards are covered ACROSS the matrix, not per-case. Tri-hazard-everywhere was declined (trivially-true assertions dilute failure messages) — **Reversibility:** reversible — assertion shape inside cases is local

### Fault induction & topology (SC1 mechanics)
- **D-05:** **Reuse + extend the v1.1 kit** — TimingS3Client, WindowGate, GC hooks (`SetGc*HookForTesting`), `InMemoryS3*` fakes, Phase 14/15/18 interrupt seams, and Phase 15's tri-state evidence fakes drive the new cases; add ONLY the missing serve-side seams (e.g. a refusal-classification interrupt, cold-read interruption). A purpose-built fresh harness was declined (a parallel kit drifts from the seams CI already knows; zero-new-deps rule) — **Reversibility:** costly — the new serve-side seams become permanent test surface later phases extend
- **D-06:** **Hybrid topology — hermetic everywhere + exactly ONE full-wire leg** — all deterministic cases are hermetic single-node + fake cold + injected evidence states; ONE two-GlobalDB full-wire failover/refusal leg (the v1.1 resurrection leg-3 recipe, real pubsub) carries the true-topology claim, with generous instrumented deadlines (status-dump-on-failure per the v1.1 round-6 discipline — instrument, don't bump). It starts Tier-1 if it holds green across dispatches, else demotes to dev-gated. Hermetic-only-with-citations was declined (the capstone should carry at least one real-wire failover proof); broad full-wire legs were declined (real-pubsub N-node is the repo's flakiest class) — **Reversibility:** costly — the full-wire leg's tier placement becomes part of the lane contract
- **D-07:** **Serve arm = evidence-aware serving core only** — cold-fetch consult + refusal classification (`ApplyColdPrecedence` surfaces) — where erase × recovery actually cross. Re-warm/LRU stays covered by the existing v1.1 spill/rewarm suites, cited compositionally — **Reversibility:** reversible — scope of which surfaces the matrix drives is per-case
- **D-08:** **Recovery arm = walk boundaries + the concurrent-erase delta** — forced walk against induced evidence states at walk boundaries (pruned mid-walk, GC-evicted mid-walk via the Phase 18 exemption, seals-present), deterministic seam-driven. Phase 15 walk/recovery semantics are re-proven ONLY under concurrent erase (the cross-feature delta), not full re-proof — **Reversibility:** reversible — bounded by the existing Phase 15 suites' coverage claims

### CI lane mechanics (SC2)
- **D-09:** **Permanent 3-platform cold-ON Tier-1 lane** — extend the existing Tier-1 cold-ON lane pattern (the permanent OSX ON leg) to ALL three desktop platforms in `cmake.yml` + `build-release-tags.yml`. Cold Tier-1 becomes continuously proven on every push/dispatch — not dispatch-only evidence. Dispatch-evidence-only was declined (nothing guards regressions after the capstone closes) — **Reversibility:** costly — a permanent lane adds standing load to the self-hosted Windows (thermal saga) and macOS (tart VM) runners; removing it later breaks the "run over run" claim
- **D-10:** **Hermetic cold only in CI** — "cold storage ON" in the lanes means the hermetic cold stack (`InMemoryS3*` fakes — fresh-clone safe, no services). Live MinIO legs stay dev-gated/Tier-3 (Phase 18 precedent). A Linux MinIO-service-container leg was declined (stronger but heavier; Windows self-hosted has the Docker Desktop landmine) — **Reversibility:** reversible — a MinIO leg can be added later without disturbing the hermetic contract
- **D-11:** **"Recovery-walk suites" = the FULL cold Tier-1 contract** — all v1.2 suites (Phase 14 gate, 15 walk, 16 matrix, 17 floor-smoke, 18 downgrade timeline, 19 cross-feature matrix) green on all three platforms. The narrow reading (walk suites only) was declined — the capstone claim would weaken to a subset — **Reversibility:** costly — this defines TEST-03's verification contract
- **D-12:** **Documented quarantine table for NON-cold flakes — never silent, never cold** — known non-cold failures (secure_storage, price_manager, network_config segfault, multi_node smoke, ...) get pre-agreed exclusion/env-knob entries recorded in the Phase 19 evidence doc with first-occurrence history. v1.1 discipline applies: `CTEST_EXCLUDE_REGEX`, append-never-replace `GTEST_FILTER` composition, `*-A:B:C` filter grammar. Cold-labeled failures are NEVER quarantined — fix-forward in scope (they are the capstone's own claim) — **Reversibility:** costly — the quarantine table is the operator-facing contract for what the lanes do and don't prove

### Portability list & evidence (SC3)
- **D-13:** **One `notes/19-*.md` — the rulings-chain home** — carries the portability list + the quarantine table (D-12) + the run evidence. Joins `notes/16-*` / `17-*` / `18-*` (citation-chain discipline). A repo-side doc home was declined (breaks the chain); notes+repo-pointer hybrid declined as unnecessary — **Reversibility:** costly — later artifacts cite this doc by location (the rulings-chain rule)
- **D-14:** **Full lane runbook depth** — SC3's four named items (CloudflareWARP adapter = environmental, distinct per-node base paths, poll predicates, gtest filter grammar) PLUS everything a fresh operator needs to reproduce the lanes: required env vars (`SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` presence, `SGNS_COLD_STORAGE` cache flag), parallel-level caps, crash-report capture, dispatch toggles, exclusion pointers — **Reversibility:** reversible — additive documentation
- **D-15:** **Evidence = run links + fresh-clone checklist** — green dispatch run links + parameters recorded in the evidence doc AND a refreshed/extended fresh-clone checklist (the v1.1 `12-FRESH-CLONE-CHECKLIST.md` precedent) proving the permanent lanes work from a clean clone on each platform — **Reversibility:** reversible — evidence accumulates additively
- **D-16:** **Green bar = one recorded green dispatch per platform** — one green closes the capstone record; the permanent Tier-1 lane (D-09) is the standing guard against resurfacing flakes (e.g. tart-VM timing) going forward. Two-consecutive-greens was considered and declined — the permanent lane already provides the recurrence proof — **Reversibility:** reversible — more evidence runs can always be added

### The Agent's Discretion
- The exact boundary inventory and named-case list (which boundaries get cases — researcher proposes within the D-03 budget; the matrix table renders it)
- New serve-side seam placement/naming (refusal-classification interrupt, cold-read interruption — siblings of the Phase 14/15/18 seam family)
- Sibling suite filename(s), test registration home, and the new Tier-1 label name (`ctest -L` contract)
- Red-first proof mechanics per race case — fault-injected bad state (Phase 18 D-01 counter-test pattern) where no live bug exists; researcher picks per case
- The full-wire leg's promotion criteria concretization (how many green dispatches = "holds green" before it keeps Tier-1)
- `cmake.yml` / `build-release-tags.yml` edit shape — how the cold-ON Tier-1 lane is expressed per platform (reuse the OSX permanent-ON-leg pattern; researcher reads both workflows first)
- Quarantine-table initial contents (which known flakes from the v1.1 dispatch history get entries; first-occurrence run IDs)
- Exact filename for `notes/19-*.md`; fresh-clone checklist refresh shape and home
- Env-knob naming for the new nondeterministic tests (reproducibility contract)
- Anchor re-location strategy against the final post-verification line (see domain status note) — researcher rules exact procedure

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 19 goal, 3 success criteria, dependency (Phases 13-18 all settled)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — TEST-02/TEST-03 letters; out-of-scope table
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions (evidence outranks bytes; barrier-driven races; zero new dependencies; SEAL-01/POLICY-01/02 decided); landed-line notes
- `.planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-CONTEXT.md` — walk/refusal/failover semantics the matrix crosses (D-04 source-consistency predicate; D-05 walk decision matrix; forced-walk bounds); the surfaces D-07/D-08 drive
- `.planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-CONTEXT.md` — D-06 two-layer race discipline (applied per case, D-03); D-07 crossfire invariants; D-09 Tier-1 fresh-clone contract that feeds these lanes
- `.planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-CONTEXT.md` — D-07 Tier-1 floor-smoke leg (a standing lane member D-11 includes); D-11 numeric triggers (not this phase's scope but lane-relevant)
- `.planning/workstreams/rocksdb-backup/phases/18-role-downgrade-collectibility-policy-gc-walk-gap-exemption/18-CONTEXT.md` — D-01 red-first counter-test pattern (the red-first mechanics precedent); D-03/D-11 hybrid tiering; the t0→t3 downgrade timeline suite (a lane member)
- `.planning/workstreams/rocksdb-backup/notes/16-txpruner-gc-composition-rulings.md`, `notes/17-seal-growth-decision.md`, `notes/18-collectibility-policy-downgrade-interlock.md` — the rulings chain the `notes/19-*` doc joins (shape + citation discipline)

### v1.2 research (2026-11-13)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — test-guidance items (red-first races, tier discipline, env-knob reproducibility); Pitfall 5 (marker crossfire invariants — matrix rows); testing traps (N-node portability landmines — why D-06 keeps full-wire legs to ONE)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — phase ordering; zero-new-dependencies rule; the two-halves/never-delete invariants the matrix asserts
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — the composed-system boundaries the case inventory derives from

### v1.1 prior phases (the extension base)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/` — the 13-case barrier-driven fault-race matrix (the frozen baseline D-02 preserves), the TimingS3Client/WindowGate/hook kit, and `12-FRESH-CLONE-CHECKLIST.md` (the checklist D-15 refreshes)
- `.planning/workstreams/rocksdb-backup/quick/261029-uj0-debug-failing-supergenius-cold-storage-t/` — the GcPassOnce serialization fix (why real-thread races on OSX are a distinct evidence class)

### CI workflows (the lanes D-09 extends — researcher reads before editing)
- `SuperGenius/.github/workflows/cmake.yml` — PR/push lane; the existing permanent OSX cold-ON Tier-1 leg pattern (env knobs, test steps, exclusion regex, crash-report capture)
- `SuperGenius/.github/workflows/build-release-tags.yml` — dispatch toggles (`run_tests`, `cold_storage`, `thirdparty_tag`); the 14-platform checkbox set; crash-report capture steps

### Code under test (anchors from prior CONTEXTs — RE-LOCATE on the final post-verification line before editing)
- `SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp` — v1.1 13-case suite + TimingS3Client/WindowGate (frozen baseline; the sibling's kit source)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — `ApplyColdPrecedence` / refusal classification (D-07's serve surfaces); walk/seal accessors (D-08's boundaries)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` / `ColdStorageStack.hpp` — GC hooks, `SetColdStorageStackClientsForTesting`, `RunHotCleanup` walk (D-08's mid-walk eviction boundary)
- `SuperGenius/src/transaction/TxPruner.cpp` / `.hpp` — interrupt seams (`kInterruptBeforeErase`, `kInterruptAfterColdGate`, Phase 16 sibling); `PruneCycleStats`
- `SuperGenius/src/transaction/PruneEligibility.cpp` / `.hpp` — marker key builders (no third builder); tri-state lookup
- Phase 15/18 test homes — `cold_compose_matrix_test.cpp`, `cold_downgrade_e2e_test.cpp` families (sibling-file pattern D-02 follows; researcher confirms exact paths/homes on the current line)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **The v1.1 fault-race kit** — TimingS3Client (latency/jitter/op-barrier decorator), WindowGate cv-latch, GC pass hooks, `InMemoryS3Client`/`InMemoryS3AdminClient` installed fakes — drives every new case (D-05)
- **Interrupt-seam family** (`kInterruptBeforeErase`, `kInterruptAfterColdGate`, Phase 16 SC1 sibling) — the deterministic interleaving layer; new serve-side seams join this family
- **Phase 15 tri-state evidence fakes + `/prune/blk` marker writers** — injected evidence states for walk/serve boundaries
- **Phase 14 journal-injection kit** — direct CF seeding for deterministic state setup
- **The two-GlobalDB full-wire recipe** (v1.1 resurrection leg 3) — real pubsub, real cold stack override, `gc_disposed_marker_count` observables — the ONE full-wire leg's template (D-06)
- **Tier-1 lane machinery** — `ctest -L` labels, cold-ON step env (`SGNS_TEST_P99_BOUND_MS` precedent for env-knobbed bounds), crash-report capture, exclusion regex plumbing in both workflows

### Established Patterns
- **Hermetic-first CI, dev-gated live evidence** — D-06/D-10's tiering
- **Red-first counter-tests via fault-injected bad state** — Phase 18 D-01 (no live bug required to prove the guard)
- **Barrier-driven, never sleeps; env-knob reproducibility on every nondeterministic test** — SC1's letter; the v1.1 norm
- **Instrument, don't bump** — poll-deadline exhaustion on some platforms only = structural: dump status in the failure message (v1.1 round-6 discipline; D-06's deadlines)
- **Append-never-replace filter composition; `*-A:B:C` grammar** — D-12's lane discipline
- **Hazard-loud failure modes** — `VALUE_PRESENT_INVARIANT_VIOLATION` stays loud (SC1); dedicated counters per unhealthy state

### Integration Points
- The sibling suite registers alongside the existing cold test targets and joins the cold Tier-1 label set (D-02/D-11)
- The permanent cold-ON Tier-1 lane extends the existing OSX ON-leg pattern in both workflows (D-09)
- The `notes/19-*` doc joins the rulings chain and is cited from the quarantine/evidence tables (D-13)
- The refreshed fresh-clone checklist extends `12-FRESH-CLONE-CHECKLIST.md` (D-15)

</code_context>

<specifics>
## Specific Ideas

- The matrix table (case → boundary → hazard → layer → tier) is the artifact TEST-02 verification reads — render it in the `notes/19-*` doc (and optionally the suite header) so the case list and the record cannot drift
- The quarantine table must carry first-occurrence run IDs per entry — history is what makes an exclusion defensible (v1.1 rounds 4-14 pattern)
- The full-wire leg's failure messages must dump the involved status structs (the round-6/round-11 diagnostics that cracked the v1.1 wedges)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (The known macOS exit-time teardown debt and the multi_node smoke Release-only flake were referenced as quarantine-table entries, not scope; their fixes remain SuperGenius backlog items per the v1.1 round-14 ruling.)

</deferred>

---

*Phase: 19-Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone*
