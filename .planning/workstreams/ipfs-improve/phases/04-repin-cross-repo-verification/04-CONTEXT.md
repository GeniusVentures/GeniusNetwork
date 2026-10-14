# Phase 4: Repin & Cross-Repo Verification - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning

<domain>
## Phase Boundary

The three fix branches verifiably become the integrated tree: `thirdparty` pins bumped by content-probed verification at the fix-branch SHAs (ipfs-bitswap-cpp `f899393` on `dev_timer_correctness`, libp2p `a54f5c4` on `dev_gossip_bounds`, ipfs-pubsub `5c6653c` on `dev_ipfs_fix`), the integrated Debug build tree refreshed per the deployed-header ABI recipe, SuperGenius focus suites passing the no-new-failures bar against a fresh pre-repin baseline, and GeniusSDK building and linking cleanly against the repinned tree (build-only). Requirements: INTG-01, INTG-02, INTG-03.

This is a **pin-and-verify phase**: no new protocol or library code is written. The only permitted in-phase source changes are trivial consumer adaptations under D-18 (fix-forward-if-trivial). Everything is local — nothing is pushed (standing operator rule).

Out of scope: CI restoration (audit P0 #3), Release-tree rebuilds, running the GeniusSDK example (smoke), Go interop harness, and any new capability work.

**Carry-forward from Phases 1–3 (locked — do not re-litigate):**
- Fix branches cut from integrated SHAs, single linear chains, never pushed; pins trusted by content probe, never branch name (INTG-01/02)
- Greppable content-probe marker vocabulary already defined per phase: bitswap (`completed_`, `REQUEST_TIMEOUT`, race-test file presence), libp2p (`Gossip::Config` knobs `max_remote_subscriptions_per_peer` / `max_pending_bytes_per_stream` / overflow threshold, violation seam), ipfs-pubsub (`BlockPeer` escalation registration, TEST-02 suite presence)
- Windows suite is primary evidence; verification happens inside existing `build/<Platform>/<Config>` trees
- libp2p carries code-marker probes only this milestone (Phase 3 D-11 consequence)

</domain>

<decisions>
## Implementation Decisions

### Pin landing & branch strategy (INTG-01/02)
- **D-01:** Dedicated thirdparty integration branch — cut a new branch (name agent discretion, e.g. `dev_ipfs_p0`) from thirdparty `develop` HEAD `1cbf85a`; the three gitlink bumps (ipfs-bitswap-cpp `f899393`, libp2p `a54f5c4`, ipfs-pubsub `5c6653c`) land as commit(s) there. thirdparty `develop` stays untouched until a reviewed merge; never pushed. — **Reversibility:** reversible — branch + commits only.
- **D-02:** Root gitlink committed on the current root branch — the root repo's `thirdparty` pointer is bumped in a commit on `dev_persisprocresults` (already carrying this workstream's docs commits), recording the full chain in git: fix branches → thirdparty integration branch → root pointer. Never pushed. — **Reversibility:** reversible — local commit.
- **D-03:** Surgical staging — the thirdparty pin commit stages exactly the three gitlinks (`git add ipfs-bitswap-cpp libp2p ipfs-pubsub`); unrelated worktree drift (`gnus_upnp` modified, `MNN`/`fmt` untracked-pointer noise) is left untouched and never swept in. Untracked junk inside libp2p (`Testing/`, `.planning/research/.cache/`) is cleaned or ignored, never committed. — **Reversibility:** reversible — staging discipline.
- **D-04:** Content probes recorded with transcript — INTG-02's grep probes run at each pinned SHA with the exact marker list from the carry-forward vocabulary; the SHA→marker evidence lands in VERIFICATION.md. Branch names appear only as provenance notes, never as trust anchors.

### Pre-pin reconciliation (blocking pre-task)
- **D-05:** Investigate the bitswap worktree rollback BEFORE touching it — the `thirdparty/ipfs-bitswap-cpp` working tree is currently rolled back ~460 lines vs HEAD `f899393` (`src/bitswap.cpp`/`.hpp` lost the Phase-2 replay/reentrancy code; the race test lost the Phase-2 cases; commits are intact, only the worktree regressed). First establish origin (WSL-sync residue vs verification probe vs other) and confirm nothing uncommitted-and-valuable hides there; then `git restore` the three files and re-verify (13-case suite green at the restored tree) before pinning. Any build run before this would compile pre-fix code. — **Reversibility:** reversible.

### Integrated-tree rebuild (INTG-03 prerequisite)
- **D-06:** Full deployed-header ABI recipe — for each repinned package: MSBuild the inner vcxproj (`thirdparty\build\Windows\Debug\<pkg>\src\<pkg>-build\src\<pkg>.vcxproj` — the top-level wrapper project compiles nothing), run INSTALL.vcxproj to refresh deployed `include/` + `lib/`, then hash-audit every deployed header vs source (`libp2p`, `ipfs-pubsub`, `ipfs-bitswap-cpp` headers all changed; `gossip.hpp`'s `Config` grew three knobs = layout change). Then CLEAN (not incremental) rebuild of dependent packages and of every SuperGenius target whose TUs include a changed header (include-grep enumeration). Incremental is rejected: stale-TU links against the new Config layout are the documented 0xC0000374 heap-corruption trap. — **Reversibility:** reversible — build-tree state only.
- **D-07:** Debug only — the existing `thirdparty/build/Windows/Debug` + `SuperGenius/build/Windows/Debug` trees; Release is not rebuilt this phase. Disk headroom ~4.8 GB on W: constrains clean-rebuild breadth. — **Reversibility:** reversible.
- **D-08:** Marker-probe binaries at the SuperGenius layer — after linking, byte-grep the built focus-suite test exes for a fix-marker string (e.g. a new bound-drop log format) proving the fixed code actually entered the binary; this catches the documented MSBuild incremental-link-skip trap where a refreshed lib member never gets pulled. — **Reversibility:** reversible — evidence-only.
- **D-09:** SuperGenius rebuild breadth = focus-suite targets + their internal deps only (clean per D-06); broad link health is the GeniusSDK build's job (D-14). — **Reversibility:** reversible.

### Focus suites & pass bar (INTG-03)
- **D-10:** Focus set = the roadmap's three named paths mapped to suites — CRDT/PubSub → `SuperGenius/test/src/crdt` + `pubsub_counts`; DAG-syncer → the suite(s) containing the DAG syncer (crdt/graphsync side); AccountMessenger → its suite. Research pins the exact ctest targets; the all-five widening (securecrdt, transaction_sync) was not selected. — **Reversibility:** reversible — set definition.
- **D-11:** Pass bar = no-new-failures vs a fresh pre-repin baseline — the same focus suites run on the pre-repin integrated tree FIRST (ordering constraint: baseline must complete before the D-06 rebuild replaces the old libs); the repinned run must add zero failures. Pre-existing reds are documented, not blocking. — **Reversibility:** reversible.
- **D-12:** TEST-01 and TEST-02 both re-run at pin time in their existing standalone trees (`thirdparty/build/Windows/Debug/ipfs-bitswap-cpp-test`, `.../ipfs-pubsub-test`) — proves the exact pinned SHAs green at the moment of pinning; both suites are deterministic so cost is minutes. — **Reversibility:** reversible — evidence-only.
- **D-13:** Flake policy = retry once + document — a suite result that differs between baseline and repinned runs gets exactly one retry; the retry result stands and the flake is recorded in VERIFICATION.md. Contradictory results on identical inputs are investigated, not retried away. — **Reversibility:** reversible.

### GeniusSDK verification (INTG-03)
- **D-14:** SDK core target + one example/service target — the library link check plus a real-consumer embedding proof; not the full solution, not lib-only. — **Reversibility:** reversible.
- **D-15:** Strictly build-only — compile + link success is the entire claim (roadmap parenthetical verbatim); nothing is executed. — **Reversibility:** reversible.
- **D-16:** SDK link evidence = tlog + hash audit — `link.read.1.tlog` (linker inputs) must show the freshly rebuilt thirdparty libs were consumed, combined with the deployed-lib hash audit from D-06. Byte-grepping the SDK binary for fix markers is NOT the SDK's evidence standard: static linking only pulls referenced object files, so marker strings can legitimately be absent. — **Reversibility:** reversible — evidence-only.
- **D-17:** Existing `GeniusSDK/build/Windows` Debug tree, reconfigured in place against the repinned thirdparty; a fresh configure dir is a documented fallback only if the stale cache fights the repin, not pre-planned. — **Reversibility:** reversible.

### Failure contingency
- **D-18:** Fix-forward if trivial — a trivial, local adaptation (missing include, a default a consumer must now pass) is fixed inside Phase 4 and recorded. Anything structural (API contract change, test redesign, pre-existing-failure escalation) stops and reports back to the operator. Applies to focus suites, the SDK build, and the rebuild itself. — **Reversibility:** reversible.

### The agent's Discretion
- Integration branch name (e.g. `dev_ipfs_p0`) and commit message shape in thirdparty and root
- Exact ctest target enumeration for the three paths (D-10) and which suite owns DAG-syncer / AccountMessenger
- Which GeniusSDK example/service target serves as the consumer proof (D-14)
- The concrete marker strings probed (from the carry-forward vocabulary) and the grep mechanics
- MSBuild invocation details (full exe path, `/m`, per-project ordering) within the D-06 recipe
- Phase-internal ordering of pin-commit vs baseline vs rebuild (only hard constraint: baseline before the D-06 rebuild clobbers old libs; pin commit before content probes)
- How the D-05 rollback investigation is evidenced (file mtimes, reflog, sync timestamps) as long as it is bounded and concludes before restore
- VERIFICATION.md internal structure

### Folded Todos
None — the single todo match ("Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path", score 0.6 on generic keywords) is the same spurious item reviewed and left in Phases 1–3; reviewed again here, left for its natural owner.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning artifacts
- `.planning/workstreams/ipfs-improve/REQUIREMENTS.md` — INTG-01, INTG-02, INTG-03 definitions (the WHAT)
- `.planning/workstreams/ipfs-improve/ROADMAP.md` §Phase Details → Phase 4 — success criteria SC1–SC4
- `.planning/workstreams/ipfs-improve/STATE.md` — pinned SHAs, phase chain, progress

### Prior phase inheritance (fix branches, markers, test trees)
- `.planning/workstreams/ipfs-improve/phases/01-bitswap-timer-correctness/01-CONTEXT.md` and `01-VERIFICATION.md` — branch `dev_timer_correctness` provenance, content-probe style, standalone test-tree recipe
- `.planning/workstreams/ipfs-improve/phases/02-bitswap-callback-reentrancy/02-CONTEXT.md` and `02-VERIFICATION.md` — the 13-case race suite (TEST-01) whose worktree state D-05 reconciles; WSL ASan supplementary pattern
- `.planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-CONTEXT.md` and `03-VERIFICATION.md` — libp2p `dev_gossip_bounds` + ipfs-pubsub `dev_ipfs_fix` branches, TEST-02 suite, code-marker-only libp2p probe consequence

### Audit origin
- `.planning/research/gnus_libp2p_comparison.md` — the audit that started the milestone; §pin/integration context for why content probes exist

### Build & verification conventions
- `.planning/codebase/TESTING.md` — verification convention: build/test inside the existing `build/<Platform>/<Config>` tree; thirdparty components build via cmake/MSBuild before SuperGenius consumes them
- `.planning/codebase/INTEGRATIONS.md` — thirdparty → SuperGenius → GeniusSDK consumption map (which layer links what)
- `thirdparty/build/Windows/Debug/` — the integrated build tree: deployed headers under `<pkg>/include/`, libs under `<pkg>/lib/`, inner vcxproj per package at `<pkg>/src/<pkg>-build/src/<pkg>.vcxproj`
- `thirdparty/build/Windows/Debug/ipfs-bitswap-cpp-test/` and `thirdparty/build/Windows/Debug/ipfs-pubsub-test/` — the standalone deterministic test trees D-12 re-runs
- `GeniusSDK/build/Windows/` — the SDK build tree D-17 reconfigures in place
- `SuperGenius/build/Windows/Debug/` — the SuperGenius tree whose focus-suite targets get clean-rebuilt (D-09)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The three fix branches, already checked out in the thirdparty worktree at their final HEADs — the repin is git-plumbing plus verification, not new code
- Standalone deterministic test trees (`ipfs-bitswap-cpp-test`, `ipfs-pubsub-test`) — both exist and are ctest-registered from Phases 1–3
- The deployed-header hash-audit technique (MD5-compare `thirdparty\<pkg>\include\**\*.hpp` vs `thirdparty\build\Windows\Debug\<pkg>\include\`) and the link-input tlog audit (`<proj>.dir\Debug\<proj>.tlog\link.read.1.tlog`) — both proven in this workspace
- `SuperGenius/test/src/` suite inventory: `crdt`, `graphsync`, `pubsub_counts`, `securecrdt`, `transaction_sync` — D-10's mapping targets

### Established Patterns
- Pin bumps on thirdparty as local commits (HEAD `1cbf85a` is exactly such a bump); detached/branch-checked-out submodules are normal — the gitlink is the source of truth
- Content-probe marker style greppable at pinned commits (INTG-02 explicitly allows grep markers)
- Fix branches never pushed; all git operations stay local (operator rule)

### Integration Points
- Pin chain: fix branches → thirdparty integration branch (D-01) → root gitlink on `dev_persisprocresults` (D-02)
- Build chain: inner vcxproj rebuild → INSTALL refresh → hash audit → clean dependents → focus-suite targets (D-06/D-09) → GeniusSDK reconfigure (D-17)
- Known landmines baked into D-05/D-06/D-08/D-16: top-level thirdparty vcxproj wrappers compile nothing; deployed headers don't refresh on lib rebuild; MSBuild doesn't recompile dependents on header change; incremental link can skip refreshed lib members; static linking can omit unreferenced marker objects

</code_context>

<specifics>
## Specific Ideas

- Baseline-before-rebuild is the one hard ordering constraint in the phase (D-11); everything else sequences around it
- The current thirdparty worktree state (fix branches checked out, gitlinks uncommitted, bitswap files rolled back) is the actual starting point — the plan should treat it as found-state, not assume a clean slate
- `gossip.hpp`'s `Config` layout change is what makes incremental builds categorically unsafe here — the clean-rebuild breadth decision (D-09) exists to bound its cost, not to question the clean itself

</specifics>

<deferred>
## Deferred Ideas

- **Release-tree rebuild + verification** — D-07 scopes to Debug; Release (the shipping/tag-build config) can be a fast-follow if wanted
- **GeniusSDK example smoke run** — rejected for this phase (D-15) because runtime node-bootstrap concerns (trust gates, config) are not this phase's subject
- **CI-side verification of the repinned chain** — out of scope per the milestone's explicit CI exclusion

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched on generic keywords (fix/supergenius/cpp, score 0.6); unrelated to IPFS repin; reviewed in Phases 1–3 and again here; left for its natural owner.

</deferred>

---

*Phase: 4-Repin & Cross-Repo Verification*
*Context gathered: 2026-10-14*
