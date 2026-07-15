# Walking Skeleton — GNUS Child Wallet Design

**Phase:** 1
**Generated:** 2026-07-13

## Capability Proven End-to-End

A SuperGenius developer can read two design documents (child-wallet identity model + registration protocol) and understand every concept needed to implement child wallets — from keypair generation to proto wire format — with every claim anchored to a concrete SuperGenius source file, method, or field.

> This is a **design-documentation milestone**, not a code milestone. The "end-to-end" is from concept → design doc → SuperGenius anchor point. The walking skeleton consists of the two design documents + this architectural decision record, which together provide the backbone for all subsequent design phases (Phase 2: CRDT persistence + consensus authority; Phase 3: discovery, rewards, lifecycle).

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Child identity model** | Emergent identity — no creation-time flag | "Child-ness" is derived from a consensus-visible registration record (RegistrationTx), not from account metadata. `GeniusAccount.hpp` stays untouched for identity. This allows any wallet to become a child later without re-creation. (D-01) |
| **Child keypair** | Independent secp256k1 via EthereumKeyGenerator | NOT HD-derived from main seed. Compromise of child reveals nothing about main. Child keypair is created identically to any other wallet keypair. Bounded compromise: child key compromise = child assets only. (D-01, IDENT-01) |
| **Child nonce** | Reuses existing per-account nonce machinery | `GeniusAccount::GetProposedNonce`/`ReserveNextNonce`/`confirmed_nonces_` — separate account = separate nonce. No new nonce system. Child nonce is naturally independent from main because it's a separate GeniusAccount. (D-03, IDENT-02) |
| **UTXO ownership** | Standard `UTXOEntryRecord.owner_address` | Child-owned UTXOs distinguished by owner_address alone. No new UTXO field or ownership scheme. `GeniusUTXO.hpp` untouched. (D-02, IDENT-04) |
| **Registration carrier** | First-class `RegistrationTx` (GeniusTransaction subclass) | New tx type with proto message appended to `SGTransaction.proto`, new oneof arm in `Consensus.proto` (`registration = 8`). Flows through the same TransactionManager path (create → sign → FilterTransaction → validate → persist) as all existing tx types. Reuses DAGStruct, FillHash, MakeSignature, deserializer registry. (D-06, D-08) |
| **Registration signing** | Child-signed-only (REG-02 REVERSED) | The child signs the RegistrationTx; the main wallet does NOT counter-sign. Main pubkey delivered via transport-agnostic connect flow. Rationale: reduces UX friction, keeps main private key out of child process. Bounded impact: any child can claim any main, but registration grants zero authority over main funds. v2 hardening: optional main acceptance signature. (D-04, D-05, D-10) |
| **Registration schema** | `RegistrationTx` with `DAGStruct dag_struct = 1`, `main_address = 2`, `sequence = 3`, `RegistrationMetadata metadata = 4` | Reuses DAGStruct convention (field 1 = DAGStruct in ALL existing tx types). `main_address` = main pubkey from connect flow. `sequence` = dedicated monotonic per-child registration counter (separate from `DAGStruct.nonce`). `RegistrationMetadata` = optional `game_id`, `publisher_id`, `dev_wallet`, `peers_cut`. (D-08, D-09) |
| **Proto evolution** | Additive-only — no renumbering, no modification of existing messages | New messages appended at end of `SGTransaction.proto`. New oneof arm added as last entry (`registration = 8`). Existing TransferTx, MintTx, EscrowTx, DAGStruct, and UTXOEntryRecord are untouched. Backward-compatibility matrix covers 7 scenarios. (D-08, REG-03) |
| **Sequence vs nonce** | Dual-counter: `DAGStruct.nonce` (account tx ordering) + `sequence` (registration lineage) | Prevents conflation: normal transfers shouldn't consume registration lineage slots, and registration shouldn't bypass nonce ordering. Tie-break rule for equal sequences = Phase 2 hand-off. (D-09, REG-05) |
| **C++ subclass** | `RegistrationTransaction` in `SuperGenius/src/account/` | Follows MintTransaction analog (simplest subclass — no UTXOs, scalar + string fields). PascalCase naming per Coding Standards.md. Deserializer registered as "registration" in TransactionManager static initializer. Switch case `EmbeddedTransaction::kRegistration` added to `DeSerializeEmbeddedTransaction`. (D-06, PATTERNS.md §3-7) |
| **Connect flow** | Transport-agnostic — main pubkey delivered, main private key never leaves GNUS Wallet app | The child app receives only the main wallet's public key. No cryptographic operation performed by the main wallet during registration. Concrete platform UI (Android, iOS, Windows, macOS, Linux) deferred to v2 (PLAT-01, PLAT-02). (D-10, REG-04) |
| **Directory layout** | Design docs at `docs/`; C++ files at `SuperGenius/src/account/` | Design documents: `docs/child-wallet-identity-model.md`, `docs/registration-protocol.md`. New C++ files (future implementation): `SuperGenius/src/account/RegistrationTransaction.hpp`, `RegistrationTransaction.cpp`. Proto modifications: append to existing `SGTransaction.proto` and `Consensus.proto` — no new proto files. |

## Stack Touched in Phase 1

- [x] **Design document scaffold** — Two design documents produced, stored at `docs/`
- [x] **Proto schema** — `SGTransaction.proto` (append `RegistrationTx` + `RegistrationMetadata`), `Consensus.proto` (add `registration = 8` to `EmbeddedTransaction` oneof)
- [x] **C++ subclass design** — `RegistrationTransaction` extends `GeniusTransaction`, follows `MintTransaction` analog
- [x] **Deserializer dispatch** — `TransactionManager.cpp` deserializer registry + `DeSerializeEmbeddedTransaction` switch case
- [x] **Identity anchor points** — `GeniusAccount.hpp`, `GeniusNode.hpp`, `GeniusUTXO.hpp`, `EthereumKeyGenerator`, `UTXOEntryRecord` all referenced in design docs
- [x] **Security analysis** — Child-signed-only security impact documented (STRIDE threat model in both PLAN.md files), REG-02 reversal rationale, bounded-impact analysis

## Out of Scope (Deferred to Later Slices)

> Explicit list — prevents Phase 2 and Phase 3 from re-litigating Phase 1 design decisions.

- **CRDT namespace layout and validating element filter** — Phase 2 (SYNC-01, SYNC-02). Phase 1 defines the RegistrationTx that carries the event; Phase 2 designs how it materializes into CRDT state.
- **PubSub broadcast/subscription** — Phase 2 (SYNC-03, SYNC-04, SYNC-05). Registration broadcast on main's pubsub channel; main subscribing to child channels.
- **Consensus authority rules** (CONS-01..06) — Phase 2. All fund-movement rules: main→child funding, destination-restricted recovery, child→arbitrary/main/developer, child-cannot-spend-main rejection.
- **Registration sequence tie-break rule + consensus-ordering mechanism** — Phase 2. Phase 1 defines the `sequence` field exists and is monotonic; Phase 2 defines how equal-sequence registrations are resolved.
- **Discovery and monitoring** (DISC-01..03) — Phase 3. How a main wallet discovers registered children from CRDT state.
- **Per-child reward policy** (RWD-01..03) — Phase 3. Reward policy resolution, hold-time pinning, authenticated dev-wallet/split updates.
- **Lifecycle state machine and change flows** (LIFE-01..04) — Phase 3. Replace/remove/detach/revoke; "supersedes seq N" linkage; main-replacement policy fork; detached child as standalone wallet.
- **Platform "Connect GNUS Wallet" UI flows** — v2 (PLAT-01, PLAT-02). Phase 1 specifies transport-agnostic handshake only.
- **Main acceptance signature (optional hardening)** — v2. If discovery spam becomes a real problem, add main-signed `RegistrationAcceptance` to upgrade pending→confirmed.
- **HD-derived child keys** — Rejected entirely (couples compromise, violates bounded-compromise goal).
- **Cross-application shared child keys** — Rejected entirely (anti-feature — one child per app).

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- **Phase 2: CRDT Persistence, PubSub & Consensus Authority** — Takes the RegistrationTx defined in Phase 1 and designs: (a) how it materializes into a consensus-visible CRDT namespace with a validating element filter, (b) how it is broadcast over pubsub and synced between main and child, (c) all six consensus authority rules that enforce the parent-child authority model.
- **Phase 3: Discovery, Rewards & Lifecycle** — Takes the registration state from Phase 2 and designs: (a) how a main wallet discovers its registered children, (b) per-child reward policy and hold-time pinning, (c) the lifecycle state machine and all change flows (replace, detach, revoke).

## Design Document Map

```
docs/
├── child-wallet-identity-model.md   ← Plan 01-01
│   ├── §1 Overview
│   ├── §2 Keypair & Address         (IDENT-01)
│   ├── §3 Wallet Creation           (IDENT-03)
│   ├── §4 Nonce Tracking            (IDENT-02)
│   ├── §5 UTXO Ownership            (IDENT-04)
│   └── §6 Traceability
│
└── registration-protocol.md         ← Plan 01-02
    ├── §1 Overview
    ├── §2 Proto Schema              (REG-01, REG-03)
    ├── §3 Oneof Dispatch            (REG-03)
    ├── §4 C++ Subclass              (REG-01)
    ├── §5 Signing Protocol          (REG-02 ⚠ REVERSED, REG-04)
    ├── §6 Sequence Numbering        (REG-05)
    ├── §7 Backward-Compat Matrix    (REG-03)
    └── §8 Traceability
```

## Key Invariants (Must Remain True Across All Phases)

1. **Main private key never enters the child process** — maintained by D-10 trivially (no main signing during registration). Phase 2 funding/recovery uses main's signature performed in GNUS Wallet app, not child process.
2. **Child key compromise is bounded to child assets** — child keypair is independent (IDENT-01, D-01). No cross-account authority derivation possible.
3. **Proto evolution is additive-only** — no existing field numbers renumbered or repurposed in any phase. Backward-compatibility guaranteed by proto3.
4. **GeniusAccount.hpp, GeniusNode.hpp, GeniusUTXO.hpp stay untouched** — identity model is emergent, UTXO ownership is address-based, creation is via existing AccountSource. These files are NOT modified in Phase 1 and should not need modification in any phase.
5. **Registration alone grants zero authority over the main wallet** — enforced by Phase 2 consensus authority rules (CONS-01..06). Phase 1 defines the registration record; Phase 2 ensures it cannot be abused.
