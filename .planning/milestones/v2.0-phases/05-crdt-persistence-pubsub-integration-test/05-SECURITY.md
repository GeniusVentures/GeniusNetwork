---
phase: 5
slug: crdt-persistence-pubsub-integration-test
status: verified
threats_open: 0
asvs_level: 1
created: 2026-07-16
---

# Phase 5 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| CRDT merge path → FilterRegistration | Untrusted reg/ deltas from peer nodes enter the element filter callback | Serialized RegistrationTx protobuf (untrusted) |
| SendTransactionItem → CRDT write | Locally signed RegistrationTx bytes pass through serialization before CRDT commit | Signed registration record (trusted, local) |
| CRDT reg/ scan → caller | GetRegistrationsForMain reads CRDT (data from any peer) and returns discovery entries | Public addresses + metadata |
| reg/ NewElementCallback → AddListenTopic | CID handler trusts filter-accepted element's main_address to follow child channel | Child address (filter-validated) |
| Test fixture → GeniusNode::New() | Tests create nodes with deterministic keys and isolated file storage | Test-only keys/data |
| Test translation units → Production headers | `friend` declarations grant test-only compile-time access to protected members | None at runtime (compile-time only) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-05-01 | Spoofing | reg/ CRDT element | mitigate | Gate (b) child signature check (TransactionManager.cpp:2852-2857); gate (d) zero-seq + sequence monotonicity via CRDT Get (TransactionManager.cpp:2866-2895) | closed |
| T-05-02 | Tampering | CRDT element value | mitigate | Gate (a) deserialization rejects malformed protobuf (TransactionManager.cpp:2834-2840); gate (b) signature verification (TransactionManager.cpp:2852-2857) | closed |
| T-05-03 | Repudiation | RegistrationTx submission | accept | Child-only signature provides non-repudiation; main node does not sign by design (TransactionManager.cpp:600-604) | closed |
| T-05-04 | Information Disclosure | reg/ CRDT storage | accept | Only public addresses/metadata stored; RegistrationDiscoveryEntry has no secrets (TransactionManager.hpp:45-51) | closed |
| T-05-05 | Denial of Service | FilterRegistration gate (d) CRDT read | mitigate | Single Get per filter invocation; rejects zero/non-monotonic sequences (TransactionManager.cpp:2868-2892) | closed |
| T-05-06 | Elevation of Privilege | Registration claiming arbitrary main_address | mitigate | Gate (c) 128-hex main_address format validation (TransactionManager.cpp:2860-2864); consensus authority gate deferred per ROADMAP (see AR-05-02) | closed |
| T-05-07 | Spoofing | GetRegistrationsForMain results | mitigate | CRDT scan gated by FilterRegistration signature + sequence checks (TransactionManager.cpp:4983-5030, 222-233) | closed |
| T-05-08 | Tampering | reg/ value during CRDT scan | mitigate | Deserialize fail / type check / null dynamic_pointer_cast skip corrupted entries (TransactionManager.cpp:5000-5014) | closed |
| T-05-09 | Information Disclosure | GetRegistrationsForMain output | accept | Discovery entries contain only public addresses + metadata (TransactionManager.hpp:45-51) | closed |
| T-05-10 | Denial of Service | AddListenTopic following bogus children | mitigate | Callback fires only for filter-validated elements; spam-follow requires expensive valid keypairs (TransactionManager.cpp:3245-3267, 245-254) | closed |
| T-05-11 | Elevation of Privilege | RegElementCallback → AddListenTopic without authority check | accept | Consensus authority gate (CheckParentChildAuthority) deferred — v2.0 out of scope (TransactionManager.cpp:3259-3266; see AR-05-03) | closed |
| T-05-12 | Spoofing | Test-signed transactions in TEST-04 | accept | Deterministic test keys only; no production keys (child_registration.cpp:179-194) | closed |
| T-05-13 | Tampering | CRDT element bytes constructed in test | accept | Test-constructed bytes exercise filter rejection logic only (child_registration.cpp:301-332) | closed |
| T-05-14 | Information Disclosure | Test node file storage | accept | `cri_` prefix + remove_all in TearDown/Suite cleanup (child_registration.cpp:105, 140-146, 167, 172) | closed |
| T-05-15 | Denial of Service | 180s boot timeout | accept | Bounded timeout; shared fixture amortizes boot cost (child_registration.cpp:121, 129, 137) | closed |
| T-05-16 | Elevation of Privilege | `friend class RegTestAccess` (TransactionManager.hpp:319) | accept | Friend class defined only in test TU, never linked into production (child_registration.cpp:64-73) | closed |
| T-05-17 | Elevation of Privilege | `friend class ChildRegTestAccess` (GeniusNode.hpp:741) | accept | Same rationale; matches existing MultiAccountTestAccess pattern (child_registration.cpp:80-95) | closed |
| T-05-18 | Tampering | Proto-level signature tampering in tests (WR-02/WR-03 fix) | mitigate | Deterministic proto-level DAG signature mutation via mutable_dag_struct(); ASSERT catches re-serialization failure (registration_transaction_test.cpp:378, 493; child_registration.cpp:315) | closed |
| T-05-SC | Tampering | Supply chain (npm/pip/cargo installs) | accept | No package manager operations this phase — C++ source only, no new dependencies | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*
*Note: Plan 05-04 originally reused IDs T-05-01..03; renumbered here as T-05-16..18.*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-05-01 | T-05-03 | Child-only signature is the designed non-repudiation model (D-04/D-05); main node counter-signature intentionally absent | Phase 5 plan (05-01) | 2026-07-16 |
| AR-05-02 | T-05-06 | Consensus parent-child authority gate (CheckParentChildAuthority) deferred to later milestone per ROADMAP; gate (c) format validation is the v2.0 control | Phase 5 plan (05-01) | 2026-07-16 |
| AR-05-03 | T-05-11 | Any filter-validated registration triggers AddListenTopic follow; authority gate deferred — documented v2.0 out-of-scope per ROADMAP/REQUIREMENTS | Phase 5 plan (05-02) | 2026-07-16 |
| AR-05-04 | T-05-04, T-05-09 | reg/ records and discovery entries contain only public addresses and metadata; no secrets by construction | Phase 5 plans (05-01, 05-02) | 2026-07-16 |
| AR-05-05 | T-05-12, T-05-13, T-05-14, T-05-15 | Test-infrastructure risks: deterministic test keys, test-constructed rejection payloads, isolated `cri_`-prefixed storage with cleanup, bounded 180s boot timeout | Phase 5 plan (05-03) | 2026-07-16 |
| AR-05-06 | T-05-16, T-05-17 | Friend declarations are compile-time-only grants; friend classes exist solely in test translation units never linked into production binaries — inert at runtime | Phase 5 plan (05-04) | 2026-07-16 |
| AR-05-07 | T-05-SC | No package-manager operations in this phase; no new dependencies introduced | Phase 5 plan (05-04) | 2026-07-16 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-07-16 | 19 | 19 | 0 | gsd-security-auditor |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-07-16
