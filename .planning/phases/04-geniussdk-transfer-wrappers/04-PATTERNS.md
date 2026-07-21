# Phase 4: GeniusSDK Transfer Wrappers - Pattern Map

**Mapped:** 2026-07-21
**Files analyzed:** 2 (both modified, no new files created)
**Analogs found:** 4 / 4 (all four new functions have exact analogs)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `GeniusSDK/src/GeniusSDK.h` (add 4 declarations) | config/header (C API declarations) | request-response | `GeniusSDK.h:442-455` (`GeniusSDKTransfer`/`GeniusSDKTransferGNUS`) and `GeniusSDK.h:547-588` (child-wallet block) | exact |
| `GeniusSDK/src/GeniusSDK.cpp` — `GeniusSDKFundChild` | controller (thin FFI wrapper) | request-response (fire-and-forget submit) | `GeniusSDK.cpp:597-627` (`GeniusSDKTransfer`) | exact |
| `GeniusSDK/src/GeniusSDK.cpp` — `GeniusSDKFundChildGNUS` | controller (thin FFI wrapper, parse+delegate) | request-response | `GeniusSDK.cpp:629-663` (`GeniusSDKTransferGNUS`) | exact |
| `GeniusSDK/src/GeniusSDK.cpp` — `GeniusSDKRecoverFromChild` | controller (thin FFI wrapper) | request-response (fire-and-forget submit) | `GeniusSDK.cpp:597-627` (`GeniusSDKTransfer`), address-type override from `GeniusSDK.cpp:1114-1143` (`GeniusSDKRegisterChild`, `const char*` null/empty check) | exact (hybrid of two analogs) |
| `GeniusSDK/src/GeniusSDK.cpp` — `GeniusSDKRecoverFromChildGNUS` | controller (thin FFI wrapper, parse+delegate) | request-response | `GeniusSDK.cpp:629-663` (`GeniusSDKTransferGNUS`) | exact |

No dedicated test files — per project convention (memory: `feedback_geniussdk_no_dedicated_tests.md`), thin GeniusSDK FFI wrappers are not given dedicated SDK-layer tests; SuperGenius/TransactionManager tests already cover `TransferFunds`/`RecoverFromChild` logic. CONTEXT.md §domain confirms this is explicitly out of scope for this phase.

## Pattern Assignments

### `GeniusSDKFundChild` (controller, request-response)

**Analog:** `GeniusSDKTransfer` — `GeniusSDK.cpp:597-627`

**Signature/address-convention divergence from analog:** per D-66, use `const char *child_address` (matching the newer child-wallet convention, `GeniusSDK.cpp:1114` `GeniusSDKRegisterChild`) instead of `GeniusAddress *dest`. Null/empty check style comes from `GeniusSDKRegisterChild` (`GeniusSDK.cpp:1125-1129`):
```cpp
if ( main_address == nullptr || main_address[0] == '\0' )
{
    ret = GENIUS_NODE_INVALID_ARGUMENT;
    break;
}
```

**Core lock-guard + do/while(0) + TransferFunds pattern** (from `GeniusSDKTransfer`, `GeniusSDK.cpp:597-627`):
```cpp
GeniusNodeReturnValue_t GeniusSDKTransfer( uint64_t amount, GeniusAddress *dest, GeniusTokenID token_id )
{
    const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

    GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
    do
    {
        if ( !GeniusNodeInstance )
        {
            break;
        }
        if ( dest == nullptr )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        std::string destination( dest->address );
        auto        result = GeniusNodeInstance->TransferFunds(
            amount,
            destination,
            sgns::TokenID::FromBytes( token_id.data, sizeof( token_id.data ) ) );
        if ( !result.has_value() )
        {
            ret = GENIUS_NODE_ERROR_TRANSFER;
            break;
        }
        ret = GENIUS_NODE_RET_OK;
    } while ( 0 );

    return ret;
}
```

**Adapted skeleton for `GeniusSDKFundChild`:**
```cpp
GeniusNodeReturnValue_t GeniusSDKFundChild( uint64_t amount, const char *child_address, GeniusTokenID token_id )
{
    const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

    GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
    do
    {
        if ( !GeniusNodeInstance )
        {
            break;
        }
        if ( child_address == nullptr || child_address[0] == '\0' )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        auto result = GeniusNodeInstance->TransferFunds(
            amount,
            std::string( child_address ),
            sgns::TokenID::FromBytes( token_id.data, sizeof( token_id.data ) ) );
        if ( !result.has_value() )
        {
            ret = GENIUS_NODE_ERROR_TRANSFER;
            break;
        }
        ret = GENIUS_NODE_RET_OK;
    } while ( 0 );

    return ret;
}
```
Note: `GeniusNode::TransferFunds` fire-and-forget overload returns `outcome::result<std::string>` (tx hash) — same `.has_value()` check as the `GeniusAddress*` overload; the wrapper discards the hash exactly like `GeniusSDKTransfer` does today.

**Header declaration placement:** Claude's Discretion per CONTEXT.md — place near `GeniusSDKTransfer`/`GeniusSDKTransferGNUS` (`GeniusSDK.h:442-455`) since it wraps the same `TransferFunds` call, OR near the child-wallet block (`GeniusSDK.h:534-588`) since it shares the `const char*` address convention. Recommend grouping with the child-wallet block (after `GeniusSDKGetChildBalanceAll`) so all child-wallet-intent calls stay adjacent, consistent with the `/* --- Child Wallet Interfaces (v2.2) --- */` section marker already in the file.

**Doc-comment pattern to mirror** (`GeniusSDK.h:434-444`, adapted with D-67 fire-and-forget caveat):
```c
/**
 * @brief     Funds a registered child wallet by transferring tokens to it (in **Minion Tokens**).
 *            Wraps the fire-and-forget overload of `GeniusNode::TransferFunds` — this is an
 *            ordinary transfer to the child's address, no new consensus mechanics involved.
 * @param[in] amount        The amount to transfer in Minion Tokens.
 * @param[in] child_address Null-terminated string representing the child wallet's public address.
 * @param[in] token_id      Token identifier.
 * @return @ref GENIUS_NODE_RET_OK on successful submission (not confirmation — see note below),
 *         @ref GENIUS_NODE_ERROR_NOT_INITIALIZED if the SDK is not initialized,
 *         @ref GENIUS_NODE_INVALID_ARGUMENT if `child_address` is null/empty,
 *         or @ref GENIUS_NODE_ERROR_TRANSFER on submission failure.
 * @note This call is fire-and-forget: it reports submission-time status only, not
 *       consensus-level confirmation.
 */
```

---

### `GeniusSDKFundChildGNUS` (controller, request-response, parse+delegate)

**Analog:** `GeniusSDKTransferGNUS` — `GeniusSDK.cpp:629-663`

**Parse-then-delegate pattern (verbatim structure to replicate):**
```cpp
GeniusNodeReturnValue_t GeniusSDKTransferGNUS( const GeniusTokenValue *amount, GeniusAddress *dest )
{
    const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

    GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
    do
    {
        if ( !GeniusNodeInstance )
        {
            break;
        }
        if ( amount == nullptr )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        if ( dest == nullptr )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        auto parseRes = GeniusNodeInstance->ParseTokens( std::string( amount->value ),
                                                         sgns::TokenID::FromBytes( { 0x00 } ) );
        if ( !parseRes.has_value() )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        GeniusTokenID gnus_id;
        memset( gnus_id.data, 0, sizeof( gnus_id.data ) );
        ret = static_cast<GeniusNodeReturnValue>( GeniusSDKTransfer( parseRes.value(), dest, gnus_id ) );
    } while ( 0 );

    return ret;
}
```

**Adapted skeleton for `GeniusSDKFundChildGNUS`** — swap `GeniusAddress *dest` for `const char *child_address`, null/empty check style from `GeniusSDKRegisterChild`, and delegate to `GeniusSDKFundChild` instead of `GeniusSDKTransfer`:
```cpp
GeniusNodeReturnValue_t GeniusSDKFundChildGNUS( const GeniusTokenValue *amount, const char *child_address )
{
    const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

    GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
    do
    {
        if ( !GeniusNodeInstance )
        {
            break;
        }
        if ( amount == nullptr )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        if ( child_address == nullptr || child_address[0] == '\0' )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        auto parseRes = GeniusNodeInstance->ParseTokens( std::string( amount->value ),
                                                         sgns::TokenID::FromBytes( { 0x00 } ) );
        if ( !parseRes.has_value() )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        GeniusTokenID gnus_id;
        memset( gnus_id.data, 0, sizeof( gnus_id.data ) );
        ret = static_cast<GeniusNodeReturnValue>( GeniusSDKFundChild( parseRes.value(), child_address, gnus_id ) );
    } while ( 0 );

    return ret;
}
```

---

### `GeniusSDKRecoverFromChild` (controller, request-response)

**Analog:** `GeniusSDKTransfer` (`GeniusSDK.cpp:597-627`) for the core lock/do-while/has_value structure, with the `const char*` null/empty check from `GeniusSDKRegisterChild` (`GeniusSDK.cpp:1125-1129`).

**Underlying call** (`SuperGenius/src/account/GeniusNode.hpp:584-586`):
```cpp
outcome::result<std::string> RecoverFromChild( const std::string &child_address,
                                               uint64_t           amount,
                                               TokenID            token_id );
```
Note the argument order is `(child_address, amount, token_id)` — differs from `TransferFunds(amount, destination, token_id)`. The wrapper's own parameter order is a planner/API-shape decision (CONTEXT.md gives no explicit order), but the call site into `GeniusNodeInstance->RecoverFromChild(...)` must match this exact signature.

**Adapted skeleton:**
```cpp
GeniusNodeReturnValue_t GeniusSDKRecoverFromChild( uint64_t amount, const char *child_address, GeniusTokenID token_id )
{
    const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

    GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
    do
    {
        if ( !GeniusNodeInstance )
        {
            break;
        }
        if ( child_address == nullptr || child_address[0] == '\0' )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        auto result = GeniusNodeInstance->RecoverFromChild(
            std::string( child_address ),
            amount,
            sgns::TokenID::FromBytes( token_id.data, sizeof( token_id.data ) ) );
        if ( !result.has_value() )
        {
            ret = GENIUS_NODE_ERROR_TRANSFER;
            break;
        }
        ret = GENIUS_NODE_RET_OK;
    } while ( 0 );

    return ret;
}
```

**Doc-comment must state the D-67 known limitation explicitly** — mirror this wording (adapt from D-67 in CONTEXT.md):
```c
/**
 * @brief     Recovers funds from a registered child wallet back to this node's address
 *            (in **Minion Tokens**). Wraps the fire-and-forget overload of
 *            `GeniusNode::RecoverFromChild`.
 * @param[in] amount        The amount to recover in Minion Tokens.
 * @param[in] child_address Null-terminated string representing the child wallet's public address.
 * @param[in] token_id      Token identifier.
 * @return @ref GENIUS_NODE_RET_OK on successful submission, @ref GENIUS_NODE_ERROR_NOT_INITIALIZED
 *         if the SDK is not initialized, @ref GENIUS_NODE_INVALID_ARGUMENT if `child_address` is
 *         null/empty, or @ref GENIUS_NODE_ERROR_TRANSFER on submission failure.
 * @note This call is fire-and-forget and reports submission-time status only. Consensus-level
 *       destination-mismatch rejection (see `CheckParentChildAuthority`) is only evaluated at
 *       finalization time and cannot be observed by this synchronous wrapper — a
 *       @ref GENIUS_NODE_RET_OK return means "submitted," not "confirmed by consensus."
 */
```

---

### `GeniusSDKRecoverFromChildGNUS` (controller, request-response, parse+delegate)

**Analog:** `GeniusSDKTransferGNUS` (`GeniusSDK.cpp:629-663`) — identical parse-then-delegate shape, delegating to `GeniusSDKRecoverFromChild` instead of `GeniusSDKTransfer`.

```cpp
GeniusNodeReturnValue_t GeniusSDKRecoverFromChildGNUS( const GeniusTokenValue *amount, const char *child_address )
{
    const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

    GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
    do
    {
        if ( !GeniusNodeInstance )
        {
            break;
        }
        if ( amount == nullptr )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        if ( child_address == nullptr || child_address[0] == '\0' )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        auto parseRes = GeniusNodeInstance->ParseTokens( std::string( amount->value ),
                                                         sgns::TokenID::FromBytes( { 0x00 } ) );
        if ( !parseRes.has_value() )
        {
            ret = GENIUS_NODE_INVALID_ARGUMENT;
            break;
        }
        GeniusTokenID gnus_id;
        memset( gnus_id.data, 0, sizeof( gnus_id.data ) );
        ret = static_cast<GeniusNodeReturnValue>(
            GeniusSDKRecoverFromChild( parseRes.value(), child_address, gnus_id ) );
    } while ( 0 );

    return ret;
}
```

## Shared Patterns

### Lock guard + do/while(0) early-break error handling
**Source:** every wrapper in `GeniusSDK.cpp` (e.g. `GeniusSDKTransfer:599-624`, `GeniusSDKRegisterChild:1116-1140`)
**Apply to:** all 4 new functions
```cpp
const std::lock_guard<std::recursive_mutex> lock( GeniusSDKMutex );

GeniusNodeReturnValue ret = GENIUS_NODE_ERROR_NOT_INITIALIZED;
do
{
    if ( !GeniusNodeInstance ) { break; }
    // ... validation checks set ret = GENIUS_NODE_INVALID_ARGUMENT; break;
    // ... call GeniusNodeInstance-> method, check .has_value(), set ret = GENIUS_NODE_ERROR_TRANSFER; break;
    ret = GENIUS_NODE_RET_OK;
} while ( 0 );

return ret;
```

### `const char*` address null/empty validation (child-wallet convention)
**Source:** `GeniusSDK.cpp:1125-1129` (`GeniusSDKRegisterChild`)
**Apply to:** `GeniusSDKFundChild`, `GeniusSDKRecoverFromChild` (and transitively their GNUS siblings)
```cpp
if ( main_address == nullptr || main_address[0] == '\0' )
{
    ret = GENIUS_NODE_INVALID_ARGUMENT;
    break;
}
```

### GNUS-string amount parse-then-delegate
**Source:** `GeniusSDK.cpp:650-659` (`GeniusSDKTransferGNUS`)
**Apply to:** `GeniusSDKFundChildGNUS`, `GeniusSDKRecoverFromChildGNUS`
```cpp
auto parseRes = GeniusNodeInstance->ParseTokens( std::string( amount->value ),
                                                 sgns::TokenID::FromBytes( { 0x00 } ) );
if ( !parseRes.has_value() )
{
    ret = GENIUS_NODE_INVALID_ARGUMENT;
    break;
}
GeniusTokenID gnus_id;
memset( gnus_id.data, 0, sizeof( gnus_id.data ) );
ret = static_cast<GeniusNodeReturnValue>( GeniusSDK<PrimaryFn>( parseRes.value(), <addr>, gnus_id ) );
```

### Error code reuse (D-69)
**Source:** `GENIUS_NODE_ERROR_TRANSFER` enum value, `GeniusSDK.h` (enum near line ~121-127)
**Apply to:** both `GeniusSDKFundChild*` and `GeniusSDKRecoverFromChild*` — no new enum value; submission failure of either `TransferFunds` or `RecoverFromChild` maps to `GENIUS_NODE_ERROR_TRANSFER`.

### Doc-comment `@return`/`@note` block style
**Source:** `GeniusSDK.h:434-455` (`GeniusSDKTransfer`/`GeniusSDKTransferGNUS`), `GeniusSDK.h:569-577` (`GeniusSDKGetChildBalance`, shows precedent for a caveat `@note`-style sentence embedded in `@return` prose)
**Apply to:** all 4 new declarations in `GeniusSDK.h`. The fire-and-forget submission-only caveat (D-67) must be added as an explicit `@note` (no existing wrapper has this exact caveat verbatim, but `GeniusSDKGetChildBalance`'s "0 is inherently ambiguous" caveat at `GeniusSDK.h:575-576` is the closest tonal precedent for documenting an observability limitation).

## No Analog Found

None — all 4 files/functions have exact or near-exact analogs already in `GeniusSDK.cpp`/`GeniusSDK.h`. The only genuinely new element is the `@note` fire-and-forget caveat wording (D-67), which has no verbatim precedent but a close tonal analog (`GeniusSDKGetChildBalance`'s ambiguity note).

## Metadata

**Analog search scope:** `GeniusSDK/src/GeniusSDK.h`, `GeniusSDK/src/GeniusSDK.cpp`, `SuperGenius/src/account/GeniusNode.hpp`
**Files scanned:** 3 (all pre-identified by CONTEXT.md canonical_refs; no additional Glob/Grep search needed beyond confirming line numbers and exact signatures)
**Pattern extraction date:** 2026-07-21
