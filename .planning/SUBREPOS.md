# Submodule Planning Directory Map

Maps each submodule to its `.planning/` directory. When working on a submodule, read this file first to find where planning artifacts live.

**Rule:** If a submodule has its own `.planning/`, write planning artifacts there. If it does not, artifacts go in the root `.planning/` or the submodule needs `.planning/` initialized via `/gsd:new-project` or `/gsd:ingest-docs`.

---

## Top-Level Submodules

| Submodule Path | Planning Directory | Has .planning/ | Primary Language | Notes |
|---|---|---|---|---|
| `GeniusCogntiveSystem/` | `GeniusCogntiveSystem/.planning/` | yes | C++ | Cognitive system; has STATE.md, workstreams |
| `GeniusSDK/` | `GeniusSDK/.planning/` | yes | C++ | SDK wrapping SuperGenius; has codebase/, notes/, seeds/, todos/ |
| `GeniusWallet/` | `GeniusWallet/.planning/` | yes | Dart/Flutter | Cross-platform wallet; has SUBREPOS.md (banxa, squidrouter) |
| `SuperGenius/` | `SuperGenius/.planning/` | yes | C++ | Core blockchain node; fully populated (PROJECT.md, ROADMAP.md, phases/, quick/, codebase/) |
| `TestVMs/` | `.planning/` (root) | no | Vagrant/PowerShell | Integration test VMs; infrastructure-only, unlikely to have independent workstreams |
| `TokenContracts/` | `TokenContracts/.planning/` | yes | Solidity/TypeScript | Smart contracts; has codebase/, workstreams |
| `thirdparty/` | `thirdparty/.planning/` | yes | CMake/C++ | Build orchestrator for 48+ C++ dependencies; has SUBREPOS.md with GeniusVentures-owned vs external breakdown |
| `zkLLVM/` | `zkLLVM/.planning/` | yes | C++ | ZK circuit compiler; has SUBREPOS.md with full crypto3 suite, build libs, and marshalling breakdown |
| `wallet-assets/` | `.planning/` (root) | no | Assets/JSON | Wallet branding/resources; assets-only, unlikely to have independent workstreams |

## Important Nested Submodules

These submodules live inside top-level submodules and have their own source code. See each submodule's `SUBREPOS.md` for the complete nested map:

| Submodule | Full Map |
|---|---|
| `SuperGenius/` | [`SuperGenius/.planning/SUBREPOS.md`](../SuperGenius/.planning/SUBREPOS.md) — 6 nested (GeniusKDF, ProofSystem, SGProcessingManager, evmrelay, gRPCForSuperGenius, docs) |
| `GeniusWallet/` | [`GeniusWallet/.planning/SUBREPOS.md`](../GeniusWallet/.planning/SUBREPOS.md) — 2 nested (banxa, squidrouter, both auto-generated) |
| `GeniusCogntiveSystem/` | [`GeniusCogntiveSystem/.planning/SUBREPOS.md`](../GeniusCogntiveSystem/.planning/SUBREPOS.md) — 1 nested (GNUS-NEO-SWARM with GQHSM) |
| `TokenContracts/` | [`TokenContracts/.planning/SUBREPOS.md`](../TokenContracts/.planning/SUBREPOS.md) — 5 nested (ZoKrates, erc20-gnus-proxy, gnus-ai, sushi-assets, etc.) |
| `thirdparty/` | [`thirdparty/.planning/SUBREPOS.md`](../thirdparty/.planning/SUBREPOS.md) — 20 GeniusVentures-owned + 27 external pinned dependencies |
| `zkLLVM/` | [`zkLLVM/.planning/SUBREPOS.md`](../zkLLVM/.planning/SUBREPOS.md) — 30+ nested (crypto3 suite, assigner, blueprint, circifier, stdlib, transpiler, marshalling) |

---

## Rules

1. **Before any work**, read this file to determine which `.planning/` directory owns the workstream.
2. **Never write planning artifacts to the root `.planning/`** for a submodule that has its own `.planning/`.
3. **When a submodule lacks `.planning/`** and needs a workstream, initialize it with `/gsd:new-project` inside that submodule, or track it in the root `.planning/` if the workstream spans multiple submodules.
4. **Nested submodules** (e.g., `SuperGenius/ProofSystem/`) use their parent's `.planning/` unless they have their own.

---

*Generated: 2026-07-06*
