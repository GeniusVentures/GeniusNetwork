# Phase 4: Repin & Cross-Repo Verification - Pattern Map

**Mapped:** 2026-10-14
**Files analyzed:** 5 (2 git-commit units, 2 doc/evidence artifacts, 1 contingency class)
**Analogs found:** 4 / 5

> **Honest scope note (read this first):** This is a **pin-and-verify phase** — no new protocol or library code is written. The "files" touched are git plumbing (gitlink bumps), build-tree state, and planning/evidence documents. The analog set is therefore structurally thin: 4 real analogs exist (all exact or role-match), 1 "file" class (D-18 contingency adaptations) has **no analog by design**. The planner should treat RESEARCH.md's verified command blocks (E1–E8) as the executable pattern source and the analogs below as the shape/style/discipline source. This near-thin map is correct for this phase — do not pad it.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| thirdparty integration-branch commit staging gitlinks `ipfs-bitswap-cpp` / `libp2p` / `ipfs-pubsub` (D-01/D-03) | config (version pin) | transform (git metadata: SHA pointers) | thirdparty commit `1cbf85a` (`chore: bump libp2p — …`, single-gitlink bump, HEAD of `develop`) | exact |
| Root repo `thirdparty` gitlink commit on `dev_persisprocresults` (D-02) | config (version pin) | transform (git metadata) | root commits `d67cf2b`, `0cef56d`, `95c35ea` (`git log -- thirdparty`) | exact |
| `04-VERIFICATION.md` (phase dir) | test (verification evidence) | file-I/O (records command transcripts) | `.planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-VERIFICATION.md` (secondary: 02-, 01-VERIFICATION.md) | exact (structural) |
| `baseline-*.log` + probe/hash-audit transcripts in phase dir (D-04/D-08/D-11 evidence) | test (evidence artifact) | file-I/O (captured stdout) | `.planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/asan_run.log`, `asan_bounds5.log` (tracked evidence logs, flat in phase dir) | role-match |
| Trivial consumer adaptation, file TBD only if triggered (D-18 fix-forward, contingency) | component (C++ consumer code) | n/a (contingency) | — none (by design; candidate files pre-identified in RESEARCH § SuperGenius Rebuild Breadth) | none |

**Tracked-source gate (#3645):** every named file analog verified via `git ls-files` in the root repo — `01-/02-/03-VERIFICATION.md` and `asan_run.log`/`asan_bounds5.log` all print as tracked (output captured this session). Commit analogs live in the `thirdparty` submodule repo and the root repo respectively (verified via `git log`/`git show`); no gitignored or mirror paths are named anywhere in this map.

## Pattern Assignments

### Thirdparty pin commit — gitlinks `ipfs-bitswap-cpp` / `libp2p` / `ipfs-pubsub` (config, transform)

**Analog:** thirdparty repo commit `1cbf85a9e982b35aad5e1c983d182cb7e33c26e3` (HEAD -> develop) — inspected via `git -C thirdparty show --stat 1cbf85a` this session.

**Commit-shape pattern** (copy this discipline):
```
commit 1cbf85a9e982b35aad5e1c983d182cb7e33c26e3 (HEAD -> develop)
Author: itsafuu <sariru@gmail.com>
Date:   Thu Oct 8 15:22:27 2026 -0400

    chore: bump libp2p — warn on setProtocolHandler overwrite (#11)

    Advance the libp2p gitlink to 28f6a62 so the setProtocolHandler
    overwrite warning and regression test land in thirdparty/develop.

 libp2p | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

**What to copy:**
- **Single-purpose commit:** the bump is the commit's entire content (`libp2p | 2 +-` — a gitlink mode-change line, nothing else). Phase 4 stages three gitlinks (`git add ipfs-bitswap-cpp libp2p ipfs-pubsub` — path-precise, never `git add -A`/`.`; D-03) and the stat must show exactly three gitlink lines.
- **Message shape:** `chore: bump <pkg> — <why>` headline; body names the **new SHA** (`28f6a62` in the analog) and the landing intent. Phase 4 must name all three pinned SHAs (`f899393`, `a54f5c4`, `5c6653c`) in the body — the SHA-in-message is the house style and doubles as a human-readable content anchor (INTG-02: branch names are provenance only, never trust anchors).
- **Branch discipline:** analog landed on `develop` directly; Phase 4 deviates deliberately per D-01 — cut `dev_ipfs_p0` from `develop` HEAD `1cbf85a` (this exact commit) and land the bumps there, leaving `develop` untouched. Never push.

---

### Root `thirdparty` gitlink commit on `dev_persisprocresults` (config, transform)

**Analog:** root repo commits touching the `thirdparty` path — inspected via `git log --oneline -8 -- thirdparty` this session:
```
d67cf2b chore(tokenprice): thirdparty pointer for sentinel cleanup
95c35ea chore(tokenprice): bump thirdparty + SuperGenius - Phase 2 (AsyncIOManager status-aware HTTPClient, price facade, hermetic suites)
0cef56d chore(submodule): advance thirdparty — bitswap lifetime hardening
```

**What to copy:**
- **Message shape:** `chore(<scope>): <verb> thirdparty — <why>` on the current working branch (no side branch at root). `0cef56d` (`chore(submodule): advance thirdparty — bitswap lifetime hardening`) is the closest topical twin — same library family, same gitlink-only change.
- **Content:** gitlink-only diff (the root `thirdparty` pointer moves `1cbf85a` → `dev_ipfs_p0` head). Stage with `git add thirdparty` — note the root-status quirk from RESEARCH found-state (`m thirdparty` = dirty-uncommitted submodule content); the commit must record the new SHA, not sweep `GeniusWallet`/`SuperGenius` dirt that happens to be lying around.
- **Order:** innermost-first (submodule commits → thirdparty commit → root commit) — D-01 then D-02; this mirrors how `95c35ea`/`0cef56d` were landed historically.

---

### `04-VERIFICATION.md` (test-verification doc, file-I/O)

**Analog:** `.planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-VERIFICATION.md` — most recent of three same-skeleton docs (01, 02, 03 all tracked, all read in full this session).

**Frontmatter pattern** (03-VERIFICATION.md lines 1-31 — copy verbatim shape, swap values):
```yaml
---
phase: 04-repin-cross-repo-verification
verified: <ISO timestamp>
status: passed
score: <N>/<N> must-haves verified
covered_files:
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-XX-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-XX-SUMMARY.md
  - thirdparty/ipfs-bitswap-cpp        # gitlink: d2ec18af -> f899393
  - thirdparty/libp2p                  # gitlink: 28f6a629 -> a54f5c4
  - thirdparty/ipfs-pubsub             # gitlink: b6eb6268 -> 5c6653c
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-*.log
covered_digest: "v2:sha256:<digest>"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
---
```
(covered_files for this phase lists gitlinks as the "modified files" plus the evidence logs — same convention 02/03 used for their submodule files.)

**Section skeleton to copy** (03-VERIFICATION.md, headings in order):
1. Title + **Phase Goal** line (quote ROADMAP Phase 4 boundary) + **Verified** + **Status → VERDICT** + **Re-verification** note
2. `## Goal Achievement` — one-paragraph **verification stance** (goal-backward, adversarial; name the exact SHAs and trees re-checked) followed by `### Observable Truths` table: `| # | Truth | Status | Evidence |` — each row's Evidence cell quotes the actual command output (SHA→marker probe results, hash-pair equalities, tlog grep True, case counts)
3. `### Prohibition Checks (all automated)` table — Phase 4 prohibitions: no `git add -A`, no push, no Release build, no `Select-String` on binaries, no incremental-across-header-change links
4. `### Required Artifacts` table — the pin commits, baseline logs, rebuilt exes/libs, tlog audit
5. `### Key Link Verification` — for this phase, the **chain wiring**: fix-branch SHA → thirdparty integration commit → root gitlink; inner vcxproj → INSTALL → deployed header hash equality; rebuilt lib → tlog link input → exe marker flip
6. `### Behavioral Spot-Checks` — the run/probe rows (see shared pattern below)
7. `### Requirements Coverage` — INTG-01, INTG-02, INTG-03 each mapped to source plan + evidence
8. `### Anti-Patterns Found`, `### Human Verification Required`, `### Regression Notes (non-blocking)` (this is where the D-05 rollback origin evidence and any D-13 flake records land), `### Gaps Summary`
9. Footer: `_Verified: <date>_` / `_Verifier: the agent (gsd-verifier)_`

**D-04 probe-row style** — copy the content-probe rows from 01-VERIFICATION.md § Behavioral Spot-Checks (exact-command → observed-output → status):
```
| Content probe: `completed_` | `git grep -n "completed_" HEAD -- src/bitswap.cpp` | lines 100, 106, 128, 132 | ✓ PASS |
```
Phase 4's version runs at the pinned SHA (`git -C <submodule> grep -c <marker> <SHA> -- <path>`) with the carry-forward vocabulary; observed counts go in the Result cell verbatim (RESEARCH E3 supplies the verified expected counts).

---

### `baseline-*.log` + probe transcripts (test-evidence artifacts, file-I/O)

**Analog:** `.planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/asan_run.log` and `asan_bounds5.log` — tracked (git ls-files confirms), **flat in the phase directory**, named-by-purpose, and referenced by name from VERIFICATION.md's spot-check tables.

**What to copy:**
- **Placement & tracking:** evidence logs live flat in `04-repin-cross-repo-verification/` and are committed alongside the docs (03's ASan logs are the precedent — VERIFICATION.md points at them by filename).
- **Naming:** purpose-prefixed — `baseline-<target>.log` for the D-11 pre-repin runs (RESEARCH E6's `Tee-Object -FilePath ...baseline-$t.log` already uses this shape); follow with e.g. `repin-<target>.log` for the post-rebuild runs so baseline/repin pairs are diffable by name.
- **Capture discipline:** raw stdout via `Tee-Object` (per-case `[  FAILED  ]` lines must survive into the log — D-11/D-13 compare per-case sets, not exit codes).

---

## Shared Patterns

### Never-push git discipline
**Source:** all three prior VERIFICATION.md § Behavioral Spot-Checks / Prohibition rows (e.g. 01: `git branch -r` → no `origin/dev_timer_correctness`; 02/03 same check per branch).
**Apply to:** both pin commits (D-01, D-02). Every commit verb ends local; VERIFICATION.md prohibition table must include a "never pushed" row with the `git branch -r` evidence, exactly as Phases 1–3 did.

### Content-probe evidence rows (INTG-02's core mechanic)
**Source:** 01-VERIFICATION.md § Behavioral Spot-Checks content-probe rows (quoted above); marker vocabulary locked in 01/02/03 CONTEXT/VERIFICATION carry-forward.
**Apply to:** D-04 (SHA→marker table), D-08 (binary byte-greps), D-16 (tlog greps). Row format is invariant: `| probe name | exact command | observed output | ✓ PASS |`. Use the ASCII-decode `Test-BinMarker` function from RESEARCH E4 — never `Select-String` on binaries (Pitfall 6: it returned False on a known-good exe this session).

### Evidence-doc skeleton + frontmatter
**Source:** 03-VERIFICATION.md (full skeleton quoted above).
**Apply to:** 04-VERIFICATION.md. The three prior docs prove the skeleton survives GSD tooling (digest, re_verification fields) — copy it mechanically; only the truths/prohibitions content changes.

### Surgical staging
**Source:** `1cbf85a`'s single-gitlink diff stat (quoted above).
**Apply to:** D-03 — stage by exact path (`git add ipfs-bitswap-cpp libp2p ipfs-pubsub` in thirdparty; `git add thirdparty` at root), verify with `git status --short` that ONLY the intended gitlinks are staged before committing. The found-state drift (`gnus_upnp` modified, `MNN`/`fmt` untracked, libp2p `Testing/` + `.planning/research/.cache/` untracked) must remain untouched.

### Build-landmine guards (RESEARCH-sourced, no codebase analog — planner must inline these)
These are **not** file patterns but execution constraints the planner must bake into plan actions, because no existing script encodes them: wrapper-vcxproj trap (build the inner vcxproj paths, three of which deviate from the naive pattern — libp2p's is `p2p.vcxproj`, pubsub's has an extra `ipfs_pubsub` dir level), INSTALL-before-hash-audit per package, libp2p-before-pubsub ordering, libs-before-tests (SG test vcxprojs do not ProjectReference the src libs), clean/rebuild never incremental across the `gossip.hpp` Config layout change, and bounded disk (never clean the whole 162 GB SG tree; the Sep-15 baseline exes are irreplaceable). Full recipes with verified paths: RESEARCH.md § Pattern 2, § Focus Suites, E5–E8.

## No Analog Found

Files/mechanics with no close match in the codebase (planner uses RESEARCH.md verified commands instead):

| File / Mechanism | Role | Data Flow | Reason |
|------|------|-----------|--------|
| D-18 trivial consumer adaptation (contingency; file unknown until triggered) | component | n/a | Contingency-only by locked decision; candidate surface pre-identified in RESEARCH § SuperGenius Rebuild Breadth (TUs including `gossip.hpp` / `gossip_pubsub.hpp` / `bitswap.hpp` — e.g. `SuperGenius/src/account/GeniusNode.cpp`, `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp`, `SuperGenius/src/processing/processing_service.cpp`). If triggered: follow workspace C++ conventions (AGENTS.md / `.planning/codebase/CONVENTIONS.md`), keep it trivial or stop-and-report. |
| MSBuild rebuild / hash-audit / byte-grep / tlog-audit orchestration | utility (build ops) | batch | No existing script or CI target encodes the deployed-header ABI recipe — it exists only as this milestone's RESEARCH E1–E8 verified command blocks. Nothing to copy from the codebase; do not invent a permanent script (verification convention: run in existing build trees, record transcripts). |

## Metadata

**Analog search scope:**
- `.planning/workstreams/ipfs-improve/phases/{01-bitswap-timer-correctness,02-bitswap-callback-reentrancy,03-gossipsub-resource-bounds}/` — docs + evidence artifacts (21 tracked files enumerated via git ls-files; 3 VERIFICATION.md read in full)
- thirdparty submodule repo — `git log --oneline -5`, `git show --stat 1cbf85a` (pin-bump commit analog)
- root repo — `git log --oneline -8 -- thirdparty` (gitlink-bump commit analogs)
- Phase-04 directory state check (currently: 04-CONTEXT.md, 04-DISCUSSION-LOG.md, 04-RESEARCH.md)

**Files scanned:** ~25 planning/evidence files enumerated, 3 verification docs + 2 git histories read in full
**Pattern extraction date:** 2026-10-14
**Tracked-source gate:** PASS — all named file analogs git-tracked (root repo); commit analogs verified in their repos; no mirror/gitignored paths emitted
