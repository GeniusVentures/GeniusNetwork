# Issue #10 Evaluation — Anthropic OSS Scanner Enrollment Execution Structure

Quick task `261009-rrt` · Live audit: 2026-10-10T00:05Z via `gh` (issue and PR re-fetched from GitHub; every planner fact as of 2026-10-09T23:59Z re-confirmed — no material deltas).

## Issue #10 Current State

- Issue: GeniusVentures/GeniusNetwork #10 (assigned review: @itsafuu — Anthropic OSS Scanner on `develop`) — **OPEN**, assignee **@itsafuu**, **0 comments**.
- Top-level "OSS Scanner enrollment checks": **3 of 9 done**
  - [x] Anthropic branch pinning confirmed (`repo: .../SuperGenius#develop`)
  - [x] Report contact confirmed (`primary_contact: admin@gnus.ai`)
  - [x] `develop` CI container config confirmed for the six native-build repos (thirdparty, zkLLVM, SuperGenius, GeniusSDK, GeniusWallet, GeniusCognitiveSystem — all on `ghcr.io/geniusventures/almalinux-8:latest`)
  - [ ] Select maintained public security-critical repos (favor direct sources over umbrella parents)
  - [ ] Per-project build Dockerfile (preferred: `.oss-scanner/Dockerfile`)
  - [ ] Pinned-submodule/build-dep fetch in the Dockerfile; no private tokens/images/source
  - [ ] Offline-capable meaningful tests; `tools/validate.py` + `tools/check <name>` before each enrollment PR
  - [ ] `project.yaml` with `#develop` suffix + `admin@gnus.ai`; threat models; report-handling guidance
  - [ ] One enrollment PR per project, CLA signed once, confidential acceptance tracking
- Per-project acceptance checklist: **1 of 8 done** — only the public `primary_contact` confirmation is checked; eligibility/maintainer identification, build-test review, isolated Dockerfile, scoped threat model, validate/check run, upstream PR, and acceptance tracking are all open.
- Proposed initial applications: all unchecked; body states "No upstream applications submitted yet; reuse is a plan, not a verified scanner build" — SuperGenius, GeniusWallet, gnus-ai + erc20-gnus-proxy, GeniusCognitiveSystem. **evmrelay newly eligible** (see evmrelay Status Update).
- Stale claim in the body: the "One exception" paragraph still describes evmrelay PR #51 as "a draft into `develop`, pending tests" — it had already merged at audit time.

## Remaining Scope Inventory

Uniform per-repo work (process-shaped and bounded, not exploratory engineering):

| Artifact/step | Shape per repo |
|---|---|
| `.oss-scanner/Dockerfile` | Publicly pullable amd64 base, `COPY . /src`, fetch pinned Gitlink submodules + release deps during build, no `GNUS_TOKEN_1`/private GHCR/secrets, offline tests in `/src`, within Anthropic's 45-min/16-CPU/64-GB budget |
| `.oss-scanner/threat_model.md` | Scoped trust boundaries, untrusted inputs, security goals, third-party exclusions |
| `projects/<name>/project.yaml` (upstream PR) | `#develop` suffix, `admin@gnus.ai` |
| Local validation | `tools/validate.py` and, where possible, `tools/check <name>` on a trusted machine |
| Enrollment PR | One PR per repo to anthropics/oss-scanner, signed by an authorized core maintainer |

Org-level (once, independent of repo count): CLA execution by an authorized core maintainer, plus confidential triage/acceptance tracking on Anthropic's side.

Candidate repos and effort shape: **SuperGenius** (largest native build; CI basis confirmed), **GeniusWallet** (Flutter + native deps; CI basis confirmed), **gnus-ai** and **erc20-gnus-proxy** (Solidity; no ARM64 CI basis — separate Hardhat-style setup), **GeniusCognitiveSystem** (CMake/ctest under almalinux-8; CI basis confirmed), **evmrelay** (newly eligible; smallest delta now that #51 merged). Each is days-not-weeks of bounded work with an external review queue after submission.

## Criteria Analysis

### a. Remaining scope (4+ repos × bounded checklist work)

Evidence: six candidate repos, each requiring the same four artifacts plus one upstream PR (inventory above). Multi-item but uniform and bounded — no cross-repo engineering coupling, no exploratory unknowns inside our control (the exploratory risk — scanner acceptance — sits with Anthropic, not in the build work). GSD phase/plan machinery exists to decompose uncertain engineering; a repeated bounded checklist does not need decomposition.
**Verdict:** scope is checklist-shaped, not phase-shaped — it does not justify workstream scaffolding.

### b. Single-owner sequential nature vs parallel engineering

Evidence: the issue is a single-owner assigned review (@itsafuu); Anthropic's process is one `project.yaml`/PR per project, reviewed serially on their side, with one CLA signer. Dockerfile authoring could theoretically be parallelized internally, but the critical path — upstream review/acceptance — stays sequential regardless of how we organize internally.
**Verdict:** single-owner sequential process work — fits a sequence of small quick tasks; a parallel workstream buys nothing on the critical path.

### c. External-party dependency (Anthropic acceptance / CLA / confidential triage)

Evidence: acceptance decisions, the CLA, and AI-generated-report triage are Anthropic-side queues outside team control (issue #10's own "Important limits"). The long pole is the external queue, not our artifact production. ROADMAP phases and verification ceremonies cannot accelerate an external party's review cadence.
**Verdict:** external gating dominates the schedule — internal structure adds no leverage, so minimize internal ceremony.

### d. Workstream-structure value (does ROADMAP/phases add value here?)

Evidence: issue #10 already carries two granular checklists (enrollment checks; per-project acceptance) plus a follow-up section — it is already the tracker, in public, where acceptance status must live anyway. The real verification gates are Anthropic's `tools/validate.py` and `tools/check`, which are per-artifact and invoked per repo, not per phase. Duplicating the checklist into ROADMAP/phases would double-track the same state.
**Verdict:** no value added by workstream structure — the issue is already the tracker and validator is already the gate.

### e. Team bandwidth (4 active workstreams)

Evidence: elmbridge, gnus-subnets, sgproc-render, and tokenprice workstreams are active; recent days show continuous quick-task load across them (STATE.md quick-task log). A fifth workstream for process work would compete for the same review capacity while delivering mostly external-queue waiting time.
**Verdict:** do not open a fifth workstream; slot enrollment work opportunistically as quick tasks.

## evmrelay Status Update

evmrelay PR #51 — "ci(develop): replace Bullseye with AlmaLinux 8 for native Linux builds" — is **MERGED** at **2026-10-09T19:52:41Z**, merge commit **`4b2d40e2f5ea83a1a75328e25a57c1aa50cbda96`** (re-verified live 2026-10-10T00:05Z via `gh pr view 51 --repo GeniusVentures/evmrelay`). This retires the issue's "One exception" claim (evmrelay `develop` CI referencing Bullseye) and closes the separate [CIDocker#1](https://github.com/GeniusVentures/CIDocker/issues/1) track. evmrelay now matches the other six native-build repos on AlmaLinux 8 and is eligible for the same per-repo enrollment steps.

## Recommendation

**Do not create a new GSD workstream for issue #10 — keep issue #10 as the single tracker and execute the per-repo OSS Scanner enrollment work as a sequence of small quick tasks when bandwidth allows, with SuperGenius first (Dockerfile, threat model, `validate.py`/`tools/check` run, then enrollment PR) and evmrelay added to the candidate list.**

Next concrete step: run the **SuperGenius enrollment quick task** — author `SuperGenius/.oss-scanner/Dockerfile` (pinned Gitlink submodules, offline tests, 45-minute budget) and scoped `threat_model.md`, pass `tools/validate.py` + `tools/check`, and stage the upstream enrollment PR for CLA-authorized maintainer sign-off. Each subsequent repo repeats the same quick-task shape; evmrelay is added to the candidate list now that #51 merged.

## Alternatives Considered

1. **New standalone GSD workstream** — rejected: all five criteria point the same way (bounded checklist scope, single-owner sequential process, external gating that internal phases cannot accelerate, an already-sufficient public tracker, and four active workstreams competing for bandwidth).
2. **Defer entirely until current workstreams wind down** — rejected as the primary path: the external Anthropic queue is the schedule's long pole, so entering it early is the only lever we control; per-repo quick tasks can slot into bandwidth opportunistically without a standing workstream. Deferral remains the fallback if bandwidth never materializes.
3. **One batched quick task covering all repos** — rejected: each repo needs its own validate/check cycle and its own upstream PR; batching couples failures across repos and exceeds quick-task size. Atomicity argues for the per-repo sequence.
4. **Keep issue #10 as the tracker + a sequence of small per-repo quick tasks** — accepted (the recommendation).

## Live-Audit Provenance

Commands run 2026-10-10T00:05Z: `gh issue view 10 --repo GeniusVentures/GeniusNetwork --json state,title,body,assignees,comments` and `gh pr view 51 --repo GeniusVentures/evmrelay --json state,mergedAt,mergeCommit,title`. Deltas vs planner facts: none material — issue OPEN/0 comments/checklist states as inventoried above; PR #51 MERGED with exactly the recorded timestamp and merge SHA. The only drift found is inside the issue body itself (the stale "One exception" paragraph), which the issue #10 comment proposes to correct.
