# Phase 2: LocalBlockStore (RocksDB Cold Tier) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-20
**Phase:** 2-LocalBlockStore (RocksDB Cold Tier)
**Areas discussed:** Storage layout, Upload journal design, Crash-test mechanics, Corruption & eviction policy

---

## Storage layout

**Q: Where do block bytes physically live?**

| Option | Description | Selected |
|--------|-------------|----------|
| Pure RocksDB | Bytes as values under cid.toBytes() keys; WAL/WriteBatch atomicity; one substrate, one crash domain; matches research SUMMARY | ✓ |
| Blob files + index | temp+fsync+rename blob files (literal BACK-03); RocksDB index only; second crash domain, dual consistency | |
| RocksDB + reserved seam | Pure RocksDB v1 behind an internal payload-writer seam for a future blob-file mode | |

**Q: How do 'atomic write' and 'sweep stale temp files' map onto pure RocksDB?**

| Option | Description | Selected |
|--------|-------------|----------|
| WriteBatch atomic | Block + journal in one batch; interrupted write leaves nothing; temp sweep vacuous-by-design, documented | ✓ |
| Staging-key + sweep | Staging key then promote (in-DB temp+rename analog); real sweep work at cost of double writes | |

**Notes:** User moved to next area after both decisions. Journal-in-same-instance noted as structural consequence (WriteBatch cannot span DBs).

---

## Upload journal design

**Q: What does the journal DO in Phase 2 with no S3 tier?**

| Option | Description | Selected |
|--------|-------------|----------|
| Active from day one | Every Put atomically births PendingUpload; records persist until transitions; PITFALLS first-write-path warning honored | ✓ |
| Quiescent + seam | Machinery exists/tested but Put writes nothing; explicit seam creates records; risks 'later tests fight the design' | |
| Defer to Phase 4 | Journal activation entirely deferred — would leave BACK-04 unmet | |

**Q: How does restart reconciliation surface pending records?**

| Option | Description | Selected |
|--------|-------------|----------|
| Tooling interface | Sync pending-set enumeration on the Phase-1 tooling/audit interface; no callbacks | ✓ |
| Startup callback | RegisterPendingUploadHandler invoked per record at startup; direct but couples lifetimes | |
| Both | Enumeration + optional callback; maximal surface to freeze | |

**Q: Who advances journal states, and via what surface?**

| Option | Description | Selected |
|--------|-------------|----------|
| Methods on backend | MarkUploadedAccepted/MarkUploadedDurable on LocalBlockStore + state accessor; Phase 4 composes externally | ✓ |
| Schema now, ops later | States land now, transition methods ship with Phase 4; EvictLocal gating would need read access anyway | |
| Journal handle | Dedicated UploadJournal object keeps backend surface minimal | |

---

## Crash-test mechanics

**Q: How should tests simulate mid-write crashes?**

| Option | Description | Selected |
|--------|-------------|----------|
| In-process reopen | FaultController seam + close-without-clean-shutdown + reopen; WAL recovery does the work; hermetic, portable | ✓ |
| Subprocess kill | Child process hard-killed at injected point; strongest realism, platform-heavy (Windows) | |
| Both | Reopen matrix + subprocess smoke tests; more harness to maintain | |

**Q: Where is the Phase 2 / Phase 5 crash-testing boundary?**

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal + seam | Prove the two criteria + corruption rejection; hooks exist; Phase 5 adds full matrix | ✓ |
| Full harness now | Complete kill-injection harness in Phase 2; Phase 5 adds S3-interleaved cases only | |

---

## Corruption & eviction policy

**Q: What happens when verify-on-read detects a corrupt block?**

| Option | Description | Selected |
|--------|-------------|----------|
| Evict + surface | Corrupt returned for this call; entry atomically removed → subsequent NotFound; re-Put repairs (self-heal) | ✓ |
| Report only | Corrupt returned; bytes stay; lingers until re-Put | |

**Q: Is EvictLocal gated on journal/durability state, or unconditional?**

| Option | Description | Selected |
|--------|-------------|----------|
| Unconditional | Removes bytes + journal record; caller owns policy; gated eviction is deferred future work | ✓ |
| Journal-gated | Refuses unless UploadedDurable; safe-by-default but pre-bakes deferred policy and is unexercisable in Phase 2 without test-marked states | |

---

## the agent's Discretion

- Column-family layout details, journal record schema, RocksDB options/tuning, options-struct shape
- RocksDB error → taxonomy mapping specifics (under frozen CORE-02 rules)
- FaultController fault-point granularity
- Test-file layout; exact transition-method/accessor names (placement was decided, names not)

## Deferred Ideas

- Durability-gated eviction policy — future work (REQUIREMENTS Future list / architecture-doc Phase 5)
- Subprocess-kill crash tests — Phase 5 candidate
- Startup callback hand-off for pending uploads — additive later if Phase 4 wants push semantics
