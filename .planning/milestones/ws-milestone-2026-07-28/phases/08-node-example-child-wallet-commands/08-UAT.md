---
status: complete
phase: 08-node-example-child-wallet-commands
source: [08-VERIFICATION.md]
started: 2026-07-28T00:05:00Z
updated: 2026-07-28T00:15:00Z
---

[testing complete]

## Tests

### 1. registerchild + listchildren round-trip (Success Criterion 1)
expected: With `node_example` built and running in `--terminal` mode, pick a 128-hex-character placeholder address and run `registerchild <that_address>`, then immediately run `listchildren <that_address>`. `registerchild` logs a success message containing a transaction hash (not an error). `listchildren` run right after shows this node's own account address registered under that main address, together with a balance. (Why human: full CRDT registration + local discovery round-trip requires a live running `GeniusNode` instance — cannot be confirmed by grep or a clean compile alone.)
result: pass

### 2. listchildren shows address + balance (Success Criterion 2)
expected: With `node_example` running in `--terminal` mode, first run `registerchild <main_address>`, then run `listchildren <main_address>`. Output includes this node's own account address together with a raw balance number on the same line — not the address alone. (Why human: requires a real local CRDT `reg/` write followed by a real CRDT read-back — cannot be confirmed by grep or a clean compile alone.)
result: pass

### 3. childbalance with no token_id (Success Criterion 3)
expected: At the REPL, run `childbalance <any-address>` with no `token_id`. Prints a single raw all-tokens balance number. (Why human: requires a live `GeniusNode` process reading real CRDT-backed UTXO state.)
result: pass

### 4. childbalance with token_id, valid and invalid (Success Criterion 4)
expected: At the REPL, run `childbalance <any-address> <64-hex-digit-token-id>`; then run `childbalance <any-address> not-valid-hex`. Valid-hex form prints a single raw per-token balance number. Invalid-hex form logs "Invalid token_id: 'not-valid-hex' — must be 64 hex digits (optionally 0x-prefixed)." and does not crash the REPL. (Why human: requires a live `GeniusNode` process reading real CRDT-backed UTXO state.)
result: pass

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
