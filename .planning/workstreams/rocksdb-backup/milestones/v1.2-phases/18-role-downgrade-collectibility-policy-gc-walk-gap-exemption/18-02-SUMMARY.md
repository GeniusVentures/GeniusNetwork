---
phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
plan: 02
subsystem: database
tags: [downgrade-interlock, prune-evidence, config, node-role, gtest]

requires:
  - phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
    provides: plan 18-01's exemption consult (the walk the downgraded node's t3 state exercises in 18-03)
provides:
  - the downgrade interlock's mechanics: PruningConfig.downgrade_acknowledged ack key, the persisted role fingerprint (/prune/role-fingerprint record + RoleFingerprintRecord proto), and the RoleFingerprint::CheckAndRewrite fail-closed helper
  - the GeniusNode disarm gate (start-normally + disarm, two distinct WARNs, once-per-process latch) and the A4 tiered-light posture INFO line
  - the cold_downgrade_e2e_test Tier-1 suite (verdict matrix FP-FirstRun/FP-DowngradeFire/FP-AckArms/FP-FullFires/FP-UnreadableDisarm/FP-SamePosture + CFG-AckParse) that 18-03's t0->t3 timeline legs extend
affects: [18-03, 18-04, phase-19-capstone]

actuals:
  tokens: 14000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "persisted posture fingerprint with fail-closed read arms (NOT_FOUND => FirstRun, read error/parse failure => UnreadableDisarm, corrupt record NEVER overwritten - no laundering)"
    - "once-per-process verdict latch at a per-generation wiring site (consent requires restart by design)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_downgrade_e2e_test.cpp
  modified:
    - SuperGenius/src/transaction/PruneEligibility.hpp
    - SuperGenius/src/transaction/PruneEligibility.cpp
    - SuperGenius/src/account/proto/SGTransaction.proto
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "Ack-key shape: boolean downgrade_acknowledged inside the sgns_config.json pruning object - one key, one home, per-key type-checked absent-keeps-default"
  - "Fingerprint record: tiny protobuf (node_type/pruning_enabled/cold_storage_enabled/written_at_unix_ms) at PRUNE_ROLE_FINGERPRINT_KEY = /prune/role-fingerprint - the never-swept /prune/ standalone-key family"
  - "Once-per-process verdict + disarm latch: StartPruneTimerIfConfigured fires per account generation; a re-check against the just-rewritten record would read NoDowngrade and arm - the latch enforces the WARN's restart-to-arm contract"
  - "Parse-failure posture: UnreadableDisarm WITHOUT overwrite - the corrupt record survives (no laundering an unreadable prior role through one reboot)"

patterns-established:
  - "Pattern: persisted-posture record with distinct verdict arms (gate WARNs and Tier-1 legs can never mislabel)"
  - "Pattern: latch-not-recheck at per-generation wiring sites (detected states persist for the process lifetime)"

requirements-completed: [POLICY-02]

coverage:
  - id: D1
    description: "The interlock substrate: ack key + persisted fingerprint record + CheckAndRewrite helper with five fail-closed read arms"
    requirement: POLICY-02
    verification:
      - kind: integration
        ref: "ctest -R cold_downgrade_e2e_test (FP-FirstRun/FP-DowngradeFire/FP-AckArms/FP-FullFires/FP-UnreadableDisarm/FP-SamePosture + CFG-AckParse green)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The GeniusNode disarm gate: check/rewrite above the enabled early-return, disarm + two distinct one-shot WARNs between the Light check and the TxPruner arm, errored-helper-resolves-safe"
    requirement: POLICY-02
    verification:
      - kind: automated
        ref: "Select-String gate: ROLE DOWNGRADE DETECTED|downgrade_acknowledged|tiered-light posture|CheckAndRewrite in GeniusNode.cpp (6 matches >= 4)"
        status: pass
      - kind: integration
        ref: "ctest -L Tier1 19/19 green (non-downgrade boots behavior-identical)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The A4 tiered-light posture INFO line (Light + cold enabled) citing the policy record path"
    requirement: POLICY-02
    verification:
      - kind: automated
        ref: "Select-String gate: 'tiered-light posture' present in GeniusNode.cpp"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-11-19
status: complete
---

# Phase 18 Plan 02: Downgrade Interlock Mechanics Summary

A detected archive/full -> light+pruning downgrade can never silently arm the pruner: the persisted role fingerprint + explicit ack key + GeniusNode disarm gate make "operator-initiated, checklist-gated" mechanically enforced, with every verdict arm Tier-1-pinned including both false-positive hazards.

## Performance

- **Duration:** 50 min
- **Tasks:** 2 / 2
- **Files:** 7 (2 transaction-layer, 1 proto, 2 node-wiring, 1 new test, 1 cmake)

## Tasks Completed

1. **Task 1** - `feat(18-02)` `ed4478169`: ack key + fingerprint record/keyspace + CheckAndRewrite (five read arms; corrupt record never overwritten; A2 Full-fires predicate; advisory-write posture).
2. **Task 2** - `feat(18-02)` `65441090e`: the GeniusNode gate (check above the enabled early-return; disarm WARNs between the Light check and the TxPruner arm; once-per-process latch), the tiered-light posture line, the cold_downgrade_e2e_test verdict matrix + Tier-1 registration. Full lane 19/19.

## Accomplishments

- D-05: consent is a real config key - downgrade_acknowledged, one key inside the existing pruning object
- D-06: fail-toward-under-erase shipped - node starts normally, pruner disarmed, one loud WARN with the full operator instruction
- D-07: birth-tiered-light (FirstRun) and same-posture restarts never fire; Full fires identically to Archive (A2)
- A4: the tiered-light posture INFO line exists (absent on the pre-phase line)
- The E2E file + fixture exist for 18-03's t0->t3 timeline legs

## Deviations from Plan

- **[Rule 1-3 - Mechanical consequence of the wiring site] Once-per-process verdict latch** - Found during: Task 2 | Issue: the plan places the check at StartPruneTimerIfConfigured, which StateTransition reaches once per account generation; a later generation re-checking against the record the first check just rewrote would read NoDowngrade and ARM - laundering a detected downgrade within one process lifetime | Fix: the verdict is computed once (role_fingerprint_checked_) and the disarm latches (role_fingerprint_{downgrade,unreadable}_disarm_) until restart - exactly the WARN's own "and restart to arm pruning" contract; WARN one-shot per process | Files: GeniusNode.hpp/.cpp | Verification: Tier-1 lane green | Commit: 65441090e

**Total deviations:** 1 auto-fixed. **Impact:** none - the latch strengthens the D-06 contract the plan specifies; no must_have weakened.

## Issues Encountered

None. (One missing TxPruner.hpp include in the new test TU, fixed at compile time.)

## Next Phase Readiness

Ready for 18-03 (downgrade E2E t0->t3 timeline) - the interlock verdicts are pinned and the E2E file/fixture/registration exist.
