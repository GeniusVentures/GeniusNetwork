# Phase 4: Repin & Cross-Repo Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-14
**Phase:** 4-Repin & Cross-Repo Verification
**Areas discussed:** Pin & branch strategy, Rebuild depth after repin, Focus-suite set & pass bar, GeniusSDK build verification

---

## Pin & branch strategy

| Option | Description | Selected |
|--------|-------------|----------|
| thirdparty develop | Commit the three gitlink bumps as a new local commit on `develop` (matches how develop tracks pins; never pushed) | |
| Dedicated branch | Cut e.g. `dev_ipfs_p0` in thirdparty so `develop` stays untouched until a reviewed merge | ✓ |

**User's choice:** Dedicated branch
**Notes:** Develop only moves via reviewed merges; the workstream has no other consumers of these pins.

| Option | Description | Selected |
|--------|-------------|----------|
| Commit on current | Bump the root's thirdparty gitlink on `dev_persisprocresults` alongside phase-4 artifacts | ✓ |
| Leave uncommitted | Record the pin only inside thirdparty + workstream docs; root pointer moves later | |

**User's choice:** Commit on current
**Notes:** Keeps the full pin chain recorded in git.

| Option | Description | Selected |
|--------|-------------|----------|
| Restore + rerun suite | Restore the rolled-back files then re-run the 13-case race suite before pinning | |
| Restore only | Restore and trust Phase 2's verification of `f899393` | |
| Investigate origin | Bounded pre-pin task: establish where the ~460-line rollback came from before touching anything | ✓ |

**User's choice:** Investigate origin
**Notes:** Suspicion that something may hide in the worktree; restore + re-verify follows unless the investigation finds otherwise.

| Option | Description | Selected |
|--------|-------------|----------|
| Fix-forward if trivial | Trivial local adaptations fixed in-phase and recorded; structural breaks stop and report | ✓ |
| Stop and report | Any verification failure halts the phase with diagnosis | |
| Baseline first | Re-run the failing suite against old pins to classify pre-existing vs regression before deciding | |

**User's choice:** Fix-forward if trivial
**Notes:** Baseline classification is anyway built in via the no-new-failures bar (D-11).

## Rebuild depth after repin

| Option | Description | Selected |
|--------|-------------|----------|
| Full ABI recipe | Inner vcxproj → INSTALL refresh → header hash audit → clean rebuild of dependents (deployed-header ABI-split precedent) | ✓ |
| Incremental | Inner vcxproj + INSTALL + audit only; dependents rebuilt incrementally | |
| Clean subtree wipe | Delete the three packages' build subtrees and rebuild from scratch | |

**User's choice:** Full ABI recipe
**Notes:** `gossip.hpp` Config layout change makes incremental categorically unsafe.

| Option | Description | Selected |
|--------|-------------|----------|
| Debug only | Existing Debug tree; Phase 1–2 test trees and focus-suite convention live there | ✓ |
| Debug + Release | Both trees; Release is what ships but doubles cost and disk pressure | |

**User's choice:** Debug only

| Option | Description | Selected |
|--------|-------------|----------|
| Marker-probe binaries | Byte-grep built test exes for a fix-marker string proving the fixed code linked | ✓ |
| Tlog audit | Check linker-input tlogs to confirm fresh libs were consumed | |
| Exit codes only | Trust clean-rebuild discipline and exit codes | |

**User's choice:** Marker-probe binaries
**Notes:** (Later refined at the SDK layer — see GeniusSDK area: tlog + hash audit is the SDK standard because static linking can omit unreferenced marker objects.)

| Option | Description | Selected |
|--------|-------------|----------|
| Focus targets only | Build the focus-suite targets + internal deps; SDK build covers broad link health | ✓ |
| Full SG tree | Clean-rebuild the entire SuperGenius Debug tree | |

**User's choice:** Focus targets only

## Focus-suite set & pass bar

| Option | Description | Selected |
|--------|-------------|----------|
| Roadmap three paths | CRDT/PubSub → crdt + pubsub_counts; DAG-syncer → its suite; AccountMessenger → its suite; research pins exact targets | ✓ |
| All five candidates | crdt + pubsub_counts + graphsync + securecrdt + transaction_sync | |
| Three + grep-driven | Start from three paths; widen only if include-grep shows more direct consumers | |

**User's choice:** Roadmap three paths

| Option | Description | Selected |
|--------|-------------|----------|
| All-green required | Every selected suite fully green on the repinned tree | |
| No-new-failures | Fresh pre-repin baseline; pass = zero new failures; pre-existing reds documented | ✓ |
| Green-subset only | All-green bar but pre-baseline-red suites dropped from the set | |

**User's choice:** No-new-failures
**Notes:** Matches the milestone's regression-evidence spirit; known pre-existing reds exist in SuperGenius suites (trust-gate migration fallout).

| Option | Description | Selected |
|--------|-------------|----------|
| Both suites | Re-run TEST-01 and TEST-02 at pin time in their existing standalone trees | ✓ |
| Bitswap only | Re-run TEST-01 (already mandated by worktree reconciliation); trust Phase 3 for TEST-02 | |
| Neither | Inherited Phase 2/3 evidence is sufficient | |

**User's choice:** Both suites

| Option | Description | Selected |
|--------|-------------|----------|
| Retry once + document | Exactly one retry; retry result stands; flake documented in VERIFICATION.md | ✓ |
| Strict single run | First run stands; no retries | |
| Best of three | Up to three runs, majority stands | |

**User's choice:** Retry once + document

## GeniusSDK build verification

| Option | Description | Selected |
|--------|-------------|----------|
| SDK lib + example | Core target plus one example/service target — link check + real-consumer proof | ✓ |
| SDK lib only | Minimal reading of "builds and links cleanly" | |
| Full SDK solution | Every target including all examples and services | |

**User's choice:** SDK lib + example

| Option | Description | Selected |
|--------|-------------|----------|
| Tlog + hash audit | Linker-input tlog shows fresh thirdparty libs consumed + deployed-lib hash audit | ✓ |
| Marker + tlog | Attempt marker probe on the SDK binary too; absence documented as expected-if-unreferenced | |
| Exit code only | Build exit code is the whole claim | |

**User's choice:** Tlog + hash audit
**Notes:** Marker-grep on the SDK binary can false-negative under static linking (unreferenced objects not pulled).

| Option | Description | Selected |
|--------|-------------|----------|
| Strictly build-only | Compile + link success is the entire claim; nothing executed (INTG-03 verbatim) | ✓ |
| Build + smoke run | Example starts, initializes the node, exits cleanly | |

**User's choice:** Strictly build-only
**Notes:** Runtime node-bootstrap concerns (trust gates, config) are not this phase's subject.

| Option | Description | Selected |
|--------|-------------|----------|
| Existing Debug tree | Reconfigure GeniusSDK/build/Windows Debug in place; fresh-dir fallback only if stale cache fights the repin | ✓ |
| Fresh configure | New build directory to avoid stale-cache interaction entirely | |

**User's choice:** Existing Debug tree

---

## The agent's Discretion

- Integration branch name (e.g. `dev_ipfs_p0`), commit message shape
- Exact ctest target enumeration for the three focus paths; DAG-syncer / AccountMessenger suite ownership
- Which GeniusSDK example/service target is the consumer proof
- Concrete marker strings probed and grep mechanics
- MSBuild invocation details within the D-06 recipe
- Phase-internal ordering (hard constraints only: baseline before rebuild; pin commit before content probes)
- D-05 investigation evidence mechanics (mtimes, reflog, sync timestamps)
- VERIFICATION.md internal structure

## Deferred Ideas

- Release-tree rebuild + verification (fast-follow candidate)
- GeniusSDK example smoke run
- CI-side verification of the repinned chain (milestone-excluded)
