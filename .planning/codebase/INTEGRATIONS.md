# External Integrations

**Analysis Date:** 2026-07-01

## APIs & External Services

**Blockchain & Web3:**
- Ethereum/EVM-compatible chains - Smart contract deployment and interaction
  - SDK/Client: ethers.js ^5.5.4, web3dart ^3.0.0, web3 ^1.2.2, Web3Modal/WalletConnect (reown_walletkit ^1.3.2)
  - Auth: Private key / wallet-based
- Axelar Network - Cross-chain token bridging
  - SDK/Client: @axelar-network/axelarjs-sdk ^0.15.0, @axelar-network/interchain-token-service ^1.2.1
  - Auth: API keys (env var)
- Uniswap - GNUS/ETH liquidity pool (wrapper integration in gnus-token contract)
  - Integration: On-chain via smart contract deployment

**P2P & Decentralized Storage:**
- IPFS - Decentralized file storage and content addressing
  - SDK/Client: ipfs-lite-cpp, ipfs-bitswap-cpp, ipfs-pubsub, cpp-ipfs-http-client (C++)
  - Transport: libp2p P2P networking layer
- CRDT-based distributed DB - Decentralized data synchronization
  - Implementation: `SuperGenius/src/crdt/globaldb/` with `heads.proto`, `delta.proto`, `bcast.proto`

**AI/ML:**
- MNN - On-device neural network inference for AI Processing jobs
  - SDK/Client: MNN C++ library via CMake `find_package(MNN CONFIG REQUIRED)`
  - Used in: `SuperGenius/example/mnn_chunkprocess/` for ML chunk processing

**Zero-Knowledge Proofs:**
- zkLLVM 0.3.0 - ZK circuit compilation and proof generation
  - SDK/Client: C++ library via `zkLLVM_INCLUDE_DIR`, LLVM integration
  - Hosted at: `https://github.com/GeniusVentures/zkLLVM`
- ZoKrates - ZK proof DSL for Ethereum smart contracts
  - SDK/Client: Rust crate (workspace), WASM/JS bridge, Solidity verifier contracts
  - Used in: `TokenContracts/gnus-ai/contracts/libraries/ZkVerifier/` (ZetherVerifier, InnerVerifier, BurnVerifier)
  - Solidity verification: `TokenContracts/gnus-ai/contracts/Zether.sol`

**Cryptocurrency Wallet:**
- TrustWalletCore - Multi-chain wallet operations (signing, key derivation, address generation)
  - SDK/Client: C++ static libraries (`wallet-core/lib/TrustWalletCore`, `TrezorCrypto`, `wallet_core_rs`)
  - Integration: `GeniusSDK/cmake/CommonBuildParameters.cmake:310`
- Web3 RPC - Ethereum node communication
  - SDK/Client: web3dart (Dart), ethers.js (TypeScript)
  - Auth: RPC endpoint URL (env var)

**GitHub:**
- GitHub API - Download release artifacts during CI and installation
  - SDK/Client: `gh` CLI, `aiohttp` (Python), REST API
  - Auth: `GITHUB_TOKEN` / `GH_TOKEN` env var
  - Used by: `util/install_from_github.py`, CI workflows
- GitHub Container Registry - Docker images for CI runners
  - Image: `ghcr.io/geniusventures/debian-bullseye:latest`

**Blockchain Infrastructure:**
- Etherscan - Contract verification and source code publishing
  - SDK/Client: @nomiclabs/hardhat-etherscan ^3.1.0
  - Auth: `ETHERSCAN_API_KEY` env var
- OpenZeppelin Defender - Admin operations for deployed contracts
  - SDK/Client: @openzeppelin/defender-admin-client ^1.54.1
  - Auth: Defender API keys

## Data Storage

**Databases:**
- RocksDB - High-performance persistent K/V store (primary node storage)
  - Client: Native C++ library via CMake (`find_package(RocksDB CONFIG REQUIRED)`)
- SQLite3 - Embedded relational database
  - Client: SQLite3 C API + SQLiteModernCpp C++ wrapper
- CRDT GlobalDB - Distributed conflict-free replicated data store
  - Implementation: `SuperGenius/src/crdt/globaldb/`
  - Protocol: Protobuf-serialized `broadcast.proto`, `heads.proto`, `delta.proto`
- Hive CE ^2.19.3 - Flutter-side structured local storage
  - Client: `hive_ce`, `hive_ce_flutter` (Dart)

**File Storage:**
- IPFS - Decentralized content-addressed file storage
  - Client: ipfs-lite-cpp, cpp-ipfs-http-client
- Local filesystem - Used for build artifacts, configs, release packages

**Caching:**
- ccache - Compiler cache (all CI platforms)
- RocksDB - Used as embedded cache layer
- Hive CE - Local cache for wallet app data

## Authentication & Identity

**Auth Provider:**
- Custom - Wallet-based cryptographic authentication
  - Implementation: Public key cryptography (secp256k1, ed25519, sr25519) using TrustWalletCore, libsecp256k1, ed25519, sr25519-donna
  - Secure storage: `flutter_secure_storage` (mobile), `libsecret-1` (Linux), local keychain (macOS/iOS)
  - WalletConnect via reown_walletkit for dApp connections

**Identity:**
- Ethereum addresses / public keys as identifiers
- Diamond pattern access control: `GeniusAccessControl.sol`, `GeniusOwnershipFacet.sol`

## Monitoring & Observability

**Error Tracking:**
- Sentry - Error and crash reporting for Flutter wallet app
  - SDK/Client: `sentry_flutter ^9.0.0`
  - Auth: Sentry DSN (env var)

**Logs:**
- spdlog + soralog - Structured C++ logging (multi-sink)
  - Integration: `find_package(spdlog CONFIG REQUIRED)`, `find_package(soralog CONFIG REQUIRED)`
  - Config: `SPDLOG_FMT_EXTERNAL` flag for fmt integration
- Flutter: Standard Dart logging, Sentry breadcrumbs

**Testing & Coverage:**
- CTest - Test runner for C++ (GTest-based)
- hardhat-gas-reporter - Gas cost analysis
- solidity-coverage - Solidity code coverage

## CI/CD & Deployment

**Hosting:**
- Not detected (self-hosted node infrastructure; contracts deployed to Ethereum/EVM chains)
- GeniusWallet: Windows desktop, macOS desktop, Linux desktop, iOS, Android via platform app stores

**CI Pipeline:**
- GitHub Actions - Multi-platform build and release
  - Workflow files: `SuperGenius/.github/workflows/cmake.yml`, `build-release-tags.yml`
  - Self-hosted runners: `sg-ubuntu-linux`, `sg-arm-linux`, `SG-WIN11`, `gv-OSX-Large`
  - Jobs: Build for Android (arm64-v8a, armeabi-v7a), iOS, macOS, Linux (x86_64, aarch64), Windows
  - Artifacts: Compressed `.tar.gz` builds uploaded as GitHub Releases
  - Container CI: Linux jobs run in `ghcr.io/geniusventures/debian-bullseye:latest`
  - Static analysis: CodeQL security scanning configured

## Environment Configuration

**Required env vars (externalized - exact values NOT read):**
- `GH_TOKEN` / `GITHUB_TOKEN` - GitHub authentication for CI artifact downloads
- `THIRDPARTY_BUILD_DIR` - Path to compiled thirdparty libraries
- `ZKLLVM_BUILD_DIR` - Path to zkLLVM build output
- `SUPERGENIUS_DIR` - Path to SuperGenius project for GeniusSDK builds
- `ANDROID_NDK_HOME` - Android NDK path
- `VULKAN_SDK` - Vulkan SDK path (defaulted to thirdparty build)
- Wallet private keys / mnemonic phrases
- Ethereum RPC endpoint URLs
- Etherscan API key
- Axelar API key
- OpenZeppelin Defender API credentials
- Sentry DSN

**Secrets location:**
- GitHub Actions secrets: `GNUS_TOKEN_1` (container registry + release auth)
- `.env.example` templates at `SuperGenius/evmrelay/examples/`, `TokenContracts/gnus-ai/`, `GeniusWallet/squidrouter/`
- `flutter_secure_storage` / `libsecret-1` for runtime secrets

## Webhooks & Callbacks

**Incoming:**
- Not detected (full nodes listen via libp2p/gRPC, not HTTP webhooks)
- WalletConnect session proposals via reown_walletkit

**Outgoing:**
- Blockchain transaction broadcasts (via Ethereum RPC)
- Axelar cross-chain bridge transactions
- IPFS content publishing (ipfs-pubsub GossipPubSub)
- gRPC service calls (protobuf-defined services)
- Sentry error reports

---

*Integration audit: 2026-07-01*
