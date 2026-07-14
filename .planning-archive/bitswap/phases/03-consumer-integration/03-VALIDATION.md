---
phase: 03
slug: consumer-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-09
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual code review checklist (no tests — CONCURRENCY-MAP.md verification only) |
| **Config file** | N/A |
| **Quick run command** | `cmake --build . --parallel 8 --config Release` (from `build/Windows/Release/`) |
| **Full suite command** | N/A (Phase 3 adds no new tests; existing GTest suite covers integration) |
| **Estimated runtime** | ~60 seconds (build only) |

---

## Sampling Rate

- **After every task commit:** Run build verification (`cmake --build ...`)
- **After every plan wave:** Review updated CONCURRENCY-MAP.md for correctness
- **Before `/gsd-verify-work`:** All 5 validation gates (V-1 through V-5) must pass
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | CONS-01 | N/A | SuperGenius builds + links with updated Bitswap | build | `cmake --build . --parallel 8 --config Release` | ✅ existing | ⬜ pending |
| 03-01-02 | 01 | 1 | CONS-02 | N/A | AsyncIOManager builds + links with updated Bitswap | build | `cmake --build . --parallel 8 --config Release` | ✅ existing | ⬜ pending |
| 03-02-01 | 01 | 1 | CONS-03 | N/A | CRDT Bitswap integration verified — no direct Bitswap calls in CRDT | manual | Review crdt/ sources for Bitswap #includes | ✅ existing | ⬜ pending |
| 03-03-01 | 01 | 1 | CONS-04 | N/A | AsyncIOManager event-loop integration verified — no strand violations | manual | Review IPFSSaver callbacks for io_context safety | ✅ existing | ⬜ pending |
| 03-04-01 | 01 | 1 | DOCS-02 | N/A | CONCURRENCY-MAP.md extended with consumer contract section | manual | grep "Phase 3: Consumer Contract" CONCURRENCY-MAP.md | ❌ W0 | ⬜ pending |
| 03-04-02 | 01 | 1 | DOCS-02 | N/A | Doxygen @note annotations on 4 methods in bitswap.hpp | manual | grep "@note" bitswap.hpp | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `CONCURRENCY-MAP.md` — consumer contract section stub (D-07 target)
- [ ] `bitswap.hpp` — Doxygen annotation stubs (D-08 target)

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PublishFile callback io_context safety | CONS-04 | Requires human reasoning about callback operations | Review IPFSSaver.cpp:107-141 — confirm all operations safe on io_context |
| PublishDirectory callback io_context safety | CONS-04 | Requires human reasoning about callback operations | Review IPFSSaver.cpp:190-221 — confirm all operations safe on io_context |
| GetBlock() const removal impact | CONS-01, CONS-02 | Requires grep + human confirmation | `rg "GetBlock\(" SuperGenius/src thirdparty/AsyncIOManager/src` — expect 0 results |
| setCacheDir init-phase safety | CONS-01, CONS-02 | Requires call-sequence analysis | Review GeniusNode.cpp:1314 and FileManager.cpp:249 — confirm single-threaded init |
| CRDT Bitswap dependence audit | CONS-03 | Requires codebase grep for indirect references | Review crdt/ sources for any Bitswap #include or usage |
| Documentation completeness | DOCS-02 | Requires human review of document quality | Read CONCURRENCY-MAP.md + bitswap.hpp — confirm D-07/D-08 coverage |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
