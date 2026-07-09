<!-- GSD:project-start source:PROJECT.md -->
## Project

**Genius Network — IPFS Bitswap Thread Safety**

A focused effort to audit and harden the `thirdparty/ipfs-bitswap` C++ library for thread safety, then propagate any required API changes to SuperGenius and AsyncIOManager — the two consumers of ipfs-bitswap in the Genius Network decentralized AI/ML blockchain node. Bitswap is the data exchange protocol that moves blocks between IPFS peers; thread-safety defects here can cause data races, crashes, or silent corruption in a multi-threaded asynchronous node.

**Core Value:** All concurrent access to IPFS Bitswap state is provably free of data races — verified through static analysis, code audit, and runtime tests — ensuring the CRDT/storage layer never corrupts or loses blocks under concurrent load.

### Constraints

- **Tech stack:** C++17, CMake, Boost.Asio, libp2p, existing thirdparty build system
- **Compatibility:** Changes to ipfs-bitswap must not break SuperGenius or AsyncIOManager builds on any supported platform (Windows x64, Linux, macOS, iOS, Android)
- **Build system:** ipfs-bitswap is built via `thirdparty/build/{Platform}/CMakeLists.txt`; any new files or dependencies must be registered there
- **Testing:** GTest testing framework; TSAN/Helgrind recommended for data-race detection
- **Coding standard:** Corelinux-derived C++ style per `Coding Standards.md` — Ullman braces, PascalCase types, `m_` member prefix
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- C++ C++17/C++20 - SuperGenius core node (`src/`), GeniusSDK (`src/`), zkLLVM (`libs/`), evmrelay, SGProcessingManager, ProofSystem, GeniusKDF, thirdparty libraries
- Dart ^3.10.0 - GeniusWallet Flutter app (`lib/`), genius_api package (`packages/genius_api/`), local_secure_storage package (`packages/local_secure_storage/`)
- Solidity ^0.8.x - Smart contracts: gnus-ai (`TokenContracts/gnus-ai/contracts/`), gnus-token (`TokenContracts/gnus-token/contracts/`), erc20-gnus-proxy (`TokenContracts/erc20-gnus-proxy/contracts/`)
- TypeScript ^4.5 - TokenContracts Hardhat scripts/tests (`gnus-ai/scripts/`, `gnus-ai/test/`, `erc20-gnus-proxy/scripts/`, `erc20-gnus-proxy/test/`)
- Rust nightly-2022-07-01 - ZoKrates proof system (`TokenContracts/ZoKrates/`), wallet-core Rust bindings (`thirdparty/wallet-core`)
- Python 3.7+ - Utility scripts (`util/install_from_github.py`), zkLLVM build helpers (`zkLLVM/detect-platform.py`, `zkLLVM/rslang-installer.py`)
- JavaScript ES6+ - gnus-token Truffle migrations (`TokenContracts/gnus-token/migrations/`)
## Runtime
- C++ compiled native (Clang/LLVM, GCC, MSVC 17 2022)
- Flutter SDK ^3.10.0 (stable channel, revision e3c29ec00c9c825c891d75054c63fcc46454dca1)
- Node.js (Hardhat v^2.9.0 / Truffle v^5.3.7)
- Python 3.7+
- Rust nightly-2022-07-01 (ZoKrates toolchain)
- CMake ^3.5 - All C++ projects
- Lockfile: `CMakeLists.txt` captures version constraints intrinsically; `CommonBuildParameters.cmake` pins Boost version (1.85.0)
- pub (Flutter/Dart) - `GeniusWallet/pubspec.yaml`
- Lockfile: `GeniusWallet/pubspec.lock` (present)
- yarn - TokenContracts (`gnus-token/`, `gnus-ai/`, `erc20-gnus-proxy/`)
- Lockfile: `yarn.lock` (present in all three)
- Cargo - ZoKrates (`TokenContracts/ZoKrates/Cargo.toml`)
- Lockfile: `TokenContracts/ZoKrates/Cargo.lock` (present)
- pip - Python utilities
- Lockfile: missing
## Frameworks
- Flutter ^3.10.0 - Cross-platform mobile/desktop wallet app (`GeniusWallet/`)
- Boost ~1.85.0 - Core C++ utility library for GeniusSDK (`GeniusSDK/cmake/CommonBuildParameters.cmake`)
- Boost ~1.89 - Core C++ utility library for SuperGenius/thirdparty
- gRPC - RPC framework for SuperGenius (`SuperGenius/gRPCForSuperGenius/`, `SuperGenius/src/api/transport/`)
- Protobuf - Protocol Buffer serialization (`GeniusSDK/cmake/CommonBuildParameters.cmake`, `SuperGenius/src/**/proto/*.proto`)
- OpenZeppelin ^4.1.0 - Solidity smart contract library (`TokenContracts/gnus-token/package.json`)
- @gnus.ai/contracts-upgradeable-diamond 4.5.0 - Diamond proxy pattern (`TokenContracts/gnus-ai/package.json`)
- Hardhat v^2.9.0 - Smart contract development & testing (`gnus-ai/`, `erc20-gnus-proxy/`)
- GTest ~1.14.0 - C++ unit testing (`GeniusSDK/cmake/CommonBuildParameters.cmake`, `SuperGenius/test/`)
- flutter_test - Flutter widget/unit testing (`GeniusWallet/pubspec.yaml`)
- Hardhat (Mocha/Chai/Waffle) - Solidity contract testing (`TokenContracts/gnus-ai/test/`)
- Truffle - Legacy contract testing (`TokenContracts/gnus-token/test/`)
- ZoKrates test suite - Proof system testing (`TokenContracts/ZoKrates/zokrates_core_test/`, `zokrates_solidity_test/`)
- solidity-coverage - Code coverage (`gnus-ai/package.json`)
- hardhat-gas-reporter - Gas usage reporting (`gnus-ai/package.json`)
- Ninja - Linux/macOS build generator (`SuperGenius/.github/workflows/cmake.yml`)
- Visual Studio 17 2022 - Windows C++ compiler
- Xcode - iOS/macOS builds (`GeniusWallet/ios/Runner.xcodeproj/`, `GeniusWallet/macos/Runner.xcodeproj/`)
- Gradle - Android builds (`GeniusWallet/android/build.gradle`)
- cbindgen - Rust-to-C FFI bindings for wallet-core (CI pipeline)
- ccache - Compiler cache (all platforms)
- TypeChain - TypeScript bindings from Solidity ABIs (`gnus-ai/`, `gnus-token/`)
- ffigen ^20.1.1 - Dart FFI bindings generator (`packages/genius_api/`)
- build_runner ^2.4.9 - Dart code generation (`GeniusWallet/`)
- freezed ^3.2.3 - Dart immutable data classes (`packages/genius_api/`)
- json_serializable ^6.8.0 - Dart JSON serialization (`GeniusWallet/`)
- hive_ce_generator ^1.10.0 - Dart Hive type adapters (`GeniusWallet/`)
- solhint, eslint, prettier - Code linting/formatting
## Key Dependencies
- Boost 1.85.0/1.89 - Outcome (error handling), ASIO (networking), Filesystem, Program Options, JSON, UUID, Log
- OpenSSL ~3.0.x - Core cryptography for SuperGenius/GeniusSDK (`GeniusSDK/cmake/CommonBuildParameters.cmake:113`)
- gRPC + Protobuf - Inter-service communication & serialization (`SuperGenius/gRPCForSuperGenius/`, `GeniusSDK/cmake/CommonBuildParameters.cmake`)
- libp2p - P2P networking layer (`GeniusSDK/cmake/CommonBuildParameters.cmake:221`, `SuperGenius/src/`)
- RocksDB - High-performance persistent key-value store (`GeniusSDK/cmake/CommonBuildParameters.cmake:127`)
- TrustWalletCore / TrezorCrypto / wallet_core_rs - Cryptocurrency wallet operations (`GeniusSDK/cmake/CommonBuildParameters.cmake:313`)
- web3dart ^3.0.0 - Ethereum interaction from Flutter (`GeniusWallet/pubspec.yaml:26`)
- ethers ^5.5.4 - Ethereum interaction from TypeScript (`gnus-ai/package.json:49`)
- Axelar SDK ^0.15.0 - Cross-chain bridge integration (`gnus-ai/`, `erc20-gnus-proxy/`)
- IPFS stack: ipfs-lite-cpp, ipfs-bitswap-cpp, ipfs-pubsub - Decentralized storage/messaging (`GeniusSDK/cmake/CommonBuildParameters.cmake:232,241,244`)
- sentry_flutter ^9.0.0 - Error tracking in wallet app (`GeniusWallet/pubspec.yaml:40`)
- hive_ce ^2.19.3 - Local key-value persistence in Flutter (`GeniusWallet/pubspec.yaml:51`)
- reown_walletkit ^1.3.2 - WalletConnect v2 integration (`GeniusWallet/pubspec.yaml:47`)
- flutter_bloc ^9.1.1 - State management (`GeniusWallet/pubspec.yaml:13`)
- go_router ^17.2.2 - Declarative routing (`GeniusWallet/pubspec.yaml:12`)
- flutter_secure_storage ^9.2.4 - Secure credential storage (`packages/local_secure_storage/pubspec.yaml:13`)
- MNN - Neural network inference engine (`GeniusSDK/cmake/CommonBuildParameters.cmake:47`, `SuperGenius/example/mnn_chunkprocess/`)
- zkLLVM 0.3.0 - Zero-knowledge proof compilation (`zkLLVM/CMakeLists.txt:21`, `GeniusSDK/cmake/CommonBuildParameters.cmake:327`)
- ZoKrates - Zero-knowledge proof DSL for smart contracts (`TokenContracts/ZoKrates/`)
- CRDT globaldb - Distributed conflict-free replicated data store (`SuperGenius/src/crdt/`)
- SQLite3/SQLiteModernCpp - Embedded relational database (`GeniusSDK/cmake/CommonBuildParameters.cmake:210`)
- spdlog + soralog - Structured logging (`GeniusSDK/cmake/CommonBuildParameters.cmake:142,149`)
- yaml-cpp - Configuration file parsing (`GeniusSDK/cmake/CommonBuildParameters.cmake:62`)
- Vulkan/MoltenVK - GPU compute (graphics pipeline)
- crypto3 suite (algebra/block/blueprint/zk) - Advanced ZK cryptography (`GeniusSDK/cmake/CommonBuildParameters.cmake:336`)
- libssh2 - SSH protocol (`GeniusSDK/cmake/CommonBuildParameters.cmake:287`)
- gnus_upnp - UPnP network discovery (`GeniusSDK/cmake/CommonBuildParameters.cmake:304`)
- c-ares - Async DNS resolution (`GeniusSDK/cmake/CommonBuildParameters.cmake:218`)
- xxhash - Fast non-cryptographic hashing
- snappy - Compression for RocksDB
## Configuration
- CMake build presets/options: `CMAKE_BUILD_TYPE`, `THIRDPARTY_BUILD_DIR`, `ZKLLVM_BUILD_DIR`, `SUPERGENIUS_DIR`, `ABI_SUBFOLDER_NAME`, `TESTING`, `BUILD_EXAMPLES`
- Flutter: `pubspec.yaml`, `assets/dev_config.json`, `assets/network_config.json`, `assets/crdt_config.json`, `assets/log_config.json`, `assets/sgns_config.json`
- Smart contracts: `hardhat.config.ts` with network configuration
- `.env.example` files present at:
- Key env vars (externalized): `GITHUB_TOKEN`/`GH_TOKEN`, `GITHUB_WORKSPACE`, `VULKAN_SDK`, wallet private keys, RPC URLs, API keys
- Main C++ projects (SuperGenius, GeniusSDK, thirdparty) do NOT have root `CMakeLists.txt`. Build entry points are inside `build/<Platform>/`.
- Build commands from `build/<Platform>/<Debug|Release>/`:
- `cmake/CommonBuildParameters.cmake` (`GeniusSDK/cmake/`) - Central dependency configuration
- `cmake/CommonCompilerOptions.cmake` - Compiler flags and toolchain config
- `cmake/functions.cmake` - Build helper functions
- `hardhat.config.ts` - Smart contract build configuration
- `pubspec.yaml` - Flutter build configuration
- `Cargo.toml` - Rust/ZoKrates workspace (`TokenContracts/ZoKrates/` only)
- `build.bat`, `build.sh` (`GeniusWallet/`) - Flutter build scripts
- `install_flutter.bat`, `install_flutter.sh` - Flutter SDK setup
## Platform Requirements
- Windows: Visual Studio 2022, CMake ^3.5, Flutter SDK ^3.10, Git
- Linux: Clang/LLVM, CMake ^3.5, Ninja, libsecret-1-dev, libvulkan-dev, dbus, gnome-keyring, Flutter SDK
- macOS: Xcode, CMake, Ninja, GNU tar, Flutter SDK, CocoaPods (for iOS)
- All: Git, Python 3.7+, Node.js (for smart contracts), Rust (for ZoKrates, wallet-core)
- Windows x86_64 (MSVC) — `cmake .. -G "Visual Studio 17 2022" -A x64 ...` from `build/Windows/`
- Linux (x86_64 or aarch64, Clang) — `cmake ../.. ...` from `build/Linux/`
- macOS universal (x86_64 + ARM64) — `cmake .. ...` from `build/OSX/`
- iOS arm64 — `cmake .. ...` from `build/iOS/`
- Android arm64-v8a, armeabi-v7a, x86_64 — `cmake ../../ -DANDROID_ABI=...` from `build/Android/`
- WebAssembly via Emscripten toolchain
- Container: `ghcr.io/geniusventures/debian-bullseye:latest` (Docker)
- Build tool: `make -j`, `cmake --build . --parallel 8 --config Release`, or Ninja
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Languages
| Language   | Primary Projects                                        |
|------------|--------------------------------------------------------|
| C++17      | SuperGenius, GeniusSDK, evmrelay, zkLLVM bindings      |
| Dart 3.x   | GeniusWallet (Flutter)                                 |
| Solidity   | TokenContracts (EIP-2535 Diamond pattern)              |
| Rust       | TokenContracts/ZoKrates, thirdparty/wallet-core       |
## Naming Patterns
### C++
- Header files: `PascalCase.hpp` (or `snake_case.hpp` when matching legacy modules)
- Source files: `PascalCase.cpp` (or `snake_case.cpp`)
- Interface headers use `I` prefix: `IBasicProof.hpp`, `IComponent.hpp`, `ISecureStorage.hpp`
- C-style API headers: `snake_case.h` (e.g., `GeniusSDK.h`)
- Top-level: `sgns`
- Sub-namespaces mirror directory structure: `sgns::base`, `sgns::crypto`, `sgns::storage`, `sgns::processing`, `sgns::crdt`, `sgns::blockchain`
- PascalCase: `Buffer`, `Blob<N>`, `HasherImpl`, `ProcessingCore`, `CrdtSet`
- Type aliases: PascalCase with prefix convention: `Hash256`, `Hash512`, `Logger`
- Template parameters: lowercase (e.g., `size_`, `K`, `V`, `T`)
- PascalCase: `GetName()`, `ProcessSubTask()`, `SetValue()`, `IsValueInSet()`
- Factory methods: `create()` (lowercase static method)
- Accessors: `Get` prefix -- `GetRenderViewCount()`, `GetName()`
- Boolean accessors: `Is` prefix -- `IsNameEmpty()`
- Mutators: `Set` prefix -- `SetName()`, `SetPayoutAddress()`
- Local variables: `camelCase` (e.g., `dataStoreResult`, `strNamespace`)
- Member variables: trailing underscore `_` (e.g., `db_`, `m_Value` in legacy)
- Constants: `UPPER_SNAKE_CASE` for macros, `kConstantName` not observed
- Function parameters: `camelCase` or `snake_case` (mixed pattern)
- PascalCase enum class name: `BlobError`, `UnhexError`, `DatabaseError`
- UPPER_SNAKE_CASE values: `INCORRECT_LENGTH`, `NOT_FOUND`, `IO_ERROR`
### Dart
- `snake_case.dart` for all files
- Generated files: `*.g.dart`
- PascalCase: `TokenInfoLoader`, `WalletDetailsCubit`, `WalletsOverview`
- Widgets end with descriptive suffix: `...Screen`, `...Widget`, `...Drawer`
- camelCase: `loadToken()`, `createState()`, `build()`
- camelCase: `tokenLoader`, `futurePrices`, `mockClient`
### Solidity
- PascalCase: `GeniusAI.sol`, `GeniusTokens.sol`, `GNUSERC1155MaxSupply.sol`
- PascalCase: `GeniusAI`, `GeniusTokens`, `AIProcessingJob`
- PascalCase: `OpenEscrow()`, `GeniusAI_Initialize()`, `calcTokenAmount()`
- UPPER_SNAKE_CASE: `MINTER_ROLE`, `INIT_SUPPLY`, `MAX_SUPPLY`
## Code Style
### C++ Formatting
#ifndef SUPERGENIUS_<MODULE>_HPP
#define SUPERGENIUS_<MODULE>_HPP
#endif  // SUPERGENIUS_<MODULE>_HPP
### C++ Linting
- `// NOLINT` for single-line suppressions
- `// NOLINTBEGIN(...)` / `// NOLINTEND(...)` for block suppressions
- Common suppressions: `modernize-use-using`, `cppcoreguidelines-avoid-c-arrays`, `performance-enum-size`
### Dart Formatting
### Solidity Formatting
## Import/Include Organization
### C++
### Dart
### Solidity
## Error Handling
### C++
### Dart
- Null-return on failure: `Future<T?>` where `null` signals error
- Standard `try`/`catch` for network/IO errors
- Sentry for production crash reporting (`sentry_flutter`)
### Solidity
- `require()` statements with descriptive error messages
- `revert()` for state-invalidating conditions
- Custom modifier-based access control (`onlyAdmin`, `onlyMinter`)
## Logging
### C++
- Android: Uses `android_logger_mt` sink
- Desktop: Uses `stdout_color_mt` (console) or `basic_logger_mt` (file if `basepath` provided)
- Pattern: `[YYYY-MM-DD HH:MM:SS][level][tag] message`
- Debug builds (`SGNS_DEBUG`): `[YYYY-MM-DD HH:MM:SS.frac][th:threadid][level][tag] message`
- `SGNS_DEBUGLOGS`: enables debug-level logging in non-Release builds
- `SGNS_PRINT_LOGS`: forces logs even in Release builds
### Dart
- `print()` / `debugPrint()` for debug output
- Sentry (`sentry_flutter`) for error/exception reporting in production
- No structured logging framework used in the wallet
## Comments
- Header files: Doxygen-style `@brief`, `@param`, `@return`, `@note` on all public interfaces
- Source files: `//` single-line comments for implementation details
- Block comments `/* ... */` allowed but `//` preferred in `.cpp` files
## Function Design
- Input parameters: pass by `const &` for complex types, by value for primitives
- `std::string_view` preferred over `const std::string&` in newer code
- `gsl::span<const uint8_t>` for buffer views
- Output: return `outcome::result<T>` for fallible operations
- `[[nodiscard]]` attribute used on functions where discarding the result is an error
- Prefer `outcome::result<T>` over exceptions for expected failures
- Factory methods return `outcome::result<std::shared_ptr<T>>`
### Dart
- Constructor parameters use `required` for mandatory fields
- `const` constructors where possible
- `super.key` pattern for widget constructors
## Module Design
### C++
- One class per header file (generally, with exceptions for tightly-coupled types)
- Interface segregation: abstract base classes in `*.hpp`, implementations in `impl/` subdirectory
- CMake `add_library()` per module
- Internal headers in `impl/` subdirectory, not part of public API
### Dart
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | File |
|-----------|----------------|------|
| SuperGenius | Core blockchain node: account ledger, consensus, AI processing, proof generation, CRDT storage, gRPC API | `SuperGenius/src/` |
| GeniusSDK | Embeddable C++ library wrapping SuperGenius for game/app developers | `GeniusSDK/src/` |
| GeniusWallet | Cross-platform Flutter wallet with fiat on-ramp, token swaps, WalletConnect | `GeniusWallet/lib/` |
| zkLLVM | Zero-knowledge circuit compiler (C++ → algebraic circuits) | `zkLLVM/libs/` |
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
- Each top-level directory (except `util`) is a separate Git submodule with its own build system
- SuperGenius uses a **layered architecture** within `src/`: each subdirectory is a self-contained module with public headers, implementation, and CMake build
- GeniusWallet uses the **BLoC (Business Logic Component)** pattern for state management with `flutter_bloc`
- Protocol Buffers define serialization contracts between components (`.proto` files in each module's `proto/` dir)
- CMake is the universal build system across all C++ components. Main projects do NOT have root `CMakeLists.txt` — builds originate from `build/<Platform>/<Debug|Release>/` using `cmake ../..` (arm64 targets) or `cmake ..` (x86_64/macOS targets).
- Cross-platform compilation to Linux, macOS, Windows, iOS, Android
- CRDT (Conflict-free Replicated Data Types) for distributed consensus-free state synchronization over IPFS
## Layers
- Purpose: Core decentralized ledger, consensus, and transaction processing
- Location: `SuperGenius/src/`
- Contains: Account/UTXO management, block-lattice consensus, transaction types (Transfer, Mint, Processing, Escrow), blockchain state, validator registry
- Depends on: Crypto layer, Storage layer, Proto definitions
- Used by: GeniusSDK, gRPC API
- Purpose: Decentralized AI/ML job submission, task splitting, worker assignment, result validation
- Location: `SuperGenius/src/processing/`
- Contains: Processing engine, task queue, subtask enqueuer, validation core, task split, processing node/service
- Depends on: Account layer (for ProcessingTransaction), Proof system (for work verification), CRDT (for distributed state), gRPC
- Used by: SGProcessingManager, GeniusWallet (via SDK)
- Purpose: Zero-knowledge proof generation and verification for AI/ML work
- Location: `SuperGenius/src/proof/`, `SuperGenius/ProofSystem/`, `zkLLVM/`
- Contains: GeniusProver, GeniusAssigner, TransferProof, RecursiveTransferProof, ProcessingProof, ZK circuits
- Depends on: zkLLVM, Crypto layer, NilFoundation crypto3
- Used by: Processing layer, TokenContracts (via ZoKrates/on-chain verification)
- Purpose: Distributed, conflict-free replicated state across nodes using IPFS and local RocksDB
- Location: `SuperGenius/src/crdt/`, `SuperGenius/src/storage/`
- Contains: CRDT datastore, DAG syncer, global database, RocksDB face, IPFS pubsub, Graphsync
- Depends on: libp2p, IPFS libraries, RocksDB
- Used by: Account layer, Processing layer, Subscription engine
- Purpose: Hashing, signing, key derivation
- Location: `SuperGenius/src/crypto/`
- Contains: Hasher abstraction (sha, keccak, twox), ed25519/sr25519 integration
- Depends on: thirdparty crypto libraries (OpenSSL, CryptoPP, libsecp256k1, ed25519, sr25519-donna), GeniusKDF
- Used by: All layers
- Purpose: gRPC service definitions and client/server stubs
- Location: `SuperGenius/src/api/transport/`, `SuperGenius/gRPCForSuperGenius/`
- Contains: gRPC service implementations, proto definitions, generated stubs
- Depends on: Account layer, Processing layer, gRPC/protobuf from thirdparty
- Used by: GeniusWallet, GeniusSDK, external clients
- Purpose: Embeddable static/shared/framework library wrapping SuperGenius for game developers
- Location: `GeniusSDK/src/`
- Contains: GeniusSDK.h/cpp, service runner, platform-specific build targets
- Depends on: SuperGenius (links `sgns::genius_node`)
- Used by: Game engines, mobile apps, GeniusWallet (via FFI)
- Purpose: Cross-platform user-facing wallet application
- Location: `GeniusWallet/lib/`
- Contains: BLoC state management, screens, navigation, providers, services (CoinGecko, CoinTelegraph), Banxa fiat on-ramp, SquidRouter swaps, WalletKit/Reown
- Depends on: GeniusSDK (via FFI/gRPC), local_secure_storage, genius_api, TokenContracts (on-chain reads)
- Used by: End users
- Purpose: On-chain Ethereum token contracts
- Location: `TokenContracts/gnus-token/`, `TokenContracts/gnus-ai/`, `TokenContracts/ZoKrates/`
- Contains: ERC-20 ICO contract, AI escrow/payment-split contract, ZK verifier contracts
- Depends on: OpenZeppelin, Uniswap, ZoKrates
- Used by: SuperGenius (as bridge), end users
## Data Flow
### Primary Path — AI/ML Processing Job
### Token Bridge Path
### Wallet Data Flow
- **GeniusWallet:** BLoC pattern (`flutter_bloc`). AppBloc manages global state; feature-specific cubits (WalletDetailsCubit, PinCubit, BanxaOrderCubit, etc.)
- **SuperGenius:** Singleton pattern via ComponentFactory (`SuperGenius/src/singleton/CComponentFactory.cpp:1`). CRDT datastore holds distributed state.
- **GeniusSDK:** Stateless wrapper; delegates all state to SuperGenius node.
## Key Abstractions
- Purpose: Represents a user account holding tokens (UTXO-based)
- Examples: `SuperGenius/src/account/GeniusAccount.cpp`, `SuperGenius/src/account/GeniusNode.cpp`
- Pattern: Block-lattice account chain (each account has its own blockchain)
- Purpose: Orchestrates AI/ML processing jobs: submission, splitting, assignment, validation
- Examples: `SuperGenius/src/processing/processing_engine.cpp`, `SuperGenius/src/processing/processing_node.cpp`
- Pattern: Service/Node pattern with task queue
- Purpose: Conflict-free replicated distributed state over IPFS
- Examples: `SuperGenius/src/crdt/crdt_datastore.hpp`, `SuperGenius/src/crdt/globaldb/`
- Pattern: Delta-state CRDT with DAG sync over IPFS Graphsync
- Purpose: ZK circuit compilation, assignment, proving, verification
- Examples: `SuperGenius/src/proof/GeniusProver.cpp`, `SuperGenius/src/proof/GeniusAssigner.cpp`, `zkLLVM/libs/assigner/`, `zkLLVM/libs/circifier/`
- Pattern: Pipeline: C++ source → LLVM IR → circuit → assigner → proof → verifier
- Purpose: Central dependency injection / service locator for SuperGenius
- Examples: `SuperGenius/src/singleton/CComponentFactory.cpp`
- Pattern: Singleton registry for all major components
## Entry Points
- Location: `SuperGenius/src/account/GeniusNode.cpp`
- Triggers: Launched as service/daemon or embedded via GeniusSDK
- Responsibilities: Initialize all subsystems, start consensus, listen for gRPC
- Location: `GeniusSDK/src/GeniusSDK.cpp`
- Triggers: Linked into game/application binary
- Responsibilities: Initialize SuperGenius node, expose simplified API
- Location: `GeniusWallet/lib/main.dart`
- Triggers: User launches app on mobile/desktop
- Responsibilities: Initialize BLoC, providers, navigation, connect to SuperGenius node
- Location: `TokenContracts/gnus-token/truffle-config.js`, `TokenContracts/gnus-ai/`
- Triggers: `truffle migrate` / Hardhat deploy
- Responsibilities: Deploy ICO and AI escrow contracts to Ethereum
- Location: `zkLLVM/bin/`
- Triggers: Developers invoke `assigner`, `clang` (zkLLVM variant), `transpiler`
- Responsibilities: Compile circuits, generate proofs, transpile to EVM verifiers
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
### Anonymous types / structs
### Multiple build passes required
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
