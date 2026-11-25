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

## Milestone: v1.2 — SuperGenius Cold-Storage Archive Integration

**Shipped:** 2026-11-25
**Phases:** 7 (13-19) | **Plans:** 25

### What Was Built
- The archive-tier semantics: TxPruner erases hot data only when every constituent block is evidence-Durable in cold (exact-equality admission at the cycle filter, in-compose TOCTOU re-check under the compose lock, deferrals as counters never errors), with the PruneEligibility evaluator kept contractually pure so develop's evaluator composes rather than conflicts.
- Evidence outranks bytes on every read path: one GlobalDB-owned role-aware predicate answers pruned / evicted-restorable / not-found consistently across HasBlock, getNode, and the cold chain — fixing both research-discovered bugs (the cold-chain resurrection gap and the forced-walk GC-evicted conflation), with pruned distinct from not-found at the protocol surface so requesters fail over to archive nodes.
- TxPruner × GC composition hardened: the stale-LRU erase window closed by post-commit DeleteCIDBlock parity, an 18-leg interleave matrix with the order-dependences asserted as the divergence table, and the disposal-starvation interplay ruled fail-safe (under-prune).
- Seal growth measured and decided (52.000 B/row at 10^6/10^7; 10^8 extrapolated 5.2 GB / ~16 s full sweep — accept; redesign deferred to the D-11 numeric triggers); D-12 validated kForcedWalkPeerFailoverPerCid = 8 in-band.
- The two-halves policy (cold permanent this milestone + the GC walk-gap evidence exemption shipped as code) and the archive→light downgrade interlock (persisted role fingerprint + `downgrade_acknowledged` ack + start-normally disarm), E2E-proven on the t0→t3 single-node timeline.
- The capstone: the X1..X11 cross-feature fault-race matrix (both production gaps it exposed — X1/X2 serve TOCTOU, X11 wire resurrection — fixed forward and re-proven red→green) plus the Tier-1 fail-closed CI lane green on Windows/Linux/macOS across dispatches D1–D8 at final HEAD `41776b0c0`. Zero new dependencies; sgns-blockstore frozen v1 untouched.

### What Worked
- Governing principle set at research time ("evidence outranks bytes, node-locally") held for the entire milestone — every phase's semantics derived from it without re-litigation.
- Zero-dependency composition: all v1.2 work composed pinned mechanisms; the frozen v1 library contract never moved, so integration risk stayed inside SuperGenius.
- The audit's recommended closure path (retroactive gsd-verifier for phases sealed out-of-band) worked twice — 13/15/16/17 on 2026-11-24 and phase 19 at wrap — turning execution-order drift into a same-day artifact reconciliation instead of a blocker.
- Fix-forward dispatch discipline: every cold-labeled CI failure across D1–D8 was root-caused and fixed (never quarantined, never excluded), and several fixes were real production improvements (the X11 merge-gate, the buffer.hpp ctor, the MoltenVK install skip).
- Milestone audit before close: the gaps_found verdict with ONE artifact blocker (not a delivery blocker) gave the wrap an exact, cheap closure list instead of a debate.
- UAT as recorded rulings: user rulings (D8 load-class, X11 promotion bar, B1/B2 push topology, WARP environmental) committed in the notes doc doubled as the retroactive UAT record.

### What Was Inefficient
- Phase 19 closed out-of-band (19-05-SUMMARY + FRESH-CLONE-CHECKLIST) without the canonical VERIFICATION/UAT/SECURITY artifacts — the wrap then paid a retroactive verifier run to canonicalize evidence that already existed. The 2026-11-24 reconciliation fixed the same shape for four phases; the lesson did not transfer to phase 19's close.
- Wall-time-fragile assertion pattern recurred across the phase-19 dispatch trail (baseline captures racing background actors) — the "gate on what HAS deterministically happened" rule was only written down after the D7 find.
- The local environment (CloudflareWARP breaking two-node loopback dials) cost an evening of triage before being ruled environmental; the runbook entry now exists but the adapter check should be first, not last.
- STATE.md tooling quirks recurred: the percent frontmatter field dropped again by state verbs, and out-of-order phase completion rewrites linear-frontier assumptions — both repaired manually this milestone.

### Patterns Established
- Covered-file digests at final HEAD as the retroactive verification instrument (v2:sha256 over planning + production touches) — verifiable evidence without re-running suites.
- The closing-evidence table per platform/CI-dispatch (run link, full-suite lane, Tier-1 lane) as the artifact class for platform-green requirements.
- SECURITY.md L1 short-circuit (plan-authored registers, asvs_level 1, threats_open 0) as the parity baseline for every phase at archive time.
- Fix-forward-never-quarantine as the CI posture for cold-labeled failures; quarantine tables reserved for NON-cold transverse suites with documented transverse status.

### Key Lessons
1. Any assertion whose truth depends on a background actor NOT having acted yet is wall-time-fragile — gate on what HAS deterministically happened; the same applies to baseline captures (snapshot only after the full deterministic fact).
2. Close phases with their canonical artifacts at execution time; retroactive canonicalization works but costs a second pass and an audit blocker if skipped (phases 13/15/16/17 AND 19 this milestone).
3. `install(FILES)` is mtime-skippable — never let two install rules write the same output file where the second must win; REMOVE-then-install instead (the MoltenVK da17826 root cause).
4. A topic-AGNOSTIC queued peer-queue push (PubSubBroadcasterExt) means pre-dial puts do NOT isolate test legs — evidence must be armed before the dial, and merges must be gated on evidence presence at the receive seam (X11's three stacked mechanisms).
5. Check the network adapter list for CloudflareWARP FIRST when local two-node pubsub tests wedge with zero gossip connections — a 60 s zero-connection window means the dial itself is blocked, not slow.
6. When an SEH fires at case start, check the fixture actually built the stack the case seeds on before blaming teardown residue (the _LegB null-deref root cause).

### Cost Observations
- Model mix: not tracked per-model (Copilot runtime, inline + subagents; gsd-verifier retroactive runs via subagent).
- Timeline: 2026-11-13 → 2026-11-24 (12 days of execution; wrap 2026-11-25).
- SuperGenius dev_coldstorage_additions: 58 files (+23,483/−215) from the merge-prep baseline; thirdparty 1 commit (`da17826`); sgns-blockstore 0. 8 CI dispatches (D1–D8).

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 4 days | 5 | First rocksdb-backup milestone; established three-tier testing + fail-closed CI as the workstream norm |
| v1.1 | 20 days | 7 | Single-seam integration discipline; barrier-driven race instrumentation; evidence-based UAT via accepted CI runs; human-checkpoint (tag cut) protocol |
| v1.2 | 12 days | 7 | Evidence-outranks-bytes governing principle; frozen-contract zero-dep composition; retroactive verification reconciliation at close; fix-forward CI dispatch discipline (D1–D8) |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 15 ctest registrations (Tier-1 lane 12/12, full battery 14/14+) | taxonomy/conformance kit across all 3 backends | minio-cpp pinned v1.0.0, no GNUS fork |
| v1.1 | SuperGenius Tier-1: 12→17 cold-storage suites + tier1_static_audit in CI (Win 153/153, Linux 152/152, OSX 155/155 fresh-clone) | fault-race matrix, resurrection counter-tests, soak evidence trio, milestone audit 5/5 seams | no new third-party deps; blake2 vendored object code reused from ipfs-lite-cpp |
| v1.2 | 20 Tier-1 registrations (19 cold_* suites + tier1_static_audit) + the Tier-1 fail-closed lane in the tag-build workflow, green on all 3 platforms (D1–D8, final HEAD 41776b0c0) | X1..X11 fault-race matrix, downgrade E2E t0→t3, GC walk-gap exemption red-first; milestone audit 30/30 seams, 7/7 flows | zero new deps; sgns-blockstore frozen v1 untouched (0 commits) |

### Top Lessons (Verified Across Milestones)

1. (First milestone — candidate pool seeded above; re-rank after v1.1+)
2. Verified in v1.1: fail-closed Tier-1 discipline scaled from 15 registrations to a three-platform fresh-clone lane without lane drift (tier audit held).
3. Verified in v1.1: hermetic fakes + evidence artifacts beat live-endpoint CI — the live tier stayed dev-gated and still closed its requirement with committed evidence.
4. Verified in v1.2: a frozen library contract + zero-new-deps posture keeps composition risk inside the consumer — three milestones in, the node never broke because the library moved under it.
5. Verified in v1.2: failing-first matrices find real production bugs unit-green code masks — the X1/X2 serve TOCTOU and X11 wire resurrection gaps were both matrix finds, both fixed forward.
