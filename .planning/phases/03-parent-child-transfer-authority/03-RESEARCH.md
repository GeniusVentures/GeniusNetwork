# Phase 3: Parent-Child Transfer Authority - Research

**Researched:** 2026-07-20
**Domain:** C++ consensus-gate design in a UTXO+DAG hybrid blockchain (SuperGenius) — signature-verification extension, CRDT-backed certified-status lookup, transaction construction
**Confidence:** HIGH (all claims below are verified by direct reads of the current repository source, not training-data recall)

## Summary

This phase adds one consensus gate (`CheckParentChildAuthority`) and one new transaction-construction method (`RecoverFromChild`) to `TransactionManager`. The phase's own CONTEXT.md (D-60) already identified that the locked recovery mechanism — main signs a tx with `src = child_addr`, and consensus accepts it because a CRDT `reg/{child_addr}` record certifies the relationship — cannot work under today's signature-verification code without a change, and that this contradicts the original "GeniusInputValidator.cpp untouched" claim. This research confirms that contradiction against current line numbers and goes one level deeper: it identifies **two more places**, beyond signature verification, where naively reusing existing transfer-construction machinery will silently misbehave: (1) `FillDAGStruct()` hardcodes `source_addr = account_m->GetAddress()` (main's own address) and reserves **main's own** nonce via `account_m->ReserveNextNonce()` — using it as-is for a `src = child_addr` tx would set the wrong nonce and wrong previous-hash; and (2) `UTXOManager::CreateTxParameter`/`SelectUTXOs` only ever select UTXOs from the manager's own bound `address_` (main's address) — they cannot select the child's UTXOs at all. `RecoverFromChild` must not call `FillDAGStruct()` or `CreateTxParameter()` unmodified; it needs new, narrowly-scoped logic for both.

On the signature question: the existing `delegated_escrow_spend` exception in `GeniusInputValidator.cpp` solves a *different* mismatch (signer == src, but UTXO owner_address ≠ src) than D-60 needs (signer ≠ src, but UTXO owner_address == src). It is a useful precedent for *shape*, not a reusable branch. The concrete recommendation below threads a single new helper — `Blockchain::CheckCertifiedParent(child_addr) -> optional<main_addr>` (using the already-existing `Blockchain::CheckCertificate` certificate-store lookup, not `tx_processed_m`) — into the three places that independently re-derive "is this signature acceptable": `GeniusTransaction::CheckSignature`'s caller (`CheckTransactionAuthorization`), `GeniusInputValidator::ValidateWitness`'s per-input check, and the new gate itself. This keeps all three call sites narrow, keeps `GeniusInputValidator.cpp`'s change to a single added branch (not a restructure), and reuses infrastructure (`Blockchain`, already passed into `ValidateWitness`) instead of inventing new cross-module plumbing.

STATE.md's decision log cites `TransactionManager.cpp:4250-4303` as the gate insertion point; **this is stale**. That range currently contains the tail of `CheckTransactionTypeRules` and the start of `ValidateWitnessForConsensus` — unrelated code. CONTEXT.md's `3988-3997` is verified correct against the current file (`ValidateTransactionForConsensus`, between the `CheckTransactionAuthorization` and `CheckTransactionTimestamp` calls). The planner must use `3988-3997`, not STATE.md's number.

**Primary recommendation:** Extend exactly three functions with one new shared lookup — `Blockchain::CheckCertifiedParent(child_addr)` — and add two new methods (`TransactionManager::RecoverFromChild` / `GeniusNode::RecoverFromChild`, mirroring `TransferFunds`'s two-layer convention) that build the recovery DAGStruct and UTXO inputs from scratch rather than reusing `FillDAGStruct()`/`CreateTxParameter()` verbatim. Details and exact code locations follow.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CONS-01 | Main funds a registered child via ordinary `"transfer"`; gate approves, unregistered dest still succeeds | Confirmed CONS-01 needs zero new code — `TransferFunds` unmodified. `CheckParentChildAuthority`'s `reg/{src}`-lookup-not-found path (dst side isn't a child concern) is a pure Approve; see Architecture Patterns, Gate Logic table |
| CONS-02 | Main recovers funds from registered child back to its own registered main address; gate approves, destination-restricted | Full mechanism designed: new `RecoverFromChild`, new signature-acceptance branch, new gate logic; see Code Examples |
| CONS-06 | Gate inserted between `CheckTransactionAuthorization`/`CheckTransactionTimestamp`, orthogonal to `ValidateWitness` UTXO-ownership checks | Insertion point verified at `TransactionManager.cpp:3988-3997` (current, not STATE.md's stale 4250-4303). "Orthogonal, zero GeniusInputValidator.cpp changes" is **not fully achievable** — see Critical Gap section; narrowest possible single-branch change identified |
| REGR-01 | Child-signed transfers to arbitrary/main addresses unaffected | Gate design: normal child-self-signed txs are distinguished from delegated-main-signed txs by which key verifies the signature — see Gate Logic table, case 2 |
| REGR-02 | Child-signed `PayDev` transfers unaffected | Confirmed `PayDev` is a thin wrapper over `TransferFunds` (`GeniusNode.cpp:2333`) — no separate code path, same REGR-01 reasoning applies |
| REGR-03 | Child cannot spend main's UTXOs even claiming delegated authority; `ValidateWitness` owner check still rejects | Confirmed the owner-address check (`GeniusInputValidator.cpp:419-432`) is **untouched and still correct** under D-60 — see Critical Gap section, "why REGR-03 survives" |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `CheckParentChildAuthority` consensus gate | API/Backend (consensus layer, `TransactionManager`) | — | Pure server-side consensus rule; no client/UI involvement in this phase |
| Certified-registration lookup (`reg/{child_addr}` → main + certified) | Database/Storage (CRDT `GlobalDB`), surfaced via `Blockchain` | API/Backend (`TransactionManager`) | Data lives in CRDT; both `TransactionManager` and `GeniusInputValidator` (via `Blockchain`) need read access |
| Signature-acceptance extension (child-key OR certified-main-key) | API/Backend (`GeniusTransaction`/`GeniusInputValidator`) | — | Cryptographic verification is a backend/consensus concern; never exposed past this tier |
| `RecoverFromChild` transaction construction | API/Backend (`TransactionManager` + `GeniusNode`) | — | Mirrors `TransferFunds`/`RegisterChild` two-layer convention; SDK/UI exposure explicitly deferred to Phase 4 |
| Regression tests (REGR-01/02/03) | Database/Storage-backed test fixture (`CRDTFixture`) | API/Backend | Tests exercise the consensus pipeline end-to-end against a real (in-memory) CRDT store, not mocks |

## Standard Stack

No new third-party libraries. This phase extends existing C++ classes (`TransactionManager`, `GeniusInputValidator`, `GeniusTransaction`, `Blockchain`, `GeniusNode`, `UTXOManager`) already in the repository. No package installation, no `npm`/`pip`/`cargo` verification applies.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Blockchain::CheckCertificate(reg_tx_hash)` for certified-status | `tx_processed_m` `CONFIRMED` lookup via `GetTrackedTxByHash` (D-63's literal wording) | `tx_processed_m` is **private to `TransactionManager`** and structurally unreachable from `GeniusInputValidator::ValidateWitness` (a stateless singleton receiving only `subject`, `tx`, `params`, `blockchain`). `CheckCertificate` is already a public `Blockchain` method and `Blockchain` is already passed into `ValidateWitness` — it is the only one of the two mechanisms usable from all three sites that need it. See Assumptions Log A1. |
| A new dedicated `Blockchain::CheckCertifiedParent` helper | Duplicating the reg/ lookup + certificate check inline in each of `CheckTransactionAuthorization`, `ValidateWitness`, and `CheckParentChildAuthority` | Duplication risks the three sites drifting out of sync (e.g., one checks certified status, another doesn't) — a shared helper is the minimal-surface option and keeps `GeniusInputValidator.cpp`'s diff to one call, not new business logic |

## Package Legitimacy Audit

Not applicable — this phase adds no new external dependencies (npm/pip/cargo packages). All work is within the existing `SuperGenius` C++ codebase using classes already present in the repository.

## Architecture Patterns

### System Architecture Diagram

```
Main wallet (GeniusNode / GeniusAccount "main")
        │
        │ RecoverFromChild(child_addr, amount, token_id)      TransferFunds(amount, child_addr, token_id)
        ▼                                                              ▼
GeniusNode::RecoverFromChild  ──────────────►  GeniusNode::TransferFunds (existing, CONS-01, unmodified)
        │  (state/balance pre-check: account_->GetUTXOManager().GetBalance(token_id, child_addr))
        ▼
TransactionManager::RecoverFromChild   (NEW — mirrors TransferFunds/RegisterChild two-layer convention)
        │
        │ 1. Select UTXOs owned by child_addr (NEW selection path — CreateTxParameter can't do this)
        │ 2. Build DAGStruct with source_addr = child_addr, nonce = child's next nonce,
        │    previous_hash = child's last tx (NOT FillDAGStruct() verbatim — see Pitfall 2)
        │ 3. Sign whole-tx AND per-input signatures with account_m (main)'s own key — MakeSignature(*account_m)
        ▼
TransferTransaction (src=child_addr, dst=main_addr, signed by main's key)
        │
        │ EnqueueTransaction → SendTransactionItem → CRDT Put at "tx/{hash}"
        ▼
   ── consensus validation path (every peer, including main's own node on ingest) ──
        ▼
TransactionManager::ValidateTransactionForConsensus  (TransactionManager.cpp:3966-4033)
        │
        ├─ CheckTransactionWellFormed                         (unchanged)
        ├─ CheckTransactionAuthorization  (line 3988)          ── EXTENDED: accept child's own sig
        │     tx.CheckSignature() || tx.CheckDAGSignatureLegacy()   OR certified-main's sig via
        │     || CheckCertifiedParentSignature(tx)                  Blockchain::CheckCertifiedParent
        │
        ├─ >>> CheckParentChildAuthority (NEW GATE — insert here, lines 3988-3997) <<<
        │     - tx.GetType() != "transfer" → Approve (not relevant)
        │     - reg/{tx.GetSrcAddress()} not found/not certified → Approve (D-64: ordinary tx)
        │     - certified, and tx.CheckSignature() verifies against src's OWN key → Approve
        │       (REGR-01/02: normal child-self-signed spend, no destination restriction)
        │     - certified, and src's own key does NOT verify, but certified main's key DOES
        │       (delegated recovery, D-60) → require tx.GetDstAddress() == certified main_addr
        │       (D-21) → Approve/Reject accordingly
        │
        ├─ CheckTransactionTimestamp                          (unchanged, line 3997)
        ├─ EvaluateTransactionReplayProtection                 (unchanged — already per-src-address
        │                                                        via account_m->GetPeerNonce(tx.GetSrcAddress()))
        └─ CheckTransactionTypeRules → SelectInputValidator → GeniusInputValidator::ValidateWitness
              │
              ├─ per-input signature check (line 357-361)      ── EXTENDED: same OR-branch as above
              └─ owner_address == src_address check (419-432)  ── UNCHANGED, still correct (see below)
```

### Recommended Project Structure

No new files/folders. Changes land in existing files:
```
SuperGenius/src/
├── account/
│   ├── TransactionManager.hpp        # add CheckParentChildAuthority, RecoverFromChild declarations
│   ├── TransactionManager.cpp        # gate impl, RecoverFromChild impl, CheckTransactionAuthorization extension
│   ├── GeniusInputValidator.cpp      # one added OR-branch in the per-input signature check (~line 357-366)
│   └── GeniusNode.cpp / .hpp         # GeniusNode::RecoverFromChild thin wrapper
├── blockchain/
│   ├── Blockchain.hpp                # add CheckCertifiedParent(child_addr) -> optional<string>
│   └── Blockchain.cpp                # impl: reg/ direct read + CheckCertificate(reg_tx_hash)
SuperGenius/test/src/account/
└── registration_transaction_test.cpp # extend existing RegistrationTransactionE2ETest fixture (D-65)
```

### Pattern 1: Two-layer method convention (TransactionManager + GeniusNode)
**What:** Every public transfer-construction capability has a `TransactionManager::X()` that builds/signs/enqueues the transaction, and a thin `GeniusNode::X()` wrapper that checks `GetTransactionManagerState() == READY`, does a local balance pre-check, and delegates.
**When to use:** `RecoverFromChild` — verified exact precedent at `GeniusNode.cpp:2258-2283` (`TransferFunds`, two overloads: fire-and-return-tx-id at 2258, and wait-for-finalized-with-timeout at 2237 which calls the first + `WaitForFinalized`) and `GeniusNode.cpp:2285-2312` (`RegisterChild`, two overloads: explicit-sequence and auto-derive-sequence).
**Example (verified, current code):**
```cpp
// GeniusNode.cpp:2258 — the pattern to mirror
outcome::result<std::string> GeniusNode::TransferFunds( uint64_t amount, const std::string &destination, TokenID token_id )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY ) { ... return failure; }
    auto available_balance = account_->GetUTXOManager().GetBalance( token_id );   // NOTE: no-arg = own address
    if ( available_balance < amount ) { ... return Error::INSUFFICIENT_FUNDS; }
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto tx_id, manager->TransferFunds( amount, destination, token_id ) );
    return tx_id;
}
```
For `RecoverFromChild`, the balance pre-check MUST use the address-parameterized overload — `account_->GetUTXOManager().GetBalance( token_id, child_addr )` (already used by Phase 1's `GetChildBalance`, confirmed child-first/token-first argument-order swap in STATE.md's Decisions log) — not the no-arg overload, which would check main's own balance instead of the child's.

### Pattern 2: Certified-parent lookup as a `Blockchain` method, not a `TransactionManager` private helper
**What:** Add `Blockchain::CheckCertifiedParent(const std::string &child_addr) const -> std::optional<std::string>` (returns the certified main address, or `std::nullopt`).
**Why `Blockchain` and not `TransactionManager`:** `Blockchain` already holds `db_` (the `GlobalDB` — confirmed at `Blockchain.hpp:464`, `std::shared_ptr<crdt::GlobalDB> db_`) and already exposes `CheckCertificate(subject_hash)` (`Blockchain.hpp:252`) for exactly this kind of "is this hash certified" check (already used in `EvaluateTransactionReplayProtection`'s previous-hash validation, `TransactionManager.cpp:4128`). Critically, `Blockchain` is **already a parameter of `GeniusInputValidator::ValidateWitness`** (`GeniusInputValidator.hpp:49`) — `TransactionManager` is not. Housing the lookup on `Blockchain` is the only option that reaches all three call sites (`CheckTransactionAuthorization`, `ValidateWitness`, `CheckParentChildAuthority`) without new plumbing.
**Implementation shape (new code, not yet in repo — recommended, not verified against a written implementation):**
```cpp
// Blockchain.cpp — new method
std::optional<std::string> Blockchain::CheckCertifiedParent( const std::string &child_addr ) const
{
    // Mirrors the exact reg/ key format already used at
    // TransactionManager.cpp:618, :1269, :2873 — GetBlockChainBase() + "reg/" + address
    std::string reg_key = /* same base-path format as TransactionManager::GetBlockChainBase() */ + "reg/" + child_addr;
    auto existing_data = db_->Get( reg_key );
    if ( !existing_data.has_value() ) { return std::nullopt; }
    auto maybe_tx = TransactionManager::DeSerializeTransaction( existing_data.value() ); // or equivalent shared deserializer
    if ( maybe_tx.has_error() || maybe_tx.value()->GetType() != "registration" ) { return std::nullopt; }
    auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( maybe_tx.value() );
    if ( !reg_tx ) { return std::nullopt; }
    if ( !CheckCertificate( reg_tx->GetHash() ) ) { return std::nullopt; }   // D-26: must be certified
    return reg_tx->GetMainAddress();
}
```
**Note on `GetBlockChainBase`/`DeSerializeTransaction` visibility:** both are currently `TransactionManager` static/member functions (`GetBlockChainBase()` at `TransactionManager.cpp:1420-1432`; the base-path format string `TRANSACTION_BASE_FORMAT` is a private `TransactionManager` constant at `TransactionManager.hpp:327`). The planner must either (a) make the reg-key-format construction a free function/static shared between `Blockchain` and `TransactionManager`, or (b) have `TransactionManager` own `CheckCertifiedParent` and give `GeniusInputValidator`/`ValidateWitness` a reference to `TransactionManager` instead of relying solely on `Blockchain` — the design intent (single shared lookup, reachable from `ValidateWitness`) is locked; the exact home for the reg-key-format helper is Claude's discretion at planning/implementation time.

### Anti-Patterns to Avoid
- **Reusing `FillDAGStruct()` unmodified for `RecoverFromChild`:** it hardcodes `dag.set_source_addr(account_m->GetAddress())` (`TransactionManager.cpp:1038`) and reserves **main's own** nonce via `account_m->ReserveNextNonce()` (`:952`) and searches `tx_processed_m` filtered by `tracked.tx->GetSrcAddress() == account_m->GetAddress()` for the previous-hash chain (`:966`). All three are wrong for a `src = child_addr` transaction. `RecoverFromChild` needs its own DAGStruct-filling logic that sets `source_addr = child_addr`, and computes nonce from `account_m->GetPeerNonce(child_addr) + 1` (the same per-address peer-nonce mechanism `EvaluateTransactionReplayProtection` already reads at `TransactionManager.cpp:4155`), plus a previous-hash lookup filtered by `child_addr`, not `account_m->GetAddress()`.
- **Reusing `UTXOManager::CreateTxParameter`/`SelectUTXOs` unmodified:** `SelectUTXOs` (`UTXOManager.cpp:1023-1066`) only ever reads `address_outpoints_[address_]` — the manager's own bound address (main's). It cannot select the child's UTXOs. `RecoverFromChild` needs a variant that selects from `child_addr`'s outpoints — either a new `UTXOManager::SelectUTXOs(amount, token_id, address)` overload, or building `InputUTXOInfo`s directly from `GetUnconsumedUTXOs(child_addr)` (already address-parameterized, `UTXOManager.hpp:228`) and signing them with `account_m->Sign(...)` directly (mirroring the escrow-payout pattern at `TransactionManager.cpp:896-899`, which manually builds a single `InputUTXOInfo` and signs it with `account_m->Sign()` rather than going through `CreateTxParameter`).
- **Treating the `delegated_escrow_spend` exception as a drop-in template for D-60:** it solves "signer == src, owner_address ≠ src" (escrow case). D-60 is "signer ≠ src, owner_address == src" (recovery case) — the inverse mismatch. Copying its shape into the owner-check block (line 419-432) would be wrong; the owner-check block needs **no change at all** for D-60 (see Critical Gap below). The needed change is in the *signature* check (line 357-361), not the owner check.
- **Reusing `GetRegistrationsForMain`'s full-scan-across-monitored-networks pattern for a single-child lookup:** it's designed for "give me every child under this main" (a UI/SDK discovery need, Phase 4) and iterates `GetMonitoredNetworkIDs()` doing a `QueryKeyValues` prefix scan per network. The gate's need is "does `reg/{child_addr}` (on the current default network) resolve to a certified main" — a single-key `Get`, exactly the pattern already used at `TransactionManager.cpp:618-619` (`RegisterChild`'s own sequence lookup) and `:2873-2874` (`FilterRegistration`'s existing-registration check). Do not build a scanning variant for this.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Verifying a signature against a public key/address | A new signature-check helper | `GeniusAccount::VerifySignature(address, signature, data)` (`GeniusAccount.cpp:790-815`) — already unhexes the address as the literal secp256k1 pubkey | Every existing check (`GeniusTransaction::CheckSignature`, `ValidateWitness`'s per-input check) already calls this; the new certified-main branch should call it too, just with a different address argument (registered main_addr instead of src_addr) |
| "Is this registration certified" | New CRDT field, new storage, a new consensus vote | `Blockchain::CheckCertificate(reg_tx_hash)` (`Blockchain.hpp:252`) — already the mechanism used elsewhere for "is this hash certified" (see `EvaluateTransactionReplayProtection`, `TransactionManager.cpp:4128`) | D-63 explicitly rules out new storage; this reuses the existing certificate-store mechanism and — unlike `tx_processed_m` — is reachable from `GeniusInputValidator::ValidateWitness` too |
| Destination restriction logic | A separate address-equality utility | Plain `std::string` comparison, `tx.GetDstAddress() == certified_main_addr` (however dst address is exposed on `TransferTransaction` — confirm accessor name during planning; `TransferTransaction`'s `outputs_`/`OutputDestInfo.dest_address` holds it) | Simple equality check; no library needed |

**Key insight:** every piece of infrastructure this phase needs (address-parameterized UTXO queries, address-parameterized nonce tracking, a certificate-existence check, a reg/ direct-key CRDT read) already exists somewhere in the codebase for a different purpose. The design work is entirely about **wiring these existing primitives into the two new construction paths and the new gate**, not inventing new primitives.

## Critical Gap: `GeniusInputValidator.cpp` cannot stay fully untouched

CONS-06/REGR-03's original wording asserts the new gate is orthogonal to `ValidateWitness` with zero changes to `GeniusInputValidator.cpp`. This survives for the **owner-address check** but not for the **per-input signature check**. Both live in the same function; the planner must treat them separately.

**Why the owner-address check (`GeniusInputValidator.cpp:419-432`) is unaffected and REGR-03 stays enforced:**
The check is `payload_owner != tx->GetSrcAddress() && !delegated_escrow_spend → reject`. `payload_owner` comes from the UTXO's own recorded `owner_address` (whoever's balance the UTXO actually belongs to — e.g. `child_addr` for a child's own UTXO). Under D-60, `RecoverFromChild` builds a tx with `src = child_addr` and spends UTXOs owned by `child_addr` — so `payload_owner == tx->GetSrcAddress()` **naturally holds**, no exception needed. If a child instead tried to construct a tx claiming `src = main_addr` to spend main's UTXOs (the REGR-03 attack), `payload_owner` (main_addr) would not equal `tx->GetSrcAddress()` only if the child also lies about `src` — but `src` in that attack IS `main_addr` by construction, so the *owner* check would actually pass trivially in that framing. **REGR-03's real protection is the per-input signature check**, not the owner check: a child cannot produce a valid signature verifying against `main_addr` (they don't have main's private key), so `CheckSignature`/the per-input check fails regardless of what `src` the child claims — this is unchanged by anything in this phase, because the new certified-main-key branch only accepts a signature by the **registered main's own key**, and a child never holds that key. Confirm this reasoning holds with a new explicit regression test (per D-65) rather than relying on this research's derivation alone.

**Why the per-input signature check (`GeniusInputValidator.cpp:357-361`) MUST change:**
```cpp
// current code, verified
if ( !GeniusAccount::VerifySignature(
         tx->GetSrcAddress(),                                    // = child_addr under D-60
         std::string_view(reinterpret_cast<const char*>(input.signature_.data()), input.signature_.size()),
         input.SerializeForSigning() ) )
{ ... return false; }
```
`input.signature_` is produced by `account_m->Sign(...)` where `account_m` = **main** (see `UTXOManager::SignInputs`, `UTXOManager.cpp:1068-1076`, called from `CreateTxParameter`; or the manual `account_m->Sign()` pattern at `TransactionManager.cpp:899`). Verifying that signature against `child_addr`'s public key will fail. The minimal fix is a single added OR-branch:
```cpp
const bool sig_ok = GeniusAccount::VerifySignature( tx->GetSrcAddress(), sig_view, input.SerializeForSigning() );
bool delegated_sig_ok = false;
if ( !sig_ok && tx->GetType() == TRANSFER_TX_TYPE )
{
    if ( auto certified_main = blockchain->CheckCertifiedParent( tx->GetSrcAddress() ) )
    {
        delegated_sig_ok = GeniusAccount::VerifySignature( *certified_main, sig_view, input.SerializeForSigning() );
    }
}
if ( !sig_ok && !delegated_sig_ok ) { logger->debug(...); return false; }
```
This is the one place in `GeniusInputValidator.cpp` that genuinely needs a new branch. It is additive (an `||`-style fallback path gated by tx type and certified-registration lookup), touches no other logic in the file, and the file's existing structure (constants in `input_validator_constants`, `blockchain` already in scope) supports it cleanly. The Requirements/Success-Criteria language for CONS-06 ("orthogonal ... no modification to GeniusInputValidator.cpp") should be corrected during planning to: "orthogonal to UTXO-ownership checks specifically; the signature-acceptance layer gains one narrow CRDT-gated branch."

**The same OR-branch is also needed in `CheckTransactionAuthorization`** (`TransactionManager.cpp:4066-4076`, the whole-tx signature check):
```cpp
bool TransactionManager::CheckTransactionAuthorization( const GeniusTransaction &tx ) const
{
    if ( tx.CheckSignature() || tx.CheckDAGSignatureLegacy() ) { return true; }
    if ( tx.GetType() == "transfer" )
    {
        if ( auto certified_main = blockchain_->CheckCertifiedParent( tx.GetSrcAddress() ) )
        {
            // GeniusTransaction has no public re-verify-against-arbitrary-address method today;
            // needs either a new GeniusTransaction::CheckSignatureAgainst(address) or inlining the
            // same clear-signature/serialize/VerifySignature sequence CheckSignature already does
            // (GeniusTransaction.cpp:72-81) with *certified_main instead of dag_st.source_addr().
            if ( /* verify tx signature against *certified_main */ ) { return true; }
        }
    }
    return false;
}
```
`GeniusTransaction::CheckSignature()` (`GeniusTransaction.cpp:72-81`) has no parameter — it always checks against `dag_st.source_addr()`. The planner should add a small new method, e.g. `GeniusTransaction::CheckSignatureAgainst(const std::string &address) const`, refactoring `CheckSignature()` to call it with `dag_st.source_addr()` — this is a two-line, behavior-preserving refactor of `GeniusTransaction.cpp` that unlocks reuse for the delegated case without duplicating the clear-signature/serialize sequence.

## How the gate distinguishes "child spending its own funds" from "main recovering on the child's behalf" (both have `src = child_addr`)

This is not spelled out in CONTEXT.md and is essential for REGR-01/REGR-02 to keep working: a normal child-signed transfer to an arbitrary address or to `main` **also** has `tx.GetSrcAddress() == child_addr`, which is a certified registered child. If the gate applied D-21's destination restriction to every tx from a certified child regardless of signer, it would break REGR-01/02 (arbitrary/main/dev destinations from a genuinely child-signed transfer would start getting rejected).

The distinguishing signal is **which key produced the signature**, not the src address alone:

| Case | src | Signed by | `tx.CheckSignature()` (verifies against src's own key) | Gate behavior |
|------|-----|-----------|------|---------------|
| CONS-01 main funds child | main_addr | main | true (src=main, always true today) | Not this gate's concern — src isn't a certified child; Approve, consistency-only reg/ check on dst |
| REGR-01/02 child spends its own funds (arbitrary/main/dev dest) | child_addr (certified) | child's own key | **true** | Approve unconditionally — no destination restriction, matches today's behavior |
| CONS-02 main recovers from child | child_addr (certified) | main (certified parent's key) | **false** (child's key ≠ main's key) — but the new certified-main branch verifies true | dst MUST equal the certified `main_addr` (D-21) — Approve only if it matches, else Reject |
| REGR-03 child impersonates main to spend main's UTXOs | main_addr (claimed) | child's key | false (child doesn't have main's key) — and main_addr is not itself a "certified child" so this gate doesn't even fire; **`CheckTransactionAuthorization`/`ValidateWitness`'s per-input check reject first** | N/A — rejected upstream, before this gate runs |

`CheckParentChildAuthority`'s implementation therefore re-derives "was this the child's own key or the certified parent's key" itself (a cheap, single `tx.CheckSignature()` call — it's already known-good from the earlier `CheckTransactionAuthorization` gate, so this is not redundant verification work, just a branch selection):
```cpp
bool TransactionManager::CheckParentChildAuthority( const GeniusTransaction &tx ) const
{
    if ( tx.GetType() != "transfer" ) { return true; }             // Approve — not relevant
    auto certified_main = blockchain_->CheckCertifiedParent( tx.GetSrcAddress() );
    if ( !certified_main ) { return true; }                        // D-64: not found/not certified -> Approve
    if ( tx.CheckSignature() ) { return true; }                    // child's own key verified -> REGR-01/02, no restriction
    // else: must be the certified-main-delegated case (CheckTransactionAuthorization already required
    // one of the two to hold, so if child's own key didn't verify, main's certified key did)
    return GetDestinationAddress( tx ) == *certified_main;         // D-21 destination restriction
}
```
(`GetDestinationAddress(tx)` — confirm/derive the exact accessor for a `TransferTransaction`'s single-recipient dest address during planning; the underlying data is `TransferTransaction`'s `outputs_` vector of `OutputDestInfo{encrypted_amount, dest_address, token_id}` per `TransferTransaction.cpp:17-18` — for a recovery tx there should be exactly one non-change output.)

## Certified-Status Lookup (D-63 resolution)

**D-63 flagged the exact keying/queryability of `tx_processed_m` as needing confirmation.** Verified findings:

- `tx_processed_m` is keyed by `GetTransactionPath(tx_hash)` = `GetBlockChainBase() + "tx/" + hash` (`TransactionManager.hpp:165-177`, `.cpp:1387-1400`). This is the **hash-based** path used for ordinary transactions.
- Registration transactions are **not** stored at that path. They are stored at `GetBlockChainBase() + "reg/" + child_addr` (`TransactionManager.cpp:1269`, the `SendTransactionItem` special-case for `transaction->GetType() == "registration"`).
- `ChangeTransactionState`, which sets `tx_processed_m[key] = TrackedTx{..., CONFIRMED, ...}` on confirmation (`TransactionManager.cpp:4796-4807`), still computes `key = GetTransactionPath(*tx)` — i.e., the hash-based `"tx/{hash}"` path, **not** `"reg/{addr}"`. A registration transaction, if it flows through the same confirmation state machine as other tx types, would get a `tx_processed_m` entry keyed by its **hash**, not by the child's address.
- Therefore, a `tx_processed_m`-based lookup for D-63 is a **two-step** process: (1) direct CRDT `Get("reg/" + child_addr)` to fetch the registration tx and extract its hash (exactly as `FilterRegistration` already does at `TransactionManager.cpp:2873-2874`, and `RegisterChild`'s own sequence lookup at `:618-619`), then (2) `GetTrackedTxByHash(reg_tx->GetHash())` (existing private method, `TransactionManager.cpp:2670-2683`, confirmed to do exactly `tx_processed_m.find(GetTransactionPath(tx_hash))`) and check `.status == TransactionStatus::CONFIRMED`.
- **This research recommends `Blockchain::CheckCertificate(reg_tx->GetHash())` instead of the `tx_processed_m` two-step**, because `tx_processed_m` is private to `TransactionManager` and unreachable from `GeniusInputValidator::ValidateWitness`, whereas `Blockchain` (which already holds `db_` and already exposes `CheckCertificate`) is reachable from all three call sites that need certified-status. Functionally, `CheckCertificate` checks for an actual consensus certificate on the hash — a stronger, more "many peers agree" signal than one node's local `tx_processed_m` cache, and it's the same class of mechanism already used for previous-hash validation in `EvaluateTransactionReplayProtection`. If the planner determines during implementation that `CheckCertificate`'s semantics don't line up with "registration certified" the way `tx_processed_m` CONFIRMED does, both lookups are cheap and could be OR'd together — but start with `CheckCertificate` as primary per Assumptions Log A1.

## Gate Insertion Point (reconciling CONTEXT.md vs STATE.md)

**Verified against current code, 2026-07-20:** `TransactionManager::ValidateTransactionForConsensus` spans `TransactionManager.cpp:3966-4033`. `CheckTransactionAuthorization` is called at line **3988**; `CheckTransactionTimestamp` is called at line **3997**. CONTEXT.md's `3988-3997` is correct.

STATE.md's decision log entry — `"CheckParentChildAuthority gate slots between CheckTransactionAuthorization and CheckTransactionTimestamp in ValidateTransactionForConsensus (TransactionManager.cpp:4250-4303)"` — cites a line range that **currently contains unrelated code** (the tail of `CheckTransactionTypeRules`, lines 4232-4256, and the start of `ValidateWitnessForConsensus`, lines 4258-4363). This is stale — almost certainly recorded before intervening v2.0-v2.2 work shifted line numbers, exactly as CONTEXT.md's own annotation predicts ("verified current line numbers; logic identical to design doc's D-19, only line numbers shifted since v2.0-v2.2 added code"). **The planner must use `3988-3997`, not `4250-4303`.**

## Registration Discovery Helpers (context for the single-child lookup)

`GetRegistrationsForMain` (`TransactionManager.cpp:4983-5031`, declared `TransactionManager.hpp:764`) iterates `GetMonitoredNetworkIDs()`, does a `QueryKeyValues(base + "reg")` prefix scan per network, deserializes every value, filters by `RegistrationTransaction::GetMainAddress() == main_address`, and returns a `RegistrationDiscoveryEntry{child_addr, main_addr, sequence, metadata}` per match (`RegistrationDiscoveryEntry` struct at `TransactionManager.hpp:45-51`). It has **no certified-status field and no certification filter today** — confirmed, matches CONTEXT.md's claim exactly. This is a full-scan-for-main-address helper; it is the wrong shape for the gate's need (single child → single certified main lookup) and should not be reused or extended for this phase. The gate's lookup (`Blockchain::CheckCertifiedParent` or equivalent) does a direct single-key `Get("reg/" + child_addr)`, no scanning.

## Common Pitfalls

### Pitfall 1: Reusing `FillDAGStruct()` for `RecoverFromChild` silently corrupts main's own nonce sequence
**What goes wrong:** `FillDAGStruct()` calls `account_m->ReserveNextNonce()` unconditionally — this consumes a slot in **main's own** outgoing nonce counter, even though the constructed tx's `src` will be `child_addr`. Main's own nonce sequence now has a gap (a reserved-but-never-used nonce), and the recovery tx itself carries the wrong nonce value (main's, not child's), which will fail `EvaluateTransactionReplayProtection`'s `account_m->GetPeerNonce(tx.GetSrcAddress())` check (`TransactionManager.cpp:4155`) against child's actual confirmed nonce.
**Why it happens:** `FillDAGStruct()` was written under the assumption "the constructing account's address is always the tx's src address" — true for every existing tx type, false for D-60's recovery tx.
**How to avoid:** `RecoverFromChild` must build its own `DAGStruct` (or a new `FillDAGStruct` overload taking an explicit `source_address` parameter) that sets `source_addr = child_addr` and derives nonce from `account_m->GetPeerNonce(child_addr) + 1` (falling back to 0/1 per whatever convention `GetPeerNonce`'s "no entry" case implies — check `EvaluateTransactionReplayProtection`'s `nonce_result.has_error()` handling at `:4156-4164` for the convention when no confirmed nonce exists yet).
**Warning signs:** recovery tx rejected with "Nonce too low"/"Nonce too high" in `EvaluateTransactionReplayProtection`, or main's own subsequent legitimate transfers start failing nonce checks after a `RecoverFromChild` call.

### Pitfall 2: `UTXOManager::CreateTxParameter`/`SelectUTXOs` cannot select the child's UTXOs
**What goes wrong:** Calling `account_m->GetUTXOManager().CreateTxParameter(amount, main_addr, token_id)` from main's `RecoverFromChild` selects from `address_outpoints_[address_]` where `address_` is main's own bound address (`UTXOManager.cpp:1030`) — it will select main's own UTXOs (or fail with insufficient funds if main has none), never the child's.
**Why it happens:** `UTXOManager` is constructed once per account with a single bound `address_` (`UTXOManager.hpp:118-123`), and `SelectUTXOs` was written for the single-owner case.
**How to avoid:** Build `InputUTXOInfo`s directly from `account_m->GetUTXOManager().GetUnconsumedUTXOs(child_addr)` (already address-parameterized) and sign each with `account_m->Sign(input.SerializeForSigning())` (mirroring `UTXOManager::SignInputs`'s per-input signing loop, `UTXOManager.cpp:1068-1076`, or the manual pattern at `TransactionManager.cpp:896-899`), rather than routing through `CreateTxParameter`.
**Warning signs:** `RecoverFromChild` returns `INSUFFICIENT_FUNDS`/`invalid_argument` even when the child visibly has balance (confirmable via the existing `GetChildBalance`/`GetBalance(token_id, child_addr)` from Phase 1).

### Pitfall 3: Treating `delegated_escrow_spend` as the template for the D-60 signature fix
**What goes wrong:** A naive read of CONTEXT.md's "closest existing precedent" framing could lead an implementer to add the D-60 exception into the *owner-address* check (line 419-432) the same way `delegated_escrow_spend` is added there. That would be a no-op for D-60 (the owner check already passes naturally, see Critical Gap section) and would miss the actual failure point, which is the *signature* check three lines above it (357-361).
**Why it happens:** Both exceptions live conceptually "near" each other and both involve a `src`/owner mismatch pattern, but they're mismatches in opposite directions (signer vs. src, vs. owner vs. src).
**How to avoid:** Read the Critical Gap section's case-by-case trace before writing the fix; write the new regression test (REGR-03, child-cannot-spend-main) *before* implementing, and confirm it fails against `main()`'s current logic in exactly the way expected (signature check failure, not owner check failure) to validate the mental model.
**Warning signs:** implementing a fix that "passes" REGR-01/02/03 tests but CONS-02's actual recovery flow still fails at the whole-tx `CheckTransactionAuthorization` gate (line 3988) — a sign the signature-check fix was only applied to `ValidateWitness`, not also to `CheckTransactionAuthorization`/`GeniusTransaction::CheckSignature`.

## Code Examples

### Verified: current whole-tx signature verification (the thing D-60 must extend)
```cpp
// GeniusTransaction.cpp:72-81 — verified current code
bool GeniusTransaction::CheckSignature() const
{
    auto str_signature = dag_st.signature();
    SGTransaction::DAGStruct dag_copy = dag_st;
    dag_copy.clear_signature();
    auto serialized = SerializeByteVector(dag_copy);
    return GeniusAccount::VerifySignature( dag_st.source_addr(), str_signature, serialized );
}
```

### Verified: current per-input witness signature + owner checks (the thing that needs exactly one new branch)
```cpp
// GeniusInputValidator.cpp:357-432 — verified current code (abridged to the two checks that matter)
if ( !GeniusAccount::VerifySignature(
         tx->GetSrcAddress(),
         std::string_view( reinterpret_cast<const char *>( input.signature_.data() ), input.signature_.size() ),
         input.SerializeForSigning() ) )
{
    logger->debug( "ValidateWitness(Genius) signature verification failed ..." );
    return false;   // <-- D-60's recovery tx fails HERE today; needs the new OR-branch
}
// ... proof/outpoint validation ...
const bool delegated_escrow_spend =
    payload_owner != tx->GetSrcAddress() && tx->GetType() == TRANSFER_TX_TYPE &&
    input.output_idx_ == ESCROW_LOCK_OUTPUT_INDEX &&
    utxo_address::IsEscrowLockAddress( payload_owner ) && tx->GetUncleHash() == payload_owner;
if ( payload_owner != tx->GetSrcAddress() && !delegated_escrow_spend )
{
    // D-60's recovery tx: payload_owner == child_addr == tx->GetSrcAddress() -> this check PASSES unmodified
    return false;
}
```

### Verified: existing `TransferFunds`/`RegisterChild` two-layer convention to mirror
```cpp
// TransactionManager.cpp:566-589 — verified current code
outcome::result<std::string> TransactionManager::TransferFunds( uint64_t amount, std::string destination, TokenID token_id )
{
    if ( GetState() != State::READY ) { return outcome::failure( boost::system::error_code{} ); }
    BOOST_OUTCOME_TRY( auto params, account_m->GetUTXOManager().CreateTxParameter( amount, std::move( destination ), token_id ) );
    auto [inputs, outputs] = params;
    auto transfer_transaction = std::make_shared<TransferTransaction>( TransferTransaction::New( inputs, outputs, FillDAGStruct() ) );
    transfer_transaction->MakeSignature( *account_m );
    account_m->GetUTXOManager().ReserveUTXOs( inputs, transfer_transaction->GetHash() );
    EnqueueTransaction( std::make_pair( transfer_transaction, std::nullopt ) );
    return transfer_transaction->GetHash();
}
```
`RecoverFromChild(child_addr, amount, token_id)` follows this shape but replaces `account_m->GetUTXOManager().CreateTxParameter(...)` with the child-address UTXO-selection logic from Pitfall 2, and `FillDAGStruct()` with the child-address DAGStruct-filling logic from Pitfall 1. `MakeSignature(*account_m)` stays unchanged (main signs, per D-60) — this part of the existing pattern is directly reusable.

### Existing test fixture to extend (D-65)
```cpp
// test/src/account/registration_transaction_test.cpp:200-254 — verified current code
class RegistrationTransactionE2ETest : public test::CRDTFixture
{
public:
    RegistrationTransactionE2ETest() : CRDTFixture( "reg_tx_e2e_test" )
    {
        account_ = GeniusAccount::New( kTestTokenId, base_path / "account" );
        blockchain_ = Blockchain::New( db_, account_, pubs_, []( outcome::result<void> ) {} );
        tm_ = TransactionManager::New( db_, io_, account_, blockchain_, true, 0, kTimestampTolerance, kMutabilityWindow );
        // ... io_context worker thread drives TickOnce() to READY
    }
    std::shared_ptr<GeniusAccount>      account_;
    std::shared_ptr<Blockchain>         blockchain_;
    std::shared_ptr<TransactionManager> tm_;
};
```
This fixture currently instantiates exactly **one** `GeniusAccount`/`TransactionManager` pair (used as the self-registering "child" against an arbitrary `main_address` string — registration is child-signed-only, no real main keypair needed for that test). **CONS-01/CONS-02 tests need a second real `GeniusAccount`** (a genuine "main" keypair) sharing the same `db_`/`CRDTFixture`, so that: (1) the "child" account registers itself under the "main" account's real address, (2) the "main" account's own `TransactionManager` (or a second `TransactionManager` instance sharing `db_`) calls `RecoverFromChild`/`TransferFunds`, and (3) `ValidateTransactionForConsensus` on either instance can resolve `reg/{child_addr}` from the shared CRDT store. No existing test file in the repo currently does two-`GeniusAccount`-same-db — this is new test infrastructure the planner should account for (see Open Questions).

## State of the Art

Not applicable in the "outdated library version" sense — this is an internal consensus-rule addition to an in-house codebase, not a third-party dependency upgrade. The relevant "state of the art" is the codebase's own established patterns (two-layer method convention, gate-list pattern in `ValidateTransactionForConsensus`, address-parameterized UTXO/nonce accessors) documented above, all of which this phase should follow rather than deviate from.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Blockchain::CheckCertificate(reg_tx_hash)` is semantically equivalent (or superior) to a `tx_processed_m` CONFIRMED check for "is this registration certified" (D-63 resolution) | Certified-Status Lookup, Don't Hand-Roll | If `CheckCertificate`'s certificate-store semantics don't actually track 1:1 with "registration confirmed by consensus" (e.g., certificates could exist for reasons unrelated to registration confirmation, or registration confirmation might not always produce a certificate under the current consensus flow), the certified-status gate could approve uncertified registrations or reject certified ones. Verify by reading `Blockchain`'s certificate-issuance path (where `CheckCertificate` entries get created) during planning/implementation before committing to this as the sole mechanism — an OR with the `tx_processed_m` two-step lookup is a low-cost hedge if uncertain. |
| A2 | `GetPeerNonce`'s "no entry found" case (used for a fresh child's first-ever recovery, or a child with no prior confirmed nonce) implies nonce `0` is the correct first value to use when building `RecoverFromChild`'s DAGStruct | Pitfall 1 | If the actual convention differs (e.g., nonce must start at some non-zero value, or an explicit registration-nonce baseline applies), the first `RecoverFromChild` call for a freshly-registered child could fail replay protection. Confirm against `EvaluateTransactionReplayProtection`'s `nonce_result.has_error() → Approve` fallback behavior (`TransactionManager.cpp:4156-4164`) and any nonce-seeding logic run at registration time. |
| A3 | `TransferTransaction`'s destination address for a single-output recovery tx is accessible via its `outputs_`/`OutputDestInfo.dest_address` and there exists (or should exist) a `GetDstAddress()`-style accessor for the gate to call | Gate distinguishing logic | If no such accessor exists today, the gate implementation needs one added to `TransferTransaction`/`GeniusTransaction`; this is a small, low-risk addition but should be confirmed, not assumed, during planning. |

## Open Questions

1. **Does the test fixture need two full `TransactionManager` instances (one "main," one "child") sharining one CRDT db, or can CONS-01/CONS-02 tests get away with one `TransactionManager` (acting as main) plus a bare second `GeniusAccount` (used only for its keypair/address, no own `TransactionManager`)?**
   - What we know: `RegisterChild`'s existing E2E tests use a single account self-registering (no second real keypair needed, since registration is child-signed-only). `RecoverFromChild`/CONS-02 needs a genuine second keypair (the "child") whose UTXOs get spent and whose registration is real, and a genuine "main" `TransactionManager` whose `RecoverFromChild` gets called.
   - What's unclear: whether the gate/consensus pipeline needs BOTH sides running their own `TransactionManager::TickOnce()` loop (to independently ingest and validate each other's transactions via `FilterTransaction`/`ValidateTransactionForConsensus`), or whether a single `TransactionManager` instance (main's) validating transactions it itself constructs (for the "child" identity, using a bare second `GeniusAccount` purely for signing) is sufficient to exercise the gate logic.
   - Recommendation: start with the single-`TransactionManager`-plus-bare-second-`GeniusAccount` shape (simpler, avoids two-node timing/threading complexity) since the gate under test (`CheckParentChildAuthority`, `CheckTransactionAuthorization`, `ValidateWitness`) are all called directly on whatever `tx` object is passed to `ValidateTransactionForConsensus`, regardless of which `TransactionManager` instance calls it — a full second node is very likely unnecessary for these specific gate-level regression tests.

2. **Exact home for the reg-key-format construction helper (`GetBlockChainBase() + "reg/" + address`) shared between `Blockchain::CheckCertifiedParent` and `TransactionManager`'s existing reg/ lookups.**
   - What we know: `GetBlockChainBase()`/`TRANSACTION_BASE_FORMAT` are currently `TransactionManager`-private/static (`TransactionManager.hpp:327`, `.cpp:1420-1432`).
   - What's unclear: whether the planner should (a) expose a shared free function, (b) give `Blockchain` its own copy of the network-ID-based path format (duplication risk), or (c) restructure so `Blockchain` owns `CheckCertifiedParent` by calling into a `TransactionManager`-exposed static helper.
   - Recommendation: expose `GetBlockChainBase` (already `static`) as a free function or a small shared utility (e.g., in a header both `Blockchain.cpp` and `TransactionManager.cpp` can include) rather than duplicating the format string — low risk either way since the format itself (`"/bc-%hu/"`) is simple and stable, but duplication should be flagged in code review if chosen.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes (transaction-origin authentication, not human auth) | `GeniusAccount::VerifySignature` — never hand-roll signature verification; the new certified-main branch reuses this exact primitive with a different address argument |
| V3 Session Management | No | No session/token concept in this consensus-layer phase |
| V4 Access Control | Yes — this phase's entire purpose | `CheckParentChildAuthority` gate + D-21 destination restriction; access control decision must be made server-side (consensus layer), never trusted from a client-supplied flag |
| V5 Input Validation | Yes | Destination-address equality check (D-21) must be an exact string match against the certified `main_address` from the `reg/` record — no normalization/case-folding that could create a bypass; malformed/empty `child_addr` or `main_addr` inputs to `RecoverFromChild` must be rejected before construction (mirror the existing `main_address.size() != 128` check pattern at `TransactionManager.cpp:2860`) |
| V6 Cryptography | Yes — never hand-roll | All signature verification MUST go through `GeniusAccount::VerifySignature` (secp256k1, existing implementation); no new crypto primitive should be introduced for the certified-main branch |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Authority-confusion attack: child crafts a tx claiming `src = main_addr` to spend main's UTXOs, hoping the new certified-parent branch loosens verification enough to let it through | Elevation of Privilege | REGR-03 regression test; verified in Critical Gap section that the certified-main branch only accepts a signature made with the *registered main's own private key* — a child never holds this key, so this attack fails identically before and after this phase's changes |
| Uncertified/pending registration used to claim recovery authority prematurely | Elevation of Privilege | D-26 (certified-status gating) + D-64 (uncertified/unsynced `reg/` record treated as "not found" → ordinary tx, no delegated authority) — enforced via the `CheckCertifiedParent`/`CheckCertificate` lookup, not a client-supplied flag |
| Destination substitution: main-signed recovery tx redirected to an address other than the certified `main_address` (e.g., attacker-controlled main node broadcasting a tx that claims delegated authority but pays out elsewhere) | Tampering | D-21 hard destination-equality check in the gate; rejected transactions never reach the UTXO-consuming stage |
| Replay of an old recovery tx after nonce/UTXO state has moved on | Replay | Existing per-src-address nonce/replay protection (`EvaluateTransactionReplayProtection`) already covers this once `RecoverFromChild` correctly derives the child's nonce (see Pitfall 1) — no new replay-protection mechanism needed, just correct nonce derivation |

## Sources

### Primary (HIGH confidence — direct source reads, this session)
- `SuperGenius/src/account/TransactionManager.cpp` (multiple ranges: 540-950, 1240-1300, 1385-1432, 2550-2700, 2760-2910, 3960-4260, 4700-4970, 4980-5032) — gate pipeline, `FillDAGStruct`, `TransferFunds`/`RegisterChild`, `CheckTransactionAuthorization`, `GetRegistrationsForMain`, `tx_processed_m` keying
- `SuperGenius/src/account/TransactionManager.hpp` (40-135, 320-360) — `RegistrationDiscoveryEntry`, `TrackedTx`, `TransactionStatus`, method declarations
- `SuperGenius/src/account/GeniusInputValidator.cpp` (1-70, 320-450) — per-input signature check, owner-address check, `delegated_escrow_spend`
- `SuperGenius/src/account/GeniusInputValidator.hpp` (full) — `ValidateWitness` signature/dependencies
- `SuperGenius/src/account/GeniusTransaction.cpp` (45-100) — `CheckSignature`, `CheckDAGSignatureLegacy`, `MakeSignature`
- `SuperGenius/src/account/GeniusTransaction.hpp` (150-200) — `GetTransactionFullPath`, `GetSrcAddress`
- `SuperGenius/src/account/RegistrationTransaction.hpp` (full) — confirms no override of `GetTransactionFullPath`
- `SuperGenius/src/account/UTXOManager.hpp` (1-260, 437-450) — `UTXOManager` constructor/address-scoping, `SelectUTXOs`/`CreateTxParameter` declarations
- `SuperGenius/src/account/UTXOManager.cpp` (380-440, 1000-1077) — `CreateTxParameter`/`SelectUTXOs` address-scoped implementation, `SignInputs`
- `SuperGenius/src/account/GeniusNode.cpp` (2230-2330) — `TransferFunds`/`RegisterChild`/`GetRegistrationsForMain` two-layer convention
- `SuperGenius/src/account/GeniusAccount.cpp` (1010-1035) — `GetPeerNonce`, `GetLocalConfirmedNonce`
- `SuperGenius/src/account/GeniusAccount.hpp` (230-290) — `GetPeerNonce`, `SetPeerConfirmedNonce`, `RollBackPeerConfirmedNonce`, `ReserveNextNonce` declarations
- `SuperGenius/src/account/TransferTransaction.cpp` (1-70) — `TransferTransaction` constructor/serialization
- `SuperGenius/src/blockchain/Blockchain.hpp` (230-300, 464) — `CheckCertificate`, `GetCertificateBySubjectHash`, `db_` member
- `SuperGenius/src/account/InputValidators.hpp` (20-36) — `TRANSFER_TX_TYPE`, `ESCROW_LOCK_OUTPUT_INDEX` constants
- `SuperGenius/test/src/account/registration_transaction_test.cpp` (1-260) — existing test fixture/conventions for D-65

### Secondary (MEDIUM confidence)
- `.planning/phases/03-parent-child-transfer-authority/03-CONTEXT.md` — locked decisions (D-60 through D-65), independently re-verified against source in this session rather than taken on faith
- `.planning/STATE.md` — decision log; the `4250-4303` line-number claim was checked and found stale against current source

### Tertiary (LOW confidence)
- None — every substantive claim above was checked against the actual current repository source in this session.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — no new dependencies
- Architecture (gate insertion point, two-layer convention, UTXO/nonce address-scoping): HIGH — all verified against current source with exact line numbers
- Signature-verification extension design (Blockchain::CheckCertifiedParent, three-call-site OR-branch): HIGH confidence on *what's broken today* (verified), MEDIUM confidence on *the exact recommended fix shape* (not yet written/compiled code — flagged as recommendation, not verified-working code; see Assumptions Log A1, A3)
- D-63 certified-status lookup resolution: MEDIUM — `tx_processed_m` keying is HIGH-confidence verified; the recommendation to use `CheckCertificate` instead is a reasoned architectural recommendation, not something already implemented elsewhere for this exact purpose
- Pitfalls (FillDAGStruct/CreateTxParameter reuse hazards): HIGH — verified directly by reading the implementations
- Test fixture guidance: MEDIUM — existing fixture verified; two-account extension is a recommendation, not verified against any existing two-account test in the repo

**Research date:** 2026-07-20
**Valid until:** Until this phase is planned/implemented — this is a one-time internal design investigation, not a library-version-dependent finding. If Phase 3 planning is delayed and other phases touch `TransactionManager.cpp`/`GeniusInputValidator.cpp` in the interim, line numbers cited here should be re-verified (as this research itself had to do against STATE.md's stale numbers).
