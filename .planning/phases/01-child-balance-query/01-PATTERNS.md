# Phase 1: Child Balance Query - Pattern Map

**Mapped:** 2026-07-17
**Files analyzed:** 3 (2 modified source files, 1 modified test file)
**Analogs found:** 3 / 3

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `SuperGenius/src/account/GeniusNode.hpp` (near line 428) — new `GetChildBalance` declarations | controller/API (public method declarations) | request-response (synchronous read) | `SuperGenius/src/account/GeniusNode.hpp:406-428` (GetBalance overload family) | exact |
| `SuperGenius/src/account/GeniusNode.cpp` (near line 2448) — new `GetChildBalance` implementations | controller/API (delegating implementation) | request-response (synchronous read, CRUD-read) | `SuperGenius/src/account/GeniusNode.cpp:2430-2448` (GetBalance implementations) | exact |
| `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` (near line 421, appended after `InvalidRegistrationRejected`) — new `TEST_F` case | test (integration, multi-node) | event-driven / poll-until-convergence | Same file's existing `TEST_F(ChildRegistrationIntegrationTest, MainDiscoversChild)` (lines 237-270); mint pattern from `SuperGenius/test/src/multiaccount/multi_account_sync.cpp:197-221` | exact |

## Pattern Assignments

### `SuperGenius/src/account/GeniusNode.hpp` (near line 428) — `GetChildBalance` declarations

**Analog:** `SuperGenius/src/account/GeniusNode.hpp:402-428` (GetBalance overload family, 4 overloads)

**Exact excerpt to mirror** (lines 402-428):
```cpp
/**
 * @brief Returns the active account balance across all tokens.
 * @return Total local UTXO balance for the active account.
 */
uint64_t GetBalance();

/**
 * @brief Returns the active account balance for a token.
 * @param[in] token_id Token identifier to filter by.
 * @return Local UTXO balance for @p token_id.
 */
uint64_t GetBalance( TokenID token_id );

/**
 * @brief Returns an address balance across all tokens.
 * @param[in] address Address whose UTXO balance should be queried.
 * @return Total local UTXO balance for @p address.
 */
uint64_t GetBalance( const std::string &address );

/**
 * @brief Returns an address balance for a token.
 * @param[in] token_id Token identifier to filter by.
 * @param[in] address Address whose UTXO balance should be queried.
 * @return Local UTXO balance for @p address and @p token_id.
 */
uint64_t GetBalance( TokenID token_id, const std::string &address );
```

**New declarations to add (per D-56/D-59 — child-first parameter order, no-token overload sums all UTXOs, both plain `uint64_t` returns per D-55):**
```cpp
/**
 * @brief Returns a child wallet's balance for a specific token, read from
 *        the locally-synced CRDT UTXO view. Thin alias over GetBalance
 *        targeting @p child_address — no registration check is performed.
 * @param[in] child_address Address of the child wallet to query.
 * @param[in] token_id Token identifier to filter by (the child's own DevConfig
 *            token, not necessarily this node's dev_config_.TokenID).
 * @return Local UTXO balance for @p child_address and @p token_id.
 * @note A return value of 0 is ambiguous — it may mean the address genuinely
 *       has no balance, or that CRDT sync has not yet propagated the child's
 *       UTXOs to this node. No sync-status distinction is provided.
 */
uint64_t GetChildBalance( const std::string &child_address, TokenID token_id );

/**
 * @brief Returns a child wallet's total balance across all tokens, read from
 *        the locally-synced CRDT UTXO view.
 * @param[in] child_address Address of the child wallet to query.
 * @return Total local UTXO balance (GNUS base units) for @p child_address,
 *         summed across all tokens.
 * @note Same 0-ambiguity caveat as the token-filtered overload applies.
 */
uint64_t GetChildBalance( const std::string &child_address );
```

Place both declarations directly after the existing `GetBalance( TokenID token_id, const std::string &address )` overload (after line 428), before the `GetInTransactions` block.

Doxygen style note: this codebase uses `@brief`/`@param[in]`/`@return`/`@note` tags consistently (see also `GetTokenID()` at lines 462-469, and `RegistrationMetadata`-related docs elsewhere). Match this exactly.

---

### `SuperGenius/src/account/GeniusNode.cpp` (near line 2448) — `GetChildBalance` implementations

**Analog:** `SuperGenius/src/account/GeniusNode.cpp:2430-2448` (GetBalance implementations, direct delegation)

**Exact excerpt to mirror** (lines 2430-2448):
```cpp
uint64_t GeniusNode::GetBalance()
{
    return account_->GetUTXOManager().GetBalance();
}

uint64_t GeniusNode::GetBalance( const TokenID token_id )
{
    return account_->GetUTXOManager().GetBalance( token_id );
}

uint64_t GeniusNode::GetBalance( const std::string &address )
{
    return account_->GetUTXOManager().GetBalance( address );
}

uint64_t GeniusNode::GetBalance( const TokenID token_id, const std::string &address )
{
    return account_->GetUTXOManager().GetBalance( token_id, address );
}
```

**New implementations (D-60 — GeniusNode-only, direct UTXOManager delegation, no TransactionManager layer; note UTXOManager::GetBalance(token_id, address) takes token first, address second — GetChildBalance's public signature is child-first per D-56, so the delegation call must swap argument order):**
```cpp
uint64_t GeniusNode::GetChildBalance( const std::string &child_address, const TokenID token_id )
{
    return account_->GetUTXOManager().GetBalance( token_id, child_address );
}

uint64_t GeniusNode::GetChildBalance( const std::string &child_address )
{
    return account_->GetUTXOManager().GetBalance( child_address );
}
```

Place both directly after the existing `GetBalance( TokenID token_id, const std::string &address )` implementation (after line 2448), before the `ProcessingDone` method.

**No error handling needed** — per D-55, GetChildBalance returns plain `uint64_t` with no failure path, exactly like GetBalance. Do not wrap in `outcome::result` or add try/catch.

---

### `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` (near line 421) — new `TEST_F` case

**Analog 1 (test structure/poll pattern):** Same file, `TEST_F(ChildRegistrationIntegrationTest, MainDiscoversChild)`, lines 237-270

**Analog 2 (mint pattern):** `SuperGenius/test/src/multiaccount/multi_account_sync.cpp`, lines 197-221

**Fixture reuse — no changes needed to fixture itself:**
- Shared 3-node fixture already exists: `genesis_node_`, `main_node_`, `child_node_` (class `ChildRegistrationIntegrationTest`, `SetUpTestSuite` at lines 111-138).
- `#include` block (lines 9-54) already has everything needed: `testutil/wait_condition.hpp` for `sgns::test::assertWaitForCondition`, `testutil/mint_source_hash.hpp` for `sgns::test::NextMintSourceHash()`.

**Poll-until-convergence pattern to copy** (from `MainDiscoversChild`, lines 249-262):
```cpp
sgns::test::assertWaitForCondition(
    [&]() -> bool
    {
        auto entries_result = main_node_->GetRegistrationsForMain( main_address );
        if ( !entries_result.has_value() ) return false;
        auto &entries = entries_result.value();
        if ( entries.size() != 1 ) return false;
        return entries[0].child_addr == child_address
            && entries[0].main_addr == main_address
            && entries[0].sequence == 2;
    },
    std::chrono::milliseconds( 60000 ),
    "Main node did not discover child registration" );
```

**MintTokens signature/call pattern to copy** (from `multi_account_sync.cpp:199-205`):
```cpp
auto mint_result = child_node_->MintTokens( /*amount=*/ 100,
                                            sgns::test::NextMintSourceHash(),
                                            "test",
                                            child_node_->GetTokenID(),
                                            "",
                                            std::chrono::milliseconds( GeniusNode::TIMEOUT_MINT ) );
ASSERT_TRUE( mint_result.has_value() ) << "Mint transaction failed or timed out on child_node_";
```
Note: `multi_account_sync.cpp` hardcodes `TokenID::FromBytes({0x00})`; per D-64/D-57 this test should instead use `child_node_->GetTokenID()` (the child's own configured DevConfig token) since GetChildBalance's `token_id` parameter refers to the child's token, not the main's. `GetTokenID()` is declared at `GeniusNode.hpp:462-469`.

**New test case skeleton (D-63/D-64/D-65 — distinct child address for isolation, child mints, main queries, poll-until-nonzero before final assert):**
```cpp
// ---------------------------------------------------------------------------
// TEST-05: MainQueriesChildBalance — child node B mints tokens using its own
//           DevConfig token; after CRDT sync converges, main node A reads the
//           child's balance via GetChildBalance without any direct child query.
// ---------------------------------------------------------------------------
TEST_F( ChildRegistrationIntegrationTest, MainQueriesChildBalance )
{
    std::string child_address  = child_node_->GetAddress();
    sgns::TokenID child_token  = child_node_->GetTokenID();
    constexpr uint64_t kMintAmount = 500;

    auto mint_result = child_node_->MintTokens( kMintAmount,
                                                sgns::test::NextMintSourceHash(),
                                                "test_05_balance",
                                                child_token,
                                                "",
                                                std::chrono::milliseconds( GeniusNode::TIMEOUT_MINT ) );
    ASSERT_TRUE( mint_result.has_value() ) << "Mint transaction failed or timed out on child_node_";

    // D-65: poll child's own view first to confirm mint landed, then poll main's
    // synced view until the CRDT propagation converges (avoids flakiness).
    sgns::test::assertWaitForCondition(
        [&]() { return child_node_->GetBalance( child_token ) > 0; },
        std::chrono::milliseconds( 60000 ),
        "child_node_ balance did not become non-zero after mint" );

    sgns::test::assertWaitForCondition(
        [&]() { return main_node_->GetChildBalance( child_address, child_token ) > 0; },
        std::chrono::milliseconds( 60000 ),
        "main_node_ did not observe child balance after CRDT sync" );

    EXPECT_EQ( main_node_->GetChildBalance( child_address, child_token ), kMintAmount );
}
```

Append this after the closing brace of `InvalidRegistrationRejected` (line 421) and before the closing `} // namespace sgns` (line 423).

**Isolation note (D-63):** this test uses `child_node_`'s own address as the "distinct child address" — since this is the only test in the file that mints tokens (the others only register / inject CRDT elements under `reg/` keys), there is no UTXO-namespace collision risk with the existing TEST-02/03/04 cases. No new address generation needed.

---

## Shared Patterns

### Direct UTXOManager delegation (no TransactionManager layer)
**Source:** `SuperGenius/src/account/GeniusNode.cpp:2430-2448`, `SuperGenius/src/account/UTXOManager.cpp:86-147`
**Apply to:** `GetChildBalance` implementations in `GeniusNode.cpp`
All balance reads bypass `TransactionManager` entirely and call `account_->GetUTXOManager().GetBalance(...)` synchronously. `UTXOManager::GetBalance` iterates `address_outpoints_[address]`, filters by `UTXOState::UTXO_READY` and (when token-filtered) `token_id.Equals(...)`, and sums `GetAmount()`. The D-17 foreign-address guard has already been removed, so no additional guard/check is needed for querying a non-owned (child) address — it already works today for any address.

### No-failure-path convention for balance reads
**Source:** `SuperGenius/src/account/GeniusNode.hpp:406-428`
**Apply to:** `GetChildBalance` declarations and implementations
Balance getters return plain `uint64_t`, never `outcome::result`. No exceptions, no error codes — 0 is the only "not found" signal and is documented as ambiguous via Doxygen `@note`.

### Doxygen style
**Source:** `SuperGenius/src/account/GeniusNode.hpp:402-469`
**Apply to:** New method declarations
Use `@brief`, `@param[in]`, `@return`, and `@note` tags; `[[nodiscard]]` is used on `GetTokenID()` (line 466) but not on the `GetBalance` family — follow the `GetBalance` precedent (no `[[nodiscard]]`) for consistency with the family being mirrored.

### Multi-node integration test scaffold (shared fixture + poll-until-condition)
**Source:** `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp:102-214` (fixture), `:237-270` (poll pattern), `SuperGenius/test/src/multiaccount/multi_account_sync.cpp:197-221` (mint pattern)
**Apply to:** New `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)`
Reuse `genesis_node_`/`main_node_`/`child_node_` statics booted once in `SetUpTestSuite`; use `sgns::test::assertWaitForCondition` with a lambda predicate and an explicit timeout + failure message string for all async convergence waits (registration discovery, CRDT sync, mint propagation).

## No Analog Found

None — all 3 files/edits have exact analogs in the existing codebase.

## Metadata

**Analog search scope:** `SuperGenius/src/account/` (GeniusNode.hpp/.cpp, UTXOManager.hpp/.cpp), `SuperGenius/test/src/multiaccount/` (child_registration.cpp, multi_account_sync.cpp)
**Files scanned:** 5 (GeniusNode.hpp, GeniusNode.cpp, UTXOManager.hpp, UTXOManager.cpp, child_registration.cpp) + 1 partial (multi_account_sync.cpp lines 185-229)
**Pattern extraction date:** 2026-07-17
