# Milestone v1.2 — Project Summary

**Generated:** 2026-11-25
**Workstream:** rocksdb-backup (`.planning/workstreams/rocksdb-backup/`)
**Milestone:** v1.2 — SuperGenius Cold-Storage Archive Integration (Phases 13–19)
**Purpose:** Team onboarding and project review

> Resolution note: invoked as `$gsd-milestone-summary 19 --ws rocksdb-backup`. Phase 19 is the capstone phase of milestone **v1.2** (phases 13–19), so this summary covers v1.2.

---

## 1. Project Overview

**What this is (workstream goal):** Older CRDT/IPLD blocks can spill from RocksDB hot state to durable, CID-verified object storage through a shared thirdparty static library (`thirdparty/sgns-blockstore`) consumable by both SuperGenius and genius-tube — no RocksDB remote-FS integration, no SDK/SuperGenius types in the public API, and local eviction is never a CRDT deletion.

**What v1.2 added (core value):** Cold storage becomes the *authoritative archive tier* of the append-only CRDT ledger. Cold-enabled (archive) nodes hold complete history and serve it; light nodes may prune locally-irrelevant data with the guarantee that anything pruned remains fetchable from archive nodes. **Evidence, not bytes, decides whether cold-resident data is live history or inert.**

**Lineage:**
- **v1.0** — CRDT Cold-Storage BlockStore Library (Sia s3d backend), phases 1–5, shipped 2026-10-22
- **v1.1** — SuperGenius Cold-Storage Integration & CRDT Garbage Collection, phases 6–12, shipped 2026-11-10
- **v1.2** — SuperGenius Cold-Storage Archive Integration (this summary), phases 13–19, complete 2026-11-24/25, wrap pending

**In one paragraph:** v1.2 landed the bootstrap-branch merge that gates all recovery work, made TxPruner erases durability-gated (fail-closed, TOCTOU-safe), fixed the two research-discovered bugs (the cold-chain resurrection gap and the forced-walk GC-evicted conflation) by making evidence outrank bytes on every read path, hardened the TxPruner × GC composition, measured and decided the seal-growth question (accept), recorded the two-halves collectibility policy plus the archive→light downgrade interlock, and closed with an 11-case cross-feature fault-race matrix plus a three-platform Tier-1 fail-closed CI lane — all with zero new dependencies.

**Status:** All 7 phases complete (ROADMAP), 25/25 plans, 20/20 requirements discharged. Milestone is complete pending wrap (this summary → audit → archive).

---

## 2. Architecture & Technical Decisions

**Governing principle (research, 2026-11-13):** *Evidence outranks bytes, node-locally* — prune markers decide serve-vs-refuse and restore-vs-skip; cold bytes alone are never authoritative.

**Governing invariants (enforced by tests across phases 14–19):**
1. Never erase hot what is not Durable in cold.
2. Node-local prune evidence is terminal; cold bytes never resurrect what a node deliberately pruned.
3. Seals are never deleted by any path (TxPruner or GC).
4. Collectibility and the GC walk-gap exemption are two halves of one rule — they ship together or not at all.

**Key technical decisions:**

- **Decision: Zero new dependencies for v1.2.**
  - **Why:** all v1.2 work composes pinned mechanisms (RocksDB 9.4.0, s3d v0.2.1, vendored ipfs-lite-cpp unedited, minio-cpp 1.0.0); no compaction-filter deletion, no DeleteRange.
  - **Phase:** research / all phases. `sgns-blockstore` itself had 0 commits in the v1.2 window (frozen v1 contract).

- **Decision: The durability gate lives in `TxPruner::RunCycle`'s block-group filter, NOT inside `PruneEligibility::Evaluate`.**
  - **Why:** the evaluator stays contractually pure, so develop's Phase 17 evaluator landing remains a merge, not a rewrite.
  - **Phase:** 14 (PRUNE-03; proven by composition test + `PruneEligibility` byte-identical diff).

- **Decision: In-compose durability re-check (guard 5) under the compose lock.**
  - **Why:** an induced journal-state regression between evaluation and erase-commit must never enable a destroying erase; refusal surfaces as `Error::COLD_NOT_DURABLE` and a `cold_deferred_groups` counter, never a failure reason.
  - **Phase:** 14 (red-first TOCTOU counter-test at the `kInterruptAfterColdGate` seam).

- **Decision: A single role-aware evidence predicate owned by GlobalDB.**
  - **Why:** the three-way answer (pruned / evicted-restorable / not-found) must be consistent across `HasBlock`, `getNode`, and the cold chain; pruned stays distinct from not-found at the protocol surface so requesters fail over to archive nodes.
  - **Phase:** 15 (SERVE-03/04; predicate went GlobalDB-native per the 2026-11-17 research ruling).

- **Decision: Pruner composition = sequence + close the LRU window; never unify the two pruners.**
  - **Why:** TxPruner and GC are both idempotent on absent keys and reverse-order safe by construction; the stale-LRU erase window is closed by post-commit `DeleteCIDBlock` parity, not by mutual exclusion.
  - **Phase:** 16 (COMP-01..03; 18-leg interleave matrix, disposal-starvation ruled fail-safe = under-prune).

- **Decision: Seal growth accepted, redesign deferred to numeric triggers.**
  - **Why:** measured 52.000 B/row at 10^6/10^7, 10^8 extrapolated at 5.2 GB / ~16 s full sweep; capacity math says in-band. D-11 trigger table (T1–T3) governs any future redesign.
  - **Phase:** 17 (SEAL-01; evidence: `phases/17-*/17-seal-growth-evidence/`, decision record `notes/17-seal-growth-decision.md`).

- **Decision: Cold collectibility is POLICY-ONLY this milestone; the GC walk-gap exemption ships as code.**
  - **Why:** sgns-blockstore v1 forbids Remove (frozen contract); enabling collection without the exemption breaks GC liveness (the poisoned-GC triangle). The exemption is a one-predicate consult at the WalkReachable gap site (counted-continue observable), red-first proven.
  - **Phase:** 18 (POLICY-01; record: `notes/18-collectibility-policy-downgrade-interlock.md`).

- **Decision: Downgrade interlock = persisted role fingerprint + `downgrade_acknowledged` ack key + start-normally disarm.**
  - **Why:** a config flip must never silently downgrade an archive node; unacknowledged downgrades stay disarmed (zero pruning) until acknowledged.
  - **Phase:** 18 (POLICY-02; E2E t0→t3 timeline in `cold_downgrade_e2e_test`).

- **Decision: CI posture — Tier-1 fail-closed lane added to `build-release-tags.yml` only; `cmake.yml` zero-diff (B2).**
  - **Why:** every `cold_storage=true, run_tests=true` tag dispatch exercises `ctest -L Tier1 --no-tests=error`; an empty selection fails rather than passing vacuously — without touching the hermetic lane.
  - **Phase:** 19.

**Code architecture touched (all inside SuperGenius, `dev_coldstorage_additions`):**
- `src/crdt/globaldb/` — `ColdStorageManager` (drainer + GC + evidence), `ColdStorageStack`/`ColdStorageStackStub` (the v1.1 single-seam decorator), `ColdReadService`, `globaldb` (evidence predicate, erase parity)
- `src/transaction/` — `TxPruner` (admission conjunct + guard 5), `PruneEligibility` (untouched, contractually pure), `TransactionManager`
- `src/crdt/impl/` — `graphsync_dagsyncer.cpp` (forced walk, failover budget, merge-gate guard), `crdt_datastore.cpp`
- `src/crdt/` — `cold_read_fallback.hpp` (rehydrate chain consulting evidence)
- `src/account/` — `GeniusNode.cpp` (bootstrap merge composition), `proto/SGTransaction.proto`
- `src/pubsub_broadcaster_ext.cpp` — X11 evidence-arming findings
- Tests: 9 new/red-first suites in `SuperGenius/test/src/crdt/` + `node_startup_test` walk cases (20 Tier-1 registrations total at final HEAD)

---

## 3. Phases Delivered

| Phase | Name | Status | One-Liner | Verification |
|-------|------|--------|-----------|--------------|
| 13 | Bootstrap Branch Merge & Composition Baseline | Complete (2026-11-16) | `fix/trust-genesis-bootstrap` merged into `dev_coldstorage_additions` as a pure composition (merge `2af184fa1`), 167/167 zero-regression, composition-only grep gate — the gate for all v1.2 recovery/walk work | passed, 9/10 (1 deferred item closed in 15) |
| 14 | Durability-Gated TxPruner Eligibility | Complete (2026-11-16) | A cold-enabled node never erases hot data that is not evidence-Durable in cold — fail closed, TOCTOU re-checked under the compose lock, evaluator pure, cold-off byte-identical | passed, 12/12 |
| 15 | Evidence-Aware Cold Serving & Forced-Walk Recovery | Complete (2026-11-24) | Evidence outranks bytes on every path — fixes the cold-chain resurrection gap and the forced-walk GC-evicted conflation; hermetic tri-state evidence fakes back every suite | passed, 28/28 (regenerated; X1/X2 re-run) |
| 16 | TxPruner × GC Composition Hardening | Complete (2026-11-24) | Stale-LRU erase window closed; 18-leg interleave matrix proven; disposal-starvation interplay ruled fail-safe (under-prune) | passed, 3/3 (canonical status) |
| 17 | Seal Growth Measurement & Decision | Complete (2026-11-24) | Seal growth measured (52 B/row; 10^8 extrapolated 5.2 GB / ~16 s) and the accept-vs-redesign decision recorded with capacity math and D-11 numeric triggers | passed, 8/8 |
| 18 | Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption | Complete (2026-11-19) | The two-halves rule recorded as one policy (cold permanent + GC walk-gap exemption as code); archive→light downgrade E2E-proven with the interlock | passed, 26/26 (12/12 prohibitions) |
| 19 | Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone | Complete (2026-11-25) | X1–X11 induced-failure matrix across erase × serve × recovery (no resurrection, no partial validation, no lost last copies) + Tier-1 fail-closed lane green on Windows/macOS/Linux | closed via 19-05 closing evidence (no standalone VERIFICATION.md — see §6) |

**UAT / interactive rulings:** 13=10/10, 15=2/2, 16=1/1, 17=4/4 sessions completed; phase 14 closed with zero human-verification items; phase 18 closed with the recorded dev-opt-in live-leg posture (`18-USER-SETUP.md`); phase 19's checkpoint rulings (B1/B2, X11 promotion) are recorded in the notes doc and 19-05.

**Reconciliation note:** phases 13/15/16/17 executed earlier but were sealed retroactively on 2026-11-24 (fresh VERIFICATION digests at HEAD `41776b0c0`, SECURITY.md, UAT completion) — recorded in root commit `46513d1`.

---

## 4. Requirements Coverage

**All 20 requirements delivered.** No `v1.2-MILESTONE-AUDIT.md` exists yet (the audit is the next wrap step — `$gsd-audit-milestone`).

| Requirement | Phase | Status | Note |
|-------------|-------|--------|------|
| PRUNE-01 | 14 | ✅ | Durable-only erase; NoRecord/Pending/Accepted/Unreadable defer loudly (fail closed) |
| PRUNE-02 | 14 | ✅ | In-compose TOCTOU re-check; red-first counter-test |
| PRUNE-03 | 14 | ✅ | Gate at RunCycle filter; evaluator byte-identical |
| SERVE-01 | 15 | ✅ | Pruned semantics even when cold bytes exist (kills the resurrection gap) |
| SERVE-02 | 15 | ✅ | GC-evicted = evict ≈ DETACH, restorable + re-warmed |
| SERVE-03 | 15 | ✅ | Single role-aware tri-state predicate owned by GlobalDB |
| SERVE-04 | 15 | ✅ | Pruned ≠ not-found at protocol surface (failover correct) |
| RECOVER-01 | 13 | ✅ | Bootstrap merge green, zero regressions (167/167) |
| RECOVER-02 | 15 | ✅ | Forced walk restores GC-evicted ancestors from cold |
| RECOVER-03 | 15 | ✅ | `CanRestoreElement` terminal for pruned |
| RECOVER-04 | 15 | ✅ | Bounded per-CID failover; abort-never-skip on gaps |
| COMP-01 | 16 | ✅ | Stale-LRU window closed (post-commit DeleteCIDBlock parity) |
| COMP-02 | 16 | ✅ | 18-leg interleave matrix; seals untouched; both orders converge |
| COMP-03 | 16 | ✅ | Disposal starvation ruled fail-safe (under-prune) |
| POLICY-01 | 18 | ✅ | Two-halves policy record; exemption shipped as code |
| POLICY-02 | 18 | ✅ | Downgrade interlock E2E t0→t3 |
| SEAL-01 | 17 | ✅ | Measured + decided (accept); D-11 triggers |
| TEST-01 | 15 | ✅ | Hermetic PrunedLookup tri-state fakes product-wide |
| TEST-02 | 19 | ✅ | X1–X11 matrix (discharged in 19-05) |
| TEST-03 | 19 | ✅ | Tier-1 lane green ×3 platforms (discharged in 19-05) |

⚠️ **Stale traceability:** `REQUIREMENTS.md` still shows TEST-02/TEST-03 unchecked ("Pending") — they were discharged by phase 19 (ROADMAP marked 5/5 complete, commit `8018966`). One-line checkbox + traceability update belongs in the wrap (`$gsd-complete-milestone`).

---

## 5. Key Decisions Log

| ID | Decision | Phase | Rationale / Evidence |
|----|----------|-------|----------------------|
| — | Evidence outranks bytes, node-locally (governing principle) | research | Prune markers decide serve-vs-refuse and restore-vs-skip; cold bytes alone never authoritative |
| — | The four governing invariants (see §2) | research | Enforced by tests across 14–19 |
| — | Zero new dependencies; compose pinned mechanisms | research | sgns-blockstore frozen v1; no compaction-filter deletion, no DeleteRange |
| D-01..D-15 | Bootstrap merge as pure composition (single sanctioned hunk; grep gates) | 13 | Merge `2af184fa1`; recovery logic composed, never re-derived |
| D-09/D-02 | Five-state journal matrix (NoRecord/Pending/Accepted/Durable/Unreadable) all defer-or-admit explicitly | 14 | `SeedVariants` + gate legs; Unreadable = real fault, dedicated counter |
| D-01 (15) | Evidence predicate goes GlobalDB-native | 15 | Layering ruling from 2026-11-17 research (anchors re-located at `095c8c502`) |
| CR-01 | Probe-lift concurrency backstop deferred, then fixed forward | 15 → 19 | X1/X2 re-consult teeth landed in 19-01 and proven (2/2 PASSED) |
| D-11 | Seal redesign deferred to numeric triggers (T1–T3, JSON-key-cited) | 17 | 52.000 B/row measured; 5.2 GB / ~16 s extrapolated at 10^8 |
| D-12 | `kForcedWalkPeerFailoverPerCid = 8` — VALIDATED in-band-with-noted-limitation | 17 | Hermetic topology; zero production touch; hermetic limitation noted |
| — | Cold permanent this milestone; collectibility = v2 contract ask | 18 | Frozen v1 forbids Remove; record in `notes/18-collectibility-policy-downgrade-interlock.md` |
| — | GC walk-gap exemption ships as code with the policy | 18 | Two-halves rule; red-first `69fa79c29` → green `01d0e85d1` |
| — | Downgrade interlock preserves the prior fingerprint on the unack'd arm | 18 | 18-REVIEW F-1 (critical) fix `d2f2a7dec`; FP-UnackedPersists regression leg |
| — | X11 promotion re-ruled to one green per platform | 19 | Checkpoint ruling 2026-11-20; met at D4, zero X11 failures thereafter |
| B1/B2 | Tier-1 lane in `build-release-tags.yml` only; `cmake.yml` zero-diff | 19 | Verified at close-out |
| — | Local two-node wire failures ruled environmental (CloudflareWARP) | 19 | Both gates green pre-WARP and on CI at same HEAD; runbook entry |

---

## 6. Tech Debt & Deferred Items

**Open advisory findings (`13-REVIEW-DISPOSITION.md`, 0 critical / 0 major):**
- **F-1 (minor, open):** unbounded `routing_` accumulation for already-stored CIDs (`pubsub_broadcaster_ext.cpp:643` / `graphsync_dagsyncer.cpp:361`) — no eviction path; slow growth on long-running nodes. Candidate: bounded-lifecycle sweep, or accepted-risk record with an operator metric on `routing_.size()`.
- **F-2 (info, open):** `bootstrap_walk_max_retries: 0` not expressible — `read_walk_limit` rejects explicit zero and silently falls back to 8.

**v2 contract asks / future requirements (recorded, not built):**
- Cold collectibility machinery (per-CID evidence-driven S3 deletion) — blocked on sgns-blockstore v2 Remove contract
- `DisposedDurable` journal terminal state (or remote-presence verification) as the v2 answer to the starvation interplay
- Seal storage redesign (spill/compaction/sidecar) — only if D-11 numeric triggers fire
- Composition with develop Phase 17 (eligibility dry-run) and Phase 20 (reclamation proof) once they land on develop

**Carried deferred signals (from v1.1, still open):**
- Soak-scale GC eviction-storm hardening
- TEST-03 MinIO-binary live leg (runbook: `18-USER-SETUP.md`, env `SGNS_BLOCKSTORE_TEST_MINIO_BIN`)
- Permanent `cmake.yml` ON-leg baseline (activates at develop merge)

**Wrap-time cleanup items (artifact hygiene):**
- Phase 19 has **no standalone** `19-VERIFICATION.md` / `19-UAT.md` / `19-SECURITY.md` — the close-out evidence lives in `19-05-SUMMARY.md` (closing evidence table, close-out gates) and `19-FRESH-CLONE-CHECKLIST.md` (Status COMPLETE). The STATE.md reconciliation record ("every phase carries VERIFICATION + UAT + SECURITY") overstates uniformity; if artifact parity matters for the archive, generate them before `$gsd-complete-milestone`.
- `REQUIREMENTS.md` TEST-02/03 checkboxes + traceability stale (delivered, see §4)
- `RETROSPECTIVE.md` has no v1.2 entry yet (normally written at milestone completion)
- GeniusSDK/GeniusWallet root gitlink drift (pre-existing; suspect sync/restore tool — same class as the 2026-11-23 rollback anomaly)
- Known non-cold transverse test failures (documented, out of scope): `multi_account` SEGFAULT on OSX-Rel (D4-documented), `transaction_sync` 50 s deadline expiries on OSX-Dbg (green on develop Nov-19 and green D5–D7 on this branch; 171-test lane load on tart VM)

**Environment note:** the dev box's CloudflareWARP tunnel breaks local two-node libp2p loopback dials — when local wire-delivery gates wedge with zero gossip connections, check `Get-NetAdapter` for CloudflareWARP first.

---

## 7. Getting Started

**Repos & branches:**
- Planning (this workstream): root `W:\gnus\GeniusNetwork`, branch `dev_persisprocresults`
- SuperGenius code: `SuperGenius/`, branch `dev_coldstorage_additions`, tag `test_coldstorage`, pushed as `origin/dev_coldstorage_additions`, final HEAD `41776b0c0`
- `thirdparty/`: 1 v1.2 commit (`da17826` — MoltenVK install-skip fix, pushed); `thirdparty/sgns-blockstore` unchanged (frozen v1)

**Run the tests (Windows):**
- Build tree: `SuperGenius/build/Windows/<Release|Debug>/` (MSVC 2022, cmake)
- Tier-1 fail-closed lane: `ctest -L Tier1 -C Release` — the `-C Release` is REQUIRED on the multi-config tree (label selection is config-scoped; without it 0 tests are found). 20 Tier-1 registrations at final HEAD (19 cold_* suites + `tier1_static_audit`).
- Key suites: `cold_cross_feature_fault_race_test`, `cold_evidence_matrix_test`, `cold_prune_gate_test`, `cold_prune_toctou_test`, `cold_compose_matrix_test`, `cold_gc_walk_gap_exempt_test`, `cold_downgrade_e2e_test`, `cold_seal_growth_test`, `cold_storage_resurrection_test`, `node_startup_test` (walk cases)

**CI:** `SuperGenius/.github/workflows/build-release-tags.yml` — every tag dispatch with `cold_storage=true, run_tests=true` runs both the full suite and the Tier-1 fail-closed lane on Windows, Linux (x86_64 + aarch64), and OSX. Closing evidence: Windows D3 169/169 + Tier-1 20/20; Linux D3 both lanes green; OSX D7 171/171 + 20/20; D8 confirming at final HEAD (Tier-1 20/20 both OSX configs).

**Configuration:** `blockstore` section of the CRDT config (`crdt_config.json`) — strict tri-state: absent/blank = disabled (byte-identical), malformed = loud (names the offender), env = credentials-only override (never logged). Cold storage is OFF by default; mobile builds force-off.

**Where to look first:**
1. This summary → `ROADMAP.md` (phase goals + success criteria) → `phases/*/`-`VERIFICATION.md` (goal-backward evidence with file:line citations)
2. Rulings & decision records: `notes/16-txpruner-gc-composition-rulings.md`, `notes/17-seal-growth-decision.md`, `notes/18-collectibility-policy-downgrade-interlock.md`, `notes/19-cross-feature-fault-race-three-platform-capstone.md`
3. Core code: `SuperGenius/src/crdt/globaldb/` (the cold stack + evidence predicate), `SuperGenius/src/transaction/TxPruner.cpp` (the durability gate), `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (the forced walk)
4. Library contract (unchanged in v1.2): `thirdparty/sgns-blockstore/`

**Lesson worth knowing before touching the code:** any assertion whose truth depends on a background actor *not having acted yet* is wall-time-fragile — gate on what HAS deterministically happened (the phase-19 D7 rule, applied to baseline captures too).

---

## Stats

- **Timeline:** 2026-11-13 → 2026-11-24 (12 days; final commits landed the evening of Nov 24, recorded as Nov 25 UTC)
- **Phases:** 7 / 7 complete · **Plans:** 25 / 25
- **Commits:** root (planning) 157 · SuperGenius (code) 52 · thirdparty 1 · sgns-blockstore 0
- **Files changed:** root 127 (+22,245 / −94) · SuperGenius 58 (+23,483 / −215, from merge-prep baseline `4ae8a9a4e^` to `41776b0c0`; excludes bootstrap-branch history that arrived via merge `2af184fa1`)
- **Contributors:** itsafuu (solo, agent-assisted)
- **CI closing evidence:** Windows 169/169 + Tier-1 20/20 (D3) · Linux x86_64+aarch64 green both lanes (D3) · OSX 171/171 + Tier-1 20/20 (D7) · D8 confirming 20/20 both OSX configs — 8 dispatches (D1–D8), zero cold quarantines, every cold failure fix-forwarded
