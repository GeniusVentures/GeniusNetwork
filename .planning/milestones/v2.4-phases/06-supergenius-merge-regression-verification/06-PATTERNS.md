# Phase 6: SuperGenius Merge & Regression Verification - Pattern Map

**Mapped:** 2026-07-23
**Files analyzed:** 9 shared/conflicting files + 15 rename-sweep targets + 2 regression test binaries = 26 files touched
**Analogs found:** N/A — this phase is a git-merge conflict-resolution + mechanical-rename phase, not new-file authorship. "Pattern" here means "the exact current code context the executor must edit," not "an analog file to imitate."

**Framing note:** There are no new files in this phase. Every row below is an existing file inside the `SuperGenius` submodule (path relative to repo root: `./SuperGenius`). All line numbers are current `dev_childwallet` HEAD (`5fd137d`), verified live via `Read`/`Grep` against the working tree — not RESEARCH.md's cited numbers, which may drift by 1-2 lines from OS newline/read differences (none found; RESEARCH.md's line numbers matched exactly).

## File Classification

| File | Role | Data Flow | Category |
|------|------|-----------|----------|
| `src/account/TransactionManager.cpp` | service (transaction dispatch/consensus) | request-response (tx validation pipeline) | conflict-resolution |
| `src/account/CMakeLists.txt` | config (build source list) | batch (build graph) | conflict-resolution |
| `src/blockchain/impl/proto/Consensus.proto` | model (wire schema) | transform | auto-merge, review-only |
| `src/blockchain/Blockchain.hpp` / `.cpp` | service | CRUD (genesis registry) | auto-merge, review-only |
| `src/account/TransactionManager.hpp` | service | request-response | auto-merge, review-only |
| `src/account/GeniusNode.hpp` / `.cpp` | service (node lifecycle/config) | event-driven (bridge catchup) | auto-merge, verification-target (`DevConfig_st` rename lands here) |
| `test/src/account/CMakeLists.txt` | config (test build target list) | batch | auto-merge, no action |
| 15 files listed in RESEARCH.md § "Full enumeration" (test fixtures + `example/node_test/NodeExample.cpp`) | test / example fixture | CRUD (config construction) | mechanical-rename sweep target |
| `test/src/account/registration_transaction_test.cpp` | test | request-response (37 `TEST_F` cases) | verification-target (regression gate, NOT a rename target — confirm via post-sweep grep) |
| `test/src/multiaccount/regtest/child_registration.cpp` | test | request-response (4 `TEST_F` cases) | verification-target (regression gate) AND mechanical-rename target (uses `DevConfig_st` at line 170) |

## Pattern Assignments

### `src/account/TransactionManager.cpp` (conflict-resolution)

**Current state at conflict site — include block, lines 17-32 (verified live read):**
```cpp
#include "TransferTransaction.hpp"
#include "MintTransaction.hpp"
#include "MintTransactionV2.hpp"
#include "MigrationTransaction.hpp"
#include "MigrationInputValidator.hpp"
#include "MigrationAllowList.hpp"
#include "EscrowTransaction.hpp"
#include "ProcessingTransaction.hpp"        // <-- develop deletes this line entirely
#include "RegistrationTransaction.hpp"      // <-- dev_childwallet addition, KEEP
#include "RevokeTransaction.hpp"            // <-- dev_childwallet addition, KEEP
#include "UTXOMerkle.hpp"
#include "account/TokenAmount.hpp"
#include "account/AccountMessenger.hpp"
#include "account/proto/SGTransaction.pb.h"
#include "crdt/proto/delta.pb.h"
```

**Resolution pattern:** delete only the `#include "ProcessingTransaction.hpp"` line; keep both `RegistrationTransaction.hpp` and `RevokeTransaction.hpp` includes exactly as-is. Result:
```cpp
#include "EscrowTransaction.hpp"
#include "RegistrationTransaction.hpp"
#include "RevokeTransaction.hpp"
#include "UTXOMerkle.hpp"
```

**Non-conflicting removals in the same file that git auto-resolves but must be spot-checked post-merge (line 1784, verified live):**
```cpp
// CURRENT (dev_childwallet HEAD) — this line is removed by develop's auto-merge:
GeniusTransaction::RegisterDeserializer( "process", &ProcessingTransaction::DeSerializeByteVector );
```
The adjacent `"registration"`/`"revoke"` `RegisterDeserializer` calls (current lines 1788-1789 per RESEARCH.md) and the `kRegistration`/`kRevoke` switch-case arms (current lines ~1846/1853) are untouched by develop — do not edit them, just confirm they remain present after merge.

**Adjacency risk to manually review (not a conflict, no excerpt needed here — see RESEARCH.md § "MVER-04"):** `EvaluateTransactionReplayProtection`, called immediately after `CheckParentChildAuthority` inside `ValidateTransactionForConsensus`. Develop extracts a `GetOutgoingPreviousHash()` helper and adds a new own-address previous-hash consistency check. Read this function's merged form end-to-end before trusting the auto-merge; do not just grep for `<<<<<<<`.

---

### `src/account/CMakeLists.txt` (conflict-resolution)

**Current state — `GENIUS_NODE_SOURCES` list, lines 57-69 (verified live read):**
```cmake
set(GENIUS_NODE_SOURCES
    GeniusTransaction.cpp
    TransferTransaction.cpp
    MintTransaction.cpp
    MintTransactionV2.cpp
    MigrationTransaction.cpp
    ProcessingTransaction.cpp      # <-- develop deletes this line
    RegistrationTransaction.cpp    # <-- dev_childwallet addition, KEEP
    RevokeTransaction.cpp          # <-- dev_childwallet addition, KEEP
    EscrowTransaction.cpp
    GeniusInputValidator.cpp
    MigrationInputValidator.cpp
    InputValidators.cpp
```

**Resolution pattern:** identical decision to `TransactionManager.cpp` above — delete the `ProcessingTransaction.cpp` line only, keep `RegistrationTransaction.cpp`/`RevokeTransaction.cpp`. **This must be resolved consistently with the include-block resolution above** — if one file keeps `ProcessingTransaction` and the other drops it, the build breaks (missing file reference or unused-file link error). Treat both edits as one atomic decision.

The rest of this file (an `evm_watcher_service` library dependency and an opt-in `find_contract_creation_blocks` custom target added by develop) merges cleanly with no action needed.

---

### `DevConfig_st` -> `GeniusNodeConfig` mechanical rename sweep (15 files)

The rename itself is auto-performed by the merge inside `src/account/GeniusNode.hpp`/`.cpp` (struct tag, extern declaration, `New()`/constructor signatures, `dev_config_` member type). The 15 files below reference the old name but are untouched by develop's diff, so they will fail to compile until swept. **Do not hand-edit these individually with different reasoning — this is a single global search-and-replace pass** (word-boundary match on the bare identifier `DevConfig_st`; do not touch the unrelated variable `DEV_CONFIG`).

**Representative excerpt 1 — local variable declaration, `test/src/account/network_config_precedence_test.cpp:20` (verified live read):**
```cpp
DevConfig_st MakeDevConfig( const boost::filesystem::path &base )
{
    return { "0xcafe", "0.65", "1.0", sgns::TokenID::FromBytes( { 0x00 } ), base.generic_string() + '/' };
}
```
Becomes:
```cpp
GeniusNodeConfig MakeDevConfig( const boost::filesystem::path &base )
```

**Representative excerpt 2 — inline stack variable, `test/src/multiaccount/regtest/child_registration.cpp:170` (verified live read; this file is ALSO the `MVER-03` `child_registration_test` regression-gate file — sweep it carefully, then rerun the test):**
```cpp
DevConfig_st devConfig = { dev_addr, "0.65", tokenValue, tokenId, outPathStr };

std::filesystem::remove_all( devConfig.BaseWritePath );
std::filesystem::create_directories( devConfig.BaseWritePath );
```
Becomes: `GeniusNodeConfig devConfig = { ... };` — field usage (`.BaseWritePath`) is unaffected since only the type name changes, not the field layout.

**Representative excerpt 3 — global variable, `example/node_test/NodeExample.cpp:481` (verified live read):**
```cpp
DevConfig_st DEV_CONFIG{ "0xcafe", "0.65", "1.0", sgns::TokenID::FromBytes( { 0x00 } ), "./" };
```
Becomes: `GeniusNodeConfig DEV_CONFIG{ ... };` — note this is a distinct global named `DEV_CONFIG` (the variable, unaffected by the rename) whose *type* happens to also be spelled similarly to the old struct name; do not confuse the type-rename with this variable name — the sweep replaces only the leading type token `DevConfig_st`, never the identifier `DEV_CONFIG`.

**Remaining sweep targets (apply the identical mechanical pattern shown above — no unique excerpt needed per RESEARCH.md, which enumerates all 15 by path):**
`test/src/account/node_type_derivation_test.cpp`, `test/src/blockchain/blockchain_genesis_test.cpp`, `test/src/blockchain/consensus_subject_test.cpp`, `test/src/bridge_e2e/bridge_e2e_test.cpp`, `test/src/multiaccount/multi_account_sync.cpp`, `test/src/processing_multi/processing_multi_test.cpp`, `test/src/processing_nodes/child_tokens_test.cpp`, `test/src/processing_nodes/full_node_test.cpp`, `test/src/processing_nodes/processing_nodes_test.cpp`, `test/src/transaction_sync/migration_sync_test.cpp`, `test/src/transaction_sync/transaction_crash_test.cpp`, `test/src/transaction_sync/transaction_sync_test.cpp`.

**Post-sweep verification command (should return zero results):**
```bash
grep -rln "DevConfig_st" --include="*.hpp" --include="*.cpp" --include="*.h" --include="*.cc" src/ test/ example/
```

---

## Shared Patterns

### Retirement of `ProcessingTransaction` (cross-cutting: 2 files)
**Applies to:** `src/account/TransactionManager.cpp` and `src/account/CMakeLists.txt`
**Rule:** Both conflicts are two views of the same upstream decision (retire the deprecated `"process"` tx type). Resolve both by fully adopting develop's removal — drop every `ProcessingTransaction` reference, keep both `RegistrationTransaction`/`RevokeTransaction` references untouched. Do not use `git checkout --ours` on one and `--theirs` on the other — this creates an inconsistent build (source list references a header no longer included).

### `DevConfig_st` -> `GeniusNodeConfig` global rename (cross-cutting: 15+2 files)
**Applies to:** all 15 enumerated rename-sweep targets, plus the 2 shared files where the rename lands automatically via merge (`GeniusNode.hpp`/`.cpp` — no manual action needed there, confirm via the same post-sweep grep returning zero hits including those 2 files).
**Rule:** word-boundary replace of the bare type token only; fields/usage sites (`.BaseWritePath`, constructor argument order, etc.) are unchanged — this is a pure type-name rename, no semantic reasoning required. Must run strictly AFTER all 9 shared-file merges are resolved and zero `<<<<<<<` markers remain repo-wide (running it mid-merge risks corrupting conflict markers or redundantly touching the 2 already-renamed shared files).

### Regression verification gate (cross-cutting: build + 2 test binaries)
**Applies to:** post-merge validation of every file above.
```
cmake --build build/Windows/Debug --target genius_node --config Debug
cmake --build build/Windows/Debug --target registration_transaction_test --config Debug
cmake --build build/Windows/Debug --target child_registration_test --config Debug
./build/Windows/Debug/test_bin/Debug/registration_transaction_test.exe
./build/Windows/Debug/test_bin/Debug/child_registration_test.exe
```
Known pre-existing benign teardown segfault (exit 139 after GTest prints PASSED) — not a regression signal by itself; only a non-zero-failure GTest summary counts as a regression.

## No Analog Found

Not applicable to this phase — there are no new files; every target file already exists and its "pattern" is its own current code context, extracted above.

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/blockchain/`, `SuperGenius/test/src/`, `SuperGenius/example/node_test/` — all read directly from the live `dev_childwallet` working tree (HEAD `5fd137d`), cross-checked against RESEARCH.md's cited line numbers (exact match, no drift found).
**Files scanned:** 5 files read directly for this pattern map (`TransactionManager.cpp` include block, `CMakeLists.txt` source list, `network_config_precedence_test.cpp`, `child_registration.cpp`, `NodeExample.cpp`); remaining 12 rename-sweep targets and 4 auto-merge review-only files rely on RESEARCH.md's already-verified grep/diff evidence (re-reading them would duplicate work already done to HIGH confidence).
**Pattern extraction date:** 2026-07-23
