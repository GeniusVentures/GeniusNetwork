# Phase 1: Subnet Addressing Scheme - Context

**Gathered:** 2026-07-24
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase produces a **design document only** — no code, no proto/CRDT/consensus changes. The doc fixes the `net_id.subnet_id` composite identity that every later phase (PubSub namespacing, Job Isolation & Consensus, Bridge/Gateway) reads from as its single source of truth. It must cover: the composite addressing format and `config_json` placement, the subnet ID allocation/registry mechanism, and an explicit resolution of whether address derivation itself needs to change to fold in `net_id.subnet_id` (Pitfall 1) — no silent inheritance of that ambiguity is acceptable per ROADMAP.md success criteria.

</domain>

<decisions>
## Implementation Decisions

### Address Derivation Scoping (Pitfall 1)
- **D-01:** Address derivation is **not changed**. `GeniusAccount::GetAddress()` keeps deriving purely from the pubkey, identical across every net/subnet — the user explicitly rejected folding `net_id.subnet_id` into derivation ("I don't think this needs to differ").
- **D-02:** Uniqueness is instead enforced via a **tuple-keying invariant**: every consumer (CRDT keys, replay-nonce tracking, `CheckCertifiedParent`/`CheckParentChildAuthority`) must key by `(net_id, subnet_id, address)`, never by bare address alone.
- **D-03:** This invariant is **mandatory, not advisory** — the design doc must require a single shared key-building/lookup helper that every consumer goes through (no call site permitted to key by bare address). This directly sets up Phase 3's JOBC-01 mandatory shared key-building function requirement; Phase 1's design doc should state the invariant and name it as the precondition Phase 3's helper must satisfy.
- **D-04 (corollary — Pitfall 8):** Nonce/replay-hash keying (`EvaluateTransactionReplayProtection`, `GetPeerNonce`, `GetOutgoingPreviousHash`) is **not detailed in this phase's doc**. State only that it falls under the general tuple-keying invariant (D-02); the specific re-audit of `GetPeerNonce`/`GetOutgoingPreviousHash`/`GetTrackedTxByNonceAndAddress` is explicitly deferred to Phase 3 (Job Isolation & Consensus Impact), which already re-audits consensus authority gates line-by-line.

### Composite ID Format & Validation
- **D-05:** Canonical representation is **dotted-decimal for display** (`"144.100"`) with **net_id and subnet_id remaining two separate `uint16_t` fields** on the wire and in-memory — no new packed/combined type, no new serialization. Matches how `TransactionManager::New(..., subnet_id)` already receives them separately.
- **D-06:** `subnet_id == 0` is **permanently reserved** to mean "main net, no subnet" — byte-identical topic/keyspace strings to today's builds. The Subnet Registry must never allocate `0`. This guarantees zero migration for existing deployments (144/369/963).
- **D-07:** No sub-range structure — the full `uint16_t` range (1–65535) is allocatable by the registry with no reserved "official" vs. "open" sub-ranges. Matches the milestone's docs-only scope; no allocation policy enforcement needed yet.
- **D-08:** `sgns_config.json` keeps `net_id` and `subnet_id` as **flat sibling fields** (as they exist today) — no nested `"subnet": {...}` object, zero config-schema migration.

### Subnet Registry Allocation Mechanism
- **D-09:** Subnet ID allocation is **main-net-operator-issued only**, not open self-registration. A subnet claim requires a certified main-net authority to write the registry entry — reuses the same CRDT-derived-authority pattern behind `CheckCertifiedParent`, not first-claim-wins broadcast (which was judged too high-blast-radius for a unit as large as a subnet, unlike child-wallet registration).
- **D-10:** The registry uses a **new top-level CRDT namespace**: `/bc-{net_id}/subnets/{subnet_id}`, structurally distinct from `reg/{child_addr}` even though both reuse the same broadcast/CRDT-sync mechanism. Do not fold subnet registrations into the existing `reg/` namespace with a type discriminator.
- **D-11:** This registry mechanism is what replaces `SetNetworkId`'s current hardcoded 3-value whitelist for the subnet dimension (per ROADMAP.md success criterion 2) — `net_id` validation stays against the existing 3-constant whitelist, unchanged.

### Claude's Discretion
- Exact naming of the shared tuple-keying helper function/type (D-03) — Claude picks a name and signature consistent with existing helper-function conventions (e.g. alongside `GetBlockChainBase()`), to be finalized during planning/Phase 3.
- Whether the "You decide" fallback was ever exercised: it wasn't — every decision in this phase had an explicit user answer, no gray area was left to Claude's judgment.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Research (primary grounding for this phase)
- `.planning/workstreams/gnus-subnets/research/SUMMARY.md` — executive synthesis; Phase 1 rationale, build-order discussion, confidence assessment
- `.planning/workstreams/gnus-subnets/research/ARCHITECTURE.md` — component responsibilities, integration structure (`sgns::version`, `TransactionManager`, Subnet Registry), architectural patterns and anti-patterns (esp. Anti-Pattern 3 on `SetNetworkId` whitelist extension)
- `.planning/workstreams/gnus-subnets/research/PITFALLS.md` — Pitfall 1 (address derivation scoping), Pitfall 2 (CRDT keyspace convention-only namespacing), Pitfall 8 (replay-nonce bare-address keying), Pitfall-to-Phase Mapping table
- `.planning/workstreams/gnus-subnets/research/STACK.md` — confirms no new libraries/serialization needed; existing stack sufficiency
- `.planning/workstreams/gnus-subnets/research/FEATURES.md` — table-stakes feature list (globally unique hierarchical addressing, centrally-allocated registry)

### Project & Requirements
- `.planning/workstreams/gnus-subnets/REQUIREMENTS.md` — ADDR-01/02/03 (this phase's mapped requirements), Out of Scope table
- `.planning/workstreams/gnus-subnets/ROADMAP.md` — Phase 1 goal and success criteria (the four criteria this design doc must satisfy)
- `.planning/PROJECT.md` — child-wallet workstream context; D-01/D-04/D-05/D-06/D-11/D-12 prior decisions (emergent identity, `reg/` CRDT namespace precedent this phase's Subnet Registry design extends)

### SuperGenius Source (named anchor points — verify against current HEAD before design-doc finalization, per research's own caveat)
- `SuperGenius/src/account/GeniusAccount.cpp` — `GetAddress()`/`CreateSecureStorage` (address derivation, unchanged per D-01)
- `SuperGenius/src/base/sgns_version.hpp`, `sgns_version.cpp` — `network_id_` global, `SetNetworkId` whitelist, `GetNetAndVersionAppendix()` (the single leverage point this design doc's format decisions must be compatible with)
- `SuperGenius/src/account/GeniusNode.hpp`, `GeniusNode.cpp` — `subnet_id_` field (currently inert), `LoadSgnsConfig()` (config_json placement, D-08)
- `SuperGenius/src/account/TransactionManager.hpp`, `TransactionManager.cpp` — `GetBlockChainBase()`, `transaction_parsers`, `EvaluateTransactionReplayProtection` (`TransactionManager.cpp:4553-4656`, relevant to the deferred D-04 corollary)
- `SuperGenius/src/blockchain/impl/Blockchain.cpp`, `Blockchain.hpp` — `CheckCertifiedParent` (`Blockchain.cpp:1852-1884`, the authority pattern D-09's registry-write gate reuses)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `reg/` CRDT namespace + pubsub-sync pattern (child-wallet registration, D-49 `RegElementCallback`) — direct structural template for the new `subnets/` namespace (D-10), though kept as a distinct namespace rather than merged.
- `CheckCertifiedParent`'s CRDT-derived-authority pattern (`Blockchain.cpp`) — direct template for the main-net-operator-issued gate on Subnet Registry writes (D-09).
- `net_id`/`subnet_id` already threaded to `TransactionManager::New(..., subnet_id)` — no new constructor plumbing needed; `TransactionManager` just needs to start consuming the value it already receives.

### Established Patterns
- Every net-scoping consumer in the codebase already funnels through one function, `version::GetNetAndVersionAppendix()` (and its CRDT-path derivative `GetBlockChainBase()`) — this phase's format decisions (D-05/D-06) are constrained to stay compatible with extending that single choke point, not introducing a parallel formatting scheme.
- `subnet_id_` already defaults to `0` everywhere it's declared (`GeniusNode.hpp` line 949, `TransactionManager.hpp` line 622) — D-06's "0 is reserved" decision aligns with, rather than fights, this existing default.

### Integration Points
- `sgns::version` ↔ everything else — single choke point; this phase's composite-ID decisions become the identity that function extends in Phase 2.
- `SetNetworkId` — `net_id` half of its whitelist stays unchanged; `subnet_id` half is replaced by the Subnet Registry (D-09/D-11), the design doc must specify this replacement explicitly, not just describe the registry in isolation.

</code_context>

<specifics>
## Specific Ideas

- User was decisive and consistently chose the backward-compatibility-preserving, lower-blast-radius option at every fork: no change to address derivation, `subnet_id=0` permanently reserved, flat (non-nested) config fields, no config-schema migration anywhere in this phase's decisions.
- User deliberately scoped the replay-nonce corollary (Pitfall 8) out of this phase's doc and into Phase 3 — a conscious choice to keep this design doc focused on identity/format/allocation, not to re-litigate consensus-gate details Phase 3 already owns.

</specifics>

<deferred>
## Deferred Ideas

- Replay-nonce/previous-hash keying specifics (`GetPeerNonce`, `GetOutgoingPreviousHash`, `GetTrackedTxByNonceAndAddress` becoming `(net_id, subnet_id, address)`-keyed) — explicitly deferred to Phase 3 (Job Isolation & Consensus Impact) per D-04.
- Subnet ID range sub-structuring (reserved "official" vs. "open" ranges) — explicitly declined for this milestone (D-07); revisit only if/when a real allocation-policy need emerges post-v1.0.
- Address-derivation domain-separation versioning (a scheme-version tag for future re-derivation) — moot given D-01 (derivation not changing this milestone), but noted here in case a future milestone revisits address derivation.

None — discussion stayed within phase scope; no scope-creep items were raised.

</deferred>

---

*Phase: 1-Subnet Addressing Scheme*
*Context gathered: 2026-07-24*
