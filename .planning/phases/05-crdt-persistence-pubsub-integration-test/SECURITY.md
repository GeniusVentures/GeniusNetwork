## SECURED

**Phase:** 05 — crdt-persistence-pubsub-integration-test
**Threats Closed:** 19/19
**ASVS Level:** L1

### Audit Date
2026-07-16

### Config
- `block_on`: high
- `asvs_level`: L1

### Threat Verification

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-05-01 | Spoofing | mitigate | **CLOSED** — Gate (b): `TransactionManager.cpp:2852-2857` (`CheckTransactionAuthorization`); Gate (d): `TransactionManager.cpp:2866-2895` (zero-sequence + monotonicity via `globaldb_m->Get(reg_key)`) |
| T-05-02 | Tampering | mitigate | **CLOSED** — Gate (a): `TransactionManager.cpp:2834-2840` (`DeSerializeTransaction` + error log); Gate (b): `TransactionManager.cpp:2852-2857` (`CheckTransactionAuthorization`) |
| T-05-03 | Repudiation | accept | **CLOSED** — Accepted: child-only signature per design D-04/D-05. Confirmed at `TransactionManager.cpp:600-604` (only `account_m` signs, no main-wallet counter-signature) |
| T-05-04 | Information Disclosure | accept | **CLOSED** — Accepted: no secrets in reg/. `RegistrationDiscoveryEntry` struct (`TransactionManager.hpp:45-51`) and `RegistrationTx` proto contain only public addresses + metadata |
| T-05-05 | Denial of Service | mitigate | **CLOSED** — Single `globaldb_m->Get(reg_key)` per invocation at `TransactionManager.cpp:2873-2874`; zero-sequence rejection at :2868-2871; non-monotonic rejection at :2884-2892 |
| T-05-06 | Elevation of Privilege | mitigate | **CLOSED** — Gate (c): `TransactionManager.cpp:2860-2864` (`reg_tx->GetMainAddress().size() != 128` hex-check) |
| T-05-07 | Spoofing | mitigate | **CLOSED** — `GetRegistrationsForMain` (`TransactionManager.cpp:4983-5030`) reads from CRDT namespace gated by `FilterRegistration` (registered at :222-233). Results reflect only filter-validated registrations |
| T-05-08 | Tampering | mitigate | **CLOSED** — Deserialization failure skip: `TransactionManager.cpp:5000-5002`; type check skip: :5006-5009; null cast skip: :5011-5014 |
| T-05-09 | Information Disclosure | accept | **CLOSED** — Accepted: `RegistrationDiscoveryEntry` (`TransactionManager.hpp:45-51`) contains only public fields (child_addr, main_addr, sequence, metadata) |
| T-05-10 | Denial of Service | mitigate | **CLOSED** — `RegElementCallback` (`TransactionManager.cpp:3245-3267`) fires only for elements already passing `FilterRegistration` (callback registered at :245-254). Spam-follow requires valid keypairs |
| T-05-11 | Elevation of Privilege | accept | **CLOSED** — Accepted: v2.0 scope per ROADMAP. `RegElementCallback` (`TransactionManager.cpp:3259-3266`) matches on `main_address` only — no `CheckParentChildAuthority` call |
| T-05-12 | Spoofing | accept | **CLOSED** — Accepted: test-only deterministic keys. `child_registration.cpp:179-194` generates keys from `self_address` hash via `std::mt19937` |
| T-05-13 | Tampering | accept | **CLOSED** — Accepted: test-constructed protobuf bytes exercise filter rejection. Verified at `child_registration.cpp:301-332` (sub-case A tampering) |
| T-05-14 | Information Disclosure | accept | **CLOSED** — Accepted: isolated test storage. `FILE_PREFIX = "cri_"` at :105; paths under `boost::dll::program_location()` at :167; `remove_all` at :172; `TearDownTestSuite` cleanup at :140-146 |
| T-05-15 | Denial of Service | accept | **CLOSED** — Accepted: bounded 180s timeout. `child_registration.cpp:121, 129, 137` all use `std::chrono::milliseconds(180000)` |
| T-05-16 | Elevation of Privilege | accept | **CLOSED** — Accepted: `friend class RegTestAccess;` at `TransactionManager.hpp:319` defined only in `child_registration.cpp:64-73` (test TU, never linked into production) |
| T-05-17 | Elevation of Privilege | accept | **CLOSED** — Accepted: `friend class ChildRegTestAccess;` at `GeniusNode.hpp:741` defined only in `child_registration.cpp:80-95`. Follows existing `MultiAccountTestAccess` pattern (:740). Production binaries have no `ChildRegTestAccess` definition |
| T-05-18 | Tampering | mitigate | **CLOSED** — Proto-level DAG signature tampering in both tests: `registration_transaction_test.cpp:378,493` (`mutable_dag_struct()->signature()` modification + `SerializeToArray`); `child_registration.cpp:315` (same pattern). Zero remaining byte-offset tampering |
| T-05-SC | Tampering | accept | **CLOSED** — Accepted: no package manager operations. All changes are C++ source files; no `package.json`, `requirements.txt`, or `Cargo.toml` modified |

### Unregistered Flags
None — all implementation artifacts are mapped to existing threats. SUMMARY 05-04 confirms: "Threat Flags: None — friend declarations are additive, compile-time-only access grants."

### Implementation Evidence Summary

**FilterRegistration gates a-d** (`TransactionManager.cpp:2827-2906`):
- Gate (a) — deserialization failure rejection (:2834-2840)
- Gate (b) — invalid signature rejection (`CheckTransactionAuthorization` at :2852-2857)
- Gate (c) — malformed main_address (not 128 hex) rejection (:2860-2864)
- Gate (d) — zero sequence rejection (:2868-2871) + non-monotonic rejection via CRDT Get (:2873-2895)

**SendTransactionItem hardening** (`TransactionManager.cpp:1261-1285`):
- Null-check after `dynamic_pointer_cast<RegistrationTransaction>` (:1263-1268)
- `SerializeByteVector` empty check (:1280-1285)

**RegisterChild auto-derive** (`TransactionManager.cpp:607-638`):
- 2-arg overload reads `reg/{child_addr}` from CRDT, delegates to 3-arg with computed sequence

**GetRegistrationsForMain** (`TransactionManager.cpp:4983-5030`):
- `QueryKeyValues` scan across monitored networks, deserialize + type-check + cast + main_address filter, return `vector<RegistrationDiscoveryEntry>`

**RegElementCallback** (`TransactionManager.cpp:3245-3267`):
- Registered for `reg/` pattern (:245-254), deserializes + type-checks + casts, calls `AddListenTopic(child_addr)` when `main_address` matches local account

**Destructor cleanup** (`TransactionManager.cpp:321-322`):
- `UnregisterNewElementCallback` + `UnregisterElementFilter` for `reg/` pattern

**Test integrity** (`child_registration.cpp`, `registration_transaction_test.cpp`):
- Proto-level DAG signature tampering in both files (no raw byte-offset)
- `friend` declarations for `RegTestAccess` and `ChildRegTestAccess` present in production headers, accessor classes defined only in test TUs
- Test fixture with isolated `cri_`-prefixed storage, cleaned up in TearDown
