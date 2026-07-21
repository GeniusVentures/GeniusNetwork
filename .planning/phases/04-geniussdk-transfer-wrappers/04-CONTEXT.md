# Phase 4: GeniusSDK Transfer Wrappers - Context

**Gathered:** 2026-07-21
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase exposes both parent-child transfer directions from Phase 3 through the public `GeniusSDK.h`/`.cpp` C API, so external games/apps can fund and recover from a registered child wallet without linking SuperGenius directly:

1. **SDKT-01 (fund child):** a new `GeniusSDKFundChild` wrapper over `GeniusNode::TransferFunds` (CONS-01 path). No new GeniusNode-level machinery — D-61 (Phase 3) already confirmed funding is an ordinary transfer.
2. **SDKT-02 (recover from child):** a new `GeniusSDKRecoverFromChild` wrapper over `GeniusNode::RecoverFromChild` (CONS-02 path, added in Phase 3).
3. **SDKT-03:** both calls return existing `GeniusNodeReturnValue_t` status codes, fire-and-forget (submission-time status only — see D-67 below).

Each of the two transfer directions also gets a GNUS-string-amount sibling (`GeniusSDKFundChildGNUS` / `GeniusSDKRecoverFromChildGNUS`), mirroring the existing `GeniusSDKTransfer`/`GeniusSDKTransferGNUS` pair — this is an API-shape decision within the phase's existing scope, not a new capability.

Out of scope: new tx types/proto messages, transfer amount limits/policy, GeniusWallet Flutter UI wiring (all out of scope for the whole v2.3 milestone), and dedicated `GeniusSDK/test` unit tests (thin FFI wrapper — SuperGenius/TransactionManager tests already cover the wrapped logic, per project convention).

</domain>

<decisions>
## Implementation Decisions

### Fund-Child Wrapper (SDKT-01)
- **D-66:** Add a new dedicated `GeniusSDKFundChild` wrapper function rather than just documenting that the existing `GeniusSDKTransfer` already satisfies SDKT-01. Even though D-61 (Phase 3) established that funding needs no new `GeniusNode`-level call — it's an ordinary `TransferFunds` — the user chose a dedicated, discoverable, symmetric name over reusing the generic transfer function for this specific caller intent.
- Both `GeniusSDKFundChild` and `GeniusSDKRecoverFromChild` take `child_address` as `const char*` — matching the newer child-specific wrapper convention (`GeniusSDKRegisterChild`, `GeniusSDKGetChildBalance`/`GetChildBalanceAll`) rather than the `GeniusAddress*` struct convention used by the older generic `GeniusSDKTransfer`.

### Recovery Wrapper & Synchronicity (SDKT-02)
- **D-67:** `GeniusSDKRecoverFromChild` (and `GeniusSDKFundChild`) use the **fire-and-forget** `GeniusNode::TransferFunds`/`RecoverFromChild` overload — same convention as every existing SDK wrapper (`GeniusSDKTransfer`, `GeniusSDKPayDev`, `GeniusSDKRegisterChild`). They do NOT call the wait-for-finalized(timeout) overload.
- **Known, accepted limitation:** because `CheckParentChildAuthority`'s D-21 destination-mismatch rejection only happens inside `ValidateTransactionForConsensus` at finalization — not at submission — the fire-and-forget wrapper cannot distinguish "gate rejected the recovery" from "submitted successfully, outcome pending." The wrapper's `GENIUS_NODE_RET_OK` return means "submitted," not "confirmed by consensus." This must be documented explicitly in the wrapper's doc comment (mirroring how `GeniusSDKTransfer` already only reports submission-time status). The user explicitly chose to accept this rather than add a blocking timeout parameter.

### Amount Overloads
- **D-68:** Add GNUS-string-amount sibling functions — `GeniusSDKFundChildGNUS` and `GeniusSDKRecoverFromChildGNUS` — taking a `GeniusTokenValue*` amount, mirroring the existing `GeniusSDKTransfer`/`GeniusSDKTransferGNUS` pair. The raw-`uint64_t`-amount versions (`GeniusSDKFundChild`, `GeniusSDKRecoverFromChild`) remain the primary functions; the GNUS variants parse the string and delegate, exactly as `GeniusSDKTransferGNUS` delegates to `GeniusSDKTransfer` today.

### Error Code Mapping (SDKT-03)
- **D-69:** Both `GeniusSDKFundChild`/`GeniusSDKFundChildGNUS` and `GeniusSDKRecoverFromChild`/`GeniusSDKRecoverFromChildGNUS` reuse the existing `GENIUS_NODE_ERROR_TRANSFER` code for submission failures — no new enum value (e.g. no `GENIUS_NODE_ERROR_RECOVERY`) is added. Rationale: both wrappers are thin `TransferFunds`/`RecoverFromChild` wrappers under the hood, and per D-67 the wrapper can only observe submission-time failures anyway (never a distinguishable "gate rejected" reason) — a dedicated code would imply a distinction the implementation can't actually surface.
- Standard existing status codes apply: `GENIUS_NODE_ERROR_NOT_INITIALIZED` (node not up), `GENIUS_NODE_INVALID_ARGUMENT` (null/empty address, null amount pointer), `GENIUS_NODE_ERROR_TRANSFER` (submission failure — insufficient funds, transaction manager not ready, etc.), `GENIUS_NODE_RET_OK` (submitted).

### Claude's Discretion
- Exact placement of the 4 new functions in `GeniusSDK.h`/`.cpp` (near `GeniusSDKRegisterChild`/`GetChildBalance`, or near `GeniusSDKTransfer`/`TransferGNUS`) — planner's call, following whichever grouping keeps related child-wallet calls adjacent per the file's existing organization.
- Whether `GeniusSDKFundChildGNUS`/`RecoverFromChildGNUS` parse the GNUS string using the same `ParseTokens`-based pattern `GeniusSDKTransferGNUS` uses (`GeniusSDK.cpp:650-659`) — planner follows that exact precedent, no new parsing logic needed.
- Doc-comment wording for the fire-and-forget limitation (D-67) — planner/researcher drafts it, consistent in tone with existing `@return` doc blocks in `GeniusSDK.h`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design & planning docs
- `docs/02-consensus-parent-child-authority.md` — Original CONS-01–06 rule specifications (primary spec for the underlying consensus behavior this phase exposes via SDK).
- `.planning/PROJECT.md` — v2.3 milestone scope, Active requirements (SDKT-01/02), Key Decisions table (D-61 through D-65 context from Phase 3).
- `.planning/REQUIREMENTS.md` — SDKT-01, SDKT-02, SDKT-03 (this phase's 3 requirements).
- `.planning/ROADMAP.md` §Phase 4 — goal + 3 success criteria this context must satisfy.
- `.planning/STATE.md` — Current milestone position, prior decisions log (D-60 through D-65).

### Prior phase context (locked decisions this phase builds on)
- `.planning/phases/03-parent-child-transfer-authority/03-CONTEXT.md` — D-60 (CRDT-derived recovery authority), D-61 (funding needs no new call), D-62 (RecoverFromChild two-layer method shape), D-63/64/65 (gate mechanics, not directly relevant to this SDK-only phase but background for understanding why RecoverFromChild's finalization-time rejection exists).

### Code anchor points (verified against current code, 2026-07-21)
- `GeniusSDK/src/GeniusSDK.h:547-588` — existing child-wallet wrapper declarations (`GeniusSDKRegisterChild`, `GeniusSDKGetRegistrationsForMain`, `GeniusSDKGetChildBalance`/`GetChildBalanceAll`) — the `const char*` address convention to follow.
- `GeniusSDK/src/GeniusSDK.h:419-464` — existing transfer wrapper declarations (`GeniusSDKTransfer`, `GeniusSDKTransferGNUS`, `GeniusSDKPayDev`) — the `GeniusAddress*`/`GeniusTokenValue*` overload-pair convention, and existing error codes.
- `GeniusSDK/src/GeniusSDK.h` (enum near line ~121-127) — `GeniusNodeReturnValue` enum: `GENIUS_NODE_RET_OK`, `GENIUS_NODE_ERROR_NOT_INITIALIZED`, `GENIUS_NODE_INVALID_ARGUMENT`, `GENIUS_NODE_ERROR_TRANSFER`, `GENIUS_NODE_ERROR_PAY_DEV`, `GENIUS_NODE_ERROR_REGISTRATION` — reuse `GENIUS_NODE_ERROR_TRANSFER`, no new value needed.
- `GeniusSDK/src/GeniusSDK.cpp:1114-1229` — existing child-wallet wrapper implementations (`GeniusSDKRegisterChild`, `GeniusSDKGetRegistrationsForMain`, `GeniusSDKGetChildBalance`/`GetChildBalanceAll`) — lock-guard + `do{}while(0)` early-break pattern to follow.
- `GeniusSDK/src/GeniusSDK.cpp:597-627` — `GeniusSDKTransfer` implementation — the exact pattern `GeniusSDKFundChild` should mirror (swap `GeniusAddress*` for `const char* child_address`).
- `GeniusSDK/src/GeniusSDK.cpp:629-663` — `GeniusSDKTransferGNUS` implementation — the exact `ParseTokens`-then-delegate pattern for `GeniusSDKFundChildGNUS`/`GeniusSDKRecoverFromChildGNUS`.
- `SuperGenius/src/account/GeniusNode.hpp:520-535` — `GeniusNode::TransferFunds` two overloads (fire-and-forget vs wait-for-finalized-timeout).
- `SuperGenius/src/account/GeniusNode.hpp:568-586` — `GeniusNode::RecoverFromChild` two overloads (same shape as `TransferFunds`).
- `SuperGenius/src/account/GeniusNode.cpp:2237-2332` — implementations of both `TransferFunds` and `RecoverFromChild` overloads; confirms the fire-and-forget path only checks local readiness/balance and submits — it does NOT know about consensus-level gate rejection, which only surfaces via `WaitForFinalized`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GeniusNode::TransferFunds(amount, destination, token_id)` (fire-and-forget overload) — `GeniusSDKFundChild` calls this directly with the child's address as destination; zero new GeniusNode-layer code (D-61 confirmed in Phase 3).
- `GeniusNode::RecoverFromChild(child_address, amount, token_id)` (fire-and-forget overload, added Phase 3) — `GeniusSDKRecoverFromChild` calls this directly.
- `ParseTokens` + `GeniusTokenValue`/`GeniusTokenID` conversion helpers already used by `GeniusSDKTransferGNUS` — reused as-is for the two new GNUS-string sibling functions.
- `GeniusSDKMutex` recursive lock guard + `do{}while(0)` early-break error pattern — used identically by every existing wrapper function in `GeniusSDK.cpp`.

### Established Patterns
- Two-layer method convention already fully in place for both transfer directions at the `GeniusNode`/`TransactionManager` level (Phase 3) — this phase only adds the C-API layer on top, no C++ business logic changes.
- Raw-amount primary function + GNUS-string sibling function that parses-then-delegates (`GeniusSDKTransfer`/`GeniusSDKTransferGNUS`) — the exact shape to replicate twice (fund + recover).
- Every wrapper function returns `GeniusNodeReturnValue_t` synchronously after a single fire-and-forget submission call — no wrapper in the current codebase waits for finalization.

### Integration Points
- `GeniusSDK.h` — add 4 new function declarations (`GeniusSDKFundChild`, `GeniusSDKFundChildGNUS`, `GeniusSDKRecoverFromChild`, `GeniusSDKRecoverFromChildGNUS`), placed near the existing child-wallet or transfer wrapper declarations (planner's discretion).
- `GeniusSDK.cpp` — add 4 new function implementations following the `GeniusSDKTransfer`/`GeniusSDKTransferGNUS` pattern exactly, swapping in `child_address` (`const char*`) and calling `GeniusNodeInstance->TransferFunds(...)` / `GeniusNodeInstance->RecoverFromChild(...)` respectively.
- No changes needed to `SuperGenius/src/account/GeniusNode.{hpp,cpp}` or `TransactionManager.{hpp,cpp}` — Phase 3 already delivered every underlying call this phase wraps.

</code_context>

<specifics>
## Specific Ideas

- User's directional calls, in order: (1) add a dedicated `GeniusSDKFundChild` rather than just documenting `GeniusSDKTransfer` covers SDKT-01; (2) use `const char*` for child addresses on both new wrappers, matching the newer child-wallet convention; (3) keep fire-and-forget semantics consistent with every other SDK wrapper, explicitly accepting that gate-level rejection (D-21) won't be synchronously visible to the caller; (4) add GNUS-string sibling overloads for both directions; (5) reuse `GENIUS_NODE_ERROR_TRANSFER` rather than introduce a new error code, since the fire-and-forget design can't distinguish failure reasons finely enough to justify one.
- Consistent theme across all four decisions: match existing conventions and keep surface area minimal, rather than introducing new mechanisms (blocking waits, new enum values) the codebase doesn't already have — same preference documented in Phase 3's context and in project memory (no dedicated GeniusSDK unit tests).

</specifics>

<deferred>
## Deferred Ideas

- Blocking/wait-for-finalized variants of the new wrappers (would let callers see actual gate-rejection, not just submission status) — explicitly declined for this phase; could resurface in a future phase if external callers need stronger guarantees.
- A new dedicated error code distinguishing recovery-specific failures from generic transfer failures — explicitly declined; revisit only if a future requirement needs finer-grained caller-facing error categories.

### Reviewed Todos (not folded)
None — no pending todos matched this phase (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 4-GeniusSDK Transfer Wrappers*
*Context gathered: 2026-07-21*
