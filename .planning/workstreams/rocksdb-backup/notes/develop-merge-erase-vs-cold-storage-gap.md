# Seed: Cold Storage as the Archive Tier — next milestone framing (post develop-merge)

Date: 2026-11-13 (supersedes the 2026-11-12 gap note; deleted and rewritten after discussion)
Context: `origin/develop` merged into SuperGenius `dev_blockstore` (merge `55fca03f8` + keep-seal `7961ec264`, root bump `53a77a7`). v1.1 is closed; this note captures the agreed model and candidate work for the next milestone.

## The tiered-node model (user-confirmed)

Two node roles, one append-only global ledger:

- **Archive/cold nodes** — configured with cold storage (`blockstore` section, v1.1). They hold complete history forever: hot RocksDB working set + S3/object cold tier. This IS the ledger ("essentially a blockchain"). They never erase; the cold tier is never a deletion target.
- **Light/pruned nodes** — no cold storage. They may purge data irrelevant to their own ledger (TxPruner). Example: gained GNUS → spent it → gained more — the intermediate spent-history knowledge may eventually be purged locally. Pruning is a LOCAL operation; develop explicitly rejected CRDT tombstone deletion because it would erase history on archive nodes too.

**Availability invariant:** anything a light node prunes must always be obtainable from archive/cold nodes (Bitcoin BIP-159 precedent — SURV-02/03: pruned nodes answer "history pruned" ≠ not-found; full nodes serve).

## What develop actually shipped (their v1.2 erasure work, phases 16–20)

- `EraseEntry` / `StageBlockRemoval` / `POST_COMMIT_ERASE_ANOMALY` = TxPruner local hot erase, NOT network erase. Phases 16/18/19 complete on develop; 17 (eligibility dry-run, spend-recency window) and 20 (disk reclamation proof) pending.
- Seals (`<cid>sealed` ≡ `markResolved`/`isResolved`) are asserted retained through every erase — the permanent "existed and was processed" record. GATE-03 bans `"sealed"` literal in production src/.
- Pruning evidence is node-local (`/prune/` markers, `PrunedLookup` tri-state) and authoritative for THAT node only.

## fix/trust-genesis-bootstrap branch (likely in develop soon — analyzed at d556f86de)

- **Validated bootstrap history recovery**: opt-in bounded "forced walk" over retained sealed FullNode ancestry; fetch = `retained ? GetStoredNode : getNode` — `getNode` is exactly our Phase-9 cold-read seam, so on a cold node the walk pulls missing parents from S3 before peers, offline-capable, CID-verified. Composition with v1.1 is nearly free: verify + test, don't build.
- **`CanRestoreElement`** (PruneEligibility): refuses restoration when local prune evidence says PRUNED, even if bytes come back. This is the pruned-vs-evicted pivot: cold bytes + no prune evidence = restorable history (archive semantics); prune evidence = inert bytes (light semantics). Local evidence decides; cold is never authoritative on its own.
- Merge forecast vs dev_blockstore: only `GeniusNode.cpp` conflicts; all CRDT seams auto-merge.
- Seals gain a second job: they are the recovery's ancestry index — raises the weight of the seal-growth question below.

## Resolution already applied on dev_blockstore (commit `7961ec264`)

GC eviction now RETAINS seals; seal access via sanctioned `markResolved`/`isResolved` only; GATE-03 passes. Verified: gc 22/22, crdt_test 47/47, retrievability 4/4, fallback 21/21.

## Candidate milestone work (order = suggested priority)

1. **Durability-gated TxPruner eligibility on cold nodes**: hot erase permitted only when the block is Durable in cold (v1.1 `kEvictionDurabilityGate` shape: Durable + Unreadable). "Never erase what isn't in cold."
2. **Archive serving from cold**: pruned-hot + cold-resident + no prune evidence → serve via re-warm (node IS an archive node, not masquerading). Compose with the forced walk: missing GC-evicted parents restore from cold; missing TxPruner-erased parents restore NOTHING (evidence refuses).
3. **TxPruner × v1.1 GC composition**: both pruners have overlapping hot-cleanup paths (set rows `/crdt/s|t/k`, seals, `DeleteCIDBlock` LRU). Unify or sequence them; seals are NEVER deleted by either.
4. **Cold-tier collectibility policy**: today cold objects live forever (correct for archive role). Decide whether cold data for LOCALY-pruned transactions can ever be collected on a node that later stops being an archive node (role downgrade), or is permanent once written.
5. **Seal growth/capacity**: seals accumulate hot forever, O(all processed CIDs), and are now also the recovery index. Assess compaction/spill options (they are not DAG blocks; blockstore spill doesn't apply naturally) or accept + document.
6. **Light-node ledger-irrelevance policy**: the gained→spent→gained purge example maps to develop's Phase 17 eligibility (spend-recency window). Confirm composition when 17 lands; cold nodes may want their own (stricter/never) policy knob.

## Environmental note (not a gap)

Local Windows network-dependent suites fail "nodes did not connect" — CloudflareWARP adapter (100.96.0.1) picked as interface address; dials hang. A/B-verified identical on pre-merge code (2026-11-12); develop Windows CI green. Disconnect WARP before running pubsub suites locally.
