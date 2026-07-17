---
phase: 4
slug: registration-proto-transaction
status: verified
threats_open: 0
asvs_level: 1
created: 2026-07-16
---

# Phase 4 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| proto bytes → ParseFromArray | Untrusted deserialization input crosses here | Serialized RegistrationTx protobuf bytes |
| CRDT delta → FilterRegistration | Untrusted peer can push any bytes into the reg/ namespace | Arbitrary peer-supplied CRDT element values |
| SendTransactionItem → CRDT Put | Local node writes RegistrationTx to reg/{child_addr} — key derived from trusted child_addr | Signed RegistrationTx bytes |
| EnqueueTransaction → consensus | RegistrationTx enters sgns.nonce.v1 pipeline; consensus validates signature + nonce | Transaction DAGStruct + signature |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-04-01 | Tampering | DeSerializeByteVector | mitigate | ParseFromArray returns false on malformed proto → return nullptr; caller null-checks (RegistrationTransaction.cpp:86-89) | closed |
| T-04-02 | Denial of Service | DeSerializeByteVector | accept | Proto3 built-in 64MB size limit; leaf deserializer, no recursion/amplification | closed |
| T-04-03 | Information Disclosure | RegistrationTx.main_address | accept | main_address is a public key — public by definition (SGTransaction.proto:149) | closed |
| T-04-04 | Spoofing | FilterRegistration gate (b) — child signature | mitigate | CheckTransactionAuthorization → CheckSignature verifies secp256k1 ECDSA sig against DAGStruct.source_addr; tampered sig → tombstone reject (TransactionManager.cpp:2852-2857, GeniusTransaction.cpp:72-81) | closed |
| T-04-05 | Tampering | FilterRegistration gate (a) — malformed proto bytes | mitigate | DeSerializeTransaction → ParseFromArray failure → error → tombstone reject (TransactionManager.cpp:2834-2840, 2897-2905) | closed |
| T-04-06 | Tampering | FilterRegistration gate (c) — malformed main_address | mitigate | GetMainAddress().size() != 128 → tombstone reject (TransactionManager.cpp:2860-2864) | closed |
| T-04-07 | Repudiation | Child-signed-only registration | accept | Per D-04/D-05: main does not counter-sign; registration grants zero authority; impact bounded to discovery spam (docs/registration-protocol.md §5.3) | closed |
| T-04-08 | Denial of Service | FilterRegistration — crafted bytes exhaust CPU | accept | Proto3 ParseFromArray bounded complexity; CRDT subsystem rate limiting; no amplification vector | closed |
| T-04-09 | Elevation of Privilege | TransactionManager::RegisterChild | accept | READY state enforced at two layers (TransactionManager.cpp:596-599, GeniusNode.cpp:2289-2292); main-wallet authority requires main's signature (deferred to consensus authority milestone) | closed |
| T-04-10 | Information Disclosure | main_address stored in reg/ CRDT | accept | main_address is a public key; reg/ namespace readable by all full nodes (same as tx/) | closed |
| T-04-SC | Tampering | Supply chain (npm/pip/cargo installs) | accept | No new package dependencies; protobuf, Boost, GTest pre-existing | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-04-01 | T-04-02 | Proto3 default 64MB parse limit bounds DoS; leaf deserializer with no recursion | user (secure-phase run) | 2026-07-16 |
| R-04-02 | T-04-03 | main_address is a public key — public information by definition | user (secure-phase run) | 2026-07-16 |
| R-04-03 | T-04-07 | Child-signed-only registration is deliberate design (D-04/D-05); registration grants zero authority | user (secure-phase run) | 2026-07-16 |
| R-04-04 | T-04-08 | Bounded parse complexity + CRDT rate limiting; no amplification vector | user (secure-phase run) | 2026-07-16 |
| R-04-05 | T-04-09 | Child signs its own registration; main-asset authority deferred to consensus authority milestone | user (secure-phase run) | 2026-07-16 |
| R-04-06 | T-04-10 | reg/ namespace visibility matches existing tx/ namespace; contains only public keys | user (secure-phase run) | 2026-07-16 |
| R-04-07 | T-04-SC | No new dependencies introduced in this phase | user (secure-phase run) | 2026-07-16 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-07-16 | 11 | 11 | 0 | gsd-security-auditor |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-07-16
