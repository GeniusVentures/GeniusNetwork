# Technology Stack

**Analysis Date:** 2026-07-01

## Languages

**Primary:**
- C++ C++17/C++20 - SuperGenius core node (`src/`), GeniusSDK (`src/`), zkLLVM (`libs/`), evmrelay, SGProcessingManager, ProofSystem, GeniusKDF, thirdparty libraries
- Dart ^3.10.0 - GeniusWallet Flutter app (`lib/`), genius_api package (`packages/genius_api/`), local_secure_storage package (`packages/local_secure_storage/`)
- Solidity ^0.8.x - Smart contracts: gnus-ai (`TokenContracts/gnus-ai/contracts/`), gnus-token (`TokenContracts/gnus-token/contracts/`), erc20-gnus-proxy (`TokenContracts/erc20-gnus-proxy/contracts/`)

**Secondary:**
- TypeScript ^4.5 - TokenContracts Hardhat scripts/tests (`gnus-ai/scripts/`, `gnus-ai/test/`, `erc20-gnus-proxy/scripts/`, `erc20-gnus-proxy/test/`)
- Rust nightly-2022-07-01 - ZoKrates proof system (`TokenContracts/ZoKrates/`), zkLLVM rslang toolchain (`zkLLVM/libs/rslang/`)
- Python 3.7+ - Utility scripts (`util/install_from_github.py`), zkLLVM build helpers (`zkLLVM/detect-platform.py`, `zkLLVM/rslang-installer.py`)
- JavaScript ES6+ - gnus-token Truffle migrations (`TokenContracts/gnus-token/migrations/`)

## Runtime

**Environment:**
- C++ compiled native (Clang/LLVM, GCC, MSVC 17 2022)
- Flutter SDK ^3.10.0 (stable channel, revision e3c29ec00c9c825c891d75054c63fcc46454dca1)
- Node.js (Hardhat v^2.9.0 / Truffle v^5.3.7)
- Python 3.7+
- Rust nightly-2022-07-01 (ZoKrates toolchain)

**Package Manager:**
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

**Core:**
- Flutter ^3.10.0 - Cross-platform mobile/desktop wallet app (`GeniusWallet/`)
- Boost ~1.85.0 - Core C++ utility library for GeniusSDK (`GeniusSDK/cmake/CommonBuildParameters.cmake`)
- Boost ~1.89 - Core C++ utility library for SuperGenius/thirdparty
- gRPC - RPC framework for SuperGenius (`SuperGenius/gRPCForSuperGenius/`, `SuperGenius/src/api/transport/`)
- Protobuf - Protocol Buffer serialization (`GeniusSDK/cmake/CommonBuildParameters.cmake`, `SuperGenius/src/**/proto/*.proto`)
- OpenZeppelin ^4.1.0 - Solidity smart contract library (`TokenContracts/gnus-token/package.json`)
- @gnus.ai/contracts-upgradeable-diamond 4.5.0 - Diamond proxy pattern (`TokenContracts/gnus-ai/package.json`)
- Hardhat v^2.9.0 - Smart contract development & testing (`gnus-ai/`, `erc20-gnus-proxy/`)

**Testing:**
- GTest ~1.14.0 - C++ unit testing (`GeniusSDK/cmake/CommonBuildParameters.cmake`, `SuperGenius/test/`)
- flutter_test - Flutter widget/unit testing (`GeniusWallet/pubspec.yaml`)
- Hardhat (Mocha/Chai/Waffle) - Solidity contract testing (`TokenContracts/gnus-ai/test/`)
- Truffle - Legacy contract testing (`TokenContracts/gnus-token/test/`)
- ZoKrates test suite - Proof system testing (`TokenContracts/ZoKrates/zokrates_core_test/`, `zokrates_solidity_test/`)
- solidity-coverage - Code coverage (`gnus-ai/package.json`)
- hardhat-gas-reporter - Gas usage reporting (`gnus-ai/package.json`)

**Build/Dev:**
- Ninja - Linux/macOS build generator (`SuperGenius/.github/workflows/cmake.yml`)
- Visual Studio 17 2022 - Windows C++ compiler
- Xcode - iOS/macOS builds (`GeniusWallet/ios/Runner.xcodeproj/`, `GeniusWallet/macos/Runner.xcodeproj/`)
- Gradle - Android builds (`GeniusWallet/android/build.gradle`)
- cbindgen - Rust-to-C FFI bindings (CI pipeline)
- ccache - Compiler cache (all platforms)
- TypeChain - TypeScript bindings from Solidity ABIs (`gnus-ai/`, `gnus-token/`)
- ffigen ^20.1.1 - Dart FFI bindings generator (`packages/genius_api/`)
- build_runner ^2.4.9 - Dart code generation (`GeniusWallet/`)
- freezed ^3.2.3 - Dart immutable data classes (`packages/genius_api/`)
- json_serializable ^6.8.0 - Dart JSON serialization (`GeniusWallet/`)
- hive_ce_generator ^1.10.0 - Dart Hive type adapters (`GeniusWallet/`)
- solhint, eslint, prettier - Code linting/formatting

## Key Dependencies

**Critical:**
- Boost 1.85.0/1.89 - Outcome (error handling), ASIO (networking), Filesystem, Program Options, JSON, UUID, Log
- OpenSSL ~3.0.x - Core cryptography for SuperGenius/GeniusSDK (`GeniusSDK/cmake/CommonBuildParameters.cmake:113`)
- gRPC + Protobuf - Inter-service communication & serialization (`SuperGenius/gRPCForSuperGenius/`, `GeniusSDK/cmake/CommonBuildParameters.cmake`)
- libp2p - P2P networking layer (`GeniusSDK/cmake/CommonBuildParameters.cmake:221`, `SuperGenius/src/`)
- RocksDB - High-performance persistent key-value store (`GeniusSDK/cmake/CommonBuildParameters.cmake:127`)
- TrustWalletCore / TrezorCrypto / wallet_core_rs - Cryptocurrency wallet operations (`GeniusSDK/cmake/CommonBuildParameters.cmake:313`)
- web3dart ^3.0.0 - Ethereum interaction from Flutter (`GeniusWallet/pubspec.yaml:26`)
- ethers ^5.5.4 - Ethereum interaction from TypeScript (`gnus-ai/package.json:49`)
- Axelar SDK ^0.15.0 - Cross-chain bridge integration (`gnus-ai/`, `erc20-gnus-proxy/`)

**Infrastructure:**
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

**Environment:**
- CMake build presets/options: `CMAKE_BUILD_TYPE`, `THIRDPARTY_BUILD_DIR`, `ZKLLVM_BUILD_DIR`, `SUPERGENIUS_DIR`, `ABI_SUBFOLDER_NAME`, `TESTING`, `BUILD_EXAMPLES`
- Flutter: `pubspec.yaml`, `assets/dev_config.json`, `assets/network_config.json`, `assets/crdt_config.json`, `assets/log_config.json`, `assets/sgns_config.json`
- Smart contracts: `hardhat.config.ts` with network configuration
- `.env.example` files present at:
  - `SuperGenius/evmrelay/examples/.env.example`
  - `TokenContracts/gnus-ai/.env.example`
  - `GeniusWallet/squidrouter/.env-example`
- Key env vars (externalized): `GITHUB_TOKEN`/`GH_TOKEN`, `GITHUB_WORKSPACE`, `VULKAN_SDK`, wallet private keys, RPC URLs, API keys

**Build:**
- Main C++ projects (SuperGenius, GeniusSDK, thirdparty) do NOT have root `CMakeLists.txt`. Build entry points are inside `build/<Platform>/`.
- Build commands from `build/<Platform>/<Debug|Release>/`:

  ```bash
  # Windows (x86_64, MSVC)
  cmake .. -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
  cmake --build . --parallel 8 --config Release     # or: cmake --build . --config Release (Debug)

  # Linux (x86_64 or aarch64, Clang)
  cmake ../.. -DCMAKE_BUILD_TYPE=Release
  make -j                                            # or: ninja, cmake --build . --parallel 8

  # macOS (OSX, universal)
  cmake .. -DCMAKE_BUILD_TYPE=Release
  make -j                                            # or: ninja, cmake --build . --parallel 8

  # iOS (arm64)
  cmake .. -DCMAKE_BUILD_TYPE=Release

  # Android (arm64-v8a, armeabi-v7a, x86_64 — adjust ANDROID_ABI)
  cmake ../../ -DANDROID_ABI="arm64-v8a" -DCMAKE_ANDROID_NDK=$ANDROID_NDK -DANDROID_TOOLCHAIN=clang -DCMAKE_BUILD_TYPE=Release
  ```

  - Single-command alternative: combine generate + build in one step with `cmake -B build/<Platform>/Release ...` plus `--build`.
  - Generator: Visual Studio on Windows; Ninja or Unix Makefiles on Linux/macOS.
  - `thirdparty/` must be built first as it provides all dependency libraries.
- `cmake/CommonBuildParameters.cmake` (`GeniusSDK/cmake/`) - Central dependency configuration
- `cmake/CommonCompilerOptions.cmake` - Compiler flags and toolchain config
- `cmake/functions.cmake` - Build helper functions
- `hardhat.config.ts` - Smart contract build configuration
- `pubspec.yaml` - Flutter build configuration
- `Cargo.toml` - Rust/ZoKrates workspace
- `build.bat`, `build.sh` (`GeniusWallet/`) - Flutter build scripts
- `install_flutter.bat`, `install_flutter.sh` - Flutter SDK setup

## Platform Requirements

**Development:**
- Windows: Visual Studio 2022, CMake ^3.5, Flutter SDK ^3.10, Git
- Linux: Clang/LLVM, CMake ^3.5, Ninja, libsecret-1-dev, libvulkan-dev, dbus, gnome-keyring, Flutter SDK
- macOS: Xcode, CMake, Ninja, GNU tar, Flutter SDK, CocoaPods (for iOS)
- All: Git, Python 3.7+, Node.js (for smart contracts), Rust (for ZK/LLVM)

**Production:**
- Windows x86_64 (MSVC) — `cmake .. -G "Visual Studio 17 2022" -A x64 ...` from `build/Windows/`
- Linux (x86_64 or aarch64, Clang) — `cmake ../.. ...` from `build/Linux/`
- macOS universal (x86_64 + ARM64) — `cmake .. ...` from `build/OSX/`
- iOS arm64 — `cmake .. ...` from `build/iOS/`
- Android arm64-v8a, armeabi-v7a, x86_64 — `cmake ../../ -DANDROID_ABI=...` from `build/Android/`
- WebAssembly via Emscripten toolchain
- Container: `ghcr.io/geniusventures/debian-bullseye:latest` (Docker)
- Build tool: `make -j`, `cmake --build . --parallel 8 --config Release`, or Ninja

---

*Stack analysis: 2026-07-01*
