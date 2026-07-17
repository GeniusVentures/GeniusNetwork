# Security Audit — Phase 4: registration-proto-transaction

**Audit Date:** 2026-07-16
**ASVS Level:** default
**Result:** SECURED — 11/11 threats verified, 0 open

---

## Threat Verification

### Mitigated Threats (verified in code)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-04-01 | Tampering | mitigate | `RegistrationTransaction.cpp:86-89` — `ParseFromArray` returns false on malformed proto → `return nullptr`. Follows TransferTransaction pattern. |
| T-04-04 | Spoofing | mitigate | `TransactionManager.cpp:2852-2857` — `FilterRegistration` calls `CheckTransactionAuthorization(*reg_tx)` which calls `CheckSignature()` (`GeniusTransaction.cpp:72-81`) verifying ECDSA sig against `dag_st.source_addr`. |
| T-04-05 | Tampering | mitigate | `TransactionManager.cpp:2834-2840` — `DeSerializeTransaction(element.value())` fails on malformed proto (ParseFromArray → nullptr) → `break` → `should_delete = true` → tombstone reject. |
| T-04-06 | Tampering | mitigate | `TransactionManager.cpp:2860-2864` — `reg_tx->GetMainAddress().size() != 128` → `break` → tombstone reject. Prevents non-address garbage in reg/ namespace. |

### Accepted Risks (documented)

| Threat ID | Category | Disposition | Rationale |
|-----------|----------|-------------|-----------|
| T-04-02 | Denial of Service | accept | Proto3 has built-in size limits (default 64MB). Oversized RegistrationTx bytes fail ParseFromArray. Leaf deserializer — no recursion / amplification vector. |
| T-04-03 | Information Disclosure | accept | `main_address` is a public key (stored as proto `bytes` — `SGTransaction.proto:149`). Proto wire format is unencrypted, same as all existing tx types. Public information by definition. |
| T-04-07 | Repudiation | accept | Per D-04/D-05: any child can claim any main; main does NOT counter-sign. Deliberate design — registration grants zero authority. Impact bounded to discovery spam (`docs/registration-protocol.md §5.3`). |
| T-04-08 | Denial of Service | accept | Proto3 `ParseFromArray` has bounded complexity. FilterRegistration is a synchronous callback in the CRDT delta processing path — CRDT subsystem has its own rate limiting. No amplification vector (single element → single deserialization, no recursion). |
| T-04-09 | Elevation of Privilege | accept | `TransactionManager.cpp:596-599` — `RegisterChild` requires `State::READY`. Child signs its own registration; authority over main assets requires main's signature (deferred to consensus authority milestone). |
| T-04-10 | Information Disclosure | accept | `main_address` is a public key. reg/ namespace readable by all full nodes (same as tx/ namespace). Public information by definition. |
| T-04-SC | Tampering | accept | No new package dependencies. Proto compiler, C++ toolchain, protobuf, Boost, GTest — all pre-existing. |

---

## Unregistered Flags

None — no `## Threat Flags` reported in 04-01-SUMMARY.md or 04-02-SUMMARY.md.

---

## Files Audited

| File | Purpose |
|------|---------|
| `SuperGenius/src/account/RegistrationTransaction.hpp` | Class declaration — New(), DeSerializeByteVector, GetMainAddress |
| `SuperGenius/src/account/RegistrationTransaction.cpp` | ParseFromArray null-return on failure, serialization, deserialization |
| `SuperGenius/src/account/TransactionManager.cpp` | FilterRegistration gates (a)(b)(c), RegisterChild READY check, CRDT reg/ diversion, CheckTransactionAuthorization, DeSerializeEmbeddedTransaction kRegistration dispatch |
| `SuperGenius/src/account/TransactionManager.hpp` | FilterRegistration, RegisterChild declarations |
| `SuperGenius/src/account/GeniusNode.cpp` | RegisterChild thin-wrapper with READY state check |
| `SuperGenius/src/account/GeniusTransaction.cpp` | CheckSignature — ECDSA verification against dag_st.source_addr |
| `SuperGenius/src/account/proto/SGTransaction.proto` | RegistrationTx main_address as `bytes main_address = 2` |
| `SuperGenius/test/src/account/registration_transaction_test.cpp` | GTest cases: TamperedSignatureRejected, FilterRegistrationAcceptsValid, FilterRegistrationRejectsBadMainAddress, FilterRegistrationRejectsTamperedSignature, FilterRegistrationRejectsZeroSequence, FilterRegistrationRejectsNonMonotonicSequence |

---

## Audit Summary

- **Total Threats:** 11
- **Mitigated & Verified:** 4 (T-04-01, T-04-04, T-04-05, T-04-06)
- **Accepted & Documented:** 7 (T-04-02, T-04-03, T-04-07, T-04-08, T-04-09, T-04-10, T-04-SC)
- **Transfer:** 0
- **Open:** 0
- **Unregistered Flags:** 0

All declared mitigations are present in the implemented code with file:line evidence. Every `mitigate` threat's mitigation pattern was found at the expected location. Every `accept` threat's rationale holds against the implementation.
