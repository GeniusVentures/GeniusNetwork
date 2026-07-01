# Architecture

**Analysis Date:** 2026-07-01

## System Overview

Genius Network is a monorepo (parent repo with Git submodules) implementing a decentralized AI/ML processing blockchain ecosystem. It consists of a block-lattice cryptocurrency (**SuperGenius**), a zero-knowledge proof pipeline (**zkLLVM**), Ethereum token contracts (**TokenContracts**), a cross-platform C++ SDK (**GeniusSDK**), and a Flutter wallet app (**GeniusWallet**).

```text
┌──────────────────────────────────────────────────────────────────────┐
│                        GeniusWallet (Dart/Flutter)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐ │
│  │  BLoC    │  │  Banxa   │  │ Squid    │  │  WalletKit (reown)   │ │
│  │  State   │  │  Fiat    │  │ Router   │  │  Wallet Connect      │ │
│  │  Mgmt    │  │  On-Ramp │  │  Swaps   │  │                      │ │
│  └────┬─────┘  └──────────┘  └──────────┘  └──────────────────────┘ │
│       │  Dart FFI / gRPC                                             │
├───────┼───────────────────────────────────────────────────────────────┤
│       ▼                                                              │
│  ┌──────────────────────────┐                                        │
│  │       GeniusSDK (C++)    │  ── Static / Shared / Framework lib    │
│  │  Wraps SuperGenius node  │                                        │
│  └───────────┬──────────────┘                                        │
│              │ links                                                  │
├──────────────┼───────────────────────────────────────────────────────┤
│              ▼                                                       │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                 SuperGenius (C++17)                            │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │   │
│  │  │ Account  │ │Blockchain│ │Processing│ │   CRDT / Store   │ │   │
│  │  │  (UTXO)  │ │(Nano B-L)│ │ (AI/ML)  │ │   (IPFS/Rocks)   │ │   │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────────┬─────────┘ │   │
│  │       │            │            │                │           │   │
│  │  ┌────┴────────────┴────────────┴────────────────┴──────────┐ │   │
│  │  │              Proof System + zkLLVM                       │ │   │
│  │  │  Circuits → Assigner → Prover → RecursiveTransferProof  │ │   │
│  │  └──────────────────────────────────────────────────────────┘ │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────────────────┐  │   │
│  │  │  Crypto  │ │ gRPC API │ │ SGProcessingManager / EVM    │  │   │
│  │  │ (hasher) │ │ (Proto)  │ │ Relay / GeniusKDF            │  │   │
│  │  └──────────┘ └──────────┘ └──────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────────┘   │
│              │ links (depends)                                        │
│  ┌───────────┴─────────────────────────────────────────────────────┐ │
│  │  thirdparty (48 C++ libs): Boost, gRPC, libp2p, IPFS, RocksDB  │ │
│  │  OpenSSL, CryptoPP, MNN (ML), wallet-core, GTest, spdlog, ...   │ │
│  └─────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────┐  ┌─────────────────────────────────────┐ │
│  │  zkLLVM (C++)         │  │  TokenContracts (Solidity / TS)     │ │
│  │  C++/Rust → Circuit   │  │  gnus-token (ICO/ERC-20)           │ │
│  │  assigner/prover/circ │  │  gnus-ai (Escrow / AI Payments)    │ │
│  │  transpiler           │  │  ZoKrates (ZK on-chain verifiers)  │ │
│  └───────────────────────┘  └─────────────────────────────────────┘ │
│                                                                      │
│  util/ (Python install scripts)     TestVMs/ (Vagrant VMs)           │
└──────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| SuperGenius | Core blockchain node: account ledger, consensus, AI processing, proof generation, CRDT storage, gRPC API | `SuperGenius/src/` |
| GeniusSDK | Embeddable C++ library wrapping SuperGenius for game/app developers | `GeniusSDK/src/` |
| GeniusWallet | Cross-platform Flutter wallet with fiat on-ramp, token swaps, WalletConnect | `GeniusWallet/lib/` |
| zkLLVM | Zero-knowledge circuit compiler (C++/Rust → algebraic circuits) | `zkLLVM/libs/` |
| TokenContracts | Ethereum smart contracts: GNUS ICO, AI escrow, SGNUS bridge | `TokenContracts/gnus-token/`, `TokenContracts/gnus-ai/` |
| ProofSystem | SuperGenius ZK proof circuits and verifier | `SuperGenius/ProofSystem/` |
| SGProcessingManager | Processing job schema, generated gRPC stubs, processing-dapp logic | `SuperGenius/SGProcessingManager/` |
| gRPCForSuperGenius | Proto definitions and generated code for SuperGenius gRPC API | `SuperGenius/gRPCForSuperGenius/` |
| GeniusKDF | Key derivation function library | `SuperGenius/GeniusKDF/` |
| EVM Relay | Ethereum Virtual Machine relay bridge | `SuperGenius/evmrelay/` |
| thirdparty | Build orchestrator for 48 C++ dependency libraries | `thirdparty/build/` |
| util | Utility scripts for dependency installation | `util/` |
| TestVMs | Vagrant test virtual machines | `TestVMs/` |

## Pattern Overview

**Overall:** Monorepo with Git Submodules

**Key Characteristics:**
- Each top-level directory (except `util`) is a separate Git submodule with its own build system
- SuperGenius uses a **layered architecture** within `src/`: each subdirectory is a self-contained module with public headers, implementation, and CMake build
- GeniusWallet uses the **BLoC (Business Logic Component)** pattern for state management with `flutter_bloc`
- Protocol Buffers define serialization contracts between components (`.proto` files in each module's `proto/` dir)
- CMake is the universal build system across all C++ components
- Cross-platform compilation to Linux, macOS, Windows, iOS, Android
- CRDT (Conflict-free Replicated Data Types) for distributed consensus-free state synchronization over IPFS

## Layers

**Blockchain Layer (SuperGenius):**
- Purpose: Core decentralized ledger, consensus, and transaction processing
- Location: `SuperGenius/src/`
- Contains: Account/UTXO management, block-lattice consensus, transaction types (Transfer, Mint, Processing, Escrow), blockchain state, validator registry
- Depends on: Crypto layer, Storage layer, Proto definitions
- Used by: GeniusSDK, gRPC API

**Processing Layer:**
- Purpose: Decentralized AI/ML job submission, task splitting, worker assignment, result validation
- Location: `SuperGenius/src/processing/`
- Contains: Processing engine, task queue, subtask enqueuer, validation core, task split, processing node/service
- Depends on: Account layer (for ProcessingTransaction), Proof system (for work verification), CRDT (for distributed state), gRPC
- Used by: SGProcessingManager, GeniusWallet (via SDK)

**Proof Layer:**
- Purpose: Zero-knowledge proof generation and verification for AI/ML work
- Location: `SuperGenius/src/proof/`, `SuperGenius/ProofSystem/`, `zkLLVM/`
- Contains: GeniusProver, GeniusAssigner, TransferProof, RecursiveTransferProof, ProcessingProof, ZK circuits
- Depends on: zkLLVM, Crypto layer, NilFoundation crypto3
- Used by: Processing layer, TokenContracts (via ZoKrates/on-chain verification)

**Storage / CRDT Layer:**
- Purpose: Distributed, conflict-free replicated state across nodes using IPFS and local RocksDB
- Location: `SuperGenius/src/crdt/`, `SuperGenius/src/storage/`
- Contains: CRDT datastore, DAG syncer, global database, RocksDB face, IPFS pubsub, Graphsync
- Depends on: libp2p, IPFS libraries, RocksDB
- Used by: Account layer, Processing layer, Subscription engine

**Crypto Layer:**
- Purpose: Hashing, signing, key derivation
- Location: `SuperGenius/src/crypto/`
- Contains: Hasher abstraction (sha, keccak, twox), ed25519/sr25519 integration
- Depends on: thirdparty crypto libraries (OpenSSL, CryptoPP, libsecp256k1, ed25519, sr25519-donna), GeniusKDF
- Used by: All layers

**API / Transport Layer:**
- Purpose: gRPC service definitions and client/server stubs
- Location: `SuperGenius/src/api/transport/`, `SuperGenius/gRPCForSuperGenius/`
- Contains: gRPC service implementations, proto definitions, generated stubs
- Depends on: Account layer, Processing layer, gRPC/protobuf from thirdparty
- Used by: GeniusWallet, GeniusSDK, external clients

**SDK Layer (GeniusSDK):**
- Purpose: Embeddable static/shared/framework library wrapping SuperGenius for game developers
- Location: `GeniusSDK/src/`
- Contains: GeniusSDK.h/cpp, service runner, platform-specific build targets
- Depends on: SuperGenius (links `sgns::genius_node`)
- Used by: Game engines, mobile apps, GeniusWallet (via FFI)

**Wallet UI Layer (GeniusWallet):**
- Purpose: Cross-platform user-facing wallet application
- Location: `GeniusWallet/lib/`
- Contains: BLoC state management, screens, navigation, providers, services (CoinGecko, CoinTelegraph), Banxa fiat on-ramp, SquidRouter swaps, WalletKit/Reown
- Depends on: GeniusSDK (via FFI/gRPC), local_secure_storage, genius_api, TokenContracts (on-chain reads)
- Used by: End users

**Smart Contract Layer (TokenContracts):**
- Purpose: On-chain Ethereum token contracts
- Location: `TokenContracts/gnus-token/`, `TokenContracts/gnus-ai/`, `TokenContracts/ZoKrates/`
- Contains: ERC-20 ICO contract, AI escrow/payment-split contract, ZK verifier contracts
- Depends on: OpenZeppelin, Uniswap, ZoKrates
- Used by: SuperGenius (as bridge), end users

## Data Flow

### Primary Path — AI/ML Processing Job

1. **Job Submission** — User submits AI processing job via GeniusWallet (`GeniusWallet/lib/submit_job/`) or gRPC API
2. **Transaction Creation** — ProcessingTransaction created in account layer (`SuperGenius/src/account/ProcessingTransaction.cpp:1`)
3. **Consensus** — Block-lattice consensus validates and orders the transaction (`SuperGenius/src/blockchain/Consensus.cpp:1`)
4. **Task Splitting** — SGProcessingManager splits job into subtasks for worker distribution (`SuperGenius/SGProcessingManager/src/`)
5. **Worker Execution** — Workers receive subtasks, execute AI/ML workload (e.g., MNN inference), produce results
6. **Proof Generation** — Workers generate ZK proof of work via zkLLVM pipeline (`SuperGenius/src/proof/ProcessingProof.cpp:1`)
7. **Validation** — ProcessingValidationCore verifies proof and result correctness (`SuperGenius/src/processing/processing_validation_core.cpp:1`)
8. **Escrow Release** — Upon validation, escrowed tokens are released; payment split (70/20/10) applied
9. **CRDT Sync** — State changes propagate to all nodes via CRDT over IPFS PubSub (`SuperGenius/src/crdt/`)

### Token Bridge Path

1. **On-Chain Purchase** — User sends ETH to gnus-token ICO contract, receives GNUS (`TokenContracts/gnus-token/`)
2. **Conversion** — GNUS tokens converted to off-chain SGNUS via gnus-ai escrow contract (`TokenContracts/gnus-ai/`)
3. **Processing Payment** — SGNUS spent for AI/ML processing; new SGNUS minted as rewards
4. **Wrapped Liquidity** — GNUS/ETH pair on Uniswap for DEX liquidity

### Wallet Data Flow

1. **App Start** — `GeniusWallet/lib/main.dart:1` → Initializes BLoC, providers, local storage, router
2. **Network/Tokens** — `NetworkProvider` + `NetworkTokensProvider` load network config and token lists
3. **Wallet Dashboard** — `wallets/cubit/` manages wallet state; displays balances from SuperGenius node (via FFI/gRPC)
4. **Fiat On-Ramp** — Banxa service layers handle fiat→crypto via Banxa API (`GeniusWallet/lib/banxa/`)
5. **Token Swaps** — SquidRouter integration for cross-chain swaps (`GeniusWallet/lib/squidrouter/`)

**State Management:**
- **GeniusWallet:** BLoC pattern (`flutter_bloc`). AppBloc manages global state; feature-specific cubits (WalletDetailsCubit, PinCubit, BanxaOrderCubit, etc.)
- **SuperGenius:** Singleton pattern via ComponentFactory (`SuperGenius/src/singleton/CComponentFactory.cpp:1`). CRDT datastore holds distributed state.
- **GeniusSDK:** Stateless wrapper; delegates all state to SuperGenius node.

## Key Abstractions

**GeniusAccount:**
- Purpose: Represents a user account holding tokens (UTXO-based)
- Examples: `SuperGenius/src/account/GeniusAccount.cpp`, `SuperGenius/src/account/GeniusNode.cpp`
- Pattern: Block-lattice account chain (each account has its own blockchain)

**ProcessingEngine:**
- Purpose: Orchestrates AI/ML processing jobs: submission, splitting, assignment, validation
- Examples: `SuperGenius/src/processing/processing_engine.cpp`, `SuperGenius/src/processing/processing_node.cpp`
- Pattern: Service/Node pattern with task queue

**CRDT Datastore:**
- Purpose: Conflict-free replicated distributed state over IPFS
- Examples: `SuperGenius/src/crdt/crdt_datastore.hpp`, `SuperGenius/src/crdt/globaldb/`
- Pattern: Delta-state CRDT with DAG sync over IPFS Graphsync

**Proof Pipeline:**
- Purpose: ZK circuit compilation, assignment, proving, verification
- Examples: `SuperGenius/src/proof/GeniusProver.cpp`, `SuperGenius/src/proof/GeniusAssigner.cpp`, `zkLLVM/libs/assigner/`, `zkLLVM/libs/circifier/`
- Pattern: Pipeline: C++ source → LLVM IR → circuit → assigner → proof → verifier

**ComponentFactory (Singleton):**
- Purpose: Central dependency injection / service locator for SuperGenius
- Examples: `SuperGenius/src/singleton/CComponentFactory.cpp`
- Pattern: Singleton registry for all major components

## Entry Points

**SuperGenius Node:**
- Location: `SuperGenius/src/account/GeniusNode.cpp`
- Triggers: Launched as service/daemon or embedded via GeniusSDK
- Responsibilities: Initialize all subsystems, start consensus, listen for gRPC

**GeniusSDK (static/shared lib):**
- Location: `GeniusSDK/src/GeniusSDK.cpp`
- Triggers: Linked into game/application binary
- Responsibilities: Initialize SuperGenius node, expose simplified API

**GeniusWallet (Flutter app):**
- Location: `GeniusWallet/lib/main.dart`
- Triggers: User launches app on mobile/desktop
- Responsibilities: Initialize BLoC, providers, navigation, connect to SuperGenius node

**TokenContracts (deploy scripts):**
- Location: `TokenContracts/gnus-token/truffle-config.js`, `TokenContracts/gnus-ai/`
- Triggers: `truffle migrate` / Hardhat deploy
- Responsibilities: Deploy ICO and AI escrow contracts to Ethereum

**zkLLVM (CLI tools):**
- Location: `zkLLVM/bin/`
- Triggers: Developers invoke `assigner`, `clang` (zkLLVM variant), `transpiler`
- Responsibilities: Compile circuits, generate proofs, transpile to EVM verifiers

**Thirdparty build:**
- Location: `thirdparty/build/{Platform}/CMakeLists.txt`
- Triggers: CMake configure/build before SuperGenius
- Responsibilities: Build all 48 third-party libraries for the target platform

## Architectural Constraints

- **Threading:** SuperGenius uses Boost.Asio for async I/O. libp2p and AsyncIOManager provide async event loops. Mutex/atomic operations required for shared state.
- **Global state:** SuperGenius uses a Singleton `CComponentFactory` (`SuperGenius/src/singleton/CComponentFactory.cpp`) to register and resolve all major components. `watcher/messaging_watcher` handles message bus.
- **Circular imports:** Not detected — modules follow a strict dependency hierarchy. Account depends on Crypto and Storage; Processing depends on Account; Proof depends on Crypto and zkLLVM.
- **Build system:** CMake with platform-specific toolchains. `thirdparty/build/CommonTargets.CMake` orchestrates all dependency builds. `CommonCompilerOptions.cmake` enforces C++17 and shared cache args.
- **Error handling:** Boost.Outcome via `outcome::result<T>` (`SuperGenius/src/outcome/outcome.hpp`). GSL for type safety. Exceptions used per coding standard (`Coding Standards.md`).
- **Serialization:** Protocol Buffers for all wire formats. Proto files in each module's `proto/` dir. Generated via `compile_proto_to_cpp` in `SuperGenius/cmake/functions.cmake:42`.
- **Coding standard:** C++ follows Corelinux-derived style (`Coding Standards.md`). Dart/Flutter follows AGENTS.md guidelines. C++ uses Ullman brace style, PascalCase types, `m_` prefix for members, `a` prefix for arguments.

## Anti-Patterns

### Platform-specific #ifdef in shared headers
**What happens:** Preprocessor `#ifdef WINDOWS` blocks in header files
**Why it's wrong:** Pollutes headers, makes them unreadable, breaks precompiled headers
**Do this instead:** Use `#include "Platform.h"` with per-platform include directories (`Coding Standards.md:1223-1249`)

### Anonymous types / structs
**What happens:** Creating anonymous types outside of private class members
**Why it's wrong:** Reduces readability, makes debugging harder
**Do this instead:** Always give named types; prefer `enum class` over plain `enum` (`Coding Standards.md:326-327`)

### Multiple build passes required
**What happens:** Dependency graph may fail on first `ninja` run
**Why it's wrong:** Inconsistent one-pass builds waste CI time
**Do this instead:** Ensure correct `DEPENDS` and `BUILD_BYPRODUCTS` in CMake ExternalProject_Add calls (`thirdparty/AGENTS.md:42-43`)

---

*Architecture analysis: 2026-07-01*
