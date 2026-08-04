---
phase: 08-node-example-child-wallet-commands
plan: 01
subsystem: node_example
tags: [cli, repl, child-wallet, registration, balance, boost-hex, spdlog]

# Dependency graph
requires:
  - phase: v2.1/v2.2/v2.3 (prior milestones)
    provides: GeniusNode::GetChildBalance, GeniusNode::GetRegistrationsForMain, GeniusNode::RegisterChild (all pre-existing, already-tested C++ methods)
provides:
  - "childbalance <child_address> [token_id]" REPL command (all-tokens or single-token child balance query)
  - "listchildren <main_address>" REPL command (lists registered children with balances)
  - "registerchild <main_address>" REPL command (registers this node as a child)
  - parse_token_id and check_arg_count_range reusable helpers in NodeExample.cpp
affects: [node_example CLI, future GeniusWallet UI phases that may wrap these same GeniusNode calls]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "boost::algorithm::unhex hex-string-to-fixed-buffer parsing, adapted from GeniusSDK.cpp's ParseTokenID to this file's bool/out-param style"
    - "check_arg_count_range for [min,max] arg-count validation, alongside existing check_arg_count/check_arg_count_min"

key-files:
  created: []
  modified:
    - SuperGenius/example/node_test/NodeExample.cpp

key-decisions:
  - "Reused cmd_childbalance's 2-arg all-tokens GetChildBalance call verbatim inside cmd_listchildren's per-entry loop, per plan's key_links spec"
  - "Kept game_id/publisher_id as literal mock placeholder strings in registerchild, per REQUIREMENTS.md Out of Scope guidance (not consumed downstream today)"

patterns-established:
  - "New REPL commands follow the existing cmd_* / COMMANDS map / cmd_help triad convention exactly"

requirements-completed: [NEXC-01, NEXC-02, NEXC-03]

coverage:
  - id: D1
    description: "childbalance <child_address> with no token_id returns the all-tokens total via GeniusNode::GetChildBalance(child_address)"
    requirement: "NEXC-03"
    verification:
      - kind: unit
        ref: "grep -c cmd_childbalance SuperGenius/example/node_test/NodeExample.cpp (== 2: definition + COMMANDS entry)"
        status: pass
    human_judgment: true
    rationale: "Requires a live GeniusNode process reading real CRDT-backed UTXO state at the REPL — cannot be confirmed by grep or a clean compile alone (plan's own human-check note)."
  - id: D2
    description: "childbalance <child_address> <token_id> parses 64-hex (optional 0x prefix) token_id and returns the single-token balance; invalid hex logs an error and does not call GetChildBalance"
    requirement: "NEXC-03"
    verification:
      - kind: unit
        ref: "grep -n parse_token_id( SuperGenius/example/node_test/NodeExample.cpp (helper present, invoked in 3-arg branch before GetChildBalance)"
        status: pass
    human_judgment: true
    rationale: "Live REPL exercise of valid/invalid hex token_id inputs required to confirm branch and error text — same class of check as D1."
  - id: D3
    description: "listchildren <main_address> prints every GetRegistrationsForMain entry together with that child's balance, not the address alone"
    requirement: "NEXC-02"
    verification:
      - kind: unit
        ref: "grep -n 'entry.child_addr' SuperGenius/example/node_test/NodeExample.cpp (logged alongside GetChildBalance(entry.child_addr) in the same logger->info line)"
        status: pass
    human_judgment: true
    rationale: "Requires a real local CRDT reg/ write (via registerchild) followed by a real CRDT read-back (via GetRegistrationsForMain) — cannot be confirmed by grep or a clean compile alone."
  - id: D4
    description: "registerchild <main_address> builds RegistrationMetadata (dev_wallet=DEV_CONFIG.Addr, peers_cut=1.0-DEV_CONFIG.Cut in ParseMinions fixed-point scale) and calls GeniusNode::RegisterChild(main_address, metadata)"
    requirement: "NEXC-01"
    verification:
      - kind: unit
        ref: "grep -n 'metadata.set_dev_wallet( DEV_CONFIG.Addr )' and 'metadata.set_peers_cut(' SuperGenius/example/node_test/NodeExample.cpp"
        status: pass
    human_judgment: true
    rationale: "Full CRDT registration + local discovery round-trip requires a live running GeniusNode instance — confirms ROADMAP.md Phase 8 success criterion 1 end-to-end, cannot be confirmed by grep or compile alone."
  - id: D5
    description: "node_example builds successfully with all three new commands wired into COMMANDS and cmd_help"
    requirement: ""
    verification:
      - kind: integration
        ref: "cmake --build SuperGenius/build/Windows/Release --target node_example --config Release (exit 0, node_example.exe produced)"
        status: pass
    human_judgment: false

# Metrics
duration: ~20min
completed: 2026-07-27
status: complete
---

# Phase 08 Plan 01: node_example Child Wallet Commands Summary

**Added `childbalance`, `listchildren`, and `registerchild` REPL commands to `node_example`, each a thin wrapper over existing tested `GeniusNode` C++ methods — `node_example` builds clean with all three wired into `COMMANDS` and `cmd_help`.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-27T23:35:00Z (approx.)
- **Completed:** 2026-07-27T23:52:50Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- `childbalance <child_address> [token_id]` — queries a child's all-tokens total or single-token balance, with a new `parse_token_id` helper validating 64-hex (optional `0x`) input via `boost::algorithm::unhex`
- `listchildren <main_address>` — lists every child registered to a main wallet via `GetRegistrationsForMain`, printing each child's address alongside its balance (reusing `cmd_childbalance`'s all-tokens lookup)
- `registerchild <main_address>` — registers this node as a child, deriving `dev_wallet` from `DEV_CONFIG.Addr` and `peers_cut` as `ParseMinions("1.0") - ParseMinions(DEV_CONFIG.Cut)`, with mock `game_id`/`publisher_id` placeholders
- `node_example` (Release config) builds cleanly end-to-end with all three commands present

## Task Commits

Each task was committed atomically (in the `SuperGenius` submodule, branch `dev_childwallet`):

1. **Task 1: Add `childbalance` command with hex token_id parsing (NEXC-03)** - `959d804b` (feat)
2. **Task 2: Add `listchildren` command reusing childbalance's balance lookup (NEXC-02)** - `55bb4cd7` (feat)
3. **Task 3: Add `registerchild` command with exact metadata derivation (NEXC-01) and build node_example** - `755f5b29` (feat)

**Plan metadata:** committed separately in the parent `GeniusNetwork` repo (docs commit, see below).

_Note: All three commits landed inside the `SuperGenius` git submodule since `files_modified` in this plan (`SuperGenius/example/node_test/NodeExample.cpp`) lives inside that submodule, not the parent repo directly._

## Files Created/Modified
- `SuperGenius/example/node_test/NodeExample.cpp` - Added `check_arg_count_range`, `parse_token_id` helpers; `cmd_childbalance`, `cmd_listchildren`, `cmd_registerchild` command functions; 3 new `COMMANDS` map entries; 3 new `cmd_help` lines; 3 new includes (`account/TokenAmount.hpp`, `boost/algorithm/hex.hpp`, `<array>`)

## Decisions Made
- Reused `cmd_childbalance`'s 2-arg `GetChildBalance(child_addr)` call verbatim inside `cmd_listchildren`'s loop, exactly as the plan's `key_links` specified, rather than introducing a separate balance-lookup path
- Kept `game_id`/`publisher_id` as literal `"mock_game_id"`/`"mock_publisher_id"` strings — no config source invented, per REQUIREMENTS.md's Out of Scope guidance that these fields are unused downstream today

## Deviations from Plan

None - plan executed exactly as written. All three tasks, helpers, `COMMANDS` entries, and `cmd_help` lines match the plan's `<action>` specs verbatim. The build (Task 3's automated verify) succeeded with exit 0 on the first attempt; the only compiler warnings emitted (`C4834`, discarding `[[nodiscard]]` return values at lines 410/426) are in pre-existing `cmd_mint`/`cmd_transfer` code untouched by this plan — out of scope per the deviation rules' scope boundary, not fixed.

Note: local IDE/IntelliSense diagnostics transiently flagged `GetChildBalance`/`GetRegistrationsForMain` as unresolved during editing (stale index, since the class declares both well before its closing brace at `GeniusNode.hpp:1308`). The actual MSVC build confirmed these resolve correctly — no action needed.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All three ROADMAP.md Phase 8 success criteria (registerchild discoverable via listchildren, listchildren shows address+balance, childbalance no-token_id and with-token_id) are ready for the Step-8 end-of-phase verifier to harvest from each task's `<verify><human-check>` block and consolidate into `08-UAT.md` (per `workflow.human_verify_mode = "end-of-phase"`)
- No blockers; `node_example.exe` built successfully at `SuperGenius/build/Windows/Release/example/node_test/Release/node_example.exe` and is ready for live REPL verification

---
*Phase: 08-node-example-child-wallet-commands*
*Completed: 2026-07-27*

## Self-Check: PASSED

- FOUND: SuperGenius/example/node_test/NodeExample.cpp
- FOUND: .planning/workstreams/milestone/phases/08-node-example-child-wallet-commands/08-01-SUMMARY.md
- FOUND commit: 959d804b (Task 1, SuperGenius submodule)
- FOUND commit: 55bb4cd7 (Task 2, SuperGenius submodule)
- FOUND commit: 755f5b29 (Task 3, SuperGenius submodule)
- FOUND commit: 5484722 (SUMMARY.md, parent repo)
