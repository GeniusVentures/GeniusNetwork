# Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-27
**Phase:** 12-Integration Hardening, Fault Races & Fresh-Clone Proof
**Areas discussed:** Fresh-clone proof surface, Soak assertion semantics, Race & resurrection methodology, Fix-forward posture

---

## Fresh-clone proof surface

### Proof surface (execution)

| Option | Description | Selected |
|--------|-------------|----------|
| Local evidence | Scripted fresh-clone runbook per platform with committed evidence artifacts (TEST-03/gc-e2e precedent); no release-cut dependency | |
| CI ON-lane | Cut the thirdparty release and extend CI to configure ON on Windows/Linux/macOS | ✓ (via free text) |
| Hybrid | CI stays OFF-lane; local-script evidence proves ON now; ON-lane is fast-follow | |

**User's choice:** Free text: "We can run a thirdparty tag build so SuperGenius can pull in from a specified tag."
**Notes:** Resolved as: CI ON-lane enabled by a thirdparty tag build; SuperGenius consumes the specified tag. Repo tag-build machinery (`build-release-tags.yml` + thirdparty `build.yml` release pipeline) already exists and was shaped for this during the milestone (tarball-limit constraints in `CommonTargets.cmake`).

### Push gate

| Option | Description | Selected |
|--------|-------------|----------|
| Human checkpoint | Executor pauses at the proof step; user pushes; script fail-closed validates remote SHAs | |
| Push-first gate | User pushes all repos at phase start; proof re-validates | |
| SHA-validate only | No workflow gate; script fails closed on non-remote HEADs | ✓ (via free text) |

**User's choice:** Free text: "I have already pushed as of end phase 11."
**Notes:** Base is pushed; CI inherently builds pushed commits only. Fail-closed SHA-on-remote validation retained where any runbook/script starts.

### Platform sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Windows first | Prove recipe on dev machine, then Linux/macOS | |
| All three at once | One wave covers the full matrix | |
| Per-machine as able | Evidence fills in as machines become available | ✓ (via free text) |

**User's choice:** Free text: "CI should run all I think"
**Notes:** Interpreted as: CI runs all three platforms — no staging-by-machine needed; combined with the "CI only" answer below, no local sequencing applies.

### Evidence artifacts

| Option | Description | Selected |
|--------|-------------|----------|
| Runbook + logs | docs/evidence/fresh-clone/ with per-platform console/ctest logs, config echo, SHA manifest + runbook | |
| Runbook + summary | Runbook + structured per-platform summary; raw logs stay local | |
| Minimal | Checklist doc with results only; details in commit history | ✓ |

**User's choice:** Minimal
**Notes:** CI run history is the archive; deliberately lighter than the TEST-03 committed-artifact precedent.

### ON-lane host (follow-up round)

| Option | Description | Selected |
|--------|-------------|----------|
| Both | Tag-build dispatch (thirdparty_tag input, ON configure) for milestone evidence + permanent cmake.yml ON leg | ✓ (with amendment) |
| cmake.yml ON leg | Develop CI ON leg only | |
| Tag dispatch only | One-time dispatch; no permanent lane | |

**User's choice:** Free text: "Both yml should work, but tag build should have the testing flag on."
**Notes:** The tag build must run with the testing flag enabled so `ctest -L Tier1` executes there — an ON configure without tests running is not the proof.

### Tag-build responsibility (follow-up round)

| Option | Description | Selected |
|--------|-------------|----------|
| User checkpoint | Phase wires everything; human checkpoint has user dispatch the thirdparty tag build + confirm tag exists | ✓ |
| Pre-phase prereq | User cuts the tag before Phase 12 planning | |
| Executor dispatch | Executor triggers workflow_dispatch via gh | |

**User's choice:** User checkpoint

### Local proof (follow-up round)

| Option | Description | Selected |
|--------|-------------|----------|
| CI only | CI ON-lane is the proof; no local fresh-clone run | ✓ |
| CI + local smoke | One local smoke to de-risk the recipe first | |

**User's choice:** CI only
**Notes:** Also avoids a ~100+ GB thirdparty build on the W: drive.

---

## Soak assertion semantics

### "Bounded journal growth" assertion

| Option | Description | Selected |
|--------|-------------|----------|
| No-multiply + drain | pending ≤ distinct published CIDs (no retry-storm duplication), watermark+alarm fire, AND post-fault-clear drain to zero in a bounded window; soak has outage + recovery phases | ✓ |
| No-multiply only | Outage-phase asserts only; recovery-drain left to Phase-8 crash-resume tests | |
| Literal cap | Hard numeric journal cap for the soak duration | |

**User's choice:** No-multiply + drain
**Notes:** Resolves the tension with Phase 8's unbounded-journal+watermark+alarm lock — "bounded" means no record multiplication plus a bounded recovery drain, never a hard cap.

### Soak shape

| Option | Description | Selected |
|--------|-------------|----------|
| Both | Iteration-based soak in Tier-1 CI + one dev-gated wall-clock soak (tens of minutes, never CI) with committed evidence | ✓ |
| Iteration Tier-1 | Deterministic count, CI-safe runtime only | |
| Wall-clock dev-gated | Minutes-long fault-held soak only | |

**User's choice:** Both

### Soak actors

| Option | Description | Selected |
|--------|-------------|----------|
| Full stack | Publishes + drainer + flush backoff + GC inhibited + peer cold-fetch + graphsync serving under one sustained outage | ✓ |
| Publish+drain core | Core soak only; peer/cold-fetch in separate focused tests | |
| Layered scenarios | Core soak first, then one-actor-at-a-time variants | |

**User's choice:** Full stack
**Notes:** Attribution cost accepted — the deterministic race matrix provides the isolation layer.

### Teardown-under-load scope

| Option | Description | Selected |
|--------|-------------|----------|
| Clean + crash | Clean Stop() under load (ordered joins, bounded grace-flush, GC + in-flight evict marks) AND kill-9 mid-soak + restart reconciliation | ✓ |
| Clean Stop only | Crash-restart left to Phase-8/10 tests | |
| Crash only | Kill-9 + restart only | |

**User's choice:** Clean + crash
**Notes:** Extends Phase-10's shutdown-under-load proof with the GC actor.

---

## Race & resurrection methodology

### Determinism approach

| Option | Description | Selected |
|--------|-------------|----------|
| Both | Deterministic barrier-driven crossings for named hazards + randomized FaultController timing-jitter iterations with end-state invariants | ✓ |
| Deterministic only | Exact interleavings only; no long-tail coverage | |
| Randomized only | Probabilistic coverage; possible flakes | |

**User's choice:** Both

### Matrix breadth

| Option | Description | Selected |
|--------|-------------|----------|
| Pairwise + triple | evict×serve, evict×drain, serve×drain + simultaneous triple, each at risky phase boundaries (mark, grace-expiry, delete-batch, delete-time re-check/cancel, re-warm attach) | ✓ |
| Minimal named set | Only the SC1-lettered simultaneous scenario | |
| Exhaustive product | Every actor-phase combination | |

**User's choice:** Pairwise + triple

### Zero-lost-blocks proof

| Option | Description | Selected |
|--------|-------------|----------|
| Audit + per-scenario | Per-scenario end-state asserts + full suite-end audit walk (every published CID ∈ {hot, cold-local, S3-retrievable, disposed-with-remote-copy}) + log-scan asserts (zero blacklist writes, zero misattributed Corrupt) | ✓ |
| Per-scenario only | No cross-suite audit walk | |
| Suite-end audit only | Lean individual scenarios | |

**User's choice:** Audit + per-scenario

### Resurrection counter-test placement

| Option | Description | Selected |
|--------|-------------|----------|
| Node-level pubsub | In-process GlobalDB pair (11-03 precedent): put → CRDT delete → force GC past retention+grace → evict → pubsub re-delivery of pre-delete delta → assert absent in both nodes, no re-integration, remote copy intact | ✓ |
| Library + node | The above plus additive library-level dedup unit tests where gaps exist | |
| Direct injection | Delta injected via datastore Put; skips the realistic peer re-broadcast vector | |

**User's choice:** Node-level pubsub

---

## Fix-forward posture

### Fix depth

| Option | Description | Selected |
|--------|-------------|----------|
| Additive library OK | Fixes in SuperGenius + additive sgns-blockstore changes (installed headers may gain additive surface, Phase-6/10 precedent); no public API removals/renames; library change ⇒ tag checkpoint re-cuts | ✓ |
| SuperGenius-only | Library frozen for the phase | |
| Anything | Including breaking library API changes if demanded | |

**User's choice:** Additive library OK

### Deep-defect handling

| Option | Description | Selected |
|--------|-------------|----------|
| Checkpoint user | One failed fix attempt or a locked-decision conflict → pause with findings + options (fix-forward / defer documented / split out), 11-04 precedent | ✓ |
| Autonomous loop | Keep fixing until green within plan budget | |
| Defer documented | Deep defects documented as deferred risk | |

**User's choice:** Checkpoint user

### Test seams in product code

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal seams OK | Small test-only hook/barrier points (e.g., pause-at-mark in the GC thread), test-build-gated/inert in release, minimal + documented | ✓ |
| No product touches | Existing FaultController/public surfaces only | |
| Fault-kit only | New instrumentation in library test headers only | |

**User's choice:** Minimal seams OK

---

## the agent's Discretion

- Barrier/hook mechanics per named crossing; which seams are actually needed
- Iteration count N for the Tier-1 soak; wall-clock soak duration; drain-window assertion form
- cmake.yml ON-leg shape (matrix leg vs separate job); exact tag-build testing-toggle wiring
- Tier-label audit mechanics (script vs checklist)
- Checklist doc location/shape
- Log-scan mechanics for blacklist/Corrupt asserts
- Resurrection test's force-GC mechanics (tiny ages vs direct invocation)
- Regression-test discipline per fix; randomized-iteration seed policy

## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — keyword-only match (0.6), unrelated; third consecutive phase reviewed-not-folded (10, 11, 12).
