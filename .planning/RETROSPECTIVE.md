# Retrospective: GNUS Child Wallet Design

## Milestone: v1.0 — Child Wallet Design

**Shipped:** 2026-07-15
**Phases:** 3 | **Plans:** 6

### What Was Built

- Child-wallet identity model design (independent secp256k1 keypair, emergent identity, nonce isolation, address-based UTXO ownership) — `docs/child-wallet-identity-model.md`
- Registration protocol design (RegistrationTx proto schema, child-signed-only protocol, dual-counter sequence numbering, backward-compat matrix) — `docs/registration-protocol.md`
- CRDT registry & pubsub design (reg/ namespace, four-gate FilterRegistration, CID-only broadcast, certified-status two-tier model) — `docs/02-crdt-registry-pubsub.md`
- Parent-child consensus authority design (CheckParentChildAuthority gate, 6 CONS rules) — `docs/02-consensus-parent-child-authority.md`
- Discovery & monitoring design (push-primary/poll-fallback via AccountMessenger) — `docs/03-01-discovery-monitoring.md`
- Reward policy & lifecycle design (dual-source policy resolution, hold-time pinning, 4-state lifecycle, supersedes-sequence conflict resolution) — `docs/03-02-reward-policy-lifecycle.md`

### What Worked

- Grounding every design decision in concrete file:line anchor points made verification objective (11/11 truths verified in Phase 2)
- Reusing existing SuperGenius machinery (AccountMessenger, escrow immutability, CRDT filters) instead of inventing new infrastructure kept designs additive
- Decision log (D-01..D-37) carried across phases prevented re-litigating settled questions

### What Was Inefficient

- REQUIREMENTS.md traceability for Phase 2 (CONS/SYNC) was left stale at Pending despite passed verification — caught at milestone close
- Phase 03 code review flagged a critical child-address proto field mapping finding that remained advisory-open at close (carried into v2.0 implementation)

### Patterns Established

- Child-ness is emergent from consensus-visible registration records — no schema flags on accounts
- Registration is child-signed-only; main key never enters child process
- Two-tier trust: CRDT optimistic, consensus certified; act only on certified state

### Key Lessons

- Design-doc milestones benefit from the same verification rigor as code — anchor points + traceability tables made review tractable
- Update requirement checkboxes at phase transition, not milestone close

### Cost Observations

- Sessions: 3 phase cycles over 2 days
- Notable: coarse granularity (3 phases, 2 plans each) fit a docs-only milestone well

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Notes |
|-----------|--------|-------|----------|-------|
| v1.0 Child Wallet Design | 3 | 6 | 2 days | Design docs only |
