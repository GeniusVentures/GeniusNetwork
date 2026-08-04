---
phase: 08-node-example-child-wallet-commands
verified: 2026-07-28T00:00:31Z
status: passed
score: 6/10 must-haves verified
behavior_unverified: 4
overrides_applied: 0
behavior_unverified_items:

  - truth: "Running registerchild <main_address> at the live REPL returns a success message with a transaction hash, and the registration is discoverable via listchildren <main_address> immediately after (ROADMAP.md Phase 8 success criterion 1)"
    test: "With node_example built and running in --terminal mode, pick a 128-hex-character placeholder address and run `registerchild <that_address>`, then immediately run `listchildren <that_address>`."
    expected: "registerchild logs a success message containing a transaction hash (not an error). listchildren run right after shows this node's own account address registered under that main address, together with a balance."
    why_human: "Full CRDT registration + local discovery round-trip requires a live running GeniusNode instance reading/writing real reg/ CRDT state — cannot be confirmed by grep or a clean compile alone."

  - truth: "Running listchildren <main_address> at the live REPL shows each child's address AND its current balance, not address alone (success criterion 2)"
    test: "With node_example running in --terminal mode, first run `registerchild <main_address>`, then run `listchildren <main_address>`."
    expected: "listchildren output includes this node's own account address (the address it just registered as a child) together with a raw balance number on the same line — not the address alone."
    why_human: "Requires a real local CRDT reg/ write (via registerchild) followed by a real CRDT read-back (via GetRegistrationsForMain) — cannot be confirmed by grep or a clean compile alone."

  - truth: "Running childbalance <child_address> with no token_id at the live REPL prints the all-tokens total (success criterion 3)"
    test: "At the REPL, run `childbalance <any-address>` with no token_id."
    expected: "Prints a single raw all-tokens balance number."
    why_human: "Requires a live GeniusNode process reading real CRDT-backed UTXO state — cannot be confirmed by grep or a clean compile alone."

  - truth: "Running childbalance <child_address> <token_id> at the live REPL prints the single-token balance (success criterion 4)"
    test: "At the REPL, run `childbalance <any-address> <64-hex-digit-token-id>`; then run `childbalance <any-address> not-valid-hex`."
    expected: "Valid-64-hex-digit form prints a single raw per-token balance number. The invalid-hex form logs \"Invalid token_id: 'not-valid-hex' — must be 64 hex digits (optionally 0x-prefixed).\" and does not crash the REPL."
    why_human: "Requires a live GeniusNode process reading real CRDT-backed UTXO state — cannot be confirmed by grep or a clean compile alone."
human_verification:

  - test: "With node_example built and running in --terminal mode, pick a 128-hex-character placeholder address and run `registerchild <that_address>`, then immediately run `listchildren <that_address>`."
    expected: "registerchild logs a success message containing a transaction hash (not an error). listchildren run right after shows this node's own account address registered under that main address, together with a balance."
    why_human: "Full CRDT registration + local discovery round-trip requires a live running GeniusNode instance — confirms ROADMAP.md Phase 8 success criterion 1 end-to-end."

  - test: "With node_example running in --terminal mode, first run `registerchild <main_address>`, then run `listchildren <main_address>`."
    expected: "listchildren output includes this node's own account address together with a raw balance number on the same line — not the address alone."
    why_human: "Requires a real local CRDT reg/ write followed by a real CRDT read-back — cannot be confirmed by grep or a clean compile alone. Confirms success criterion 2."

  - test: "At the REPL, run `childbalance <any-address>` with no token_id."
    expected: "Prints a single raw all-tokens balance number."
    why_human: "Requires a live GeniusNode process reading real CRDT-backed UTXO state. Confirms success criterion 3."

  - test: "At the REPL, run `childbalance <any-address> <64-hex-digit-token-id>`; then run `childbalance <any-address> not-valid-hex`."
    expected: "Valid-hex form prints a single raw per-token balance number. Invalid-hex form logs the exact error message and does not crash the REPL."
    why_human: "Requires a live GeniusNode process reading real CRDT-backed UTXO state. Confirms success criterion 4."
---

# Phase 8: node_example Child Wallet Commands Verification Report

**Phase Goal:** Users can register the running `node_example` instance as a child wallet, discover all children registered to a given main wallet, and query any child's balance — all from the `node_example` interactive REPL (`SuperGenius/example/node_test/NodeExample.cpp`), reusing `GeniusNode::RegisterChild`/`GetRegistrationsForMain`/`GetChildBalance` with no new proto, consensus, or GeniusSDK work.
**Verified:** 2026-07-28T00:00:31Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `childbalance <child_address>` with no `token_id` returns the all-tokens total via `GeniusNode::GetChildBalance(child_address)` | VERIFIED | `NodeExample.cpp:314-317` — 2-arg branch calls `node->GetChildBalance( args[1] )`, matches `GeniusNode.hpp:477` signature `uint64_t GetChildBalance( const std::string &child_address )` |
| 2 | `childbalance <child_address> <token_id>` parses `token_id` as 64 hex digits (optional `0x` prefix) and returns the single-token balance via `GeniusNode::GetChildBalance(child_address, token_id)` | VERIFIED | `NodeExample.cpp:320-327` calls `parse_token_id(args[2], token_id)` (impl at 262-287: strips `0x`/`0X`, requires `hex.size()==64`, `boost::algorithm::unhex` into `std::array<uint8_t,32>`), then `node->GetChildBalance( args[1], token_id )` matching `GeniusNode.hpp:467` |
| 3 | An invalid (non-64-hex) `token_id` argument to `childbalance` logs an error and does not call `GetChildBalance` | VERIFIED | `NodeExample.cpp:321-325` — on `parse_token_id` failure, `logger->error(...)` then `return;` before reaching the `GetChildBalance` call on line 327 |
| 4 | `listchildren <main_address>` prints every entry returned by `GeniusNode::GetRegistrationsForMain(main_address)` together with that child's balance — not the address alone | VERIFIED | `NodeExample.cpp:337,350-353` — `node->GetRegistrationsForMain(args[1])`, then per-entry `logger->info("Child: {}  Balance: {}", entry.child_addr, node->GetChildBalance(entry.child_addr))` — both address and balance on one log line |
| 5 | `registerchild <main_address>` builds `SGTransaction::RegistrationMetadata` with `dev_wallet = DEV_CONFIG.Addr` and `peers_cut = TokenAmount::ParseMinions("1.0") - TokenAmount::ParseMinions(DEV_CONFIG.Cut)`, then calls `GeniusNode::RegisterChild(main_address, metadata)` | VERIFIED | `NodeExample.cpp:363-383` — exact derivation matches: `ParseMinions("1.0")`, `ParseMinions(DEV_CONFIG.Cut)`, `metadata.set_dev_wallet(DEV_CONFIG.Addr)`, `metadata.set_peers_cut(one_scale.value() - dev_cut.value())`, `node->RegisterChild(args[1], metadata)` — matches 2-arg auto-sequence overload at `GeniusNode.hpp:584-585` |
| 6 | `node_example` (target `node_example`) builds successfully with all three new commands wired into `COMMANDS` and `cmd_help` | VERIFIED | Rebuilt live: `cmake --build SuperGenius/build/Windows/Release --target node_example --config Release` exits 0, no errors, produces `node_example.exe` (29.4MB, timestamp matches Task 3 commit). `COMMANDS` map (lines 483-499) and `cmd_help` (lines 501-518) both list `childbalance`/`listchildren`/`registerchild` |
| 7 | [ROADMAP SC1] Running `registerchild <main_address>` at the live REPL returns a success message with a transaction hash, and the registration is discoverable via `listchildren <main_address>` immediately after | PRESENT_BEHAVIOR_UNVERIFIED | Code present and wired (see #5, #4) but no test exercises the live CRDT registration → discovery round-trip. Routed to human verification. |
| 8 | [ROADMAP SC2] Running `listchildren <main_address>` at the live REPL shows each child's address AND its current balance, not address alone | PRESENT_BEHAVIOR_UNVERIFIED | Code present and wired (see #4) but requires a live REPL + real CRDT read to confirm rendered output. Routed to human verification. |
| 9 | [ROADMAP SC3] Running `childbalance <child_address>` (no `token_id`) at the live REPL prints that child's all-tokens total balance | PRESENT_BEHAVIOR_UNVERIFIED | Code present and wired (see #1) but requires a live `GeniusNode` reading real CRDT-backed UTXO state. Routed to human verification. |
| 10 | [ROADMAP SC4] Running `childbalance <child_address> <token_id>` at the live REPL prints the balance for just the specified token | PRESENT_BEHAVIOR_UNVERIFIED | Code present and wired (see #2) but requires a live `GeniusNode` reading real CRDT-backed UTXO state. Routed to human verification. |

**Score:** 6/10 truths verified (4 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/example/node_test/NodeExample.cpp` | `registerchild`/`listchildren`/`childbalance` REPL commands, their `COMMANDS` map entries, and `cmd_help` text | VERIFIED | File exists (723 lines), contains `cmd_childbalance` (2 occurrences: def + COMMANDS entry), `cmd_listchildren` (2), `cmd_registerchild` (2). Not a stub — each function calls a real `GeniusNode` method with real error handling (`outcome::result` checks, `logger->error` branches), not hardcoded/static returns |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `COMMANDS` map entry `"childbalance"` | `cmd_childbalance` | static map initializer | WIRED | Line 488: `{ "childbalance", cmd_childbalance },` |
| `cmd_childbalance` 3-arg branch | `parse_token_id` | direct call before `GetChildBalance(child_address, token_id)` | WIRED | Line 321: `if ( !parse_token_id( args[2], token_id ) )` — called before line 327's `GetChildBalance` |
| `COMMANDS` map entry `"listchildren"` | `cmd_listchildren` | static map initializer | WIRED | Line 489: `{ "listchildren", cmd_listchildren },` |
| `cmd_listchildren` per-entry loop | `GeniusNode::GetChildBalance` | same all-tokens balance call as `cmd_childbalance`'s 2-arg branch | WIRED | Line 352: `node->GetChildBalance( entry.child_addr )` — identical call shape to line 316 |
| `COMMANDS` map entry `"registerchild"` | `cmd_registerchild` | static map initializer | WIRED | Line 490: `{ "registerchild", cmd_registerchild },` |
| `cmd_registerchild` | `GeniusNode::RegisterChild` | 2-arg auto-derived-sequence overload | WIRED | Line 383: `node->RegisterChild( args[1], metadata )` — matches `GeniusNode.hpp:584-585` overload (not the 3-arg caller-supplied-sequence variant) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `cmd_childbalance` | `node->GetChildBalance(...)` return value | `GeniusNode::GetChildBalance` (`GeniusNode.hpp:467,477`) — pre-existing, tested method reading UTXO/balance state | Yes — real method, not a stub | FLOWING |
| `cmd_listchildren` | `result.value()` (vector of `RegistrationDiscoveryEntry`) | `GeniusNode::GetRegistrationsForMain` (`GeniusNode.hpp:677-678`) — "Scans the reg/ CRDT namespace and returns entries whose main_address matches" | Yes — real CRDT scan, not a static/empty return | FLOWING |
| `cmd_registerchild` | `result.value()` (tx hash) | `GeniusNode::RegisterChild` (`GeniusNode.hpp:584-585`) — pre-existing method enqueuing a real registration transaction | Yes — real method | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `node_example` builds cleanly with all 3 new commands | `cmake --build SuperGenius/build/Windows/Release --target node_example --config Release` | Exit 0, `node_example.vcxproj -> .../Release/node_example.exe` produced, no compile errors | PASS |
| Live REPL command behavior (registerchild/listchildren/childbalance round-trip) | requires launching `node_example --terminal`, waiting for `NodeState::READY` (network/CRDT bootstrap), then issuing REPL commands | Not run — requires a live networked node process, real reg/ CRDT writes, and interactive stdin | SKIP (routed to human verification, per plan's own `<human-check>` blocks and `workflow.human_verify_mode = end-of-phase`) |

### Probe Execution

No probes declared in PLAN/SUMMARY and no conventional `scripts/*/tests/probe-*.sh` found in the repository. Step 7c: SKIPPED (no probes found for this phase).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| NEXC-01 | 08-01-PLAN.md | `registerchild <main_address>` registers the running node as a child wallet with `dev_wallet`/`peers_cut` derived per spec and mock `game_id`/`publisher_id` | SATISFIED (code) / human confirmation pending | `cmd_registerchild` implements exact derivation (truth #5); live REPL round-trip is truth #7, routed to human verification |
| NEXC-02 | 08-01-PLAN.md | `listchildren <main_address>` lists all children with address and balance | SATISFIED (code) / human confirmation pending | `cmd_listchildren` implements this (truth #4); live REPL output is truth #8, routed to human verification |
| NEXC-03 | 08-01-PLAN.md | `childbalance <child_address> [token_id]` queries single-token or all-tokens balance | SATISFIED (code) / human confirmation pending | `cmd_childbalance` implements this (truths #1-3); live REPL output is truths #9-10, routed to human verification |

No orphaned requirements — REQUIREMENTS.md maps only NEXC-01/02/03 to Phase 8, and all three are claimed in `08-01-PLAN.md`'s `requirements:` frontmatter.

### Anti-Patterns Found

None. Scanned `SuperGenius/example/node_test/NodeExample.cpp` for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER` (case-insensitive) and "placeholder/coming soon/not yet implemented" phrasing — no matches. The literal strings `"mock_game_id"`/`"mock_publisher_id"` are present (lines 380-381) but these are an intentional, spec-mandated placeholder value per REQUIREMENTS.md's Out of Scope table ("Real (non-mock) game_id/publisher_id values... Nothing downstream consumes these fields yet; mock values are sufficient until a consumer exists") — not an unresolved debt marker, and the plan explicitly directs using these literal strings.

### Human Verification Required

Automated/static checks (code presence, wiring, data-flow, and a live build) all pass. Four items require a live `node_example --terminal` REPL session with a real running `GeniusNode` (CRDT read/write) to confirm ROADMAP.md Phase 8's four success criteria end-to-end — these were deliberately deferred by the plan's `<human-check>` blocks per `workflow.human_verify_mode = "end-of-phase"` rather than requiring a mid-execution halt.

### 1. registerchild + listchildren round-trip (Success Criterion 1)

**Test:** With `node_example` built and running in `--terminal` mode, pick a 128-hex-character placeholder address and run `registerchild <that_address>`, then immediately run `listchildren <that_address>`.
**Expected:** `registerchild` logs a success message containing a transaction hash (not an error). `listchildren` run right after shows this node's own account address registered under that main address, together with a balance.
**Why human:** Full CRDT registration + local discovery round-trip requires a live running `GeniusNode` instance — cannot be confirmed by grep or a clean compile alone.

### 2. listchildren shows address + balance (Success Criterion 2)

**Test:** With `node_example` running in `--terminal` mode, first run `registerchild <main_address>`, then run `listchildren <main_address>`.
**Expected:** `listchildren` output includes this node's own account address together with a raw balance number on the same line — not the address alone.
**Why human:** Requires a real local CRDT `reg/` write (via `registerchild`) followed by a real CRDT read-back (via `GetRegistrationsForMain`) — cannot be confirmed by grep or a clean compile alone.

### 3. childbalance with no token_id (Success Criterion 3)

**Test:** At the REPL, run `childbalance <any-address>` with no `token_id`.
**Expected:** Prints a single raw all-tokens balance number.
**Why human:** Requires a live `GeniusNode` process reading real CRDT-backed UTXO state — cannot be confirmed by grep or a clean compile alone.

### 4. childbalance with token_id, valid and invalid (Success Criterion 4)

**Test:** At the REPL, run `childbalance <any-address> <64-hex-digit-token-id>`; then run `childbalance <any-address> not-valid-hex`.
**Expected:** Valid-hex form prints a single raw per-token balance number. Invalid-hex form logs `"Invalid token_id: 'not-valid-hex' — must be 64 hex digits (optionally 0x-prefixed)."` and does not crash the REPL.
**Why human:** Requires a live `GeniusNode` process reading real CRDT-backed UTXO state — cannot be confirmed by grep or a clean compile alone.

### Gaps Summary

No gaps. All code-level must-haves (function definitions, `COMMANDS`/`cmd_help` wiring, exact metadata derivation, key links, and a clean live rebuild) are verified against the actual codebase — this is not a SUMMARY.md-only claim. The remaining four items are not gaps: they are runtime behaviors that inherently require a live, networked `GeniusNode` process and real CRDT state that cannot be produced or observed through static analysis, grep, or a compile check. The plan's authors correctly recognized this and deferred these checks as `<human-check>` blocks per the project's `workflow.human_verify_mode = "end-of-phase"` setting, to be consolidated into one end-of-phase UAT session rather than three separate mid-execution halts.

---

_Verified: 2026-07-28T00:00:31Z_
_Verifier: Claude (gsd-verifier)_
