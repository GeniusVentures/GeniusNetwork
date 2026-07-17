# Phase 04: Registration Proto & Transaction - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 04-registration-proto-transaction
**Areas discussed:** Child-side API surface, Sequence tracking, Phase 4 storage path, Validation eagerness

---

## Child-side API surface (from checkpoint)

| Option | Description | Selected |
|--------|-------------|----------|
| Both layers, full convention | TransactionManager::RegisterChild + GeniusNode wrapper, mirroring TransferFunds/MintTokens | ✓ |
| TransactionManager only | API at TransactionManager level only, no GeniusNode wrapper | |
| No API yet (test-driven only) | GTest constructs RegistrationTx directly through New(), no public API | |

**User's choice:** Both layers, full convention
**Notes:** Full metadata param selected: main_address + optional RegistrationMetadata (game_id, publisher_id, dev_wallet, peers_cut) defaulting to empty; GTest round-trips it.

---

## Sequence tracking (from checkpoint)

| Option | Description | Selected |
|--------|-------------|----------|
| Caller-supplied param | RegisterChild(main_address, metadata, sequence). Phase 4 GTest passes 1; Phase 5 derives from reg/ state | ✓ |
| In-memory counter | TransactionManager tracks a counter per child locally | |
| Hardcode 1 for now | Always use sequence=1; revisit in Phase 5 | |

**User's choice:** Caller-supplied param
**Notes:** No throwaway in-memory state. Phase 5 derives "last confirmed + 1" from reg/{child_addr} and can wrap it with a convenience overload.

---

## Phase 4 storage path (from checkpoint)

| Option | Description | Selected |
|--------|-------------|----------|
| tx/ temporarily, reg/ in Phase 5 | Write to tx/{hash} in Phase 4, migrate to reg/{child_addr} in Phase 5 | |
| reg/ path lands in Phase 4 | Divert CRDT write to GetBlockChainBase() + reg/{child_addr} now | ✓ |
| No CRDT write in Phase 4 | GTest validates construction/signing only, no persistence | |

**User's choice:** reg/ path lands in Phase 4
**Notes:** Open follow-up: planner must address how incoming reg/ deltas are handled in Phase 4 (no FilterRegistration yet) and confirm the GetTransactionFullPath() override approach since it hardcodes "tx/" + GetHash().

---

## Validation eagerness

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal filter in Phase 4 | Register basic FilterRegistration stub: signature + well-formed gates, defer sequence monotonicity to Phase 5 | ✓ |
| No filter in Phase 4 | Write to reg/ with no element filter at all; Phase 4 GTest runs isolated | |
| Full FilterRegistration in Phase 4 | Pull all four gates into Phase 4 scope — expands scope into Phase 5 territory | |

**User's choice:** Minimal filter in Phase 4

### Reject gate set

| Option | Description | Selected |
|--------|-------------|----------|
| Signature + well-formed only | Reject: deserialization failure, invalid signature, malformed main_address (not 128-hex) | ✓ |
| Signature only | Reject invalid signatures only | |
| Full gates, skip sequence | Reject: deserialization, bad sig, malformed main_address, well-formed check on all fields | |

**User's choice:** Signature + well-formed only
**Notes:** Accepts everything else including sequence=0. Phase 5 adds sequence monotonicity gate.

### Filter code structure

| Option | Description | Selected |
|--------|-------------|----------|
| Partial FilterRegistration | Name it FilterRegistration (same name Phase 5 extends), register on reg/ pattern | ✓ |
| Separate FilterRegistrationV1 | Distinct name so Phase 5's filter is a clean replacement | |
| Inline lambda | Anonymous lambda in TransactionManager::New() | |

**User's choice:** Partial FilterRegistration

### Filter test scope

| Option | Description | Selected |
|--------|-------------|----------|
| Test accepts + rejects | GTest: valid tx passes filter, tampered-signature tx is rejected | ✓ |
| Test accept only | Only assert valid tx passes; assume deserializer covers signature errors | |
| Full rejection suite | Test all rejection paths now (bad sig, malformed address, bad deserialization) | |

**User's choice:** Test accepts + rejects

---

## the agent's Discretion

- Proto field numbers (8+) and mechanical shape of RegistrationTx + RegistrationMetadata messages
- `registration = 8` oneof arm in `Consensus.proto` `EmbeddedTransaction`
- Naming and file placement of `RegistrationTransaction` under `SuperGenius/src/account/`
- GTest file placement under `SuperGenius/test/src/account/`

## Deferred Ideas

- Full FilterRegistration with sequence monotonicity — Phase 5
- CRDT pubsub broadcast — Phase 5
- Main-node discovery read path — Phase 5
- Multi-node integration test — Phase 5
- Consensus authority gate (CheckParentChildAuthority) — later milestone
