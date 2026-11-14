# Feature Research: Tiered Archive/Pruned-Node Semantics (v1.2 Cold-Storage Archive Integration)

**Domain:** Tiered-node archive/pruning semantics on the SuperGenius cold-storage stack (rocksdb-backup workstream, v1.2)
**Researched:** 2026-11-13
**Confidence:** HIGH for SuperGenius-internal facts (read from `.planning` artifacts and the v1.1 archive); MEDIUM for first-party prior-art specs fetched directly this run (BIP-159, ethereum.org, docs.ipfs.tech, docs.filecoin.io, postgresql.org — each cross-checked against independent training knowledge, exact match); LOW for BitTorrent (training data only — brave search unavailable this run) and EIP-4444 (training data, not fetched).

Note on the classify-confidence seam: it returned LOW for every provider this run (degraded — no legitimacy metadata resolvable offline). First-party fetched sources are therefore labeled MEDIUM with the dual-basis rationale above rather than the seam's flat LOW; nothing LOW is presented as authoritative.

---

## Our Context in One Paragraph (the mapping target)

One append-only global CRDT ledger. Two node roles: **archive/cold nodes** (v1.1 `blockstore` config; hot RocksDB working set + S3/s3d cold tier; hold complete history; cold is never a deletion target) and **light/pruned nodes** (develop's TxPruner; local hot erase with node-local `/prune/` evidence; never CRDT tombstones). The v1.1 stack already ships: journal-first spill-on-write, CID-verified cold-read fallback + async re-warm serving, flush-gated durability (`Durable` = s3d flush + `pendingObjects==0`), eviction-only retention GC (tombstones/metadata never purged, bounded disposed markers), keep-seal semantics (`markResolved`/`isResolved`, retained through GC since `7961ec264`), tri-state config gate. Develop ships TxPruner phases 16/18/19 (erase primitives, service, survival); 17 (eligibility dry-run, spend-recency window) and 20 (reclamation) pending. `fix/trust-genesis-bootstrap` adds the opt-in bounded forced-walk recovery whose `getNode` flows through our cold seam, with `CanRestoreElement` (PruneEligibility) as the pruned-vs-evicted pivot: **local prune evidence decides; cold bytes are never authoritative on their own.**

Prior art does not have our exact shape. Bitcoin/Ethereum prune *blocks/state from disk with nowhere else local to get them*; we have a node-local second tier (S3) that makes hot erasure *reversible in bytes but not in semantics* — evidence, not bytes, is the pivot. That inversion is the main thing prior art cannot be copied wholesale on.

---

## Feature Analysis by Category

### Table Stakes (the tiered model is broken or dishonest without these)

| # | Feature | Why Expected (prior-art basis) | Complexity | Notes |
|---|---------|-------------------------------|------------|-------|
| TS-1 | **Durability-gated TxPruner eligibility on cold nodes** — hot erase permitted only when the target block is `Durable` in cold (v1.1 `kEvictionDurabilityGate` shape: Durable ∧ evidence-backed); "never erase what isn't in cold" | Bitcoin prunes only what the network provably retains elsewhere; Filecoin retains only what PoSt proves; PG drops a partition only after it was safely detached/archived. Our archive node *is* its own redundancy — the durability gate replaces Bitcoin's network-redundancy assumption with node-local cold evidence | **MEDIUM** | Composes develop's Phase-17 evaluator with v1.1 DUR-01 evidence. Must fail closed: no durability evidence → no erase (GC eviction remains the only hot-shedding path). Prune evidence written atomically with the hot erase |
| TS-2 | **Pruned-vs-evicted serving semantics on the cold node** — GC-evicted + cold-resident + no prune evidence → serve via re-warm (node IS an archive, not masquerading); TxPruner-erased + prune evidence → refuse restoration even if bytes come back (inert bytes) | Ethereum full nodes honestly refuse or regenerate rather than returning wrong answers; BIP-159: a limited node must never masquerade as a full-history server; our own SURV-02 tri-state is the local-query precedent | **MEDIUM-HIGH** | This is the `CanRestoreElement` composition — the milestone's semantic core. The subtle point no prior art has: on a cold node, TxPruner-erased bytes still exist in S3 yet *must not* restore while evidence exists. Evidence outranks bytes, node-locally |
| TS-3 | **Seals survive both pruners** — TxPruner × GC composition never deletes `<cid>sealed` rows; overlapping hot-cleanup paths (set rows, `DeleteCIDBlock` LRU) unified or explicitly sequenced to one fixed point | IPFS GC never deletes pinned data — pins are the retain evidence; seals are our pin-equivalent ("existed and was processed") and now also the bootstrap ancestry index; GATE-03 already asserts this for TxPruner, `7961ec264` for GC | **MEDIUM** | Both orders must converge: GC-evict-then-TxPruner-erase (block already cold — erase must tolerate absent hot block) and TxPruner-erase-then-GC (GC never sees it). Mirrors PRUNE-04's crash fixed-point discipline |
| TS-4 | **Role-consistent, uniform serving behavior** — a cold node answers *all*-history queries (async, slower) or is honestly degraded; never "sometimes gone depending on local disk state" | BIP-159 deliberately fixes a *constant* 288-block floor so peers share one uniform expectation regardless of individual prune depth; anti-fingerprinting rationale applies to eviction depth too | **LOW-MEDIUM** | Mostly composition tests over v1.1 READ-02 async serving. Uniformity is what makes archive nodes reliable sync sources for the mesh |
| TS-5 | **Availability-invariant E2E: pruned light node bootstrap served by a cold archive node** — anything a light node prunes is obtainable from archive/cold nodes, proven in a mesh test | BitTorrent: a swarm stalls permanently when availability < 1.0 — at least one complete copy must exist; SURV-03 proved it for full nodes; the v1.2 tiered model needs the cold-node variant | **MEDIUM** | The tiered model's headline safety claim. Also the place to prove the forced-walk pulls GC-evicted parents from cold before peers (offline-capable) |
| TS-6 | **Bootstrap composition: verify + test, don't build** — forced-walk recovery on a cold node fetches missing (GC-evicted) parents through the `getNode` cold hook; erased parents terminate/refuse via `CanRestoreElement`; every restored parent CID-verified | Ethereum checkpoint/weak-subjectivity bootstrap and Bitcoin assumeutxo (HIST-02 analog) both treat "recovery reads through the storage tier" as a composition to verify, not a new subsystem; the seed note itself forecasts "nearly free" | **LOW** | Merge forecast: only `GeniusNode.cpp` conflicts; CRDT seams auto-merge. Watch: does the walk's `retained ? GetStoredNode : getNode` consult seals uniformly after GC eviction (seals retained → "retained" answer changes meaning)? Needs an explicit test |
| TS-7 | **Role/policy coherence in config** — node role (archive-cold vs light) determines pruning policy: cold nodes default never-erase or opt-in durability-gated erase; light nodes keep develop's spend-recency window; tri-state gate discipline extended to the new knobs | Bitcoin `-prune=N` vs full node is one config axis with fail-closed semantics; PG partition strategy is a deliberate up-front design decision, not runtime drift; our GATE-01/GATE-06 precedent | **LOW** | Reuse v1.1 INTG-02 strict tri-state shape (blank = disabled = today's behavior, malformed = loud, resolved values logged) |
| TS-8 | **Per-cycle observability for the new gates** — durability-gated eligibility counts, evicted-vs-erased answer breakdown, re-warm-on-serve counts, seal-row count/bytes | RECL-03/04 precedent; Filecoin makes retention *provable/inspectable*, not assumed | **LOW** | Feeds directly into TS-9/D-2 capacity decisions |

### Differentiators (valued, not expected — choose deliberately)

| # | Feature | Value Proposition | Complexity | Notes |
|---------|---------|-------------------|------------|-------|
| D-1 | **Seal growth/capacity: measure + model + explicit decision** (recommended v1.2 scope) — instrument seal-row count/bytes/rate, document the growth model (O(all processed CIDs), dual role: processed-marker + bootstrap ancestry index), make an explicit accept-and-document vs compaction decision | Bitcoin keeps an unbounded block/tx index forever and documents it — accept-and-document is legitimate industry practice when the constant is small (seal ≈ tiny row vs block ≈ KBs); Ethereum's archive-node cost is documented, not hidden | **LOW** (measure+document) / **HIGH** (compaction) | Seals are *not* DAG blocks — blockstore spill does not apply (create-only PUTs, no CID semantics); a compaction scheme (epoch-layered Bloom/bitmap) is its own design. RTN-02 already carries this as deferred. Recommend: v1.2 ships measurement + documented decision; compaction is a future milestone |
| D-2 | **Cold-tier collectibility / archive-role downgrade as explicit policy** — decide whether cold bytes for locally-pruned transactions can ever be collected when a node stops being an archive; ship the *decision + guardrails* (operator-initiated, checklist-gated role downgrade; config interlock preventing silent downgrade), not deletion machinery | Filecoin retention is term-bound with explicit renewal and explicit expiry — never silent; PG's detach→(archive)→drop requires explicit DDL at each step. The uniform prior-art answer: role/data-class transitions are deliberate operator acts | **LOW** as policy+guardrails / **VERY HIGH** as machinery | **Hard dependency finding:** the frozen sgns-blockstore v1 contract has *no Remove/Delete, ever* (v1.0 CORE-05/06) — cold collectibility is impossible without a library contract v2. This milestone should ship policy + interlock and defer any deletion API |
| D-3 | **Cold health/retention spot-audit (PoSt analog)** — periodically re-read a sample of `Durable`-marked cold objects (CID-verify) to detect silent unreadability | Filecoin's core insight: retained ≠ provably retained; v1.0 already documented that s3d can list buffered objects that are not readable — credentials/endpoint drift is a real failure mode for a "forever" tier | **MEDIUM** | High value for the archive role's credibility; bounded cost (sampling). Strong candidate for this milestone or the next hardening pass |
| D-4 | **Revocable prune on cold nodes (future semantic, decide now)** — because durability-gated erase leaves bytes in cold, a cold node's prune is *reversible in principle*: deleting the local `/prune/` markers (operator act) + re-warm restores archive semantics; light-node erase is irreversible locally | No prior art has this: PG DETACH is re-attachable while DROP is not — our evidence marker is exactly the detach/drop switch, node-local and revocable; Bitcoin/Ethereum pruning is one-way | **MEDIUM** (as a designed-in property) / **HIGH** (as a shipped "restore-from-prune" operation) | The design decision to make now: evidence is authoritative *for this node* and revocable only by local operator act — never by peers, never by cold bytes alone. Ship the invariant + maybe a test; the restore operation itself can wait |

### Anti-Features (explicitly do NOT build)

| # | Anti-Feature | Why It Tempts | Why It's Wrong for Us | Do Instead |
|---|--------------|---------------|----------------------|------------|
| AF-1 | Network-wide CRDT tombstone deletion as "pruning" | Looks like the standard CRDT GC answer | Erases history on *archive* nodes too — develop explicitly rejected it; go-ds-crdt ships no tombstone GC for exactly this reason (resurrection hazards, prior research 2026-10-22) | Node-local hot erase + local evidence markers (current model) |
| AF-2 | Deleting from the cold tier automatically (S3 lifecycle/GC in the node) | "Cold objects live forever" feels wasteful for downgraded nodes | Violates the frozen BlockStore v1 contract (no Remove, ever) and archive permanence; Filecoin never expires silently — term end is explicit and operator-driven | D-2: policy + interlock now; explicit, operator-initiated, contract-v2 work later if ever |
| AF-3 | Treating prune evidence as network-authoritative (broadcast `/prune/` markers; refusing based on *another* node's evidence) | "The network knows this was pruned" seems efficient | Evidence is node-local by design — a node's prune decision is irrelevant to what an archive node must serve; this would recreate AF-1 through the back door. BIP-159's signaling is a *service description*, not data-authority | Keep evidence local; service behavior (what I serve) is the only network-visible surface |
| AF-4 | Light nodes serving historical sync (masquerading as archive) | More redundancy feels safer | BIP-159's central MUST NOT (limited node must not signal full service); v1.2 Out of Scope already; masquerading breaks the availability invariant TS-5 | Honest refusal (SURV-02) + failover to archive nodes |
| AF-5 | Erasing hot on a cold node without the durability gate ("peers have it") | Bitcoin gets away with network-redundancy assumptions | An archive node IS the redundancy provider; if it erases hot with the only copy undurable (s3d staged/buffered), a crash can lose ledger history permanently — the exact failure v1.0's "accepted ≠ durable" finding warns about | TS-1 durability gate, fail closed |
| AF-6 | Spilling or compacting seals through the blockstore (or deleting seals ever) | "Seals grow — spill them to cold like everything else" | Seals are not DAG blocks (no CID-content binding; create-only cold PUTs don't fit); deleting them breaks GATE-03, dedup/resurrection guards, and the bootstrap ancestry index | D-1: measure + document; a dedicated seal index design only if data demands it |
| AF-7 | Auto role-downgrade / watermark-driven cold collection | IPFS-style StorageMax auto-GC feels native | Silent downgrade of an archive node can orphan pruned light nodes (TS-5 invariant) with no operator awareness; PG/Filecoin transitions are always explicit DDL/deal events | Role changes are operator-initiated with a downgrade checklist (D-2) |
| AF-8 | "Trust bytes if present" restore bypass (skip `CanRestoreElement` when cold bytes arrive quickly) | Latency temptation on the serving path | Collapses the pruned-vs-evicted distinction — restored-but-pruned data re-enters CRDT state on an archive node, undoing the light-node semantics the evidence encodes; violates "evidence outranks bytes" | TS-2: evidence check always; re-warm only for no-evidence misses |

### Feature Dependencies (how the new features chain onto the existing stack)

```
[TS-1 Durability-gated TxPruner eligibility]
    ├──requires──> v1.1 DUR-01 durability evidence (AdvanceDurabilityOnce, Durable = flush + pendingObjects==0)
    ├──requires──> develop TxPruner evaluator (Phase 17, pending) + EraseEntry/StageBlockRemoval (Phase 16, shipped)
    ├──requires──> v1.1 kEvictionDurabilityGate compile-time gate shape (pattern to extend)
    └──writes───>  /prune/ markers atomically with hot erase (develop 17-05 marker design)

[TS-2 Pruned-vs-evicted serving]
    ├──requires──> v1.1 READ-01/02 (cold-read fallback + async re-warm serving)
    ├──requires──> v1.1 GC-01..03 (eviction + disposed markers — the "no evidence" side)
    ├──requires──> develop PrunedLookup tri-state (19-05) — the evidence side
    └──requires──> fix/trust-genesis-bootstrap CanRestoreElement (the pivot)

[TS-3 TxPruner × GC composition]
    ├──requires──> v1.1 GC engine (11-x) + keep-seal resolution 7961ec264
    ├──requires──> develop GATE-03 seal retention + PRUNE-04 fixed-point discipline
    ├──shares───>  set rows /crdt/s|t/k, DeleteCIDBlock LRU, seals (the overlap surface)
    └──blocked-until──> develop Phase 17 lands (eligibility) — sequencing decision: unify vs order

[TS-5 Availability E2E]  ──requires──> [TS-2] + SURV-03 mesh harness pattern + v1.1 s3d E2E harness

[TS-6 Bootstrap composition]
    ├──requires──> v1.1 Phase-9 cold-read seam (getNode flows through cold hook)
    ├──requires──> fix/trust-genesis-bootstrap forced walk (merge; only GeniusNode.cpp conflicts)
    └──requires──> [TS-2] (walk restoration consults the same evidence pivot)

[TS-7 config]  ──extends──> v1.1 INTG-02 tri-state blockstore gate + GATE-06 pruning knobs

[D-2 cold collectibility policy]
    ├──hard-blocked-on──> sgns-blockstore contract v2 (v1 forbids Remove — CORE-05/06) for any machinery
    └──ships-now-as──>   policy decision + downgrade interlock (config/lifecycle)

[D-1 seal capacity] ──extends──> RTN-02 deferred item + keep-seal resolution; feeds TS-8 observability
[D-3 cold audit]    ──builds-on──> v1.1 installed S3AdminClient facade + DUR-01 flush evidence machinery
```

**External dependency to watch:** develop Phase 17 (eligibility dry-run, spend-recency window) and Phase 20 (reclamation) are still pending — TS-1/TS-3 composition work is *designable* now but *executable* only against 17's evaluator shape. The seed note also flags develop's Phase-17 eligibility semantics as the thing cold nodes may want a stricter (or never) policy knob for (TS-7).

---

## Prior-Art Table

Mapped to our context: single ledger, append-only CRDT, node-local pruning evidence, S3 cold tier. Confidence per row noted.

| System | Retention Model | Role/Tier Signaling | Deletion Semantics | Evidence / Retain Marker | Old-Data Retrieval | Lesson for Us (what to copy / what not) | Conf. |
|--------|----------------|--------------------|--------------------|--------------------------|--------------------|------------------------------------------|-------|
| **Bitcoin full node** | Complete history forever on disk | `NODE_NETWORK` service bit | Never deletes | The whole chain | Serves any block | The archive-role baseline: complete + serving is a *role*, not an accident | HIGH |
| **Bitcoin pruned node (BIP-159)** | Last ~288 blocks guaranteed (2 days) + tip state | `NODE_NETWORK_LIMITED` (bit 10); MUST NOT signal full service; constant floor so peer expectations are uniform; do not serve deeper than signaled even if held (anti-fingerprinting); 144-block reorg buffer | Prunes only data the network provably retains elsewhere; local, irreversible | pruneheight watermark (local) | Refuses deep requests; peers fail over to full nodes | Copy: honest limited-service semantics, constant uniform thresholds, distinct refusal. Do NOT copy: network-redundancy assumption — our archive node must be self-sufficient (TS-1 gate replaces it) | HIGH (fetched) |
| **Ethereum full node (snap-synced)** | Blocks + ~128 blocks of state; older state deleted, *regenerable* from retained snapshots | Serves network by default; regenerates historical state on demand | Deleting old state is *normal operation*, not degradation | Retained snapshots/checkpoints | Regenerate from snapshots, or honestly fail | Copy: evicted-hot = normal + regenerable — exactly our GC-evict + re-warm story | HIGH (fetched) |
| **Ethereum archive node** | Everything from genesis, never deleted (TBs) | The explicit "someone must hold history" role | Never deletes | Role/config choice | Local-disk fast historical reads | Copy: archive as explicit role. Ours differs: two-tier (hot + S3) makes it affordable; serving is async/slower — that trade is fine (Filecoin retrieval is slower too) | HIGH (fetched) |
| **Ethereum EIP-4444 direction** | Even full nodes will prune old block bodies; history served out-of-band (portal) | — | Bounded history on ordinary nodes becomes the norm | Checkpoints + out-of-band archives | Archive/portal nodes | The trendline endorses our tiered model: history retention must be *someone's explicit job* | LOW-MED (training, not fetched) |
| **IPFS node + GC + pins/MFS** | Node-local cache; GC deletes whatever is unpinned | No role signaling — each node serves what it holds | GC is strictly node-local, never a network delete | Pins (incl. recursive) and MFS membership = retain evidence | Serve if held; discoverable ≠ available | Copy: node-local GC + explicit retain evidence = our seals/keep-set model. Lesson: discoverability without a retention role leaves data lost — the availability invariant | HIGH (fetched) |
| **IPFS pinning service** | Paid third party holds pins | Economic service | Service stops when payment stops | Their pin set | Fast | Anti-lesson: availability is economic — our archive nodes need an operator who intends "forever" (D-2 downgrade policy) | HIGH (fetched) |
| **Filecoin deals/sectors** | Term-bound sector lifespans, actively renewed; PoSt proves continued storage; collateral at stake | Storage provider vs retrieval provider are distinct roles | Expiry is explicit at term end; never silent | On-chain deal record + periodic proofs | Retrieval role, separate pricing, commonly slower | Copy: retention is proven (PoSt → our D-3 spot-audit + DUR-01 evidence), term-bound, explicitly renewed. Do NOT copy: deal/payment machinery | HIGH (fetched) |
| **BitTorrent swarm** | Seeders hold full copies; leechers serve held pieces; super-seeding hands each piece out once until a 2nd copy exists | — | Client policies (ratio/time-limited seeding) | Availability ≥ 1.0 requires one complete copy | Swarm dies below availability 1.0 | Copy: the at-least-one-complete-copy invariant → TS-5 mesh E2E; deliberate behavior when sole source (re-warm caching) | LOW (training only) |
| **PostgreSQL partitioned tables** | Range/list/hash partitions; old data lives in whole partitions | — | DROP = instant bulk delete; DETACH = remove from queried hierarchy but retain as standalone (back up, then drop later); cheaper-media migration blessed | Partition bounds (metadata) | Detached tables remain readable | The sharpest vocabulary for us: **evict ≈ DETACH** (re-attachable via re-warm), **erase-with-evidence ≈ DROP** (gone from active, marker remains). Bulk structural ops beat row-level work (compaction reclamation, RECL-01) | HIGH (fetched) |
| **go-ds-crdt (ipfs)** | Append-only DAG forever; no automatic GC | — | PurgeDAG = admin-only, namespace-quiesce, delete-heads-last, resumable; maintainer-flagged resurrection hazards | Processed-block markers (our seals' cousin) | Full history | The closest CRDT prior art: pruning is special, admin-grade, and evidence-fragile — validates node-local conservative evidence + bounded markers (v1.1 shipped exactly this) | HIGH (prior internal research 2026-10-22) |

---

## Dependencies on Existing (summary for requirements categorization)

1. **v1.1 cold stack (shipped, must not regress):** spill-on-write decorator + drainer, CID-verified fallback + async re-warm, DUR-01 flush-gated durability evidence, GC-01..03 eviction engine + disposed markers, keep-seal (`7961ec264`), INTG-01/02 tri-state config gate, `kEvictionDurabilityGate` compile-time eviction gate, installed `S3AdminClient` facade (reusable for D-3 audit).
2. **develop TxPruner (partially shipped):** Phase 16 erase primitives (`EraseEntry`/`StageBlockRemoval`), Phase 18 service + fixed-point + observability, Phase 19 survival incl. PrunedLookup tri-state + SURV-02 refusals; **pending Phase 17** (eligibility evaluator, spend-recency window, GATE-01 Light-only gate — the fail-closed gate must widen to admit cold-node durability-gated mode) **and Phase 20** (CompactRange reclamation — the TxPruner×GC sequencing interacts with post-cycle compaction).
3. **fix/trust-genesis-bootstrap (merge pending):** forced-walk recovery, `retained ? GetStoredNode : getNode` fetch, `CanRestoreElement` PruneEligibility pivot. Merge surface: `GeniusNode.cpp` only.
4. **Library contract constraint:** sgns-blockstore frozen v1 has no delete — cold collectibility (D-2) is policy-only this milestone; any machinery is a contract-v2 ask.
5. **Carried deferred items that this milestone should absorb or explicitly re-defer:** RTN-02 seal lifecycle (absorb as D-1), HIST-03 disk-budget auto-GC (re-defer; AF-7), HIST-01/02 on-demand historical fetch / snapshot bootstrap (TS-6 touches HIST-02's adjacency; the forced walk is not assumeutxo — keep deferred).

## Sources

- **BIP-159 (NODE_NETWORK_LIMITED)** — bitcoin/bips master, fetched 2026-11-13: https://raw.githubusercontent.com/bitcoin/bips/master/bip-0159.mediawiki — MEDIUM (first-party, cross-checked)
- **Ethereum node types & sync modes** — ethereum.org (page updated 2026-10-29), fetched 2026-11-13: https://ethereum.org/en/developers/docs/nodes-and-clients/ — MEDIUM (first-party, cross-checked)
- **IPFS persistence/GC/pinning** — docs.ipfs.tech, fetched 2026-11-13: https://docs.ipfs.tech/concepts/persistence/ — MEDIUM (first-party, cross-checked)
- **Filecoin deals/sectors** — docs.filecoin.io, fetched 2026-11-13: https://docs.filecoin.io/provide-storage/filecoin-deals/storage-deals.md and https://docs.filecoin.io/getting-started/what-is-filecoin/storage-model.md — MEDIUM (first-party, cross-checked)
- **PostgreSQL partitioning** — postgresql.org docs §5.12 (current), fetched 2026-11-13: https://www.postgresql.org/docs/current/ddl-partitioning.html — MEDIUM (first-party, cross-checked)
- **BitTorrent seeding semantics** — training data only (brave search unavailable, no API key); LOW, flagged
- **EIP-4444** — training data only, not fetched; LOW-MEDIUM, flagged
- **Internal (HIGH):** `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` (tiered-node model seed, 2026-11-13); `SuperGenius/.planning/REQUIREMENTS.md` v1.2 section (PRUNE/GATE/SURV/RECL + Out of Scope); `SuperGenius/.planning/ROADMAP.md` phases 16-20; `.planning/workstreams/rocksdb-backup/STATE.md` (v1.0/v1.1 completion record, deferred items, CIDv0 delta finding); prior research `FEATURES-rocksdb-backup-2026-10-22.md` (go-ds-crdt PurgeDAG, Merkle-CRDT GC-external-truth, BlockStore CORE-05/06 no-delete contract, v1.0 durability-signal finding)
