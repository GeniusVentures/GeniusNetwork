# Pitfalls Research: GNUS Subnets (Addressing, PubSub Namespacing, Bridge/Gateway, Job Isolation & Consensus)

**Domain:** Adding subnet/sidechain-style isolation + cross-net token bridge to an existing single-net libp2p/CRDT/consensus system
**Researched:** 2026-07-24
**Confidence:** HIGH (codebase-grounded findings) / MEDIUM (cross-net bridge-attack literature)

All findings below are anchored to the current `SuperGenius` implementation as of the `dev_childwallet` branch (post v2.4 merge). Line/file references are current at time of research; verify against HEAD before design-doc finalization. Confidence tags: **[HIGH]** = read directly from source; **[MEDIUM]** = cross-verified against multiple independent industry sources (bridge-hack post-mortems, gossipsub specs) but not project-specific.

---

## Critical Pitfalls

### Pitfall 1: Address derivation has no net/subnet scoping — cross-net address collision **[HIGH]**

**What goes wrong:**
`GeniusAccount::GetAddress()` derives the address purely from the secp256k1 public key (base58-encoded hash of the pubkey, see `GeniusAccount.cpp` `CreateSecureStorage`/`GetAddress`). Nothing in the derivation includes `net_id` or `subnet_id`. The same keypair therefore produces the *identical* address string whether the account is used on main net `144`, on subnet `144.100`, or on a sibling subnet `144.200`.

**Why it happens:**
The address scheme predates subnets; it was never designed to be a compound identity. Adding subnet addressing as a config/topic-layer concern (rather than an identity-layer concern) is the natural-seeming shortcut, but it leaves the actual account identity net-agnostic.

**How to avoid:**
Decide explicitly, in the addressing design, whether an address is meant to be globally unique across all nets/subnets (requiring the derivation itself to fold in `net_id.subnet_id`, e.g. via a domain-separated hash or an address prefix) or whether uniqueness is enforced structurally elsewhere (e.g. every CRDT key, transaction, and registry lookup is always tuple-keyed `(net_id, subnet_id, address)` with no code path that keys by bare address alone). The second option is riskier because it requires *every* current and future callsite to remember the extra key components — Pitfall 2 shows this convention already leaks today for CRDT keys.

**Warning signs:**
- Any place that computes or compares an address without also carrying/checking `net_id`/`subnet_id`.
- Two child wallets on different subnets independently deriving from the same seed/keypair and successfully "registering" without conflict detection.
- A `CheckCertifiedParent`-style lookup (keyed only by address, see Pitfall 10) returning a match for an address that belongs to a different net's account.

**Phase to address:** Addressing (subnet addressing scheme phase) — must be resolved before pubsub/bridge/job-isolation phases, since they all assume addresses are the unit of identity.

---

### Pitfall 2: CRDT keyspace namespacing is convention-only, not structurally enforced **[HIGH]**

**What goes wrong:**
The `/bc-{net_id}/...` prefix that scopes all CRDT/GlobalDB keys (e.g. registration records at `/bc-%hu/reg/{child_addr}`, confirmed in `Blockchain::CheckCertifiedParent`, `Blockchain.cpp:1852-1884`, mirroring the format used in `TransactionManager.cpp:618-619,2873-2874`) is built by `boost::format` string concatenation at each callsite. `crdt_datastore`/`globaldb` themselves have no concept of a "net" or "subnet" root — they just store whatever key string they're given. There is no schema/type layer that rejects a key written outside its owning net's prefix.

**Why it happens:** The prefix is cheap to add at each call site, so it was added independently, repeatedly, wherever a key needed scoping — a "just keep doing what worked" pattern that is fine for one net but becomes a landmine once N subnets need their own prefixes plus a distinct main-net prefix, all sharing one underlying CRDT/IPFS datastore process.

**How to avoid:** Introduce a single, mandatory key-building function/type (e.g. `SubnetScopedKey(net_id, subnet_id, suffix)`) that every CRDT read/write for subnet-aware data must go through — no raw `boost::format` string-building of `/bc-.../` keys anywhere else. Add a startup/CI assertion or lint rule that flags any string literal matching `/bc-` outside that helper. Treat the main net as `subnet_id = 0`/absent rather than a special case, so main-net and subnet code paths share the same key-building function (reduces the chance of a forgotten prefix).

**Warning signs:**
- New subnet-related CRDT keys added via ad hoc string formatting instead of the shared helper.
- A subnet's registration/job/tx data becomes visible to (or is overwritten by) main-net queries that scan a prefix without the subnet component.
- Migration code (see `Migration0_2_0To1_0_0.cpp`, `Migration1_0_0To3_4_0.cpp`, etc.) that hardcodes topic/key literals and would silently need per-subnet variants but doesn't get them.

**Phase to address:** Addressing (define the canonical key-building scheme) and Job isolation & consensus (enforce it at every CRDT-touching validation/registration/dispatch site).

---

### Pitfall 3: `net_id` is a process-wide global singleton — breaks any node that must see two nets at once **[HIGH]**

**What goes wrong:**
`sgns::version::GetNetworkID()`/`SetNetworkId()` (`sgns_version.hpp/.cpp`) is a single global value per process. Every net-scoped key, topic-legacy-suffix, and validator context implicitly reads this one global. A gateway/bridge node — by definition the one node type that must simultaneously understand main net `144` and a subnet `144.100` (and potentially several subnets) — cannot hold two "current net" contexts in one process under this model.

**Why it happens:** The system was built as one-node-one-net; globalizing `net_id` was the simplest way to thread it through many call sites without passing it as a parameter everywhere. That shortcut is invisible until a process needs multi-net awareness, which is exactly what a bridge/gateway needs.

**How to avoid:** Design the bridge/gateway explicitly as either (a) two co-located processes/instances (one per net) communicating over a narrow internal API, each with its own `net_id` global, or (b) refactor the net-scoped state (Blockchain instance, ValidatorRegistry, TransactionManager) to be parameterized by net context rather than reading a process global, and have the gateway hold multiple instances. Do not attempt to "toggle" the global net_id at runtime per-request — this is a classic source of race conditions/data corruption in a multi-threaded libp2p node.

**Warning signs:** Any bridge/gateway design that calls `SetNetworkId()` more than once during steady-state operation, or that relies on save/restore of the global around bridge operations.

**Phase to address:** Bridge/gateway design (primary) — informs whether the addressing phase needs to expose a non-singleton net-context API.

---

### Pitfall 4: PubSub topic names are hardcoded literals today — no systematic namespacing function exists to extend **[HIGH]**

**What goes wrong:**
`TransactionManager::GNUS_FULL_NODES_TOPIC` is a compile-time string constant (`"SuperGNUSNode.TestNet.FullNode"`), with a separate hand-maintained legacy constant (`GNUS_FULL_NODES_TOPIC_LEGACY = "SuperGNUSNode.TestNet.FullNode.963"`) for backward compatibility. There is no function today that *computes* a topic name from `net_id` (`963` is baked into the legacy string, not appended programmatically). Adding `subnet_id` to topic naming means retrofitting a naming function into code that currently treats topic strings as static constants referenced from multiple migration files (`Migration0_2_0To1_0_0.cpp`, `Migration1_0_0To3_4_0.cpp`, `Migration3_4_0To3_5_0.cpp`, `Migration3_5_0To3_6_0.cpp`, `Migration3_6_0To3_7_0.cpp`) and `TransactionManager.cpp`.

**Why it happens:** A single net didn't need computed topic names; a hardcoded constant was simpler and cheaper.

**How to avoid:** Introduce one canonical `BuildTopicName(net_id, subnet_id, purpose)` function (mirroring the CRDT key-building function from Pitfall 2) and route every topic subscribe/publish/`AddTopicName`/`AddListenTopic` call through it — including the "full node" broadcast topic, which itself needs to become subnet-scoped (a subnet's full nodes should not be the same broadcast group as main net's, or one subnet's). Explicitly enumerate every existing hardcoded topic-string call site (`TransactionManager.cpp:379`, migration files) as a checklist item to convert; missing even one leaves an unnamespaced leak.

**Warning signs:** Any new subnet code that appends `subnet_id` to a topic string ad hoc in one place while another call site still uses the bare legacy constant — the two topic strings won't match and peers will silently fail to hear each other (or worse, all subnets keep converging on the same unscoped legacy topic and cross-talk).

**Phase to address:** PubSub namespacing (primary).

---

### Pitfall 5: Single gateway node as sole trust anchor — federated-bridge single point of failure **[HIGH for existing pattern] / [MEDIUM for industry corroboration]**

**What goes wrong:**
The existing child-wallet precedent this milestone must not blindly copy: `CheckCertifiedParent`/`CheckParentChildAuthority` grant transfer authority based on a *recorded certification* in CRDT (a "certified main" address whose signature substitutes for the child's own), not on a fresh cryptographic multi-party proof at transaction time (`TransactionManager.cpp:4381-4429`, `Blockchain.cpp:1852-1884`). This is a reasonable design for a parent-child relationship *within one net/validator set*, but if the bridge/gateway reuses the same shape — a single gateway address whose signature is trusted to authorize mint/burn across two independently-validated nets — it recreates the exact "federated bridge" pattern responsible for the majority of real-world cross-chain bridge losses: a compromised, censoring, or offline single signer breaks the entire bridge. Industry analysis (ImmuneBytes, ACM DLT survey — see Sources) consistently identifies single/small trusted-signer bridges as the dominant real-world attack surface, versus bridges requiring quorum certification from both sides' validator sets.

**Why it happens:** Reusing an existing, already-shipped authority pattern (parent-child) is the path of least resistance, and it "works" in testing because both sides of a test bridge are typically controlled by the same operator.

**How to avoid:** Require the bridge/gateway design to produce a certification that references quorum/weighted validator agreement from the *source* net's `ValidatorRegistry` (see Pitfall 7 — registries are per-net, weight- and epoch-based) before the *destination* net accepts a mint/unlock. Do not accept a single gateway-address signature as sufficient proof of a source-net burn/lock; require the certificate (or a threshold-signed attestation derived from it) itself to cross the boundary, not just a delegate's endorsement of it.

**Warning signs:** Bridge design documents that describe "the gateway signs and forwards" rather than "the gateway relays and the destination net independently verifies a certificate/proof from the source net's validator set."

**Phase to address:** Bridge/gateway (primary).

---

### Pitfall 6: Bridge tx certified against a stale/rotated validator epoch — split-brain across the trust boundary **[HIGH for mechanism] / [MEDIUM for attack framing]**

**What goes wrong:**
`ValidatorRegistry` is versioned by `GetRegistryCid()`/`GetRegistryEpoch()`, and registry updates chain via `prev_registry_hash` (`ValidatorRegistry.cpp:751,843,849`). Each net's registry evolves independently. If a bridge certifies a lock/burn on the source net at epoch N, but the mint on the destination net is processed after the source net has already rotated to epoch N+1 (validator set/weights changed) with no epoch-pinning or staleness check in the bridge protocol, the mint could be authorized against a validator set that no longer represents the source net's current consensus — a superseded validator (already removed for e.g. compromise) could still get its earlier-epoch certification honored on the destination side.

**Why it happens:** Registry epoch tracking exists for single-net consensus continuity, not for cross-net proof validity windows; nothing currently ties a cross-net proof's validity to "this epoch is still current," because no cross-net proof exists yet.

**How to avoid:** Bridge certificates must carry the source-net registry epoch/CID they were certified under, and the destination side (or the gateway) must check that epoch is still the *current* (or an explicitly allowed recent) epoch before honoring the mint — reject or require re-certification otherwise. Treat epoch rotation on either side as an event that can invalidate in-flight bridge proposals, not just local consensus state.

**Warning signs:** Bridge proposals that only check "was this ever certified" rather than "is this still certified under the source net's current validator set."

**Phase to address:** Bridge/gateway (primary), Job isolation & consensus (registry epoch propagation).

---

### Pitfall 7: No cross-net atomicity — lock/burn and mint are separate, uncoordinated CRDT commits (double-spend/double-mint window) **[MEDIUM]**

**What goes wrong:**
Main net and each subnet run independent CRDT/consensus domains with no shared transaction boundary. A bridge that (1) records a burn/lock on the source net's CRDT and (2) separately submits a mint transaction on the destination net's CRDT has no atomic "both or neither" guarantee. Classic failure modes: the burn is recorded but reorganized/rolled back after the mint has already been submitted and certified (asset duplicated); or the mint is submitted twice (duplicate submission, retry after timeout, or two gateway processes racing) before the first is confirmed, producing a double-mint from a single burn.

**Why it happens:** This is the standard cross-chain double-spend class (well documented — ScienceDirect double-spend analysis, Gate.com replay-attack guide; see Sources) and it is structurally hard to avoid without either finality-based confirmation depth or an idempotency key. It is easy to underestimate in a docs-only design pass because within one net, the existing nonce/previous-hash chain (`EvaluateTransactionReplayProtection`, `TransactionManager.cpp:4553-4656`) already solves single-net replay — it's tempting to assume it "just works" across the bridge too, but that mechanism is address-scoped per net (see Pitfall 8), not cross-net.

**How to avoid:** Require the bridge design to specify (a) a finality/confirmation-depth threshold on the source net before a burn/lock is considered irreversible enough to mint against, and (b) a mint idempotency key derived from the source burn's transaction hash (or certificate hash) so a duplicate mint submission for the same burn is provably rejected regardless of timing/retries — i.e. the destination net's CRDT should record "this source-burn-hash has already been minted" and treat resubmission as a no-op/reject, not process it again.

**Warning signs:** Bridge flow diagrams that show mint being triggered purely by "gateway observed a burn event" with no persisted idempotency record on the destination side.

**Phase to address:** Bridge/gateway (primary).

---

### Pitfall 8: Replay-protection nonce/hash chains are keyed by bare address, not `(net_id, address)` — reusable across nets if addresses collide **[HIGH]**

**What goes wrong:**
`EvaluateTransactionReplayProtection` derives expected previous-hash and confirmed-nonce purely from `tx.GetSrcAddress()` (`account_m->GetPeerNonce(tx.GetSrcAddress())`, `GetOutgoingPreviousHash(nonce)` — `TransactionManager.cpp:4558-4620`). Combined with Pitfall 1 (address derivation has no net/subnet component), a transaction signed for use on a subnet could, in principle, satisfy the nonce/previous-hash expectations of a same-addressed account on main net (or vice versa) if nonce counters happen to align — because nothing in the check itself distinguishes "this nonce is scoped to net 144" from "this nonce is scoped to subnet 144.100."

**Why it happens:** Nonce tracking was built assuming one net per process/account; it inherits the same implicit single-net assumption as Pitfalls 1 and 3.

**How to avoid:** Either (a) make nonce/previous-hash tracking explicitly keyed by `(net_id, subnet_id, address)` everywhere it's read/written (`GetPeerNonce`, `GetOutgoingPreviousHash`, `GetTrackedTxByNonceAndAddress`), or (b) guarantee via Pitfall 1's resolution that an address can never resolve validly on more than one net/subnet, making the bare-address key safe by construction. Pick one and verify the other invariant doesn't quietly get violated by a future feature (e.g. address import/recovery across subnets).

**Warning signs:** A tx built for a subnet passing well-formed/authorization/replay checks intended for main net (or vice versa) without an explicit net/subnet-mismatch rejection anywhere in the chain of `ValidateTransactionForConsensus`.

**Phase to address:** Addressing (root cause), Bridge/gateway and Job isolation & consensus (must not assume this is "already handled" without an explicit check).

---

### Pitfall 9: Unknown-tx-type silent rejection — new bridge/subnet tx types invisible until the dispatch table is updated **[HIGH]**

**What goes wrong:**
`CheckTransactionWellFormed` rejects any transaction whose type isn't present in the `transaction_parsers` dispatch map (`TransactionManager.cpp:4371-4375`, `"Unknown tx type"`). This exact bug already happened once in this codebase: registration transactions were completely unprocessable for a period because `transaction_parsers` had no `"registration"` entry, discovered only while building v2.3 regression tests (per PROJECT.md Context). A new bridge/mint/burn tx type introduced for subnets is at high risk of repeating this — the proto/wire format and signing logic can be fully implemented while the dispatch table entry is simply forgotten, and the failure mode (silent rejection, logged as a generic "unknown type" debug/error line) does not fail loudly.

**Why it happens:** The dispatch table is a separate, easy-to-forget registration step decoupled from where the tx type's actual class/proto lives; nothing enforces "every `GeniusTransaction` subclass must have a `transaction_parsers` entry" at compile time.

**How to avoid:** When the bridge/gateway design introduces a new tx type (e.g. `"bridge_lock"`/`"bridge_mint"`), add an explicit design-doc and implementation checklist item: "add to `transaction_parsers`," and add a regression test asserting the new type round-trips through `CheckTransactionWellFormed` before any other bridge-specific logic is tested (mirroring how the registration-dispatch gap was only caught via regression tests in v2.3).

**Warning signs:** A new tx type that passes construction/signing unit tests but has never been exercised through `ValidateTransactionForConsensus` end-to-end.

**Phase to address:** Bridge/gateway (primary, since this is where new tx types are introduced) — call out explicitly rather than assuming "the existing pattern will catch this."

---

### Pitfall 10: Cross-net reuse of the parent-child "certified signature" trapdoor **[HIGH]**

**What goes wrong:**
`CheckTransactionAuthorization`'s explicit trapdoor — for `tx.GetType() == "transfer"`, a signature from a *different* address (the CRDT-certified "main") is accepted in place of the source address's own signature, if `CheckCertifiedParent` returns a match (`TransactionManager.cpp:4381-4400`) — was deliberately scoped narrowly to the single-net parent-child relationship (see PROJECT.md D-60). Because `CheckCertifiedParent`'s CRDT lookup is keyed only by address with no net/subnet component (Pitfall 1/2), and because the trapdoor is gated on the tx *type string* ("transfer") rather than any net-boundary check, there is a real risk that a subnet address which happens to look "registered" under this same CRDT key shape could inherit main net's certified-signature trapdoor across the net boundary — i.e., a main-net key could end up authorized to sign for what should be a subnet-only account, or vice versa, purely because the authority check has no concept of "same net" as a precondition.

**Why it happens:** The trapdoor was added as a narrow, well-reviewed exception for one specific feature; extending the system with subnets introduces a new dimension (net/subnet boundary) that this check was never designed to reason about, so it will pass through unchanged unless someone explicitly revisits it.

**How to avoid:** Any subnet/bridge design must explicitly re-audit `CheckTransactionAuthorization` and `CheckParentChildAuthority` and add a net/subnet-match precondition to the certified-parent trapdoor (the certifying registration record and the transaction being authorized must belong to the same net *and* subnet), not assume the existing gate "already handles it" because it currently passes all child-wallet tests (which are all single-net).

**Warning signs:** No explicit test exercising `CheckCertifiedParent`/`CheckParentChildAuthority` with a registration recorded under one net/subnet and a transaction submitted under a different one.

**Phase to address:** Job isolation & consensus (primary — this is exactly the "validation-gate subnet-awareness" deliverable named in the milestone scope).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|--------------------|-----------------|------------------|
| String-formatted `/bc-{net}/...` CRDT keys per callsite instead of a shared key-building function | Fast to add one prefix | Keyspace collisions across nets/subnets as call sites multiply (Pitfall 2) | Never for subnet work — retrofit the helper before adding subnet keys |
| Reusing the child-wallet "certified signature" trapdoor shape for bridge trust | Reuses reviewed, shipped code | Recreates single-signer federated-bridge risk (Pitfall 5) | Never for the bridge itself; fine only for same-net child-wallet flows |
| Treating `net_id` as a global rather than threading it through | Minimal refactor | Blocks any process (gateway) that must hold two net contexts (Pitfall 3) | Acceptable only if bridge/gateway is architected as two cooperating single-net processes |
| Ad hoc topic-string subnet suffixing at individual call sites | Quick to ship a first subnet | Silent cross-talk/isolation failures when one call site is missed (Pitfall 4) | Never — centralize before shipping more than one subnet-aware call site |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|-----------------|-------------------|
| CRDT/GlobalDB keyspace | Assuming the datastore enforces net/subnet scoping because keys "look" namespaced | Enforce scoping in a single shared key-building function; datastore itself is scope-agnostic |
| PubSub (gossipsub via libp2p) topics | Assuming topic strings alone provide security/isolation, not just routing | Topic names are advisory routing hints only — pair with a `TopicSubscriptionFilter`-style application-level check that rejects/ignores messages whose embedded subnet_id doesn't match the local subnet context, since a misbehaving or misconfigured peer can still publish to a topic it can compute the name for |
| ValidatorRegistry (per-net) | Assuming one shared registry/epoch space across main net and subnets | Each net/subnet likely needs its own registry+epoch; any bridge check must reference the correct one explicitly, never "the current global registry" |
| TransactionManager dispatch table | Assuming a new tx type "just works" once the proto is added | Explicitly add to `transaction_parsers`; regression-test the dispatch path first (Pitfall 9) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Bridge waits on full source-net finality/confirmation depth before minting | Slow bridge UX, users perceive "stuck" transfers | Make confirmation-depth a documented, tunable design parameter, not an afterthought | Becomes visible as soon as more than a trivial number of bridge transfers run concurrently |
| Every full node subscribing to every subnet's full-node topic (no scoping) | Bandwidth/CPU growth proportional to total subnet count, not to subnets a node actually serves | Namespaced topics (Pitfall 4) + selective subscription per node's served subnet(s) | Breaks as soon as subnet count grows past a handful, since every node would otherwise ingest all subnets' gossip |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Single gateway address trusted to authorize mint/burn (Pitfall 5) | Total bridge compromise from one compromised/censoring key — the dominant real-world cross-chain bridge attack pattern | Require quorum/threshold certification from the source net's validator registry, not a single relaying signature |
| No epoch-pinning on bridge certificates (Pitfall 6) | Stale/removed validator's certification honored after rotation — split-brain trust | Bind bridge proofs to a specific registry epoch/CID and check currency at destination-side validation |
| No mint idempotency key (Pitfall 7) | Double-mint from a single burn/lock via retry or race | Persist "source-burn-hash already minted" record on destination net, reject duplicates unconditionally |
| Certified-parent trapdoor with no net/subnet precondition (Pitfall 10) | Cross-net signature authority bypass | Add explicit net/subnet-match check to `CheckCertifiedParent`/`CheckParentChildAuthority` before extending to subnets |
| Address derivation with no net/subnet binding (Pitfall 1) | Identical address usable (and confusable) across nets | Fold net/subnet into address derivation, or make every consuming check tuple-keyed |

## "Looks Done But Isn't" Checklist

- [ ] **Subnet addressing scheme:** Looks done once `net_id.subnet_id` parses and validates — verify address *derivation* itself (not just config/topic strings) also carries net/subnet scoping (Pitfall 1), or that every downstream consumer is tuple-keyed instead.
- [ ] **PubSub namespacing:** Looks done once new subnets get a computed topic name — verify *every* existing hardcoded topic constant and migration-file literal (Pitfall 4) was converted, not just newly-written code.
- [ ] **Bridge/gateway:** Looks done once a lock-on-source/mint-on-destination happy path works in a demo — verify epoch-pinning (Pitfall 6), mint idempotency (Pitfall 7), and quorum-based (not single-signer) trust (Pitfall 5) are all specified, since the happy-path demo will pass without any of them.
- [ ] **Job isolation & consensus:** Looks done once subnet jobs are scheduled on subnet-scoped topics — verify `CheckParentChildAuthority`/`CheckCertifiedParent` and `transaction_parsers` were explicitly re-audited for net/subnet-boundary gaps (Pitfalls 9, 10), not just carried over unchanged.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|-----------------|
| Address collision across nets (Pitfall 1) | HIGH | Requires an address-format migration (new derivation) or a global uniqueness registry retrofit across all existing accounts — plan this before any subnet ships real value, not after |
| CRDT keyspace collision (Pitfall 2) | MEDIUM | Introduce the shared key-building function and run a one-time migration/audit of existing `/bc-` literals; contained because CRDT data is namespaced by string prefix already, just inconsistently |
| Hardcoded/missed topic namespacing (Pitfall 4) | LOW–MEDIUM | Centralize topic-name construction; roll out with a transition period supporting both old and new topic names (mirrors the existing `GNUS_FULL_NODES_TOPIC_LEGACY` precedent) |
| Single-signer bridge already deployed (Pitfall 5) | HIGH | Requires a bridge protocol upgrade to quorum-based certification and a migration/pause window — far cheaper to design correctly up front than retrofit after real value is bridged |
| Missing dispatch-table entry for new tx type (Pitfall 9) | LOW | Same fix as the historical registration-tx incident: add the `transaction_parsers` entry; cheap once caught, but only caught by testing the full validation path, not unit tests of the tx class alone |

## Pitfall-to-Phase Mapping

| Pitfall | Design-Doc Phase | Verification |
|---------|-------------------|---------------|
| 1. Address collision across nets/subnets | Addressing | Design doc specifies whether address derivation includes net/subnet, or documents the tuple-keying invariant everywhere it must hold |
| 2. CRDT keyspace collision (convention-only prefixing) | Addressing (scheme) + Job isolation & consensus (enforcement) | Design doc specifies one canonical key-building function; no raw `/bc-` literals outside it |
| 3. Global `net_id` singleton blocks multi-net processes | Bridge/gateway | Design doc explicitly states gateway process architecture (two single-net processes vs. refactored net-context parameter) |
| 4. Hardcoded pubsub topic literals, no naming function | PubSub namespacing | Design doc specifies one topic-naming function and enumerates every existing hardcoded topic to migrate |
| 5. Single gateway signer as sole trust anchor | Bridge/gateway | Design doc requires quorum/threshold certification from source validator registry, not single-signer relay |
| 6. Bridge certified against stale registry epoch | Bridge/gateway | Design doc requires epoch/CID binding + currency check on bridge proofs |
| 7. No cross-net atomicity (double-mint/double-spend) | Bridge/gateway | Design doc requires confirmation-depth threshold + mint idempotency key |
| 8. Replay/nonce chains keyed by bare address | Addressing (root cause) + Bridge/gateway (must not assume solved) | Design doc states explicitly whether nonce tracking becomes `(net,subnet,address)`-keyed |
| 9. Unknown-tx-type silent rejection for new bridge tx types | Bridge/gateway | Design doc includes dispatch-table update + regression test as an explicit deliverable checklist item |
| 10. Cross-net reuse of certified-parent signature trapdoor | Job isolation & consensus | Design doc requires net/subnet-match precondition added to `CheckCertifiedParent`/`CheckParentChildAuthority` |

## Sources

- **Primary (HIGH confidence, direct source read):** `SuperGenius/src/account/TransactionManager.cpp`, `TransactionManager.hpp`, `GeniusAccount.cpp`, `blockchain/impl/Blockchain.cpp`, `blockchain/Blockchain.hpp`, `blockchain/ValidatorRegistry.cpp/.hpp`, `base/sgns_version.hpp`, `account/RevokeTransaction.hpp` — read directly from the `dev_childwallet` branch during this research pass.
- **Project history (HIGH confidence):** `.planning/PROJECT.md` — documents the actual historical registration-dispatch-table gap (Pitfall 9's precedent) and the D-60 certified-signature trapdoor scoping (Pitfall 10's root cause).
- **Cross-chain bridge attack patterns (MEDIUM confidence, cross-verified across multiple industry sources):**
  - [Blockchain Cross-Chain Bridge Security: Challenges, Solutions, and Future Outlook — ACM DLT Research and Practice](https://dl.acm.org/doi/10.1145/3696429)
  - [What are Cross-Chain Bridge Attacks? How To Tackle Them? — ImmuneBytes](https://immunebytes.com/blog/what-are-cross-chain-bridge-attacks-how-to-tackle-them/)
  - [Double-Spending Attacks in Cross-Blockchain Ecosystems — ScienceDirect](https://www.sciencedirect.com/science/article/pii/S2096720925001058)
  - [What Is a Replay Attack? Definition & Prevention Guide — Gate Glossary](https://www.gate.com/learn/glossary/replay-attack)
  - [Cybersecurity Risks of Cross-Chain Interoperability Explained — Built In](https://builtin.com/articles/cybersecurity-risks-cross-chain-interoperability)
- **libp2p gossipsub topic mechanics (MEDIUM confidence, protocol spec — no project-specific multi-tenant isolation guidance found):**
  - [libp2p gossipsub spec — libp2p/specs](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.0.md)

---
*Pitfalls research for: GNUS Subnets (addressing, pubsub namespacing, bridge/gateway, job isolation & consensus)*
*Researched: 2026-07-24*
