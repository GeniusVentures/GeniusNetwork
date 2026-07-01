# Codebase Structure

**Analysis Date:** 2026-07-01

## Directory Layout

```
GeniusNetwork/                         # Monorepo root (parent repo)
├── .gitmodules                        # Submodule definitions (8 submodules)
├── .planning/                         # Planning config and generated docs
│   ├── config.json                    # Workflow configuration
│   └── codebase/                      # Generated architecture/struct docs
├── Readme.md                          # Top-level readme
├── INSTALL.md                         # Third-party libs integration guide
├── Coding Standards.md                # C++ coding standards (Corelinux-based)
├── ThirdParty_Libraries_Integration.md # 48-library dependency catalog
│
├── SuperGenius/                       # [submodule] Core blockchain node (C++17)
│   ├── src/                           # Source code (16 modules)
│   │   ├── CMakeLists.txt             # Top-level source CMake
│   │   ├── account/                   # Account, UTXO, transactions, migrations
│   │   ├── api/                       # gRPC transport layer
│   │   ├── base/                      # Base utilities and types
│   │   ├── blockchain/                # Block-lattice consensus, validators
│   │   ├── coinprices/                # Coin price data
│   │   ├── crdt/                      # CRDT distributed state, IPFS sync
│   │   ├── crypto/                    # Hashing (sha, keccak, twox)
│   │   ├── local_secure_storage/      # Local secure key storage
│   │   ├── macro/                     # Compiler macros
│   │   ├── outcome/                   # Boost.Outcome wrapper
│   │   ├── processing/                # AI/ML job processing engine
│   │   ├── proof/                     # ZK proof generation/verification
│   │   ├── singleton/                 # ComponentFactory singleton
│   │   ├── storage/                   # RocksDB database face
│   │   ├── subscription/              # Pub/sub engine
│   │   └── watcher/                   # Message bus watcher
│   ├── ProofSystem/                   # ZK proof circuits (sub-submodule)
│   ├── SGProcessingManager/           # Processing job manager (sub-submodule)
│   ├── gRPCForSuperGenius/            # gRPC proto definitions (sub-submodule)
│   ├── GeniusKDF/                     # Key derivation function (sub-submodule)
│   ├── evmrelay/                      # EVM bridge relay (sub-submodule)
│   ├── cmake/                         # CMake helpers (functions, install, version)
│   ├── example/                       # Example apps (crdt, echo, ipfs, processing)
│   ├── test/                          # Unit tests
│   ├── AgentDocs/                     # AI agent documentation
│   ├── docs/                          # Developer documentation
│   ├── build/<Platform>/<Config>/     # Build tree (cmake ../.. or cmake ..)
│   │   ├── Linux/Debug/                # Linux x86_64 debug build
│   │   ├── Linux/Release/              # Linux x86_64 release build
│   │   ├── Windows/Debug/              # Windows MSVC debug build
│   │   ├── Windows/Release/            # Windows MSVC release build
│   │   ├── OSX/Debug/                  # macOS universal debug build
│   │   ├── OSX/Release/                # macOS universal release build
│   │   ├── Android/                    # Android NDK cross-compile (arm64-v8a, armeabi-v7a, x86_64)
│   │   └── iOS/                        # iOS cross-compile (arm64)
│   └── Readme.md                      # SuperGenius build instructions
│
├── GeniusSDK/                         # [submodule] C++ SDK wrapping SuperGenius
│   ├── src/                           # SDK source (GeniusSDK.h/cpp)
│   ├── services/                      # Systemd service files, service runner
│   ├── cmake/                         # CMake config (CommonBuildParameters, flags)
│   ├── example/                       # SDK usage examples
│   ├── test/                          # Unit tests
│   ├── AgentDocs/                     # AI agent documentation
│   └── Readme.md                      # SDK build instructions
│
├── GeniusWallet/                      # [submodule] Flutter cross-platform wallet
│   ├── lib/                           # Dart source code (29 subdirectories)
│   │   ├── main.dart                  # App entry point
│   │   ├── bloc/                      # Global BLoC: app_bloc, pin_cubit
│   │   ├── wallets/                   # Wallet management (cubit + view)
│   │   ├── dashboard/                 # Dashboard UI, transactions cubit
│   │   ├── navigation/                # GoRouter route definitions
│   │   ├── screens/                   # Top-level screens (splash, pin, loading)
│   │   ├── providers/                 # Network/token providers
│   │   ├── services/                  # CoinGecko, CoinTelegraph APIs
│   │   ├── banxa/                     # Banxa fiat on-ramp integration
│   │   ├── squid_router/              # SquidRouter token swap integration
│   │   ├── reown/                     # WalletKit / Reown WalletConnect
│   │   ├── theme/                     # App theme and colors
│   │   ├── components/                # Reusable UI components
│   │   ├── tokens/                    # Token list and management
│   │   ├── chart/                     # Price chart widgets
│   │   ├── settings/                  # App settings
│   │   ├── onboarding/                # First-run onboarding flow
│   │   ├── submit_job/                # AI job submission UI
│   │   ├── network/                   # Network selection/config
│   │   ├── utils/                     # Utility helpers
│   │   ├── hive/                      # Local Hive DB initialization
│   │   ├── web/                       # Web platform helpers
│   │   ├── test/                      # In-app test utilities
│   │   └── tokeninfo/                 # Token detail views
│   ├── packages/                      # Local Dart packages
│   │   ├── genius_api/                # Genius API client package
│   │   └── local_secure_storage/      # Local encrypted storage package
│   ├── assets/                        # JSON configs, images, fonts
│   ├── android/                       # Android platform code
│   ├── ios/                           # iOS platform code
│   ├── windows/                       # Windows platform code
│   ├── linux/                         # Linux platform code
│   ├── macos/                         # macOS platform code
│   ├── test/                          # Flutter unit/widget tests
│   ├── pubspec.yaml                   # Flutter dependencies and config
│   └── README.md                      # Wallet docs
│
├── zkLLVM/                            # [submodule] ZK circuit compiler
│   ├── libs/                          # Core libraries
│   │   ├── assigner/                  # Circuit execution trace generator
│   │   ├── blueprint/                 # Circuit blueprint
│   │   ├── circifier/                 # LLVM IR → circuit conversion
│   │   ├── crypto3/                   # NilFoundation cryptography suite
│   │   ├── stdlib/                    # ZK standard library
│   │   └── transpiler/                # Circuit → EVM verifier transpiler
│   ├── bin/                           # Built binaries (assigner, clang)
│   ├── examples/                      # Example circuits (C++/Rust)
│   ├── tests/                         # Test circuits and inputs
│   ├── cmake/                         # CMake configuration
│   ├── CMakeLists.txt                 # Root CMake
│   └── README.md                      # zkLLVM docs
│
├── TokenContracts/                    # [submodule] Ethereum smart contracts
│   ├── gnus-token/                    # GNUS ICO (Truffle + TypeScript)
│   │   ├── contracts/                 # Solidity contracts
│   │   ├── test/                      # Truffle tests
│   │   ├── truffle-config.js          # Truffle configuration
│   │   └── Readme.md                  # Token contract docs
│   ├── gnus-ai/                       # AI escrow + diamond contracts (Hardhat)
│   │   ├── contracts/                 # Solidity contracts
│   │   ├── test/                      # Hardhat tests
│   │   ├── zokrates/                  # ZoKrates ZK circuits + verifiers
│   │   └── tsconfig.json              # TypeScript config
│   ├── ZoKrates/                      # ZoKrates tooling (Rust)
│   │   ├── zokrates_test/             # Test framework
│   │   └── zokrates_test_derive/      # Test derive macros
│   ├── erc20-gnus-proxy/              # ERC-20 proxy contract
│   ├── sushi-assets/                  # SushiSwap integration assets
│   ├── test/                          # Cross-contract tests
│   └── README.md                      # Token system overview
│
├── thirdparty/                        # [submodule] Build orchestrator for 48 C++ libs
│   ├── build/                         # Platform build scripts
│   │   ├── Linux/CMakeLists.txt       # Linux build entry
│   │   ├── OSX/CMakeLists.txt         # macOS build entry
│   │   ├── iOS/CMakeLists.txt         # iOS cross-compile entry
│   │   ├── Android/CMakeLists.txt     # Android NDK build entry
│   │   ├── Windows/CMakeLists.txt     # Windows (MSVC) build entry
│   │   ├── CommonTargets.CMake        # All library ExternalProject_Add defs
│   │   └── CommonCompilerOptions.CMake # C++17, cache args, flags
│   ├── .github/workflows/             # CI build/test/release pipelines
│   ├── .gitmodules                    # Thirdparty's own submodules
│   └── AGENTS.md                      # Thirdparty build guidelines
│
├── TestVMs/                           # [submodule] Vagrant test VMs
│   ├── Windows/                       # Windows Vagrant VM
│   │   ├── Vagrantfile                # VM definition
│   │   └── bootstrap.ps1              # Provisioning script
│   └── Ubuntu64/                      # Ubuntu Vagrant VM
│
└── util/                              # Utility scripts (not a submodule)
    ├── install_from_github.py         # Clone/build thirdparty from GitHub
    └── setup-windows-docker.ps1       # Windows Docker environment setup
```

## Directory Purposes

**SuperGenius/ (`src/` modules):**
- Purpose: Core blockchain node — every subdirectory is an independent CMake target
- Contains: C++ headers (`.hpp`) and sources (`.cpp`), with `proto/` subdirectories for Protocol Buffers
- Key files: `GeniusNode.cpp` (node entry), `GeniusAccount.cpp` (account model), `Consensus.cpp` (consensus)

**GeniusSDK/:**
- Purpose: Embeddable library wrapping SuperGenius for external apps/games
- Contains: Minimal C++ SDK with `GeniusSDK.h` as public API header
- Key files: `src/GeniusSDK.h` (public header), `src/GeniusSDK.cpp` (implementation)

**GeniusWallet/:**
- Purpose: Flutter cross-platform wallet application
- Contains: Dart code organized by feature area, each with `cubit/` (state) and `view/` (UI)
- Key files: `lib/main.dart` (entry point), `lib/navigation/router.dart` (route definitions)

**zkLLVM/:**
- Purpose: Compile C++/Rust → ZK circuits → proofs
- Contains: LLVM-based compiler libraries with CMake build
- Key files: `libs/assigner/` (trace gen), `libs/circifier/` (IR→circuit), `libs/transpiler/` (circuit→EVM)

**TokenContracts/:**
- Purpose: On-chain Ethereum contracts for GNUS token economy
- Contains: Solidity contracts, TypeScript tests/deploy, ZoKrates ZK circuits
- Key files: `gnus-token/contracts/`, `gnus-ai/contracts/`

**thirdparty/:**
- Purpose: Centralized build of all C++ dependencies for SuperGenius/GeniusSDK
- Contains: Platform-specific CMakeLists.txt + shared `CommonTargets.CMake`
- Key files: `build/CommonTargets.CMake` (48 library definitions), `build/CommonCompilerOptions.CMake`

## Key File Locations

**Entry Points:**
- `SuperGenius/src/account/GeniusNode.cpp`: SuperGenius node process entry
- `GeniusSDK/src/GeniusSDK.cpp`: SDK library initialization
- `GeniusWallet/lib/main.dart`: Flutter app entry point
- `TokenContracts/gnus-token/truffle-config.js`: Token contract deploy config
- `zkLLVM/bin/assigner/assigner`: ZK circuit assigner CLI

**Configuration:**
- `.planning/config.json`: Workflow configuration (model profile, git strategy, hooks)
- `GeniusWallet/pubspec.yaml`: Flutter app dependencies
- `GeniusWallet/assets/sgns_config.json`: SuperGenius node configuration
- `GeniusWallet/assets/network_config.json`: Network/chain configuration
- `GeniusWallet/assets/crdt_config.json`: CRDT synchronization config
- `GeniusWallet/assets/log_config.json`: Logging configuration
- `SuperGenius/cmake/functions.cmake`: CMake helper functions (test, proto-compile)
- `SuperGenius/cmake/install.cmake`: Install rules
- `SuperGenius/cmake/version.cmake`: Version definitions
- `GeniusSDK/cmake/CommonBuildParameters.cmake`: SDK build parameters
- `GeniusSDK/cmake/CompilationFlags.cmake`: Compiler flags
- `thirdparty/build/CommonCompilerOptions.CMake`: C++17 + shared cache args

**Core Logic:**
- `SuperGenius/src/account/GeniusAccount.cpp`: Account/balance management
- `SuperGenius/src/blockchain/Consensus.cpp`: Block-lattice consensus
- `SuperGenius/src/processing/processing_engine.cpp`: AI/ML job orchestration
- `SuperGenius/src/processing/processing_validation_core.cpp`: Proof validation
- `SuperGenius/src/proof/GeniusProver.cpp`: ZK proof generation
- `SuperGenius/src/proof/GeniusAssigner.cpp`: ZK circuit assignment
- `SuperGenius/src/crdt/crdt_datastore.hpp`: Distributed state store
- `SuperGenius/src/singleton/CComponentFactory.cpp`: Component registry

**Tests:**
- `SuperGenius/test/`: GTest-based C++ unit tests
- `GeniusSDK/test/`: SDK unit tests
- `GeniusWallet/test/`: Flutter widget/unit tests
- `GeniusWallet/lib/test/`: In-app test/dev utilities
- `TokenContracts/gnus-token/test/GnusToken.ts`: Token contract tests
- `TokenContracts/gnus-ai/test/`: AI contract tests
- `zkLLVM/tests/`: Circuit compiler tests
- `TestVMs/`: Integration test VMs

**Documentation:**
- `Readme.md`: Top-level instructions (clone, setup)
- `INSTALL.md`: Third-party library integration guide (246 lines)
- `ThirdParty_Libraries_Integration.md`: Same content as INSTALL.md (246 lines)
- `Coding Standards.md`: C++ coding standards (1256 lines, Corelinux-based)
- `SuperGenius/Readme.md`: SuperGenius build and architecture overview
- `GeniusSDK/Readme.md`: SDK build instructions
- `TokenContracts/README.md`: Token system overview
- `zkLLVM/README.md`: zkLLVM usage and build docs
- `SuperGenius/docs/`: Additional architecture docs
- `AGENTS.md`: AI agent guidelines (GeniusSDK, GeniusWallet, thirdparty)
- `CLAUDE.md`: Alternative AI guidelines (GeniusSDK, GeniusWallet)

**Build System:**
- Main C++ projects (SuperGenius, GeniusSDK, thirdparty) do NOT have root `CMakeLists.txt`. Build entry points are inside `build/<Platform>/`.
- `thirdparty/` must be built first as it provides all dependency libraries.
- Build commands issued from `build/<Platform>/<Debug|Release>/`:

  | Platform | CMake generate | Build |
  |----------|---------------|-------|
  | Windows (x64, MSVC) | `cmake .. -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release` | `cmake --build . --parallel 8 --config Release` |
  | Linux (x86_64/aarch64, Clang) | `cmake ../.. -DCMAKE_BUILD_TYPE=Release` | `make -j` |
  | macOS (OSX, universal) | `cmake .. -DCMAKE_BUILD_TYPE=Release` | `make -j` |
  | iOS (arm64) | `cmake .. -DCMAKE_BUILD_TYPE=Release` | - |
  | Android | `cmake ../../ -DANDROID_ABI="arm64-v8a" -DCMAKE_ANDROID_NDK=$ANDROID_NDK -DANDROID_TOOLCHAIN=clang -DCMAKE_BUILD_TYPE=Release` | - |

  - Adjust `ANDROID_ABI` per target: `arm64-v8a`, `armeabi-v7a`, or `x86_64`.
  - Set `-DCMAKE_BUILD_TYPE=Debug` for debug builds.
  - Generator alternatives: Ninja (`-G Ninja`) on Linux/macOS for faster builds.
  - Single-command option: `cmake -B build/<Platform>/<Config> <source-path> ...` then `cmake --build build/<Platform>/<Config> --parallel 8`.

**Generated / Build Artifacts:**
- `build/<Platform>/<Config>/`: Build outputs in all C++ projects (not committed)
- `SuperGenius/src/*/proto/`: Source `.proto` files; generated `.pb.h/.pb.cc` in build tree
- `GeniusWallet/lib/libadd.dylib`: Prebuilt macOS native library
- `GeniusWallet/.dart_tool/`: Dart tooling cache

## Naming Conventions

**Files:**
- C++: PascalCase `.hpp` / `.cpp` (e.g., `GeniusAccount.hpp`, `GeniusNode.cpp`)
- C++ interfaces: `I` prefix (e.g., `IGeniusTransactions.hpp`, `IComponent.hpp`, `ISecureStorage.hpp`)
- Dart: `snake_case.dart` (e.g., `app_bloc.dart`, `wallet_details_cubit.dart`)
- Proto: `SG*.proto` or `PascalCase.proto` (e.g., `SGProcessing.proto`, `SGAccountComm.proto`)
- CMake: `CMakeLists.txt` (case-sensitive), functional `.cmake` files PascalCase (e.g., `CommonBuildParameters.cmake`)

**Directories:**
- C++ modules: lowercase with underscores for multi-word (`local_secure_storage/`, `coinprices/`)
- Dart features: lowercase with underscores (e.g., `squid_router/`, `submit_job/`)
- Platform build dirs: PascalCase (`Linux/`, `iOS/`, `Android/`)

**Classes/Types (C++):**
- Types start uppercase, mixed case: `GeniusAccount`, `ProcessingEngine`, `CComponentFactory`
- Data members: `m_` prefix (`m_Name`, `m_InstanceCount`)
- Arguments/locals: `a` prefix (`aRef`, `aName`)
- Accessors: `Get` prefix (`GetName()`, `GetComponent()`), boolean: `Is` prefix (`IsNameEmpty()`)
- Mutators: `Set` prefix (`SetName()`), no return value
- Factories: `Create` / `Destroy` prefix

**Namespaces:**
- SuperGenius: `sgns::` (e.g., `sgns::genius_node`, `sgns::ipfs_lite`)
- GeniusWallet: `genius_wallet` (Dart package name)
- GeniusSDK: Flat C API in `GeniusSDK.h`, C++ namespace not heavily used

## Where to Add New Code

**New Feature (SuperGenius C++ module):**
- Primary code: `SuperGenius/src/<new_module>/`
- Public headers: `SuperGenius/src/<new_module>/*.hpp`
- Implementation: `SuperGenius/src/<new_module>/*.cpp`
- Proto definitions: `SuperGenius/src/<new_module>/proto/`
- CMake: Add `add_subdirectory(<new_module>)` to `SuperGenius/src/CMakeLists.txt:1`
- Tests: `SuperGenius/test/`
- Examples: `SuperGenius/example/`

**New Feature (GeniusWallet Flutter):**
- Primary code: `GeniusWallet/lib/<feature_name>/`
- BLoC/Cubit: `GeniusWallet/lib/<feature_name>/cubit/`
- UI: `GeniusWallet/lib/<feature_name>/view/`
- Routes: Add to `GeniusWallet/lib/navigation/router.dart`
- Tests: `GeniusWallet/test/`

**New Feature (GeniusSDK):**
- Primary code: `GeniusSDK/src/` (modify `GeniusSDK.h` / `GeniusSDK.cpp`)
- Examples: `GeniusSDK/example/`
- Tests: `GeniusSDK/test/`

**New Smart Contract:**
- Primary code: `TokenContracts/<new_contract>/contracts/`
- Tests: `TokenContracts/<new_contract>/test/`
- Deploy scripts: `TokenContracts/<new_contract>/`

**New zkLLVM Target:**
- Libraries: `zkLLVM/libs/<new_lib>/`
- Examples: `zkLLVM/examples/`
- Tests: `zkLLVM/tests/`

**New Third-party Library:**
- CMake entry: `thirdparty/build/CommonTargets.CMake` (add `ExternalProject_Add`)
- Platform configs: `thirdparty/build/<Platform>/CMakeLists.txt` if platform-specific

## Special Directories

**build/<Platform>/<Debug|Release>/:**
- Purpose: CMake build entry points and output directories. The `build/<Platform>/` subdirectories contain the actual `CMakeLists.txt` build entries; there is no root-level CMakeLists.txt for main projects. The cmake source path depth varies by platform: `..` (Windows, OSX, iOS), `../..` (Linux), or `../../` (Android).
- Build tool: `make -j` (Linux/macOS), `cmake --build . --parallel 8 --config Release` (Windows), or Ninja.
- Generated: Yes (by CMake generate + build)
- Committed: Build outputs no; the `CMakeLists.txt` entry points in `build/<Platform>/` are committed.

**SuperGenius/src/*/proto/:**
- Purpose: Protocol Buffer source definitions
- Generated: The `.proto` files are source; the `.pb.h`/`.pb.cc` files are generated during build
- Committed: Proto sources yes; generated code no

**.planning/:**
- Purpose: Planning workflow configuration and AI-generated analysis docs
- Generated: Partially (config is manual; codebase docs are AI-generated)
- Committed: Yes

**AgentDocs/:**
- Purpose: Documentation for AI coding agents
- Generated: No (manually written)
- Committed: Yes

**GeniusWallet/banxa/ and GeniusWallet/squidrouter/:**
- Purpose: Auto-generated API client code for Banxa and SquidRouter
- Generated: Yes (code generation)
- Committed: Yes (but per AGENTS.md: "Do not change them")

**GeniusWallet/packages/:**
- Purpose: Internal Dart packages shared with the wallet app
- Generated: No
- Committed: Yes

**Thirdparty/** (the submodule root, not vendor libs):
- Purpose: Git repository containing all third-party library build scripts
- Generated: N/A
- Committed: Yes (as a submodule reference)

**TestVMs/:**
- Purpose: Vagrant virtual machines for integration testing
- Generated: Partially (Vagrant boxes are downloaded)
- Committed: Yes (Vagrantfile and bootstrap scripts only)

---

*Structure analysis: 2026-07-01*
