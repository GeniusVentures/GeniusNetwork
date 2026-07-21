# Phase 4: GeniusSDK Transfer Wrappers - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-21
**Phase:** 4-GeniusSDK Transfer Wrappers
**Areas discussed:** Fund child wrapper, Sync wait vs fire-and-forget, Recovery wrapper signature, Error code mapping

---

## Fund Child Wrapper

**Q1: How should Phase 4 satisfy SDKT-01 (fund child)?**

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse GeniusSDKTransfer as-is | Zero new code — document that external callers fund a registered child by calling the existing GeniusSDKTransfer with the child's address as destination. | |
| New GeniusSDKFundChild wrapper | Add a dedicated function name for API symmetry with the new GeniusSDKRecoverFromChild call. | ✓ |

**Q2: What should GeniusSDKFundChild's child_address parameter type be?**

| Option | Description | Selected |
|--------|-------------|----------|
| const char* child_address | Matches the newer child-specific wrapper convention (GeniusSDKRegisterChild, GeniusSDKGetChildBalance). | ✓ |
| GeniusAddress* dest | Matches GeniusSDKTransfer's existing struct-based destination parameter. | |

**User's choice:** New dedicated `GeniusSDKFundChild` wrapper, taking `const char* child_address`.
**Notes:** D-61 (Phase 3) established funding needs no new GeniusNode-level call — this decision is purely about C-API naming/discoverability, not new business logic.

---

## Sync Wait vs Fire-and-Forget

**Q1: Should GeniusSDKRecoverFromChild block until finalized?**

| Option | Description | Selected |
|--------|-------------|----------|
| Block until finalized | Wrapper calls the wait-for-finalized(timeout) overload, returns OK only once consensus CONFIRMED the recovery. | |
| Fire-and-forget, like other wrappers | Matches every existing SDK wrapper's convention; returns OK as soon as submitted. | ✓ |

**Q2: Is not surfacing D-21 gate rejection synchronously an acceptable documented limitation?**

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, document the limitation | CONTEXT.md notes gate-level rejection is not surfaced synchronously. | ✓ |
| Reconsider — add finalization wait after all | Go back to blocking wait-for-finalized(timeout). | |

**User's choice:** Fire-and-forget; documented limitation accepted.
**Notes:** CONS-02/D-21 destination-mismatch rejection only happens inside `ValidateTransactionForConsensus` at finalization time, so a fire-and-forget wrapper genuinely cannot distinguish "gate rejected" from "submitted, pending" at return time. User chose consistency with existing wrapper conventions over adding new blocking/timeout machinery.

---

## Recovery Wrapper Signature

**Q1: Should GeniusSDKRecoverFromChild (and GeniusSDKFundChild) get a GNUS-string-amount sibling?**

| Option | Description | Selected |
|--------|-------------|----------|
| Raw uint64 amount only | Matches GeniusSDKRegisterChild/GetChildBalance — no GNUS-string convenience overloads. | |
| Add GNUS-string sibling functions | GeniusSDKFundChildGNUS / GeniusSDKRecoverFromChildGNUS mirroring GeniusSDKTransfer/GeniusSDKTransferGNUS. | ✓ |

**User's choice:** Add GNUS-string sibling functions for both directions.
**Notes:** child_address type (const char*) was already settled in the Fund Child Wrapper area and applies identically here.

---

## Error Code Mapping

**Q1: Should recovery/fund-child failures reuse GENIUS_NODE_ERROR_TRANSFER or get a new dedicated code?**

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse GENIUS_NODE_ERROR_TRANSFER | Both wrappers are thin TransferFunds/RecoverFromChild wrappers — reuse matches minimal-surface-area preference. | ✓ |
| New GENIUS_NODE_ERROR_RECOVERY code | Dedicated error code mirroring GENIUS_NODE_ERROR_REGISTRATION's precedent. | |

**User's choice:** Reuse `GENIUS_NODE_ERROR_TRANSFER`.
**Notes:** Because the fire-and-forget design (see Sync Wait vs Fire-and-Forget above) can't distinguish failure reasons finely enough, a dedicated error code would imply a distinction the implementation can't actually surface.

---

## Claude's Discretion

- Exact placement of the 4 new functions in `GeniusSDK.h`/`.cpp` (grouped near child-wallet wrappers vs near transfer wrappers).
- Whether `GeniusSDKFundChildGNUS`/`RecoverFromChildGNUS` reuse `GeniusSDKTransferGNUS`'s exact `ParseTokens`-based pattern (yes, by convention — no new parsing logic).
- Doc-comment wording for the fire-and-forget/D-21 limitation.

## Deferred Ideas

- Blocking/wait-for-finalized variants of the new wrappers — declined for this phase, could resurface later if external callers need stronger guarantees.
- A new dedicated error code for recovery-specific failures — declined for this phase, revisit only if a future requirement needs finer-grained error categories.
