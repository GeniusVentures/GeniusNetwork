## evmrelay status correction

The issue's **"One exception"** note (evmrelay `develop` CI still referencing Bullseye) is now resolved:

- [evmrelay PR #51](https://github.com/GeniusVentures/evmrelay/pull/51) — "ci(develop): replace Bullseye with AlmaLinux 8 for native Linux builds" — was **MERGED** on **2026-10-09T19:52:41Z** (merge commit `4b2d40e2f5ea83a1a75328e25a57c1aa50cbda96`).
- This closes the separate [CIDocker#1](https://github.com/GeniusVentures/CIDocker/issues/1) track; evmrelay now matches the other six native-build repos on AlmaLinux 8 and is eligible for the same per-repo enrollment steps.

## Execution-structure evaluation (summary)

We evaluated how the remaining enrollment work should be run, one criterion per line:

- **Scope** — 4+ repos × a bounded, uniform checklist (Dockerfile, threat model, `project.yaml`, validate run, one PR each): checklist-shaped, not phase-shaped.
- **Ownership** — single-owner, sequential per Anthropic's one-PR-per-project process; internal parallelism cannot shorten the critical path.
- **External gating** — acceptance, CLA, and confidential report triage sit in Anthropic's queue; internal phase structure adds no leverage.
- **Tracker value** — this issue already carries the per-project checklists; a parallel ROADMAP/phases structure would double-track the same state.
- **Bandwidth** — four engineering workstreams are active; a fifth for process work would compete for the same review capacity.

**Recommendation:** Do not create a new GSD workstream for issue #10 — keep issue #10 as the single tracker and execute the per-repo OSS Scanner enrollment work as a sequence of small quick tasks when bandwidth allows, with SuperGenius first (Dockerfile, threat model, `validate.py`/`tools/check` run, then enrollment PR) and evmrelay added to the candidate list.

First next step: a SuperGenius enrollment quick task (`.oss-scanner/Dockerfile` with pinned Gitlink submodules and offline tests, scoped threat model, `tools/validate.py` + `tools/check` pass), staging the upstream enrollment PR for CLA-authorized maintainer sign-off.

Note on Dockerfiles: these are distinct from the shared CIDocker CI base images. CIDocker stays the single source for CI containers (referenced via `container:`); the scanner requires one purpose-built `.oss-scanner/Dockerfile` per **enrolled** repo (the scanner clones one repo non-recursively). Each can use the public GHCR AlmaLinux 8 image as its base, with repo-specific submodule fetch, build, and offline-test layers on top. CIDocker itself is not a scan target.

The full criteria analysis lives in the GeniusNetwork repo's `.planning/workstreams/tokenprice/quick/261009-rrt-evaluate-issue-10-oss-scanner-enrollment/EVALUATION.md` (internal record; quick task `261009-rrt`).

## Suggested issue-body updates (for @itsafuu, not applied here)

- Mark the "One exception" paragraph as resolved (link PR #51 + merge commit) rather than leaving it as a pending draft.
- Add evmrelay to the proposed initial applications list alongside SuperGenius, GeniusWallet, `gnus-ai`/`erc20-gnus-proxy`, and GeniusCognitiveSystem.

This is a status report and recommendation for the assignee/maintainers — the final execution-structure call remains with you.
