# Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption - Research

**Researched:** 2026-11-19
**Domain:** C++ node internals — CRDT cold-storage GC walk exemption, node-role downgrade interlock, policy documentation (SuperGenius submodule, `dev_coldstorage_additions`)
**Confidence:** HIGH (all code anchors re-located and read against the final post-Phase-17 line `84d87d462`; all claims below carry per-claim provenance)

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

#### GC walk-gap exemption (the two-halves rule's v1.2 form)
- **D-01:** **Ship code + red-first counter-test** — the exemption lands as production code this phase, not a design record. GC's walk-gap abort site consults prune evidence: a prune-evidenced absent link is expected-absent (walk continues). A red-first counter-test fault-injects the v2 state (cold object deleted + evidence present) to prove the walk survives. This is the strongest form of SC1's "no collection can ever land without the exemption" — v2 collection cannot ship without the exemption already existing and tested. Design-record-only and tripwire-test alternatives were considered and rejected (documented-not-enforced; today's abort recorded as a future failure mode) — **Reversibility:** costly — the counter-test becomes part of the evidence chain any v2 collection milestone gates on; removing it re-opens the poisoned-GC-triangle prevention argument (PITFALLS Interaction A)
- **D-02:** **Consult routes through the Phase 15 role-aware GlobalDB evidence predicate** — the GC walk's gap site derives its verdict from the SAME single predicate the serving path and forced walk use; "pruned" ⇒ expected-absent. Extends the Phase 15 D-04 source-consistency ruling (every classifying surface projects from ONE predicate) to the GC walk. Keys built in `PruneEligibility` — no third builder (D-C1 discipline) — **Reversibility:** costly — a GC-local second consult surface would need consistency-by-test rather than by-construction
- **D-03:** **Counter-test tiered hermetic Tier-1 + dev-gated live** (Phase 16 D-11 both-legs precedent) — the deterministic Tier-1 leg uses the hermetic fake cold with test-side deletion (the fake can delete; production adapters cannot) + `/prune/blk` evidence seeded via the sanctioned marker writer; the dev-gated live leg proves the state on a real stack
- **D-04:** **Counted-continue** — each exempted gap increments a dedicated walk-exempted counter in the GC pass stats, surfaced in the per-pass INFO summary (Phase 14 D-03 / Phase 16 D-10 never-healthy-by-omission precedent). An operator can see how much of the walked graph the exemption is carrying

#### Downgrade interlock (SC4 mechanics)
- **D-05:** **Hard gate + explicit ack config key** — a new deliberate config key (shape agent-discreet) must be set before a detected downgrade arms pruning; "operator-initiated, checklist-gated" becomes mechanically enforced, not advisory. WARN-only was considered and rejected (only as strong as log-review discipline). The new config surface is small and singular — Phase 14 D-04's no-config-knob posture applied to the durability gate and stays intact
- **D-06:** **Fire behavior = start, pruning disarmed** — on unacknowledged downgrade detection the node starts normally (serving, cold chain, sync all live) but the pruner stays disarmed with a loud WARN until acknowledged. Fail-toward-under-erase: a misconfigured node degrades to "keeps everything", never to "stops working" or "erases unacknowledged" — **Reversibility:** costly — this is the interlock's failure-mode contract; switching to refuse-to-start later changes the degradation story operators were told
- **D-07:** **Detection = persisted role fingerprint** — a small persisted meta record of the last-run role/config (node_type + pruning + cold-enabled) written at startup; archive-before → light+pruning-now = downgrade. Deterministic; cleanly distinguishes birth-tiered-light from downgraded-archive (the DB heuristic's false-positive — a birth-tiered-light's first prune cycle matches the same signature — is avoided); hermetically testable. One new tiny persisted state write
- **D-08:** **Operator checklist lives in the policy record** — the checklist (verify another archive replica exists, remote tier healthy, ack-key instructions) is a section of the Phase 18 rulings doc (D-13); the ack key's documentation references it by path. One canonical home, cited from code docs

#### Downgrade E2E (SC2/SC3/SC4 evidence)
- **D-09:** **Single-node restart topology** — one node restarted as light (same DBs + cold config, `node_type` flipped; ARCHITECTURE §(f): config surfaces are independent today, downgrade = restart). The 2-node light+archive-peer topology was considered and declined for the E2E (real-pubsub N-node tests are the repo's flakiest class; cross-node semantics already proven on Phase 15's line) — **Reversibility:** costly — the SC2 compositional interpretation (D-10) is defined against this topology; adding a node later re-opens the E2E's evidence contract
- **D-10:** **SC2's cross-node letter = compositional coverage** — the E2E proves the downgraded node's half (prunes under light rules, its remote S3 objects remain intact/unchurned, refusal activates); the "fetchable from other archive nodes" claim rides on landed Phase 15 SERVE-04 semantics (distinct refusal → requesters fail over to serving archive nodes), cited as evidence. Recorded HERE so verification does not re-litigate it — **Reversibility:** costly — this defines SC2's evidence contract for the verifier
- **D-11:** **Hybrid tiering** — Tier-1 hermetic single-node re-open timeline (fake cold, deterministic t0→t3 mechanics, interlock fire/ack legs, marker accumulation, refusal activation) + a dev-gated live leg on the real S3 stack. Phase 15/16 D-11 hybrid discipline
- **D-12:** **Full t0→t3 timeline** — after markers + refusal + interlock legs, local cold copies of pruned data get retention-evicted and the test proves remote-backed serving still works for non-pruned cold data + walk health (D-01's exemption exercised in-band). Retention-age manipulation is deterministic in the hermetic tier (Phase 11 GC test precedent). Stopping at t2 was considered and declined (t3 is the capstone completeness — the steady state the policy record describes)

#### Policy record (SC1 deliverable)
- **D-13:** **One rulings doc** — `notes/18-*.md` carries everything: the two-halves policy (cold permanent this milestone, permanent-once-written invariant, v2 contract ask), the GC walk-gap exemption record, the operator downgrade checklist (D-08), the tiered-node model writeup (archive vs tiered-light vs plain-light), and the downgrade timeline documentation. Joins the `notes/16-*` / `notes/17-*` rulings chain; STATE.md gets a one-liner (Phase 17 D-10 precedent) — **Reversibility:** costly — later phases cite this doc by location (the rulings-chain discipline); moving it breaks the citation chain
- **D-14:** **V2 contract ask = sketch, not pointer** — the record sketches the v2 `Remove` surface: what it must require (evidence-driven, node-local, per-CID — never age), why (the two-halves rule + poisoned-GC-triangle), and its preconditions (the exemption shipped — satisfied by D-01 — plus the Durable-then-`DisposedDurable` lifecycle pointer). REQUIREMENTS Future entries cross-referenced. Enough for a future milestone to plan against without re-deriving

### The Agent's Discretion
- Ack-key naming/shape and its config-file home (sgns_config.json vs the crdt config)
- Fingerprint record mechanics — which meta keyspace, what exactly is fingerprinted, when written, and its test seams
- Exemption consult mechanics at the GC walk-gap abort site — the exact seam, and how the Phase 15 predicate is exposed to the GC pass (GlobalDB injection per the `OpenColdStorageStack` precedent vs. an already-exposed surface on the post-17 line)
- Counter-test fixture shape — how the hermetic fake cold models test-side deletion; evidence seeding through the one sanctioned marker writer (testing-trap 1)
- Walk-exempted counter naming + INFO summary format
- E2E restart mechanics — in-process re-open of the same DBs (hermetic-friendly) vs. process restart; researcher confirms feasibility and picks
- SC3's no-re-drain observable — exact assertion shape (e.g. no new journal transitions / no drainer activity post-downgrade)
- Test file homes — sibling-file precedent (`cold_compose_matrix_test.cpp` / `cold_compose_live_smoke_test.cpp` pattern → e.g. a `cold_downgrade_e2e_test.cpp` family)
- Exact filename for `notes/18-*.md`
- Tier-1 floor/registration details for the new suites (label discipline, `ctest -L` contract)
- Anchor re-location strategy against the final post-Phase-17 line (see domain status note) — researcher rules exact procedure

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (SC2's cross-node exercise was resolved compositional-within-phase by D-10, not deferred; the v2 collection machinery remains a REQUIREMENTS Future entry sketched by D-14, not a Phase 18 idea.)

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POLICY-01 | Cold collectibility ships as an explicit recorded policy decision — cold objects are permanent this milestone; the machinery is documented as an sgns-blockstore v2 contract ask (frozen v1 forbids Remove). | D-13/D-14 rulings-doc pattern verified (`notes/16-*`, `notes/17-*` chain read); frozen v1 no-Remove constraint confirmed in REQUIREMENTS out-of-scope + STACK row 4; exemption machinery enabled by the located consult seam (Anchor Record, §Code Examples). |
| POLICY-02 | An archive-role downgrade (archive → light) is E2E-proven: after downgrade the node prunes under light rules, history remains fetchable from other archive nodes, and existing Durable records satisfy the prune gate without re-drain or migration. | Full-GlobalDB hermetic fixture with in-process re-open on the same dirs verified feasible (`BuildStackOnDir` + `ShutdownNow` teardown in `cold_evidence_matrix_test.cpp:390-380`); role flips via `NodeType` between opens; `TransactionManager::New` takes the role param; SC3 no-re-drain assertion shape resolved (held-drainer posture); cross-node half composes onto develop SURV-02 (verified Complete) + 19-07 refusal/failover. |

</phase_requirements>

## Summary

Phase 18 lands three coupled deliverables on the post-Phase-17 line (`dev_coldstorage_additions` @ `84d87d462`): (1) the GC walk-gap evidence exemption as production code inside `ColdStorageManager::WalkReachable`, (2) the archive→light downgrade interlock at `GeniusNode::StartPruneTimerIfConfigured` backed by a persisted role fingerprint, and (3) the two-halves policy record in the `notes/` rulings chain, E2E-proven by a single-node in-process re-open timeline test.

The central research finding: **the consult seam D-02 requires already exists on the post-17 line and needs no new injection.** `GraphsyncDAGSyncer::LookupPruneEvidence(cid)` (`graphsync_dagsyncer.cpp:366-376`) is public, ungated, returns the Phase 15 `PruneEvidenceClass` (with nullopt = cold-disabled), and the GC walk already holds the DAG syncer (`gc_dag_syncer_`, used at the gap site itself, `ColdStorageManager.cpp:838`). The "GlobalDB injection per `OpenColdStorageStack`" alternative is unnecessary — the exemption consult is a one-line call at the existing gap site. Equally important: **the poisoned-GC triangle is not a future v2 hazard on this line — it is live today for any light+cold+retention node that prunes.** `GetNodeWithoutRequest` → `FetchNodeFromColdStorage` consults evidence BEFORE the cold Get (Phase 15 SERVE-01), so a TxPruner-erased CID is unreadable to the walk even while its cold bytes still exist → every GC pass on a downgraded-posture node aborts with `pass-aborted-walk-gap`. The counter-test's red state is reachable without any v2 fault injection; the stricter deleted-cold leg (D-03's "fake can delete") adds the future-v2 coverage on top.

For the interlock, all wiring homes are verified: config read (`GeniusNode.cpp:518-536`, `PruningConfig::FromJSON`), the Light role gate (`:5202-5210`), the disarm point (the top of `StartPruneTimerIfConfigured`, `:5194`), a node-local persisted-record precedent (`/crdt/gc/epoch-watermark`, written through the attached face; `/prune/` markers via `GlobalDB::PutRaw`), and a hermetic full-GlobalDB test recipe (`SetColdStorageStackClientsForTesting` + `BuildStackOnDir` re-open) that makes the whole E2E Tier-1-real: real GlobalDB, real ColdStorageManager, real TxPruner/TransactionManager, fake S3 only.

**Primary recommendation:** Implement the exemption as a predicate consult + counted-continue at `WalkReachable`'s gap site (`ColdStorageManager.cpp:845-861`); implement the interlock as a fingerprint read/compare/write helper (unit-testable over a real GlobalDB) gated inside `StartPruneTimerIfConfigured` before pruner construction; build the E2E on the `cold_evidence_matrix_test` fixture recipe with in-process re-open; write `notes/18-collectibility-policy-downgrade-interlock.md` joining the rulings chain. Zero new dependencies, zero library-contract changes.

## Anchor Re-Location Record (the ruled procedure, executed)

**Procedure** (this is the concrete procedure the CONTEXT status note demands; the planner should re-run it if any commit lands on `dev_coldstorage_additions` before execution):

1. `git -C SuperGenius rev-parse HEAD` → establish the exact line. Executed 2026-11-19: **`84d87d462c529cbea93c2a67b907805cdd04a243`** (`HEAD -> dev_coldstorage_additions`, in sync with origin; = Phase 17's landing commit `84d87d462 "test(17-02): dev-gated growing-DB big legs..."`).
2. `git -C SuperGenius log --oneline -12` → confirm the post-17 production surface: Phase 17's only production touch was the conditional walk-bounds re-tune (SEAL D-12 verdict: no production touch — `kForcedWalkPeerFailoverPerCid = 8` validated in-band); commits `f758356fe` (16-03 flake stabilization) and below are Phase 16/17 test/docs.
3. Per anchor symbol: `git -C SuperGenius grep -n "<symbol>" -- <file>` then **Read** the located range (grep alone is not sufficient — the in-repo value provenance rule).
4. Record every re-located line below; planners/executor cite THESE anchors, not the CONTEXT.md estimates.

**Anchor deltas:** `GeniusNode.cpp` anchors drifted **+228 lines** from the CONTEXT estimates (4966→5194) — Phase 17's 17-01/17-02 test commits did not touch it, but earlier 16-03 work did. All other files re-located within their expected functions.

| File | CONTEXT.md estimate | **Re-located anchor @ `84d87d462`** | What lives there |
|---|---|---|---|
| `SuperGenius/src/account/GeniusNode.cpp` | prune timer arming ~:4966+; Light check ~:4978 | **:5194** `StartPruneTimerIfConfigured()`; Light check **:5202-5210** (`node_type_ != NodeType::Light` WARN-return); TxPruner::New arm **:5218-5228**; timer wiring **:5230-5290**; called from StateTransition **:1264-1265** | The interlock's disarm gate + WARN emission home; fingerprint wiring home |
| `SuperGenius/src/account/GeniusNode.cpp` | — | "pruning" config read **:518-536**; `node_type` read **:481-493**; cold-storage config read **:630-710** (`ParseColdStorageConfig`); cold config into GlobalDB **:2423** | The ack key's config-file home + the fingerprint's three inputs all resolved in `LoadSgnsConfig` |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` | GC pass / RunHotCleanup walk; gap-abort site | **`WalkReachable` :798-863**; **gap-abort site :845-861** (the `GetNodeWithoutRequest` failure branch + `pass-aborted-walk-gap` WARN); `GcPassOnce` :869-987 (per-pass INFO summary **:942** `"gc: pass complete - {} candidate(s), {} evicted..."`; zero-candidate eligibility breakdown :951-974); `EvaluatePass` :990+ (walk call :1004, abort streak :1005-1011) | D-01's consult site + D-04's counter/INFO home |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` | EvictLocalAndMarkDisposed; retention surfaces | `EvictLocalAndMarkDisposed` call **:1311** (HALF 1, under `cold_store_mutex_`, D-16 hooks around it); `RunHotCleanup` **:1347-1394** (HALF 2 + A6 LRU invalidation); `FinishOrphanedHotCleanups` :1397+; `TrimDisposedMarkers` :1477+ | The t3 leg's eviction surfaces; `Backdate` drives age via `SetSpilledAt` |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` | — | `kGcPinnedPrefix = "/crdt/gc/"` **:124**; `kGcEpochWatermarkKey` **:127** (node-local record precedent); `RetentionOptions` :96-111 (`retention_age_ms` 0=off); `GetStatus` :236; `ColdStorageStatus` atomics :603+ | Fingerprint record precedent (pinned node-local, non-replicated, direct face write) |
| `SuperGenius/src/transaction/PruneEligibility.hpp` | marker statics home; /prune/blk builders | `PRUNE_MARKER_PREFIX = "/prune/tx/"` **:418**; **`PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/"` :421**; `PruningConfig` struct **:243-292** (`FromJSON` :291 — the ack-key parse home candidate); `BuildPruneBlockMarkerKey` :520; `LookupPrunedBlockEntry` :545; `BuildPruneBlockMarkerEntry` :587; `WritePrunedBlockEntryForTest` :600+ | D-C1 one-key-home discipline; the sanctioned TEST-ONLY writer (testing trap 1) |
| `SuperGenius/src/transaction/PruneEligibility.cpp` | LookupPrunedEntry tri-state | `LookupPrunedEntry` **:180-236** (tx tri-state WITH invariant-violation leg); `LookupPrunedBlockEntry` (block lookup — **deliberately NO `VALUE_PRESENT_INVARIANT_VIOLATION` leg**: a block marker legitimately coexists with cold bytes; verdicts NOT_FOUND / PRUNED / error); `CanRestoreElement` :158-172 | The block-marker tri-state shape the exemption consult maps from |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` | OpenColdStorageStack; EraseEntry staging | `OpenColdStorageStack` call **:841**; predicate install **:870-916** (`SetPruneEvidenceLookupOnColdReadService` + the GlobalDB-owned lambda: `GetRaw` + `PrunedBlockRecord` parse, fail-closed `Malformed`); **`EraseEntry` :1572-1764** (guards 1-4 :1597-1640; guard 5 COLD_NOT_DURABLE re-check :1641-1693; `extra_entries` marker staging :1700-1712; single commit :1719; post-commit LRU invalidation :1736) | D-02's exposure path (already built); SC3's atomic erase context |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` | — | `GetRaw` **:432**; `PutRaw` **:440**; `EraseEntry` **:521**; test seams `:527/:537` (interrupt + window-observer hooks); concrete DAGSyncer member :821 | The fingerprint write/read surface (node-local raw map) |
| `SuperGenius/src/transaction/TxPruner.cpp` | RunCycle group filter; disposed consult | **`ColdGateAdmitsGroup` :89-148** (NoRecord arm consults `IsColdDisposed` :121-136); **`RunCycle` :167-440** (group filter :245-296; `EraseTransactionEntryPruned` call :312; COLD_NOT_DURABLE deferral :314-327); per-cycle INFO summary **:422-440** | What arms post-ack; the counter/INFO precedent D-04 mirrors |
| `SuperGenius/src/transaction/TxPruner.hpp` | PruneCycleStats | `PruneCycleStats` **:68-110** (`cold_disposed_stranded_groups` :109 — the Phase 16 D-10 split-counter precedent); `RunCycle` :243; interrupt seams :289 (`kInterruptAfterColdGate = 5` etc.) | Counter naming/field precedent |
| `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` | ApplyColdPrecedence / refusal classification | **`LookupPruneEvidence` :366-376** (public; `nullopt` = cold disabled = surface-availability signal); `GetNodeWithRouteBudget` :379+ (SERVE-04 terminal refusal :412-418); **`FetchNodeFromColdStorage` evidence consult :860-880** (THE consult — before the cold Get); `GetNodeWithoutRequest` :1130+ (delegates cold leg directly); `ApplyColdPrecedence` (cold-classification precedence on terminal errors) | **D-02's answer: the already-exposed surface.** SC4's refusal observable |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` | — | `Error::HISTORY_PRUNED_LOCALLY` **:108**; `Error::PRUNE_EVIDENCE_CORRUPT` **:109**; `PruneEvidenceClass` fwd-decl :31 | The distinct refusal error codes the E2E asserts |
| `SuperGenius/src/crdt/cold_read_fallback.hpp` | — | `PruneEvidenceClass` enum **:66-72** (NoEvidence/Pruned/Malformed); `ColdReadFallback` interface :77+ (ungated seam header) | The verdict vocabulary of the exemption consult |
| `SuperGenius/src/crdt/globaldb/ColdReadService.cpp/.hpp` | — | `SetPruneEvidenceLookup` **:478-487** (install-once); `LookupPruneEvidence` **:483-494** (**nullptr ⇒ NoEvidence** — the pre-install/test-stub posture) | How a hermetic fixture arms evidence for the walk consult |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp/.cpp` | — | `SetPruneEvidenceLookupOnColdReadService` :320 (ungated bridge); **`SetColdStorageStackClientsForTesting` :340+** (TEST-ONLY full-stack fake injection) | The E2E's hermetic full-GlobalDB enabler |
| `SuperGenius/src/account/NodeType.hpp` | — | `enum class NodeType : uint8_t { Full = 0, Light = 1, Archive = 2 }` **:31-37**; `ReplicatesAllAccounts` :48 | The fingerprint's role input; the downgrade flip |
| `SuperGenius/test/src/crdt/cold_storage_gc_test.cpp` | — | Fixture **:599-780** (real `LocalBlockStore` + `InMemoryS3Client`/`InMemoryS3AdminClient` fakes + real `ColdReadService`/`GraphsyncDAGSyncer`/`CrdDatastore`); `MakeManager`/`AttachGcDependencies` :721-733; **`Backdate` :750-755** (`SetSpilledAt` — deterministic retention age); `DeriveTestKey` :217 (test-side S3 object-key derivation) | The counter-test fixture + t3 retention mechanics precedent |
| `SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp` | — | `BuildStack`/`BuildStackOnDir` **:390-517** (**re-open on an EXISTING hot dir** — in-process restart proven); teardown **:355-380** (`db_->ShutdownNow()` + `pubs_->Stop()`); hermetic cold posture :424-452 (incl. held-journal faulted fakes); `TransactionManager::New(..., sgns::NodeType::Light, ...)` :505 | The E2E's fixture recipe; the role flip point |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | — | Tier-1 pattern **:386-435** (`if(SGNS_COLD_STORAGE)` → `addtest` → link set incl. `genius_node_test` whole-archive → `LABELS "Tier1"`); Tier-3 dev-gated pattern **:437-500** (`LABELS "Tier3"`, env `SGNS_BLOCKSTORE_TEST_MINIO_BIN`, loud labelled skip) | The new suites' registration contract |

All anchors above are `[VERIFIED: SuperGenius @ 84d87d462 — file:line, read this session]`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| GC walk-gap exemption consult + counted-continue | Storage/CRDT layer — `ColdStorageManager::WalkReachable` (gated TU) | — | The walk owns reachability computation; the gap site is inside it; the consult rides the syncer handle the walk already holds |
| Prune-evidence classification (ONE predicate) | CRDT serving layer — GlobalDB-installed lambda on `ColdReadService` (landed Phase 15) | `GraphsyncDAGSyncer::LookupPruneEvidence` (the exposed projection) | D-02/Phase 15 D-04 source-consistency: every classifying surface projects from one predicate; GC joins the existing consumers — it must not grow a second consult surface |
| `/prune/` key building | Transaction layer — `PruneEligibility` statics | — | D-C1 no-third-builder discipline; the fingerprint's key home belongs in the same discipline |
| Downgrade detection (fingerprint read/compare/write) | Node wiring — `GeniusNode` (config resolved) + node-local raw record via `GlobalDB::PutRaw/GetRaw` | Transaction layer (helper home candidate for hermetic testability) | All three fingerprint inputs (node_type, pruning, cold-enabled) resolve in `LoadSgnsConfig`; the record is node-local non-replicated state |
| Pruner arming / disarm gate | Node wiring — `StartPruneTimerIfConfigured` | `TxPruner::New` factory (defense-in-depth re-check candidate) | The timer is the single arm point; D-06's disarm = WARN + return before construction |
| Interlock acknowledgment (consent) | Config layer — `sgns_config.json` "pruning" object via `PruningConfig::FromJSON` | — | GATE-06 home; per-key type-checked reads; the ack is operator consent, lives beside the consent gate |
| E2E downgrade timeline | Test layer — `test/src/crdt/` sibling suites | — | Hermetic-first discipline; real GlobalDB + fake S3 |
| Policy record | Workstream planning tree — `notes/18-*.md` | STATE.md one-liner | D-13 rulings-chain discipline (cited by location) |
| Cross-node fetchability claim (SC2 letter) | Compositional citation — Phase 15 SERVE-04 + develop SURV-02/19-07 | — | D-10 locks this: proven semantics cited, not re-proven |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---|---|---|---|
| (in-repo) `ColdStorageManager` / `WalkReachable` | @ `84d87d462` | The GC pass + walk the exemption modifies | The only reachability oracle; D-16 two-half machinery consumed as-is |
| (in-repo) `GraphsyncDAGSyncer::LookupPruneEvidence` | @ `84d87d462` | The exemption's consult — Phase 15 predicate projection, public + ungated | D-02's single-predicate ruling; already exposed to the GC pass via `gc_dag_syncer_` |
| (in-repo) `PruneEligibility` statics | @ `84d87d462` | `/prune/tx`, `/prune/blk` key homes, `PrunedBlockRecord` shape, sanctioned TEST-ONLY writer | D-C1 one-home; testing trap 1 (no hand-built keys) |
| (in-repo) `GlobalDB::GetRaw/PutRaw` | @ `84d87d462` | Node-local raw record surface for the fingerprint | The `/prune/` markers and journal already use it; non-replicated, never broadcast |
| (in-repo) GTest + `addtest`/LABELS | ~1.14 (pinned) | Test framework + lane registration | Repo convention; `ctest -L Tier1` contract |
| (in-repo) `InMemoryS3Client`/`InMemoryS3AdminClient` | vendored (sgns-blockstore) | Hermetic fake cold (the fake that CAN delete) | The GC-test fixture precedent; `SetColdStorageStackClientsForTesting` for full-stack runs |

### Supporting
| Library | Version | Purpose | When to Use |
|---|---|---|---|
| `SetSpilledAt` (via fixture `Backdate`) | @ `84d87d462` | Deterministic retention-age manipulation | t3 leg; counter-test age setup |
| `GcPassOnce` direct-drive + dormant default cadence | @ `84d87d462` | Deterministic GC passes without the background thread | All hermetic GC legs (`gc_interval_ms = 0` ⇒ dormant) |
| `TxPruner::RunCycle` + interrupt seams (`kInterruptBeforeErase` etc.) | @ `84d87d462` | Driving/observing prune cycles + interleaves | E2E t2; interlock disarm observability |
| `PollUntil` poll-predicate helper | test convention | Bounded waits | Every wait in the new suites (never fixed sleeps — Windows CI) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|---|---|---|
| `gc_dag_syncer_->LookupPruneEvidence` consult | New GlobalDB-injected callable via `OpenColdStorageStack` widening | More wiring, a second exposure path for one predicate — rejected (D-02 consistency-by-construction) |
| Error-code matching (`HISTORY_PRUNED_LOCALLY` from `GetNodeWithoutRequest`) at the gap site | — | Carries the same info today but couples the walk to serve-path error taxonomy; brittle if the chain reorders; the consult is the ruled single source |
| DB-content heuristic downgrade detection | Persisted fingerprint (D-07) | Heuristic false-positives on birth-tiered-light (ruled out by D-07) |
| 2-node real-pubsub E2E | Single-node restart (D-09) | Flakiest test class in the repo (testing trap 5); declined |

**Installation:** none — zero new dependencies is a workstream rule (STATE.md key decisions; SUMMARY-v1.2 "zero new libraries"). No package installs occur in this phase; the Package Legitimacy Audit below is therefore vacuous.

## Package Legitimacy Audit

> No external packages are installed by this phase (workstream zero-new-dependencies rule; verified against the phase boundary — all changes are in-repo C++ sources, tests, and planning docs).

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| — | — | — | — | — | — | N/A (no packages) |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram — the composed downgrade flow (t0→t3) and the exemption

```mermaid
flowchart TD
    subgraph t0["t0 — archive era (open #1: NodeType::Archive + cold ON)"]
        A1[Publish history through real CRDT Put] --> A2[decorator journals spills]
        A2 --> A3[drainer → journal Durable + S3 objects permanent]
        A1 --> A4[ShutdownNow + teardown — DBs/cold dir/S3 fake persist]
    end

    subgraph t1["t1 — restart light (open #2: same dirs, NodeType::Light + pruning ON)"]
        B1[GlobalDB re-open on same hot dir + cold config] --> B2{fingerprint check at StartPruneTimerIfConfigured}
        B2 -- "prev=Archive, now=Light+pruning, ack absent" --> B3[START NORMALLY — pruner DISARMED + loud WARN<br/>(D-06 fail-toward-under-erase)]
        B2 -- "ack present OR no downgrade" --> B4[prune timer arms]
        B3 -- "operator sets ack key + restart" --> B4
    end

    subgraph t2["t2 — prune cycles (light rules)"]
        B4 --> C1[TxPruner::RunCycle evaluate]
        C1 --> C2[ColdGateAdmitsGroup: archive-era journal Durable ⇒ admit<br/>(SC3: no re-drain — held-drainer proves it)]
        C2 --> C3[EraseEntry: one batch — value+block+raw-map removal +<br/>/prune/tx + /prune/blk markers, seals retained]
        C3 --> C4[markers accumulate (LookupPrunedBlockEntry = PRUNED)]
        C4 --> C5[refusal activates: GetNodeWithoutRequest ⇒<br/>HISTORY_PRUNED_LOCALLY (SERVE-04 semantics)]
    end

    subgraph t3["t3 — steady state (retention GC)"]
        D1[GC pass: walk from heads] --> D2{link missing from<br/>hot+LRR+cold+remote?}
        D2 -- "no" --> D3[walk continues]
        D2 -- "yes (gap site :845)" --> D4{LookupPruneEvidence consult<br/>(D-02 — the ONE predicate)}
        D4 -- Pruned --> D5[COUNTED-CONTINUE: treat as expected-absent leaf<br/>++walk_exempted (D-04)]
        D4 -- "Malformed" --> D6[ABORT pass — fail closed]
        D4 -- "NoEvidence / nullopt" --> D7[ABORT pass — today's behavior]
        D5 --> D8[retention evicts local cold copies of pruned data<br/>(EvictLocalAndMarkDisposed) — remote S3 objects REMAIN]
        D8 --> D9[remote-backed serving still works for non-pruned cold data<br/>+ walk_exact = true, exempted counter &gt; 0]
    end

    C5 --> D1
```

A reader traces SC2/SC3/SC4 from t0 to t3; the t3 decision diamond IS the poisoned-GC-triangle defusal (D-01). The cross-node half of SC2 rides compositionally on Phase 15 SERVE-04 + develop SURV-02 (D-10): the downgraded node's distinct refusal is exactly the signal that makes requesters fail over to serving archive nodes.

### Recommended Project Structure
```
SuperGenius/src/
├── crdt/globaldb/ColdStorageManager.cpp/.hpp   # MODIFIED: gap-site consult + walk_exempted counter/status
├── account/GeniusNode.cpp                       # MODIFIED: interlock gate + fingerprint wiring + Light+cold WARN/INFO
├── transaction/PruneEligibility.hpp/.cpp        # MODIFIED (small): ack-key parse (PruningConfig) + fingerprint key home/statics
│                                                #   (or a sibling helper header if the planner prefers a unit-testable seam)
SuperGenius/test/src/crdt/
├── cold_gc_walk_gap_exempt_test.cpp             # NEW Tier-1: red-first counter-test (D-03)
├── cold_downgrade_e2e_test.cpp                  # NEW Tier-1: t0→t3 timeline + interlock legs (D-11/D-12)
├── cold_downgrade_live_smoke_test.cpp           # NEW Tier-3: dev-gated live leg (SGNS_BLOCKSTORE_TEST_MINIO_BIN)
.planning/workstreams/rocksdb-backup/notes/
└── 18-collectibility-policy-downgrade-interlock.md   # NEW: the policy record (D-13/D-14/D-08)
```

### Pattern 1: Evidence consult at a destructive/aborting boundary (one predicate, fail-closed arms)
**What:** Every surface that classifies a CID by prune evidence calls the same predicate; only the `Pruned` arm is permissive; `Malformed` always fails closed; absence of the surface (`nullopt`) preserves legacy behavior.
**When to use:** The gap-site consult mirrors `FetchNodeFromColdStorage`'s switch (`graphsync_dagsyncer.cpp:868-880`) — copy that shape.
**Example:** see Code Examples §1.

### Pattern 2: Node-local pinned meta record
**What:** Small, non-replicated, never-broadcast records written through the direct face — `/prune/` markers (`PutRaw`), `/crdt/gc/epoch-watermark` (pinned prefix, direct hot-store write). The fingerprint joins this family: tiny payload, written at startup after read-compare, under a keyspace GC hot-cleanup never sweeps.
**When to use:** D-07's fingerprint. Crash-between-read-and-write is safe: stale fingerprint ⇒ downgrade re-detected next boot (fail-closed direction).

### Pattern 3: Hermetic full-stack via TEST-ONLY client override
**What:** `SetColdStorageStackClientsForTesting(InMemoryS3Client, InMemoryS3AdminClient)` around `GlobalDB::New` runs the real stack (real `ColdStorageManager`, real drainer, real GC, real predicate install) with zero network; re-open on the same dir = in-process restart.
**When to use:** The E2E (D-11 hermetic tier) and the interlock's fingerprint legs.

### Pattern 4: Both-homes documentation (code comment + rulings doc)
**What:** Phase 16 D-12 discipline — the full analysis lives in the rulings doc; the two code sites carry ruling comments pointing at it (see the `[D-12, v1.2 Phase 16, COMP-03]` comment block at `ColdStorageManager.cpp:1298-1305` for the exact shape).
**When to use:** The exemption site, the interlock gate, and the ack-key parse all get `[...]`-style ruling comments citing `notes/18-*`.

### Anti-Patterns to Avoid
- **A second evidence surface:** building the gap-site verdict from raw `/prune/blk` reads or error-code matching instead of `LookupPruneEvidence` — re-opens D-02 consistency-by-construction.
- **Treating `Malformed` as exempted (or as NoEvidence):** unreadable evidence at the gap must ABORT (fail closed) — mirroring the predicate's own Pitfall-7 arms.
- **Interlock that blocks startup or erases unacknowledged:** D-06's contract is start-normally + disarm; any harder failure mode changes the operator story.
- **Hand-built marker keys in tests:** evidence seeding goes through `BuildPruneBlockMarkerEntry`/`WritePrunedBlockEntryForTest` (D-C1; testing trap 1).
- **Exempting by age or any non-evidence signal:** collectibility is evidence-driven, never age (P4) — the exemption consult must read ONLY the predicate.
- **Fingerprint keyed on mutable storage that GC can sweep:** keep it under `/prune/`-family (GC hot-cleanup never touches it; marker-namespace crossfire prevention, Pitfall 5) or a pinned prefix.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Prune-evidence classification at the gap | A GC-local `/prune/blk` reader | `GraphsyncDAGSyncer::LookupPruneEvidence(cid)` | One predicate (D-02); handles cold-disabled (`nullopt`) and malformed (`Malformed`) arms already; consistency by construction |
| Marker key/record construction | Ad-hoc key strings in tests | `PruneEligibility::BuildPruneBlockMarkerEntry` / `WritePrunedBlockEntryForTest` | D-C1 one-home; WR-04 shape guarantees; testing trap 1 |
| Hermetic cold tier | New fake block stores | `InMemoryS3Client` + `InMemoryS3AdminClient` (+ `SetColdStorageStackClientsForTesting` for full-stack) | Proven across GC/durability/evidence/compose suites; the fake legitimately CAN delete (v2-state fault injection) |
| Retention-age determinism | Wall-clock sleeps | `Backdate` fixture helper → `LocalBlockStore::SetSpilledAt` | Phase 11 precedent; deterministic under load |
| GC pass determinism | Background-thread timing | Direct `GcPassOnce()` drive with `gc_interval_ms = 0` (dormant default cadence) | The GC-suite discipline |
| Re-open/restart mechanics | Process spawn | In-process `ShutdownNow` + rebuild on same dirs (`BuildStackOnDir` recipe) | Proven in `cold_evidence_matrix_test.cpp`; hermetic-friendly, no process management |
| Waits | Fixed sleeps | `PollUntil` bounded predicates | Windows CI starvation landmine (testing trap 5) |

**Key insight:** every mechanism this phase needs — predicate, markers, fakes, retention manipulation, re-open, direct-drive — already exists and is test-proven on this line. The phase is composition + one consult + one gate + one record.

## Common Pitfalls

### Pitfall 1: The poisoned-GC triangle is LIVE on this line (not a v2-only hazard)
**What goes wrong:** A light+cold+retention node that prunes anything: the next `GcPassOnce` walk reaches the pruned CID; `GetNodeWithoutRequest` → `FetchNodeFromColdStorage` consults evidence BEFORE the cold Get (`graphsync_dagsyncer.cpp:868-880`) and returns `HISTORY_PRUNED_LOCALLY` even while cold bytes exist; `WalkReachable` sees a node-miss → `pass-aborted-walk-gap` → **GC liveness broken from the first prune cycle onward**.
**Why it happens:** Phase 15 made evidence outrank bytes on the serve path; the GC walk still treats every unreadable link as a gap.
**How to avoid:** The exemption consult (this phase). Write the counter-test's LEG-1 against exactly this state (evidence + hot-gone + cold-present) — it is red TODAY; LEG-2 (cold deleted both tiers via the fake's deletion + `DeriveTestKey`) adds the v2-state coverage.
**Warning signs:** `gc: pass-aborted-walk-gap` WARN streaks on any downgraded-posture node; `gc_abort_streak_` climbing.

### Pitfall 2: Birth-tiered-light false positive (the interlock's own hazard)
**What goes wrong:** A fresh light node's first prune cycle looks like a downgrade to any DB-content heuristic (markers absent + Durable records present).
**Why it happens:** Archive-era Durable records are indistinguishable from a light node's own spilled history by content alone.
**How to avoid:** D-07's persisted fingerprint — absence of a prior fingerprint = first run = no downgrade. The E2E must include a birth-tiered-light control leg proving no interlock fire.
**Warning signs:** interlock WARN on a node that was never an archive node.

### Pitfall 3: Under-erase direction inversion at the interlock
**What goes wrong:** An interlock failure mode that erases, blocks startup, or serves inconsistently.
**How to avoid:** D-06 exactly: detected-unacknowledged ⇒ node fully starts, pruner disarmed, one loud WARN (repeat-cadenced like the GC inhibit streaks — 1st + every Nth). Every error path in the fingerprint read (missing record, unreadable record) resolves to the SAFE arm (no downgrade detected OR disarm — planner picks, but never to "arm anyway on parse failure").
**Warning signs:** any interlock code path whose failure arms the pruner.

### Pitfall 4: Marker-namespace crossfire / swept fingerprint
**What goes wrong:** The fingerprint record lands in a keyspace GC hot-cleanup or TxPruner sweeps; or tests hand-build `/prune/blk` keys.
**How to avoid:** Fingerprint under the `/prune/` family or a pinned `/crdt/`-style prefix (GC never sweeps either — `RunHotCleanup` deletes exactly the block's binary key + own membership rows); keys from `PruneEligibility` statics only.
**Warning signs:** fingerprint disappearing across GC passes in tests.

### Pitfall 5: SC3 proven the weak way
**What goes wrong:** Asserting "erased > 0" with a live drainer — a re-drain could have re-advanced states invisibly, proving nothing about NO-re-drain.
**How to avoid:** The held-drainer posture (faulted fakes — `S3Op::Put` Unavailable + admin Unreachable, the evidence-matrix `inject_hermetic_clients=false` recipe) or `drain_interval_ms = 60000`: if erases proceed while the drainer CANNOT advance anything, no re-drain was needed. Assert journal states stay Durable across the cycle AND `stats.erased > 0`.
**Warning signs:** any SC3 leg whose fixture lets a drain cycle run between open #1 and the erase assertion.

### Pitfall 6: Walk-exempted semantics drift
**What goes wrong:** "Continue" implemented as skip-without-count, descend-into-missing-links, or a counter that counts passes not CIDs.
**How to avoid:** D-04 exactly: per-exempted-CID increment, per-pass reset (alongside `pass_reclaimed_count_`), surfaced in the `"gc: pass complete"` INFO line (:942); the exempted CID is a LEAF (its links are not traversed — bytes are unavailable by definition). Never-healthy-by-omission: a persistently-growing exempted count on a steady graph signals v2 collection eating the walk — the INFO line is the operator's early-warning surface.
**Warning signs:** exempted counter exceeding the number of pruned CIDs; walk_exact=true with exempted=0 on a graph that contains pruned links.

### Pitfall 7: In-process re-open ordering
**What goes wrong:** Fixture teardown order violations (manager threads joining against dead stores; pubsub stopped before DB).
**How to avoid:** The evidence-matrix teardown verbatim: blockchain Stop → tm/account reset → `db_->ShutdownNow()` → `db_.reset()` → `pubs_->Stop()` (catch) → reset; declaration order == reverse destruction order (the GC fixture's documented rule). On rebuild, re-inject fakes BEFORE `GlobalDB::New` and clear AFTER (`SetColdStorageStackClientsForTesting(nullptr, nullptr)` hygiene).
**Warning signs:** hangs/joins in teardown on Windows CI.

### Pitfall 8: Red-first discipline skipped
**What goes wrong:** The counter-test written green (post-consult) — it then proves nothing.
**How to avoid:** D-01: write the counter-test FIRST against the unmodified walk (LEG-1 is red today — see Pitfall 1), commit/observe the failure, then land the consult. The v1.1 resurrection suite found a real defect precisely because it was failing-first.
**Warning signs:** a counter-test that has never been observed red.

### Pitfall 9: Windows/PS 5.1 command and CI quirks
**What goes wrong:** CI/portability failures misread as regressions (CloudflareWARP breaks local Windows pubsub; RocksDB LOCK fixture-dir contention; starved-runner timeouts).
**How to avoid:** FreshDir-per-case distinct paths; poll predicates; the label contract (`ctest -L`, never `-LE`, `--no-tests=error`); no real-pubsub N-node topology in the E2E (D-09 already declines it). For local runs on this Windows host: `git -C SuperGenius ...` form; PS 5.1 quoting (single-quote literal args).
**Warning signs:** flaky-only-on-Windows legs in the new suites.

## Code Examples

### 1. The exemption consult at the gap site (the production change's shape)

Source: composed from verified anchors — gap site `[VERIFIED: ColdStorageManager.cpp:845-861]`, predicate `[VERIFIED: graphsync_dagsyncer.cpp:366-376]`, consult-arm shape `[VERIFIED: graphsync_dagsyncer.cpp:868-880]` (`FetchNodeFromColdStorage`'s switch).

```cpp
// Inside ColdStorageManager::WalkReachable — the current gap branch:
//   auto node = gc_dag_syncer_->GetNodeWithoutRequest( current );
//   if ( !node.has_value() ) { /* walk-gap WARN; return { {}, false }; */ }
//
// becomes (D-01/D-02/D-04) — sketch, exact naming at planner's discretion:
auto node = gc_dag_syncer_->GetNodeWithoutRequest( current );
if ( !node.has_value() )
{
    // [D-01, v1.2 Phase 18 — GC walk-gap evidence exemption. The two-halves
    // rule: what may be absent = what may be collected. A prune-evidenced
    // link is EXPECTED-ABSENT (this node deliberately erased it) — the walk
    // treats it as a leaf and CONTINUES, counted. Consult routes through the
    // ONE Phase 15 predicate (D-02 extends SERVE-03/D-04 source-consistency
    // to the GC walk) — never a GC-local /prune/blk read. Full record:
    // notes/18-collectibility-policy-downgrade-interlock.md]
    const auto evidence = gc_dag_syncer_->LookupPruneEvidence( current );
    if ( evidence.has_value() && *evidence == PruneEvidenceClass::Pruned )
    {
        ++pass_walk_exempted_; // D-04 counted-continue; leaf — no links pushed
        continue;
    }
    // Malformed / NoEvidence / nullopt (cold disabled): abort the pass
    // toward under-eviction — exactly today's behavior (fail closed;
    // Pitfall 7 discipline — unreadable evidence is never exemption).
    ...existing walk-gap WARN + return { {}, false };...
}
```

### 2. The interlock gate at `StartPruneTimerIfConfigured` (sketch)

Source: gate home `[VERIFIED: GeniusNode.cpp:5194-5228]`, config homes `[VERIFIED: GeniusNode.cpp:481-536, 630-710]`, raw record surface `[VERIFIED: globaldb.hpp:432,440]`.

```cpp
void GeniusNode::StartPruneTimerIfConfigured()
{
    if ( !pruning_config_.enabled ) { return; }
    if ( node_type_ != NodeType::Light ) { ...existing WARN-return... }

    // [D-05/D-06/D-07, v1.2 Phase 18 — downgrade interlock] Read the
    // persisted role fingerprint (node_type + pruning + cold-enabled,
    // written at every startup through the node-local raw surface);
    // archive-before -> light+pruning-now = DOWNGRADE. Without the explicit
    // ack key the node STARTS NORMALLY but the pruner stays DISARMED with a
    // loud WARN (fail-toward-under-erase). Checklist: notes/18-*.md §operator.
    const auto verdict = RoleFingerprint::CheckAndRewrite( *tx_globaldb_,
                                                            node_type_,
                                                            pruning_config_,
                                                            cold_storage_config_.enabled );
    if ( verdict == RoleFingerprint::DowngradeUnacknowledged )
    {
        node_logger_->warn( "ROLE DOWNGRADE DETECTED (archive/full -> light+pruning) - pruning DISARMED. "
                            "Set \"<ack key>\": true in sgns_config.json's pruning object after completing "
                            "the operator checklist (see notes/18-collectibility-policy-downgrade-interlock.md) "
                            "and restart to arm pruning." );
        return; // D-06: serving, cold chain, sync all live; pruner disarmed
    }
    ...existing TxPruner::New arm + timer wiring...
}
```
(Whether `RoleFingerprint` lives as `PruneEligibility` statics or a sibling helper is planner's pick — the hermetic-testability argument favors a small dedicated unit either way; both `GetRaw`/`PutRaw` and the fixture recipe are verified.)

### 3. E2E timeline skeleton (fixture recipe, Tier-1 hermetic)

Source: `[VERIFIED: cold_evidence_matrix_test.cpp:390-517]` (BuildStackOnDir + role param), `[VERIFIED: cold_storage_gc_test.cpp:165-185, 721-755]` (retention/Backdate/MakeManager), teardown `[VERIFIED: :355-380]`.

```cpp
// Leg order = the t0->t3 timeline (D-12):
// t0: BuildStackOnDir(cold=true, drain fast, NodeType::Archive role param);
//     SeedTransaction(...); WaitAllDurable(cids);  // journal Durable + fake S3 objects
//     interlock leg 0: fingerprint written as Archive posture
//     teardown (ShutdownNow recipe)
// t1: BuildStackOnDir(same hot_dir, cold=true, NodeType::Light, pruning enabled);
//     EXPECT interlock: pruner disarmed (no cycles run; no markers; the WARN is
//     observable via the logger sink or the fingerprint helper's verdict API)
//     ack leg: flip the ack key (rebuild stack or set config before open) -> armed
// t2: SC3 leg: re-open with HELD drainer (faulted fakes / drain_interval 60000);
//     TxPruner::RunCycle -> erased > 0 while journal states stayed Durable
//     (no re-drain provable: the drainer cannot advance anything)
//     markers: LookupPrunedBlockEntry(cid) == PRUNED (accumulate from zero)
//     refusal: GetNodeWithoutRequest(pruned_cid) error == HISTORY_PRUNED_LOCALLY
// t3: attach GC (retention fast, interval dormant); Backdate(pruned cold copies);
//     GcPassOnce() -> walk_exact, exempted counter > 0, local cold evicted
//     (EvictLocalAndMarkDisposed), remote-backed serving still works for
//     non-pruned cold data (fake S3 still holds bytes; Get succeeds + rehydrates)
```

### 4. Verbatim values the planner will need (all read this session)

- `PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/"` — `[VERIFIED: PruneEligibility.hpp:421]`
- `PRUNE_MARKER_PREFIX = "/prune/tx/"` — `[VERIFIED: PruneEligibility.hpp:418]`
- `kGcPinnedPrefix{ "/crdt/gc/" }`, `kGcEpochWatermarkKey{ "/crdt/gc/epoch-watermark" }` — `[VERIFIED: ColdStorageManager.hpp:124-127]`
- `enum class NodeType : uint8_t { Full = 0, Light = 1, Archive = 2 };` — `[VERIFIED: NodeType.hpp:31-37]`
- `enum class PruneEvidenceClass : uint8_t { NoEvidence, Pruned, Malformed };` — `[VERIFIED: cold_read_fallback.hpp:66-72]`
- `Error::HISTORY_PRUNED_LOCALLY` / `Error::PRUNE_EVIDENCE_CORRUPT` — `[VERIFIED: graphsync_dagsyncer.hpp:108-109]`
- Per-pass INFO format today: `"gc: pass complete - {} candidate(s), {} evicted (retention {} ms, dry_run {})"` — `[VERIFIED: ColdStorageManager.cpp:942-945]`
- Per-cycle INFO format today: `"Prune cycle [generation {}]: examined={}, eligible={}, erased={}, held_blocks={}, cold_deferred={}, cold_unreadable={}, cold_disposed_stranded={}, skipped={}, errors={}, duration_ms={}, watermark={} — bytes reclaimed: not measured until Phase 20"` — `[VERIFIED: TxPruner.cpp:422-440]`
- Registration idiom: `addtest(<name> <file>.cpp)` + link set + `set_tests_properties(<name> PROPERTIES LABELS "Tier1")` under `if(SGNS_COLD_STORAGE)` — `[VERIFIED: test/src/crdt/CMakeLists.txt:386-435]`; Tier-3 live: `LABELS "Tier3"` + env `SGNS_BLOCKSTORE_TEST_MINIO_BIN` `[VERIFIED: :437-500]`

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| GC walk treats every unreadable link as an abort-worthy gap | Evidence-aware exemption consult (this phase) | Phase 18 | Keeps GC live on downgraded nodes; two-halves rule enforced in code |
| Downgrade detection imagined as DB-content heuristic (v1.2 research §(f)) | Persisted role fingerprint (D-07) | Phase 18 decision | Deterministic, false-positive-free, hermetically testable |
| Advisory-only downgrade documentation | Mechanical ack-key interlock (D-05) | Phase 18 decision | "Operator-initiated, checklist-gated" becomes enforced |
| Collectibility deferred silently to v2 | Recorded v2 contract-ask sketch + shipped exemption precondition (D-14 + D-01) | Phase 18 | A future v2 collection milestone can plan directly; the exemption already gates it |

**Deprecated/outdated:** none on this line — the phase composes Phase 14/15/16/17 surfaces as-is.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The ack key should live in the `"pruning"` object of sgns_config.json (e.g. `"downgrade_acknowledged": true`), parsed by `PruningConfig::FromJSON` | Discretion resolution 1 | Low — any single-home config location works; moving it later is a config-migration footnote |
| A2 | A **Full→Light+pruning** flip should ALSO fire the interlock (not only Archive→Light) — `ReplicatesAllAccounts` is the dangerous-hold property; the checklist applies identically | Discretion (D-07 interpretation) | Low/medium — planner + user should confirm the fingerprint's downgrade predicate includes Full; if Archive-only, a Full→Light downgrade would arm un-gated |
| A3 | `notes/18-collectibility-policy-downgrade-interlock.md` as the rulings-doc filename | Discretion resolution 9 | None — any `notes/18-*.md` satisfies D-13; the chain cites by location once written |
| A4 | The Light+cold posture WARN/INFO line (ARCHITECTURE §2 "GeniusNode ... Light+cold WARN/INFO") does not exist yet on this line (grep found no such log line) — the phase adds it | SC4 observability | Low — verified absent by grep this session; if one exists elsewhere the phase merely amends it |
| A5 | GeniusNode-level hermetic wiring test (WARN/disarm at the node layer) follows the `node_startup_test.cpp` recipe (`SetColdStorageStackClientsForTesting` around `GeniusNode::New`) if the planner wants node-level coverage beyond the helper-unit legs | Test tiering | Low — the helper-unit + BuildStackOnDir legs already cover the verdict logic; node-level is defense-in-depth |

All other claims in this research are `[VERIFIED: ...]` (read at `84d87d462` this session) or `[CITED: <doc>]` (workstream planning docs read this session). No web sources were used — the phase is entirely in-repo; external search providers are disabled in this environment's config anyway.

## Open Questions (RESOLVED)

> All three resolved by the 18-02 planner rulings (recorded in 18-02-PLAN.md objective + tasks). Dispositions appended per question below — original question text preserved.

1. **Full→Light in the downgrade predicate (A2)** — What we know: D-07's letter says "archive-before → light+pruning-now"; Full nodes also hold replicating history and also never prune (GATE-01 Light-only). What's unclear: whether the user's intent covers Full. Recommendation: include Full (any `ReplicatesAllAccounts` prior role); one line in the fingerprint compare + one E2E control leg. Confirm at plan review. **(RESOLVED — 18-02 ruling, A2/FP-FullFires):** Full IS included — the RoleFingerprint::CheckAndRewrite downgrade predicate is (prior node_type ∈ {Full, Archive}) AND Light+pruning-now (any ReplicatesAllAccounts prior role is a downgrade source), pinned by the FP-FullFires Tier-1 leg in cold_downgrade_e2e_test; remains a flagged assumption in 18-02 for user sign-off at review (override cost: one predicate line + one leg).
2. **Fingerprint write timing under ack** — What we know: read-compare-rewrite at `StartPruneTimerIfConfigured` (or at config-load + db-init junction). What's unclear: whether the rewrite should happen even when the timer never arms (disabled pruning ⇒ no downgrade risk ⇒ arguably still write, keeping the record fresh). Recommendation: always write at startup once `tx_globaldb_` exists (fresh record, no stale-downgrade ghost after a role change back); cheap and monotone. **(RESOLVED — 18-02 ruling):** written EVERY startup — the check/rewrite runs at the top of GeniusNode::StartPruneTimerIfConfigured BEFORE the pruning-enabled early return (an archive-era node typically runs pruning-disabled; a write gated on pruning-enabled would leave every later downgrade blind), once tx_globaldb_ exists; fresh record each boot, crash-between-read-and-write safe (stale ⇒ re-detected next boot).
3. **WARN cadence for the disarmed pruner** — one-shot at startup vs. repeat-with-streak (the GC inhibit-streak shape). Recommendation: one-shot at startup + a cadenced repeat if something later tries to arm (or a status getter the operator can poll); keep it simple — D-06 only demands "loud". **(RESOLVED — 18-02 ruling):** one-shot WARN at startup — the gate runs once per boot and the WARN text carries the full operator instruction (ack key, sgns_config.json pruning object, checklist path); D-06 demands loud, not cadenced. The cadenced-repeat/status-getter extension was not adopted this phase.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows + PowerShell 5.1 host | local runs | ✓ | — | Use `git -C SuperGenius ...`; single-quote literals (PS 5.1) |
| SuperGenius submodule @ `dev_coldstorage_additions` | everything | ✓ | `84d87d462` (== origin) | — |
| CMake + MSVC 17 2022 + Ninja/generator presets | builds | ✓ (repo-standard) | per `build/Windows/` | existing build tree |
| GTest (~1.14) | new suites | ✓ | pinned via thirdparty | — |
| `SGNS_BLOCKSTORE_TEST_MINIO_BIN` | Tier-3 dev-gated live legs only | ✗ (opt-in by design) | — | Loud labelled skip (the established Tier-3 contract); NOT in Tier-1 lane |
| MinIO binary + real S3 stack | Tier-3 live leg | ✗ unless dev sets env | — | Same as above |

**Missing dependencies with no fallback:** none — nothing blocks execution.
**Missing dependencies with fallback:** the Tier-3 env gates (by design; the workstream has one outstanding live-leg UAT from Phase 16 in the same posture — precedent for `human_needed` verification rather than blocking).

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1`, `security_block_on: high` (`.planning/config.json`, read this session). Level-1-relevant categories for this phase:

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No identity/credential surface touched |
| V3 Session Management | no | No session surface |
| V4 Access Control | **yes** | The ack key IS an operator authorization gate (D-05): a persisted-state-destroying capability (pruning post-downgrade) requires an explicit, deliberate config consent. Control: single-key explicit ack + persisted fingerprint + fail-toward-under-erase (V4.1 deny-by-default posture) |
| V5 Input Validation | **yes** | The fingerprint record and any ack-key value are parsed from persisted/config input: malformed fingerprint must resolve to the SAFE arm (never arm-on-parse-failure); ack-key parsing follows `PruningConfig::FromJSON`'s per-key type-checked fail-closed discipline (`PruneEligibility.hpp:291` contract) |
| V6 Cryptography | no | No new crypto; CID verification stays inside the library (never bypassed) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silent downgrade via config tamper (an operator or stray edit flips node_type+pruning) | Elevation | D-05/D-07 interlock: persisted fingerprint + ack key + disarm (this phase's core control) |
| Destructive action on unreadable evidence (malformed fingerprint / malformed `/prune/blk` row) | Tampering | Fail-closed arms everywhere: `Malformed` aborts the walk consult; unreadable fingerprint resolves safe; `PRUNE_EVIDENCE_CORRUPT` stays a hard error (Pitfall 7 discipline, landed Phase 15) |
| Erase of last copy (interlock bypass via TOCTOU between fingerprint read and cycle) | Tampering/Destruction | Guard 5's compose-lock Durable re-check (`globaldb.cpp:1641-1693`, landed Phase 14) already covers the erase path; the interlock only gates ARMING, not per-erase authorization — no new TOCTOU surface |
| Test seam abuse (sanctioned writers reaching production) | Repudiation | TEST-ONLY markers on writers/hooks (`WritePrunedBlockEntryForTest`, `SetColdStorageStackClientsForTesting` — both carry explicit no-production-caller contracts); keep the new fingerprint test helpers in the same posture |

## Sources

### Primary (HIGH confidence — all read this session at `84d87d462`)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp/.hpp` — WalkReachable gap site, GcPassOnce, pass INFO, eviction halves, pinned-prefix precedents
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` + `src/crdt/graphsync_dagsyncer.hpp` — LookupPruneEvidence, FetchNodeFromColdStorage consult, refusal errors
- `SuperGenius/src/crdt/cold_read_fallback.hpp`, `src/crdt/globaldb/ColdReadService.cpp/.hpp`, `src/crdt/globaldb/ColdStorageStack.hpp` — predicate vocabulary, install surface, TEST-ONLY client override
- `SuperGenius/src/transaction/PruneEligibility.hpp/.cpp`, `TxPruner.hpp/.cpp` — marker homes, PruningConfig, gate/stats/INFO
- `SuperGenius/src/account/GeniusNode.cpp` (config reads + StartPruneTimerIfConfigured), `src/account/NodeType.hpp`
- `SuperGenius/test/src/crdt/` — `cold_storage_gc_test.cpp`, `cold_evidence_matrix_test.cpp`, `CMakeLists.txt` (fixture recipes, registration contract)
- `.planning/workstreams/rocksdb-backup/` — 18-CONTEXT.md, REQUIREMENTS.md, STATE.md, ROADMAP (phase entry), `notes/16-*`, `notes/17-*` (rulings-chain shape), 15/16/17-CONTEXTs
- `.planning/research/` — ARCHITECTURE-v1.2 (§(f), §3.5, §2, §4 item 6), PITFALLS-v1.2 (hazard 7, Interaction A, P4, AF-7 reference via FEATURES, testing traps 1/5), SUMMARY/FEATURES/STACK cited rows
- `SuperGenius/.planning/REQUIREMENTS.md` — SURV-02 letter (Complete) `[VERIFIED: :171]`; `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-07-SUMMARY.md` — refusal/failover/per-CID accounting semantics (D-10's compositional evidence)

### Secondary (MEDIUM confidence)
- None — no web sources were consulted; the phase is fully in-repo and external providers are disabled in this environment.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — everything is in-repo, read at the pinned commit; zero new dependencies verified against the phase boundary
- Architecture: HIGH — the consult seam, interlock homes, and E2E recipe are all verified-existing surfaces with test precedents on this line
- Pitfalls: HIGH — Pitfall 1 (live poisoned triangle) derived from read code paths (evidence consult precedes cold Get; walk treats the resulting miss as a gap), not inference; red-first LEG-1 reachability follows mechanically

**Research date:** 2026-11-19
**Valid until:** the next commit landing on `dev_coldstorage_additions` that touches the anchored files (re-run the Anchor Re-Location Record procedure, Step 1-4, before editing; the procedure is cheap — minutes)
