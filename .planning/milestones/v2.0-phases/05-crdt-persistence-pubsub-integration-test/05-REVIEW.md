---
phase: 05-crdt-persistence-pubsub-integration-test
reviewed: 2026-07-16T22:30:00Z
depth: deep
files_reviewed: 7
files_reviewed_list:
  - SuperGenius/src/account/TransactionManager.cpp
  - SuperGenius/src/account/TransactionManager.hpp
  - SuperGenius/src/account/GeniusNode.cpp
  - SuperGenius/src/account/GeniusNode.hpp
  - SuperGenius/test/src/account/registration_transaction_test.cpp
  - SuperGenius/test/src/multiaccount/regtest/child_registration.cpp
  - SuperGenius/test/src/multiaccount/regtest/CMakeLists.txt
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-16T22:30:00Z
**Depth:** deep
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the full Phase 05 implementation across 12 commits (scopes 05-01, 05-02, 05-03) for CRDT persistence, pubsub discovery, and the capstone multi-node integration test. The production code — FilterRegistration gate (d), RegisterChild auto-derive overload, GetRegistrationsForMain CRDT scan, and RegElementCallback CID handler — is broadly sound: gate (d) correctly enforces non-zero and strictly-greater sequence monotonicity, the auto-derive overload cleanly reads stored sequence + 1 (or 1 for first registration), the discovery scan iterates monitored networks with proper deserialization/cast guards, and the CID handler uses `weak_ptr`-safe callbacks with proper destructor unregistration.

**Two BLOCKER-level compilation errors** were found in the integration test `child_registration.cpp` — `RegTestAccess` accesses `TransactionManager::FilterRegistration` (a protected method) without a `friend` declaration, and `child_node_->account_` accesses `GeniusNode::account_` (a protected member) without friend access. These tests **will not compile**. Five WARNINGs cover a Phase 4 unfixed flaky test (byte-offset signature tampering) replicated in the integration test, an unused function parameter, a stale `SerializeByteVector` contract mismatch with the new empty-check hardening, cross-network deduplication, and missing error logging in the callback path. Four INFO items note duplicated boilerplate and minor code-style polish.

---

## Critical Issues

### CR-01: `RegTestAccess` cannot access `TransactionManager::FilterRegistration` — protected member, no `friend` declaration

**File:** `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp:64-72`
**Also:** `SuperGenius/src/account/TransactionManager.hpp:636` (declaration), `TransactionManager.hpp:314-318` (friend list)

**Issue:** The integration test defines `sgns::RegTestAccess` (lines 64-73) which calls `tm.FilterRegistration(element)` on line 71. `FilterRegistration` is declared at `TransactionManager.hpp:636` inside the `protected:` section (which starts at line 313). The `TransactionManager`'s friend list at lines 314-318 includes `GeniusNode`, `Migration3_6_0To3_7_0`, `CertificateFallbackTestAccess`, `TransactionManagerPendingLifecycleTestAccess`, and `RegistrationE2ETestAccess`. **`RegTestAccess` is not a friend** — it has no access to protected members.

This is a **compilation error**. The build will fail with an access-violation error on line 71.

The Phase 4 E2E test (`registration_transaction_test.cpp`) avoids this problem because `RegistrationE2ETestAccess` is explicitly declared as a friend of `TransactionManager` (line 318). The integration test's `RegTestAccess` was not added to the friend list.

**Fix:** Add `friend class RegTestAccess;` to `TransactionManager.hpp`'s protected section (e.g., after line 318):

```cpp
// TransactionManager.hpp, protected section (~line 319):
friend class RegTestAccess;
```

---

### CR-02: `child_node_->account_` accesses `GeniusNode::account_` — protected member, test class not a friend

**File:** `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp:286`
**Also:** `SuperGenius/src/account/GeniusNode.hpp:750` (declaration), `GeniusNode.hpp:738-740` (protected section + friends)

**Issue:** At line 286, the integration test calls:
```cpp
tx.MakeSignature( *child_node_->account_ );
```

`GeniusNode::account_` is declared at `GeniusNode.hpp:750` inside the `protected:` section (which starts at line 738). The `GeniusNode` friend list includes only `TransactionSyncTest` (line 739) and `MultiAccountTestAccess` (line 740). `MultiAccountTestAccess` exposes `blockchain_` and `consensus_manager_` accessors but **does not expose `account_`**. The test class `ChildRegistrationIntegrationTest` is neither a friend nor a subclass of `GeniusNode`.

This is a **compilation error**. The build will fail with an access-violation error on line 286.

**Fix:** Either (a) add a static accessor to `MultiAccountTestAccess` that returns the `account_` shared pointer, or (b) add `friend class ChildRegistrationIntegrationTest;` to `GeniusNode.hpp` (though this couples the test to the production header):

```cpp
// Option A — in MultiAccountTestAccess (multi_account_sync.cpp ~line 46):
static std::shared_ptr<GeniusAccount> GetAccount( const std::shared_ptr<GeniusNode> &node )
{
    return node ? node->account_ : nullptr;
}

// Then in child_registration.cpp replace:
//   tx.MakeSignature( *child_node_->account_ );
// with:
//   tx.MakeSignature( *MultiAccountTestAccess::GetAccount( child_node_ ) );
```

---

## Warnings

### WR-01: `RegElementCallback` receives `cid` parameter by value — unused, wasted copy per invocation

**File:** `SuperGenius/src/account/TransactionManager.cpp:3245` (implementation), `TransactionManager.hpp:703` (declaration)

**Issue:** The `RegElementCallback` signature takes `std::string cid` by value, which forces a heap allocation + copy for every reg/ element that arrives (once per `RegisterNewElementCallback` invocation). The parameter is never read in the function body — it is silently discarded. This matches the `NewElementCallback` pattern (which stores the CID on the queue), but `RegElementCallback` has no use for it.

In a busy system with frequent child registrations, this is wasted allocation. Not a correctness bug, but a per-invocation performance drain.

**Fix:** Remove the unused parameter from both the declaration and definition, or mark it `/* unused */`:

```cpp
// Option A — remove (preferred if CRDTCallbackManager allows it):
void RegElementCallback( crdt::CRDTCallbackManager::NewDataPair new_data );

// Option B — keep signature but silence:
void RegElementCallback( crdt::CRDTCallbackManager::NewDataPair new_data, std::string /*cid*/ );
```

**Note:** The `CRDTCallbackManager::RegisterNewElementCallback` API requires a two-argument callback `(NewDataPair, const std::string&)`. If the API cannot be changed, use `[[maybe_unused]]` on the parameter name or prefix with `/*unused*/`.

---

### WR-02: `FilterRegistrationRejectsTamperedSignature` (E2E test) tampers arbitrary byte — flaky test, identical to Phase 4 WR-03 (unfixed)

**File:** `SuperGenius/test/src/account/registration_transaction_test.cpp:487-493`

**Issue:** The test serializes a `RegistrationTx`, tampers a raw byte at offset `-5` from the end, and feeds it to `FilterRegistration`:
```cpp
auto serialized = tx.SerializeByteVector();
if ( serialized.size() > 10 )
{
    serialized[serialized.size() - 5] ^= 0xFF;
}
```

This was flagged as WR-03 in Phase 4's review (04-REVIEW.md:108-138) and was **not fixed** in Phase 05. The `-5` offset is not guaranteed to land in the DAGStruct signature field — protobuf field encoding order and varint sizes can shift the signature's position. A change to any field (e.g., `main_address` length, metadata size) could move the signature out of range, silently making this test a no-op.

The unit test `ChildRegistrationTamperedSignatureRejected` (line 340) demonstrates the correct approach: deserialize → modify `dag_mutable->signature()` → re-serialize.

**Fix:** Adopt the same approach as the unit test — deserialize, tamper the signature field directly in the proto struct, then re-serialize:

```cpp
SGTransaction::RegistrationTx tx_struct;
ASSERT_TRUE( tx_struct.ParseFromArray( serialized.data(), serialized.size() ) );
auto *dag_mutable = tx_struct.mutable_dag_struct();
std::string sig = dag_mutable->signature();
ASSERT_FALSE( sig.empty() );
sig[sig.size() - 1] ^= 0xFF;
dag_mutable->set_signature( sig );
// Re-serialize and construct CRDT element
```

---

### WR-03: Integration test sub-case A also uses byte-offset tampering — flaky test (same pattern as WR-02)

**File:** `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp:288-293`

**Issue:** Identical pattern to WR-02 — the integration test's negative signature sub-case tampers `serialized[serialized.size() - 5]` without confirming the byte lands in the signature field. A change to any RegistrationTx field size shifts the signature offset, potentially making this negative test silently pass (the signature remains valid because it wasn't actually tampered).

The fix is the same as WR-02 — deserialize, modify `dag_mutable->signature()`, re-serialize.

**Fix:** Same approach as WR-02 — proto-level signature tampering rather than raw byte flipping.

---

### WR-04: `GetRegistrationsForMain` does not deduplicate across monitored networks — may return duplicate entries

**File:** `SuperGenius/src/account/TransactionManager.cpp:4986-5028`

**Issue:** The function iterates ALL monitored networks:
```cpp
for ( auto network_id : GetMonitoredNetworkIDs() )
{
    // ... QueryKeyValues, deserialize, filter, push_back ...
}
```

If the same child registration exists in multiple monitored networks (e.g., CRDT cross-sync), the entry is appended once per network without deduplication. The test `TEST-03: MainDiscoversChild` asserts `entries.size() == 1` (line 246), which assumes no duplicates — this could become flaky in a multi-network deployment.

In practice, `GetMonitoredNetworkIDs()` typically returns one network (the current one via `version::GetNetworkID()`), so this is unlikely to trigger today. However, the API contract should either document this behavior or deduplicate.

**Fix:** Either (a) deduplicate by `child_addr` using an intermediate `std::unordered_set<std::string>`:

```cpp
std::unordered_set<std::string> seen;
// ... inside the inner loop:
if ( seen.insert( reg_tx->GetSrcAddress() ).second )
{
    results.push_back( std::move( entry ) );
}
```

Or (b) document in the doxygen that callers should deduplicate themselves when multiple networks are monitored.

---

### WR-05: `SerializeByteVector` empty-check hardening does not catch protobuf serialization failures — `RegistrationTransaction::SerializeByteVector()` returns pre-allocated (zero-filled) vector, not empty

**File:** `SuperGenius/src/account/TransactionManager.cpp:1280-1284` (Phase 05 hardening)
**Also:** `SuperGenius/src/account/RegistrationTransaction.cpp:54-60` (Phase 4 code, WR-02 context)

**Issue:** The Phase 05 advisory fix at `a4f8efc2` added an explicit empty-check after `SerializeByteVector()`:
```cpp
auto serializedBytes = transaction->SerializeByteVector();
if ( serializedBytes.empty() )
{
    m_logger->error( "SendTransactionItem: SerializeByteVector returned empty..." );
    return outcome::failure( ... );
}
```

However, `RegistrationTransaction::SerializeByteVector()` (and all existing transaction subclasses) returns a **pre-allocated, zero-filled vector** on serialization failure — not an empty vector:
```cpp
// RegistrationTransaction.cpp:54-60
size_t size = tx_struct.ByteSizeLong();
std::vector<uint8_t> serialized_proto( size );  // pre-allocated to ByteSizeLong()
if ( !tx_struct.SerializeToArray( serialized_proto.data(), serialized_proto.size() ) )
{
    std::cerr << "Failed to serialize RegistrationTx\n";
}
return serialized_proto;  // returns zero-filled, non-empty vector
```

Since `ByteSizeLong()` returns a non-zero size for any valid proto message, the `empty()` check at line 1281 will **never catch** a `SerializeToArray` failure. The empty-check only catches the degenerate case where `ByteSizeLong()` returns 0 (impossible for a properly initialized RegistrationTx).

This means the Phase 05 hardening provides a **false sense of security** — protobuf serialization failures still result in silent data corruption (zero-filled CRDT writes).

**Fix:** Fix the root cause in `RegistrationTransaction::SerializeByteVector()` to return an empty vector on failure:

```cpp
if ( !tx_struct.SerializeToArray( serialized_proto.data(), serialized_proto.size() ) )
{
    std::cerr << "Failed to serialize RegistrationTx\n";
    return {};  // empty vector signals failure → caught by Phase 5 empty-check
}
```

This fix should be applied to all transaction subclasses (TransferTransaction, MintTransaction, etc.) for consistency, but at minimum `RegistrationTransaction` should be corrected since the Phase 5 hardening specifically targets the reg/ path.

---

## Info

### IN-01: Unused return value `crdt_reg_filter_initialized` — matches existing codebase anti-pattern

**File:** `SuperGenius/src/account/TransactionManager.cpp:223`

**Issue:** `bool crdt_reg_filter_initialized = instance->globaldb_m->RegisterElementFilter(...)` stores the return value but never reads it. This matches the existing pattern for `crdt_tx_filter_initialized` and `crdt_proof_filter_initialized` (both also unused). Phase 4's IN-01 flagged this pattern; it persists across all filter registrations.

**Fix:** Prefix with `(void)` to silence static analysis, consistent with the `RegisterNewElementCallback` calls on lines 242 and 249 which already use `(void)`:

```cpp
(void) instance->globaldb_m->RegisterElementFilter( ... );
```

---

### IN-02: Duplicated wait-for-READY polling loop — repeated in 7 test cases

**File:** `SuperGenius/test/src/account/registration_transaction_test.cpp` — lines 269-285, 641-652, 678-688, 726-737, 763-774, 788-799, 836-843

**Issue:** The same 15-line polling loop (start TM → poll `GetState()` until `READY` with 60s timeout) is copy-pasted in 7 separate test cases. The integration test (`child_registration.cpp`) also has a similar pattern but uses `assertWaitForCondition`. Any change to the wait strategy requires updating 7 locations.

**Fix:** Extract a helper into the `RegistrationTransactionE2ETest` fixture:

```cpp
void WaitForREADY( std::chrono::seconds timeout = std::chrono::seconds( 60 ) )
{
    tm_->Start();
    auto state = tm_->GetState();
    auto start = std::chrono::steady_clock::now();
    while ( state != TransactionManager::State::READY )
    {
        if ( std::chrono::steady_clock::now() - start > timeout )
            break;
        std::this_thread::sleep_for( std::chrono::milliseconds( 100 ) );
        state = tm_->GetState();
    }
    ASSERT_EQ( state, TransactionManager::State::READY )
        << "TransactionManager did not reach READY within " << timeout.count() << "s";
}
```

---

### IN-03: `RegElementCallback` silently discards deserialization/cast failures — no diagnostic logging

**File:** `SuperGenius/src/account/TransactionManager.cpp:3249-3257`

**Issue:** The callback silently returns when deserialization fails or the cast is invalid:
```cpp
if ( maybe_tx.has_error() || maybe_tx.value()->GetType() != "registration" )
{
    return;  // silent — no log
}
auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( maybe_tx.value() );
if ( !reg_tx )
{
    return;  // silent — no log
}
```

Since the element already passed `FilterRegistration` validation upstream (gates a-d), a deserialization or cast failure in the callback path indicates an unexpected condition (e.g., data corruption between filter and callback, or a memory issue). The silent failure makes debugging difficult.

**Fix:** Add `m_logger->debug(...)` or `m_logger->trace(...)` on the skipped paths to aid diagnostics:

```cpp
if ( maybe_tx.has_error() )
{
    m_logger->debug( "RegElementCallback: deserialization failed, skipping" );
    return;
}
if ( maybe_tx.value()->GetType() != "registration" )
{
    m_logger->debug( "RegElementCallback: non-registration type in reg/ namespace, skipping" );
    return;
}
```

---

### IN-04: `GetBlockChainBase()` without network context in `FilterRegistration` gate (d) — consistent with existing filter pattern but fragile

**File:** `SuperGenius/src/account/TransactionManager.cpp:2873`

**Issue:** Gate (d) constructs the CRDT read key as:
```cpp
std::string reg_key = GetBlockChainBase() + "reg/" + reg_tx->GetSrcAddress();
```

`GetBlockChainBase()` without arguments resolves to `GetBlockChainBase(version::GetNetworkID())`. The CRDT filter, however, is registered per-monitored-network with a per-network `blockchain_base`. In a multi-network deployment where `version::GetNetworkID()` differs from the monitored network that triggered the filter, the key would mismatch — gate (d) would read from the wrong CRDT location.

This matches the existing `FilterTransaction` pattern (`KeyExistsInDB(GetTransactionPath(*new_tx))` at line 2786 also uses the no-argument `GetBlockChainBase()`). It is not a regression from Phase 05, but it is a latent fragility in the filter design.

**Fix:** Extract the network ID from the element's key prefix and pass it through, or add a `network_id` parameter to `FilterRegistration`. This is a broader refactor that should be coordinated with the `FilterTransaction`/`FilterProof` methods.

---

## Security Notes

- **Main-wallet private key never exposed.** `RegisterChild` signs with the child's `account_m` (child's private key). The `main_address` parameter is a public key string — no main-wallet key material transits any phase of the registration flow. FilterRegistration's gate (b) verifies the child's signature via `CheckTransactionAuthorization` before accepting.
- **Child compromise is bounded to that child's assets.** Each child holds its own independent keypair. Compromising child B's private key lets an attacker submit registrations naming any main wallet, but the attacker cannot sign as the main wallet or derive the main wallet's key. Consensus authority gate (`CheckParentChildAuthority`, deferred to Phase 06) will further bound this by requiring on-chain parent-child authorization before the main wallet acts on discovered children.
- **FilterRegistration gates are complete and non-bypassable for the CRDT merge path.** All four gates (a-d) execute inside the CRDT element filter before any element is accepted into the reg/ namespace. The `element.filter()` path is the only entry point for reg/ CRDT data — there is no unfiltered write path. Negative injection in TEST-04 confirms tombstone generation for tampered signatures, malformed main_address, and non-monotonic sequences.
- **CRDT namespace hygiene is correct.** RegistrationTx writes go to `reg/{child_addr}` — never `tx/`. The filter regex `^/?/{bc-base}reg/[^/]+` matches only reg/. Tombstone generation is an empty vector (no cascade-delete to a paired proof/ namespace per D-13). Destructor cleanup unregisters both the reg/ filter and callback.
- **Pubsub callback is `weak_ptr`-safe.** The `RegElementCallback` lambda captures a `weak_ptr<TransactionManager>`; if the TransactionManager is destroyed before a scheduled callback fires, `weak_ptr.lock()` returns `nullptr` and the callback body is skipped. Destructor unregistration is called before `Stop()`, reducing the window for in-flight callbacks.

---

## Structural Findings

No structural findings (cross-module fallow analysis) were provided for this review.

---

_Reviewed: 2026-07-16T22:30:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_
